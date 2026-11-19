import Foundation

/// A turn of a page in steps of 90 degrees, clockwise as seen on screen.
public enum QuarterTurn: Int, Sendable, CaseIterable {
    case upright = 0
    case clockwise = 1
    case upsideDown = 2
    case counterClockwise = 3

    /// This turn followed by `other`.
    public func adding(_ other: QuarterTurn) -> QuarterTurn {
        QuarterTurn(rawValue: (rawValue + other.rawValue) % 4) ?? .upright
    }

    /// A quarter turn either way makes a portrait page landscape and back.
    public var swapsSides: Bool { self == .clockwise || self == .counterClockwise }
}

/// One line of text as the recogniser read it, with the direction it reads in.
public struct RecognizedLine: Equatable, Sendable {
    public let text: String
    /// 0...1, as the recogniser reports it.
    public let confidence: Double
    /// From the start of the line to its end, in pixels of the image the line was read in, y up (Vision's
    /// convention). Upright text points right: positive x, y near 0.
    public let baselineX: Double
    public let baselineY: Double

    public init(text: String, confidence: Double, baselineX: Double, baselineY: Double) {
        self.text = text
        self.confidence = confidence
        self.baselineX = baselineX
        self.baselineY = baselineY
    }
}

/// Which way is up, decided from the text itself.
///
/// Apple's text recogniser (revision 3, the only one from iOS 18) reads a page in any quarter turn and reports
/// each line's corners, so one reading of the page as it came in tells which way its lines run. Every line
/// votes for the turn that makes it read left to right, weighted by its letters and digits times the
/// recogniser's confidence. Only a clear majority over enough trusted text turns the page.
public enum PageOrientation {
    /// Letters and digits (times confidence) a page needs before it is turned automatically.
    public static let minimumWeight = 12.0
    /// The share of that weight the winning direction needs.
    public static let requiredShare = 0.8
    /// Lines the recogniser trusts less than this do not vote.
    public static let minimumConfidence = 0.4

    /// The turn that makes the page upright; `nil` when the text does not say so clearly (too little text,
    /// or lines in several directions), in which case the page stays as it is.
    public static func correction(for lines: [RecognizedLine]) -> QuarterTurn? {
        var weights: [QuarterTurn: Double] = [:]
        for line in lines where line.confidence >= minimumConfidence {
            let characters = line.text.unicodeScalars.filter(CharacterSet.alphanumerics.contains).count
            guard characters > 0, line.baselineX != 0 || line.baselineY != 0 else { continue }
            weights[turn(readingAlong: line), default: 0] += Double(characters) * line.confidence
        }
        let total = weights.values.reduce(0, +)
        guard
            total >= minimumWeight,
            let winner = weights.max(by: { $0.value < $1.value }),
            winner.value >= total * requiredShare
        else { return nil }
        return winner.key
    }

    /// The turn after which `line` reads left to right.
    private static func turn(readingAlong line: RecognizedLine) -> QuarterTurn {
        if abs(line.baselineX) >= abs(line.baselineY) {
            return line.baselineX > 0 ? .upright : .upsideDown
        }
        // Reading downwards: the page was turned a quarter clockwise, so it goes back counter-clockwise.
        return line.baselineY < 0 ? .counterClockwise : .clockwise
    }
}
