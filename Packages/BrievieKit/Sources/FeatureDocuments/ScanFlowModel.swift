import BrievieCore
import BrievieScan
import Foundation
import Observation

/// Turns the pages of a scan into a queued upload: recognise the text, encode the image, write to the queue.
@MainActor
@Observable
public final class ScanFlowModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case recognising(page: Int, total: Int)
        case failed(message: String)
        /// The scan is safe in the upload queue.
        case finished

        var label: String {
            switch self {
            case let .recognising(page, total): String(format: DocumentStrings.recognisingFormat, page, total)
            case let .failed(message): message
            case .idle, .finished: ""
            }
        }
    }

    public private(set) var phase: Phase = .idle

    private let workspaceID: UUID
    private let uploads: any UploadQueue
    private let recognizer: any PageTextRecognizer
    private let maxPages: Int

    public init(
        workspaceID: UUID,
        uploads: any UploadQueue,
        recognizer: any PageTextRecognizer = VisionTextRecognizer(),
        maxPages: Int = UploadLimits.server.maxPages
    ) {
        self.workspaceID = workspaceID
        self.uploads = uploads
        self.recognizer = recognizer
        self.maxPages = maxPages
    }

    /// One page at a time: only the JPEG and the text of earlier pages stay in memory.
    public func process(_ sources: [PageSource]) async {
        guard !sources.isEmpty else {
            phase = .failed(message: DocumentStrings.noPages)
            return
        }
        guard sources.count <= maxPages else {
            phase = .failed(message: DocumentStrings.tooManyPages)
            return
        }
        var pages: [ScannedPage] = []
        for (index, source) in sources.enumerated() {
            phase = .recognising(page: index + 1, total: sources.count)
            do {
                let image = try PageImageEncoder.prepare(source)
                // No text is not a reason to lose the page: the review then happens by hand.
                let text = (try? await recognizer.text(in: image)) ?? ""
                pages.append(ScannedPage(jpeg: try PageImageEncoder.jpeg(from: image), text: text))
            } catch {
                phase = .failed(message: DocumentStrings.unreadablePage)
                return
            }
        }
        do {
            _ = try await uploads.enqueue(pages: pages, workspaceID: workspaceID)
            phase = .finished
        } catch {
            phase = .failed(message: Self.message(for: error))
        }
    }

    public func reset() {
        phase = .idle
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
