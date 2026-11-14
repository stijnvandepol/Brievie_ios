import Foundation

/// One scanned document waiting to reach the server. Stored on disk next to its upload body, so the
/// queue survives the app being closed.
public struct UploadItem: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable {
        case waiting
        case uploading
        /// Trying again will not help by itself; the user can retry or delete it.
        case failed
    }

    /// Also the document's `client_id` on the server: a repeated upload finds the same document there.
    public let id: UUID
    public let workspaceID: UUID
    /// The pairing the latest attempt was made with: a late answer to an older pairing is told apart by it.
    public var deviceID: UUID
    public let createdAt: Date
    public let pageCount: Int
    public let bodyByteCount: Int64
    public let boundary: String
    public var state: State
    /// Failed attempts so far.
    public var attempt: Int
    /// Index into the connection's URLs for the next attempt.
    public var urlIndex: Int
    public var nextAttemptAt: Date?
    /// Set with `.failed`. Diagnostic: an error code from a closed set, mapped to Dutch text by the UI.
    public var failureCode: String?
}

/// What the server accepts in one upload (host settings `BRIEVIE_MAX_PAGES`, `BRIEVIE_MAX_UPLOAD_BYTES`,
/// `BRIEVIE_MAX_PAGE_TEXT_CHARS`). Checked on the phone, so a scan that cannot succeed is never queued.
public struct UploadLimits: Sendable {
    public static let server = UploadLimits(maxPages: 30, maxBodyBytes: 32 * 1024 * 1024, maxTextCharacters: 20_000)

    public let maxPages: Int
    public let maxBodyBytes: Int64
    /// Per page. Longer text is cut, never refused.
    public let maxTextCharacters: Int

    public init(maxPages: Int, maxBodyBytes: Int64, maxTextCharacters: Int) {
        self.maxPages = maxPages
        self.maxBodyBytes = maxBodyBytes
        self.maxTextCharacters = maxTextCharacters
    }
}

public enum UploadQueueError: Error, Equatable {
    case noPages
    case tooManyPages
    case tooLarge
    case diskFull
    case writeFailed
}
