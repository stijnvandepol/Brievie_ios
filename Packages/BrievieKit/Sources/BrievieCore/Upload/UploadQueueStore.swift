import BrievieScan
import Foundation

/// The upload queue on disk: one directory per document, holding its record (`item.json`) and its upload
/// body (`body.multipart`). A scan is complete here before its upload starts and leaves only after the
/// server confirmed it.
public actor UploadQueueStore {
    /// Writes the upload body of a scan to a file; replaceable so tests can simulate a full disk.
    public typealias BodyWriter = @Sendable (
        _ clientID: UUID, _ pages: [ScannedPage], _ boundary: String, _ maxTextCharacters: Int, _ file: URL
    ) throws -> Int64

    private static let incomingPrefix = ".incoming-"
    private static let itemFile = "item.json"
    private static let bodyFileName = "body.multipart"

    private let directory: URL
    private let limits: UploadLimits
    private let writeBody: BodyWriter
    private let files = FileManager.default
    /// Items removed at load because their record could not be read; reported once.
    private var removedUnreadable: Int

    /// - Parameter directory: live: `Application Support/Uploads`.
    public init(
        directory: URL,
        limits: UploadLimits = .server,
        writeBody: @escaping BodyWriter = { clientID, pages, boundary, maxText, file in
            try MultipartBodyWriter.write(
                clientID: clientID, pages: pages, boundary: boundary, maxTextCharacters: maxText, to: file
            )
        }
    ) {
        self.directory = directory
        self.limits = limits
        self.writeBody = writeBody
        // An enqueue that was interrupted (crash, kill) never became an item: remove what it left.
        // Plain paths: the default percent-encodes a space ("Application Support") and then finds nothing.
        let path = directory.path(percentEncoded: false)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for name in leftovers where name.hasPrefix(Self.incomingPrefix) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
        // An item whose record cannot be read can never be uploaded: remove it instead of keeping its scan on
        // disk where nobody sees it. A record that exists but cannot be opened yet (phone not unlocked since
        // the restart) is left alone.
        var removed = 0
        for name in leftovers where !name.hasPrefix(".") {
            let itemDirectory = directory.appending(path: name)
            if case .unreadable = Self.record(in: itemDirectory),
               (try? FileManager.default.removeItem(at: itemDirectory)) != nil {
                removed += 1
            }
        }
        removedUnreadable = removed
    }

    /// How many unreadable items were removed when the queue was loaded; 0 after the first call.
    public func takeRemovedUnreadableCount() -> Int {
        defer { removedUnreadable = 0 }
        return removedUnreadable
    }

    /// Writes the scan to disk as a waiting item. Nothing is left behind when it fails.
    public func enqueue(
        pages: [ScannedPage], workspaceID: UUID, deviceID: UUID
    ) throws(UploadQueueError) -> UploadItem {
        guard !pages.isEmpty else { throw .noPages }
        guard pages.count <= limits.maxPages else { throw .tooManyPages }
        // The images alone already decide this, before anything is written.
        let imageBytes = pages.reduce(Int64(0)) { $0 + Int64($1.jpeg.count) }
        guard imageBytes <= limits.maxBodyBytes else { throw .tooLarge }

        let id = UUID()
        let boundary = "brievie-\(UUID().uuidString)"
        let incoming = directory.appending(path: "\(Self.incomingPrefix)\(id.uuidString)")
        do {
            try prepareDirectory(directory)
            try prepareDirectory(incoming)
            let bodyFile = incoming.appending(path: Self.bodyFileName)
            let byteCount = try writeBody(id, pages, boundary, limits.maxTextCharacters, bodyFile)
            guard byteCount <= limits.maxBodyBytes else {
                try? files.removeItem(at: incoming)
                throw UploadQueueError.tooLarge
            }
            let item = UploadItem(
                id: id, workspaceID: workspaceID, deviceID: deviceID, createdAt: Self.wholeMilliseconds(Date()),
                pageCount: pages.count,
                bodyByteCount: byteCount, boundary: boundary, state: .waiting, attempt: 0, urlIndex: 0,
                nextAttemptAt: nil, failureCode: nil
            )
            try write(item, in: incoming)
            protect(bodyFile)
            // Only a complete item gets its real name.
            try files.moveItem(at: incoming, to: itemDirectory(id))
            return item
        } catch {
            try? files.removeItem(at: incoming)
            if let queueError = error as? UploadQueueError { throw queueError }
            throw Self.isDiskFull(error) ? .diskFull : .writeFailed
        }
    }

    /// Oldest first. A directory that cannot be read as an item is skipped.
    public func items() -> [UploadItem] {
        let names = (try? files.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> UploadItem? in
                if case let .item(item) = Self.record(in: directory.appending(path: name)) { return item }
                return nil
            }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    private enum Record {
        case item(UploadItem)
        /// No record, or one that is not an item: the directory can never be uploaded.
        case unreadable
        /// The record is there but cannot be opened now (file protection before the first unlock).
        case unavailable
    }

    private static func record(in itemDirectory: URL) -> Record {
        let file = itemDirectory.appending(path: itemFile)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? .unavailable : .unreadable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            Self.date(milliseconds: try decoder.singleValueContainer().decode(Int64.self))
        }
        guard let item = try? decoder.decode(UploadItem.self, from: data) else { return .unreadable }
        return .item(item)
    }

    public func item(_ id: UUID) -> UploadItem? {
        items().first { $0.id == id }
    }

    public func bodyFile(for id: UUID) -> URL {
        itemDirectory(id).appending(path: Self.bodyFileName)
    }

    public func update(_ item: UploadItem) throws {
        try write(item, in: itemDirectory(item.id))
    }

    public func remove(_ id: UUID) throws {
        let directory = itemDirectory(id)
        guard files.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try files.removeItem(at: directory)
    }

    /// Deletes everything in the queue directory: every item, also one whose record cannot be read, and what
    /// an interrupted enqueue left. Tries every entry, then throws the first error.
    public func removeAll() throws {
        let path = directory.path(percentEncoded: false)
        guard files.fileExists(atPath: path) else { return }
        var firstError: (any Error)?
        for name in try files.contentsOfDirectory(atPath: path) {
            do {
                try files.removeItem(at: directory.appending(path: name))
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    private func itemDirectory(_ id: UUID) -> URL {
        directory.appending(path: id.uuidString)
    }

    private func write(_ item: UploadItem, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.milliseconds(date))
        }
        let file = directory.appending(path: Self.itemFile)
        try encoder.encode(item).write(to: file, options: .atomic)
        protect(file)
    }

    private func prepareDirectory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        protect(url)
    }

    /// Scans are not backed up (they are on the server soon, or on the phone until then), and are readable
    /// after the first unlock: the background upload has to read them while the phone is locked.
    private nonisolated func protect(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        #endif
    }

    // Dates are stored as whole milliseconds, so a record reads back equal to what was written.
    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// For other code that sets a date on an item (`nextAttemptAt`).
    public static func wholeMilliseconds(_ date: Date) -> Date {
        Self.date(milliseconds: milliseconds(date))
    }

    private static func isDiskFull(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDiskFull(underlying)
        }
        return false
    }
}
