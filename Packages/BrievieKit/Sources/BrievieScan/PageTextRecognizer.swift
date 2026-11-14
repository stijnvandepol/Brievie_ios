import CoreGraphics
import Foundation
import Vision

/// Recognises the text on a page. Runs on the device: the image never leaves it for this.
public protocol PageTextRecognizer: Sendable {
    /// The text on the page, lines separated by `\n`; empty when there is none.
    func text(in image: CGImage) async throws -> String
}

/// Apple Vision, accurate mode, Dutch when the system supports it.
public struct VisionTextRecognizer: PageTextRecognizer {
    public init() {}

    public func text(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let dutch = request.supportedRecognitionLanguages.first { $0.languageCode?.identifier == "nl" }
        if let dutch {
            request.recognitionLanguages = [dutch]
        } else {
            request.automaticallyDetectsLanguage = true
        }

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            throw ScanError.recognitionFailed
        }
        return Self.lines(in: observations).joined(separator: "\n")
    }

    /// Top to bottom, then left to right. Vision's origin is the lower-left corner.
    private static func lines(in observations: [RecognizedTextObservation]) -> [String] {
        observations
            .sorted { first, second in
                let firstBox = first.boundingBox
                let secondBox = second.boundingBox
                // Lines on (almost) the same height read left to right.
                if abs(firstBox.origin.y - secondBox.origin.y) > min(firstBox.height, secondBox.height) / 2 {
                    return firstBox.origin.y > secondBox.origin.y
                }
                return firstBox.origin.x < secondBox.origin.x
            }
            .compactMap { $0.topCandidates(1).first?.string }
    }
}
