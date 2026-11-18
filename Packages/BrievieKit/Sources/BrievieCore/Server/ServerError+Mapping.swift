import BrievieAPI
import Foundation
import OpenAPIRuntime

extension ServerError {
    /// The answer was longer than the app reads (a JSON body above `LiveBrievieServer.maxJSONResponseBytes`, or a
    /// CA certificate above its own cap).
    public static let responseTooLarge = ServerError.other("response_too_large")

    /// Error codes that may pass through into `.other`. Everything else a server sends (it may not even be a
    /// Brievie server yet) becomes the fixed form `http_<status>`, so no server-chosen text reaches the app.
    static let passThroughCodes: Set<String> = [
        "no_private_ca", "validation_error", "workspace_not_found", "document_not_found", "page_not_found",
        "document_not_reviewable", "document_not_failed", "device_not_found", "person_not_found",
        "label_not_found", "suggestion_not_found", "person_exists", "document_processing", "task_not_found"
    ]

    /// A non-2xx answer. `code` is the `code` field of the server's `{code, message}` error body.
    init(status: Int, code: String?) {
        switch (status, code) {
        // A wrong proof or code, an unknown pairing, and an expired or replayed challenge: one refusal for the user.
        case (400, "pairing_code_invalid"), (400, "pairing_challenge_invalid"):
            self = .invalidCode
        case (401, "not_authenticated"):
            // The host's answer to a revoked or unknown device token. Any other 401 (a reverse proxy with its own
            // login, say) is not the server's verdict on this device: it must not forget the pairing or remove
            // the calendars.
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
        case is ResponseTooLargeError:
            self = .responseTooLarge
        case is ForeignUnauthorizedError:
            self = .other("http_401")
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
