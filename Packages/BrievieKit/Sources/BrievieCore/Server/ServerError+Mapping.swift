import Foundation
import OpenAPIRuntime

extension ServerError {
    /// Error codes that may pass through into `.other`. Everything else a server sends (it may not even be a
    /// Brievie server yet) becomes the fixed form `http_<status>`, so no server-chosen text reaches the app.
    static let passThroughCodes: Set<String> = ["no_private_ca", "validation_error"]

    /// A non-2xx answer. `code` is the `code` field of the server's `{code, message}` error body.
    init(status: Int, code: String?) {
        switch (status, code) {
        case (400, "pairing_code_invalid"):
            self = .invalidCode
        case (401, _):
            self = .unauthorized
        case (429, _):
            self = .tooManyAttempts
        case let (400..<500, code?) where Self.passThroughCodes.contains(code):
            self = .other(code)
        default:
            self = .other("http_\(status)")
        }
    }

    /// An error thrown while making a request: a `ServerError` passes through, the generated client's
    /// `ClientError` is unwrapped, and `URLError`s are sorted into unreachable and untrusted.
    /// Callers check for task cancellation first (see `throwingCancellation(_:)`).
    init(requestError error: any Error) {
        switch Self.unwrapped(error) {
        case let error as ServerError:
            self = error
        case let error as URLError:
            self = Self(urlError: error.code)
        case is DecodingError:
            self = .incompatible
        case let error:
            self = .other(String(describing: type(of: error)))
        }
    }

    /// `CancellationError` when the current task was cancelled (URLSession then reports `URLError.cancelled`,
    /// which would otherwise read as a refused trust challenge); otherwise the mapped `ServerError`.
    static func throwingCancellation(_ error: any Error) -> any Error {
        if Task.isCancelled || unwrapped(error) is CancellationError {
            return CancellationError()
        }
        return ServerError(requestError: error)
    }

    private static func unwrapped(_ error: any Error) -> any Error {
        (error as? ClientError)?.underlyingError ?? error
    }

    private init(urlError code: URLError.Code) {
        switch code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .networkConnectionLost,
             .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
             .cannotLoadFromNetwork:
            self = .unreachable
        // Outside task cancellation, `.cancelled` is what URLSession reports when a session delegate cancels
        // the TLS challenge.
        case .cancelled, .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            self = .untrusted
        default:
            self = .other("url_error_\(code.rawValue)")
        }
    }
}
