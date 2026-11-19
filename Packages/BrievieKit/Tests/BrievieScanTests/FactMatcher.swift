import Foundation

/// Whether a fact of a letter survived recognition, tolerant only where OCR legitimately varies.
///
/// Everything: case, accents and spacing (line breaks included) do not count. Amounts, dates and any phrase
/// with a digit in it: exact after that, so a misread number never passes. Names and phrases without digits
/// (sender, addressee, "zolang de voorraad strekt"): also the usual confusions (1/l, 0/o, | /l), punctuation
/// and apostrophes are ignored, and one wrong, missing or extra character per ten is allowed.
enum FactMatcher {
    static func found(_ fact: LetterFixture.Fact, in text: String) -> Bool {
        let haystack = normalized(text)
        let needle = normalized(fact.text)
        if isExact(fact) { return haystack.contains(needle) }
        let looseNeedle = loose(needle)
        return distance(of: looseNeedle, inside: loose(haystack)) <= allowedErrors(for: looseNeedle)
    }

    static func isExact(_ fact: LetterFixture.Fact) -> Bool {
        fact.kind == .amount || fact.kind == .date || fact.text.contains(where: \.isNumber)
    }

    /// The recognised line closest to `fact`, for the report of what was read instead.
    static func closestLine(to fact: LetterFixture.Fact, in text: String) -> String {
        let needle = loose(normalized(fact.text))
        let lines = text.split(separator: "\n").map(String.init)
        return lines.min { first, second in
            distance(of: needle, inside: loose(normalized(first)))
                < distance(of: needle, inside: loose(normalized(second)))
        } ?? ""
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func loose(_ text: String) -> [Character] {
        text.compactMap { character -> Character? in
            switch character {
            case "1", "|", "!": "l"
            case "0": "o"
            case ".", ",", "'", "\u{2019}", "`", "\"", ":", ";": nil
            default: character
            }
        }
    }

    private static func allowedErrors(for needle: [Character]) -> Int {
        max(1, needle.count / 10)
    }

    /// The fewest edits that turn `needle` into some stretch of `text` (approximate substring matching).
    static func distance(of needle: [Character], inside text: [Character]) -> Int {
        costs(of: needle, endingIn: text).min() ?? needle.count
    }

    /// Per position of `text`: the fewest edits that turn `needle` into a stretch of `text` ending there.
    static func costs(of needle: [Character], endingIn text: [Character]) -> [Int] {
        guard !needle.isEmpty else { return Array(repeating: 0, count: text.count) }
        // previous[i]: edits for needle[..<i] ending at the previous position of text; a match may start anywhere.
        var previous = Array(0...needle.count)
        var result: [Int] = []
        result.reserveCapacity(text.count)
        for character in text {
            var current = [0]
            for index in 1...needle.count {
                let substitution = previous[index - 1] + (needle[index - 1] == character ? 0 : 1)
                current.append(min(substitution, previous[index] + 1, current[index - 1] + 1))
            }
            result.append(current[needle.count])
            previous = current
        }
        return result
    }
}
