import Foundation
import Synchronization

/// Uploads through one background `URLSession`: the system keeps sending while the app is suspended and
/// relaunches it when an upload ends.
///
/// There is exactly one per process (a session identifier may be used only once). When the user swipes the
/// app away, iOS cancels its background uploads; they are queued again the next time the app opens.
public final class BackgroundUploadTransport: NSObject, UploadTransport, URLSessionDataDelegate {
    public static let sessionIdentifier = "nl.stijnvdpol.brievie.upload"
    /// The system waits for a connection by itself; this bounds how long one attempt may wait.
    static let resourceTimeout: TimeInterval = 7 * 24 * 60 * 60
    /// An error body is `{"code", "message"}`; anything longer is not ours.
    private static let maxResponseBytes = 16 * 1024

    private struct State {
        var bodies: [Int: Data] = [:]
        var trustRefused: Set<Int> = []
        var cancelledByApp: Set<Int> = []
    }

    public let events: AsyncStream<UploadEvent>
    private let continuation: AsyncStream<UploadEvent>.Continuation
    private let trustProvider: any UploadTrustProvider
    private let state = Mutex(State())
    private let session = Mutex<URLSession?>(nil)
    private let configuration: @Sendable () -> URLSessionConfiguration

    public convenience init(trustProvider: any UploadTrustProvider) {
        self.init(trustProvider: trustProvider) { Self.configuration(identifier: Self.sessionIdentifier) }
    }

    init(trustProvider: any UploadTrustProvider, configuration: @escaping @Sendable () -> URLSessionConfiguration) {
        self.trustProvider = trustProvider
        self.configuration = configuration
        (events, continuation) = AsyncStream.makeStream(of: UploadEvent.self, bufferingPolicy: .unbounded)
        super.init()
    }

    /// Not `SessionConfiguration.hardened`: its 30 s resource timeout would end every slow upload.
    static func configuration(identifier: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }

    /// Creates the session; call once at launch so the system can deliver the events of a relaunch.
    public func activate() {
        _ = urlSession()
    }

    private func urlSession() -> URLSession {
        session.withLock { session in
            if let session { return session }
            let created = URLSession(configuration: configuration(), delegate: self, delegateQueue: nil)
            session = created
            return created
        }
    }

    // MARK: - UploadTransport

    public func start(
        itemID: UUID, deviceID: UUID, url: URL, bodyFile: URL, boundary: String, token: String, earliestBegin: Date?
    ) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(MultipartBodyWriter.contentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // From a file: the system reads it while the app is not running, and sends a Content-Length.
        let task = urlSession().uploadTask(with: request, fromFile: bodyFile)
        task.taskDescription = Self.description(itemID: itemID, deviceID: deviceID)
        task.earliestBeginDate = earliestBegin
        task.resume()
    }

    public func runningItemIDs() async -> Set<UUID> {
        let tasks = await urlSession().allTasks
        return Set(tasks.filter { $0.state == .running || $0.state == .suspended }
            .compactMap { Self.ids(from: $0.taskDescription)?.itemID })
    }

    public func cancel(itemID: UUID) async {
        for task in await urlSession().allTasks where Self.ids(from: task.taskDescription)?.itemID == itemID {
            state.withLock { _ = $0.cancelledByApp.insert(task.taskIdentifier) }
            task.cancel()
        }
    }

    /// The upload endpoint of a workspace on the server at `base`.
    public static func uploadURL(base: URL, workspaceID: UUID) -> URL {
        base.appending(path: "api/v1/workspaces/\(workspaceID.uuidString.lowercased())/documents")
    }

    // MARK: - Delegate

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        let decision = Self.disposition(
            authenticationMethod: space.authenticationMethod,
            serverTrust: space.serverTrust,
            host: space.host,
            trust: trustProvider.currentTrust()
        )
        if decision == .cancelAuthenticationChallenge {
            state.withLock { _ = $0.trustRefused.insert(task.taskIdentifier) }
            return (decision, nil)
        }
        guard decision == .useCredential, let serverTrust = space.serverTrust else { return (decision, nil) }
        return (.useCredential, URLCredential(trust: serverTrust))
    }

    /// The API never redirects; a followed redirect could carry the token and the scan to another host.
    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let ids = Self.ids(from: task.taskDescription) else { return }
        continuation.yield(.sent(itemID: ids.itemID, bytes: totalBytesSent, of: totalBytesExpectedToSend))
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        state.withLock { state in
            var body = state.bodies[dataTask.taskIdentifier] ?? Data()
            guard body.count < Self.maxResponseBytes else { return }
            body.append(data.prefix(Self.maxResponseBytes - body.count))
            state.bodies[dataTask.taskIdentifier] = body
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let identifier = task.taskIdentifier
        let (body, trustRefused, cancelledByApp) = state.withLock { state in
            (
                state.bodies.removeValue(forKey: identifier) ?? Data(),
                state.trustRefused.remove(identifier) != nil,
                state.cancelledByApp.remove(identifier) != nil
            )
        }
        guard let ids = Self.ids(from: task.taskDescription) else { return }
        let outcome = Self.outcome(
            error: error,
            status: (task.response as? HTTPURLResponse)?.statusCode,
            body: body,
            trustRefused: trustRefused,
            cancelledByApp: cancelledByApp
        )
        continuation.yield(.finished(itemID: ids.itemID, deviceID: ids.deviceID, outcome: outcome))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        continuation.yield(.allEventsDelivered)
    }

    // MARK: - Pure parts

    /// Only server-trust challenges are decided here. Without a readable pairing the connection is
    /// refused: never a fallback to the system's trust for a server that should be pinned.
    static func disposition(
        authenticationMethod: String, serverTrust: SecTrust?, host: String, trust: ServerTrust?
    ) -> URLSession.AuthChallengeDisposition {
        guard authenticationMethod == NSURLAuthenticationMethodServerTrust else { return .performDefaultHandling }
        guard let trust, let serverTrust, trust.evaluate(serverTrust, host: host) else {
            return .cancelAuthenticationChallenge
        }
        return .useCredential
    }

    static func outcome(
        error: (any Error)?, status: Int?, body: Data, trustRefused: Bool, cancelledByApp: Bool
    ) -> UploadOutcome {
        guard let error else {
            guard let status else { return .unreachable }
            return .status(status, code: errorCode(in: body))
        }
        if trustRefused { return .untrusted }
        if cancelledByApp { return .cancelledByUser }
        switch (error as? URLError)?.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired:
            return .untrusted
        default:
            // Also every other cancellation: the system cancels uploads when the user swipes the app away.
            return .unreachable
        }
    }

    private static func errorCode(in body: Data) -> String? {
        struct ErrorBody: Decodable { let code: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: body))?.code
    }

    static func description(itemID: UUID, deviceID: UUID) -> String {
        "\(itemID.uuidString)/\(deviceID.uuidString)"
    }

    static func ids(from description: String?) -> (itemID: UUID, deviceID: UUID)? {
        guard let parts = description?.split(separator: "/"), parts.count == 2,
              let itemID = UUID(uuidString: String(parts[0])), let deviceID = UUID(uuidString: String(parts[1]))
        else { return nil }
        return (itemID, deviceID)
    }
}
