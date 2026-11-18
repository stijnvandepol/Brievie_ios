import Foundation
import Synchronization

/// Answers requests from a table keyed by host, so tests running in parallel each use their own host.
/// Requests are recorded per host for inspection.
final class StubURLProtocol: URLProtocol {
    indirect enum Answer: Sendable {
        case response(status: Int, json: String)
        /// A different answer per path (`/api/v1/health`, ...); an unlisted path fails as an unknown host.
        case routes([String: Answer])
        case data(status: Int, contentType: String, body: Data)
        case redirect(URL)
        case failure(URLError.Code)
    }

    private static let answers = Mutex<[String: Answer]>([:])
    private static let requests = Mutex<[String: [URLRequest]]>([:])

    /// A fresh `https` base URL whose requests get `answer`.
    static func serve(_ answer: Answer) throws -> URL {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        answers.withLock { $0[host] = answer }
        guard let url = URL(string: "https://\(host)") else { throw URLError(.badURL) }
        return url
    }

    static func requests(to url: URL) -> [URLRequest] {
        requests.withLock { $0[url.host() ?? ""] ?? [] }
    }

    /// An ephemeral configuration that routes every request to this stub.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        var recorded = request
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        Self.requests.withLock { $0[host, default: []].append(recorded) }

        guard var answer = Self.answers.withLock({ $0[host] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if case let .routes(routes) = answer {
            guard let routed = routes[url.path()] else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            answer = routed
        }
        switch answer {
        case .routes:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        case let .response(status, json):
            respond(url: url, status: status, body: Data(json.utf8))
        case let .data(status, contentType, body):
            respond(url: url, status: status, body: body, contentType: contentType)
        case let .redirect(target):
            guard let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
            ) else { return }
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    private func respond(url: URL, status: Int, body: Data, contentType: String = "application/json") {
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType]
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        // `read` blocks until bytes arrive or the stream ends; `hasBytesAvailable` can still be false
        // right after `open`, which would record an empty body.
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
            data.append(buffer, count: count)
        }
        return data
    }
}
