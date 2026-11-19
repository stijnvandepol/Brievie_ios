import BrievieCore
import BrievieScan
import Foundation
import Observation

/// Turns the pages of a scan into a queued upload: turn each page upright and read it, let the user check the
/// pages (and turn one by hand), then write the scan to the queue.
@MainActor
@Observable
public final class ScanFlowModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case recognising(page: Int, total: Int)
        /// Every page is ready; the user checks them before saving.
        case reviewing
        case saving
        case failed(message: String)
        /// The scan is safe in the upload queue.
        case finished

        var label: String {
            switch self {
            case let .recognising(page, total): String(format: DocumentStrings.recognisingFormat, page, total)
            case let .failed(message): message
            case .idle, .reviewing, .saving, .finished: ""
            }
        }
    }

    /// One page as the preview shows it.
    public struct Page: Identifiable, Equatable, Sendable {
        /// 0-based position in the scan.
        public let id: Int
        /// A small JPEG of exactly the pixels that will be uploaded.
        public let preview: Data
        /// The text decided the turn; the user did not.
        public let turnedAutomatically: Bool
        /// Being turned and read again right now.
        public let isTurning: Bool
    }

    public private(set) var phase: Phase = .idle
    /// The scan flow's screen is on the navigation stack.
    public var isPresented: Bool { phase != .idle && phase != .finished }
    public var pages: [Page] {
        processed.enumerated().map { index, page in
            Page(
                id: index, preview: page.preview, turnedAutomatically: page.turnedAutomatically,
                isTurning: turning == index
            )
        }
    }

    /// Saving waits until no page is being turned.
    public var canSave: Bool { phase == .reviewing && turning == nil }

    private let workspaceID: UUID
    private let uploads: any UploadQueue
    private let processor: PageProcessor
    private let maxPages: Int
    /// The pages as they came in, kept until saving: a turn by hand starts again from them, so the JPEG is
    /// encoded once from the original and never from an earlier JPEG.
    private var sources: [PageSource] = []
    private var processed: [ProcessedPage] = []
    private var turning: Int?
    /// Counts discards: work that started before one never writes its result.
    private var generation = 0
    var work: Task<Void, Never>?

    public init(
        workspaceID: UUID,
        uploads: any UploadQueue,
        recognizer: any PageTextRecognizer = VisionTextRecognizer(),
        maxPages: Int = UploadLimits.server.maxPages
    ) {
        self.workspaceID = workspaceID
        self.uploads = uploads
        self.processor = PageProcessor(recognizer: recognizer)
        self.maxPages = maxPages
    }

    /// Starts processing in a task of its own, so `discard()` can stop it.
    public func start(loaded sources: [PageSource?]) {
        work?.cancel()
        phase = .recognising(page: 1, total: max(sources.count, 1))
        work = Task { await process(loaded: sources) }
    }

    /// For pages that had to be loaded first (photo library, scanner): `nil` is a page that could not be
    /// loaded. A scan with a missing page is refused as a whole; uploading the rest would silently lose it.
    public func process(loaded sources: [PageSource?]) async {
        let complete = sources.compactMap { $0 }
        guard complete.count == sources.count else {
            phase = .failed(message: DocumentStrings.unreadablePage)
            return
        }
        await process(complete)
    }

    /// One page at a time, off the main actor: only the JPEGs and texts of earlier pages stay in memory,
    /// next to the compressed pages as they came in.
    public func process(_ sources: [PageSource]) async {
        guard !sources.isEmpty else {
            phase = .failed(message: DocumentStrings.noPages)
            return
        }
        guard sources.count <= maxPages else {
            phase = .failed(message: DocumentStrings.tooManyPages)
            return
        }
        let started = generation
        var results: [ProcessedPage] = []
        for (index, source) in sources.enumerated() {
            phase = .recognising(page: index + 1, total: sources.count)
            do {
                results.append(try await processor.process(source))
            } catch is CancellationError {
                return
            } catch {
                guard started == generation else { return }
                phase = .failed(message: DocumentStrings.unreadablePage)
                return
            }
            guard started == generation else { return }
        }
        self.sources = sources
        processed = results
        phase = .reviewing
    }

    /// Turns a page a quarter clockwise and reads it again. Ignored while another page is being turned.
    public func turn(page index: Int) async {
        guard phase == .reviewing, turning == nil, processed.indices.contains(index) else { return }
        let started = generation
        turning = index
        defer { if started == generation { turning = nil } }
        let turn = processed[index].turn.adding(.clockwise)
        // The page decoded and encoded fine a moment ago; a failure now keeps it as it was.
        guard let result = try? await processor.process(sources[index], turn: turn), started == generation
        else { return }
        processed[index] = result
    }

    /// Writes the checked pages to the upload queue.
    public func save() async {
        guard canSave else { return }
        phase = .saving
        do {
            _ = try await uploads.enqueue(pages: processed.map(\.page), workspaceID: workspaceID)
            clearPages()
            phase = .finished
        } catch {
            phase = .failed(message: Self.message(for: error))
        }
    }

    /// Throws the scan away: stops reading, forgets every page.
    public func discard() {
        work?.cancel()
        reset()
    }

    public func reset() {
        generation += 1
        work = nil
        clearPages()
        phase = .idle
    }

    private func clearPages() {
        sources = []
        processed = []
        turning = nil
    }

    private static func message(for error: UploadQueueError) -> String {
        switch error {
        case .noPages: DocumentStrings.noPages
        case .tooManyPages: DocumentStrings.tooManyPages
        case .tooLarge: DocumentStrings.tooLarge
        case .diskFull: DocumentStrings.diskFull
        case .writeFailed: DocumentStrings.scanFailed
        }
    }
}
