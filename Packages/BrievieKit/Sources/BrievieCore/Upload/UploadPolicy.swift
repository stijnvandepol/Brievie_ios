import Foundation

/// How one upload attempt ended.
public enum UploadOutcome: Equatable, Sendable {
    /// The server answered. `code` is the `code` field of its error body, when there was one.
    case status(Int, code: String?)
    /// No connection, a timeout, a connection lost after sending, and every cancellation that was not our
    /// own trust refusal (the system cancels background uploads when the user swipes the app away).
    case unreachable
    /// The TLS connection was refused by the certificate pin.
    case untrusted
    /// The app cancelled the upload itself (`delete`): nothing to decide.
    case cancelledByUser
    /// There was no pairing to check the server against (it was cleared while the upload waited).
    case unpaired
}

public enum UploadDecision: Equatable, Sendable {
    /// The document is on the server: remove the item.
    case done
    case retry(urlIndex: Int, after: Duration)
    /// Waiting will not help. The item stays; the user may retry or delete it.
    case failed(code: String)
    /// The server no longer knows this device. The item stays for after pairing again.
    case revoked
    /// Nothing is wrong with the scan; it waits until the app is paired again.
    case paused
}

/// Decides what happens after each upload attempt. Retries never end by themselves: a scan waits as long
/// as it takes for the server to come back.
public enum UploadPolicy {
    public static let backoff: [Duration] = [
        .seconds(30), .seconds(120), .seconds(600), .seconds(1800), .seconds(3600)
    ]

    /// Error codes of the upload endpoint that may be kept; anything else becomes `http_<status>`, so no
    /// server-chosen text is stored or shown.
    static let knownCodes: Set<String> = [
        "document_conflict", "page_checksum_mismatch", "workspace_not_found", "validation_error",
        "payload_too_large", "length_required"
    ]

    public static func decide(_ outcome: UploadOutcome, item: UploadItem, urlCount: Int) -> UploadDecision {
        let wait = backoff[min(max(item.attempt, 0), backoff.count - 1)]
        switch outcome {
        case let .status(status, code):
            return decide(status: status, code: code, item: item, wait: wait)
        case .unreachable:
            if item.urlIndex + 1 < urlCount {
                return .retry(urlIndex: item.urlIndex + 1, after: .zero)
            }
            return .retry(urlIndex: 0, after: wait)
        case .untrusted:
            // A changed certificate is not fixed by waiting.
            return .failed(code: "untrusted")
        case .cancelledByUser:
            return .failed(code: "cancelled")
        case .unpaired:
            return .paused
        }
    }

    /// The server (or something in front of it) answered.
    private static func decide(status: Int, code: String?, item: UploadItem, wait: Duration) -> UploadDecision {
        switch status {
        case 200, 201:
            return .done
        case 401 where code == "not_authenticated":
            // Only the host's own code: a 401 from something in front of it is no revocation.
            return .revoked
        case 429, 500...:
            return .retry(urlIndex: item.urlIndex, after: wait)
        case 400..<500:
            if let code, knownCodes.contains(code) {
                return .failed(code: code)
            }
            return .failed(code: "http_\(status)")
        default:
            // A proxy page, a redirect: not our server's verdict on the document.
            return .retry(urlIndex: item.urlIndex, after: wait)
        }
    }
}
