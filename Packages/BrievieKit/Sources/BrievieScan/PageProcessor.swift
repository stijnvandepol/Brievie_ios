import CoreGraphics
import Foundation

/// One page after processing: what is uploaded, a small preview of the same pixels, and how it was turned.
public struct ProcessedPage: Equatable, Sendable {
    public let page: ScannedPage
    /// A small JPEG of the uploaded pixels, for the preview before saving.
    public let preview: Data
    /// The turn applied to the page as it came in.
    public let turn: QuarterTurn
    /// `true` when the text decided the turn (not the user), and it is not `.upright`.
    public let turnedAutomatically: Bool

    public init(page: ScannedPage, preview: Data, turn: QuarterTurn, turnedAutomatically: Bool) {
        self.page = page
        self.preview = preview
        self.turn = turn
        self.turnedAutomatically = turnedAutomatically
    }
}

/// Decodes a page, turns it upright, reads its text and encodes it: the JPEG holds upright pixels (no EXIF
/// orientation) and the text is the text of that upright page.
///
/// A scanner page is upright only as far as the phone knew which way was up: held flat above a letter on a
/// table, it does not know, and the page comes out turned. So the first reading decides the turn
/// (`PageOrientation`); an upright page costs nothing extra, a turned page is read once more after turning, so
/// the kept text is in the right order. Runs off the main actor and stops when its task is cancelled.
public struct PageProcessor: Sendable {
    private let recognizer: any PageTextRecognizer

    public init(recognizer: any PageTextRecognizer = VisionTextRecognizer()) {
        self.recognizer = recognizer
    }

    /// - Parameter turn: the turn the user chose; `nil` lets the text decide.
    @concurrent
    public func process(_ source: PageSource, turn: QuarterTurn? = nil) async throws -> ProcessedPage {
        try Task.checkCancellation()
        let decoded = try PageImageEncoder.prepare(source)
        var image = try PageImageEncoder.rotated(decoded, by: turn ?? .upright)
        try Task.checkCancellation()
        // No text is not a reason to lose the page: the review then happens by hand.
        var lines = await read(image)
        var applied = turn ?? .upright
        var automatic = false
        if turn == nil, let correction = PageOrientation.correction(for: lines), correction != .upright {
            try Task.checkCancellation()
            image = try PageImageEncoder.rotated(image, by: correction)
            lines = await read(image)
            applied = correction
            automatic = true
        }
        try Task.checkCancellation()
        return ProcessedPage(
            page: ScannedPage(
                jpeg: try PageImageEncoder.jpeg(from: image), text: lines.map(\.text).joined(separator: "\n")
            ),
            preview: try PageImageEncoder.preview(of: image),
            turn: applied,
            turnedAutomatically: automatic
        )
    }

    private func read(_ image: CGImage) async -> [RecognizedLine] {
        (try? await recognizer.lines(in: image)) ?? []
    }
}
