import Foundation
import OpenAPIRuntime

extension ServerError {
    /// A non-2xx answer. `code` is the `code` field of the server's `{code, message}` error body.
    init(status: Int, code: String?) {
        switch (status, code) {
        case (400, "pairing_code_invalid"):
            self = .invalidCode
        case (401, _):
            self = .unauthorized
        case (429, _):
            self = .tooManyAttempts
        case (_, let code?) where status < 500:
            self = .other(code)
        default:
            self = .other("http_\(status)")
        }
    }

    /// An error thrown while making a request: a `ServerError` passes through, the generated client's
    /// `ClientError` is unwrapped, and `URLError`s are sorted into unreachable and untrusted.
    init(requestError error: any Error) {
        let underlying = (error as? ClientError)?.underlyingError ?? error
        switch underlying {
        case let error as ServerError:
            self = error
        case let error as URLError:
            self = Self(urlError: error.code)
        case is DecodingError:
            self = .incompatible
        default:
            self = .other(String(describing: type(of: underlying)))
        }
    }

    private init(urlError code: URLError.Code) {
        switch code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .networkConnectionLost,
             .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
             .cannotLoadFromNetwork:
            self = .unreachable
        // `.cancelled` is what URLSession reports when a session delegate cancels the TLS challenge.
        case .cancelled, .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            self = .untrusted
        default:
            self = .other("url_error_\(code.rawValue)")
        }
    }
}
