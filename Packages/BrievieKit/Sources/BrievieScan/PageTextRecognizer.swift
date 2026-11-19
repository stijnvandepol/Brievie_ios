import CoreGraphics
import Foundation
import Vision

/// Recognises the text on a page. Runs on the device: the image never leaves it for this.
public protocol PageTextRecognizer: Sendable {
    /// The lines on the page in reading order (for an upright page), each with the direction it reads in;
    /// empty when there is no text.
    func lines(in image: CGImage) async throws -> [RecognizedLine]
}

extension PageTextRecognizer {
    /// The text on the page, lines separated by `\n`; empty when there is none.
    public func text(in image: CGImage) async throws -> String {
        try await lines(in: image).map(\.text).joined(separator: "\n")
    }
}

/// Apple Vision, accurate mode, Dutch when the system supports it.
public struct VisionTextRecognizer: PageTextRecognizer {
    public init() {}

    public func lines(in image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let dutch = request.supportedRecognitionLanguages.first { $0.languageCode?.identifier == "nl" }
        if let dutch {
            request.recognitionLanguages = [dutch]
        } else {
            request.automaticallyDetectsLanguage = true
        }

        // One recognition at a time in the process: many at once crashed inside Vision (EXC_BAD_ACCESS while
        // TextRecognition released a request, macOS 26.6, about 1 run in 12 of the scan-quality tests).
        await RecognitionQueue.shared.enter()
        let outcome: [RecognizedTextObservation]?
        do {
            outcome = try await request.perform(on: image)
        } catch {
            outcome = nil
        }
        await RecognitionQueue.shared.leave()
        guard let observations = outcome else { throw ScanError.recognitionFailed }
        let width = Double(image.width)
        let height = Double(image.height)
        return Self.ordered(observations).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                baselineX: (observation.bottomRight.x - observation.bottomLeft.x) * width,
                baselineY: (observation.bottomRight.y - observation.bottomLeft.y) * height
            )
        }
    }

    /// Top to bottom, then left to right. Vision's origin is the lower-left corner. Right only for an upright
    /// page: `PageProcessor` turns a page upright before the text that is kept is read.
    private static func ordered(_ observations: [RecognizedTextObservation]) -> [RecognizedTextObservation] {
        observations.sorted { first, second in
            let firstBox = first.boundingBox
            let secondBox = second.boundingBox
            // Lines on (almost) the same height read left to right.
            if abs(firstBox.origin.y - secondBox.origin.y) > min(firstBox.height, secondBox.height) / 2 {
                return firstBox.origin.y > secondBox.origin.y
            }
            return firstBox.origin.x < secondBox.origin.x
        }
    }
}

/// Lets one text recognition run at a time; the others wait their turn, in order.
actor RecognitionQueue {
    static let shared = RecognitionQueue()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
