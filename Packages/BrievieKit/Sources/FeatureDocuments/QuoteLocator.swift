import Foundation

/// Finds where a quote stands in the letter text, to highlight it.
///
/// Looser than the server's check on purpose (case, accents and line breaks are ignored): it only finds what
/// to highlight; it never decides whether a value can be trusted.
enum QuoteLocator {
    static func ranges(of quote: String, in text: String) -> [Range<String.Index>] {
        let needle = fold(quote).map(\.character)
        let haystack = fold(text)
        guard !needle.isEmpty, haystack.count >= needle.count else { return [] }

        var ranges: [Range<String.Index>] = []
        var start = 0
        while start + needle.count <= haystack.count {
            if (0..<needle.count).allSatisfy({ haystack[start + $0].character == needle[$0] }) {
                let last = haystack[start + needle.count - 1]
                ranges.append(haystack[start].range.lowerBound..<last.range.upperBound)
                start += needle.count
            } else {
                start += 1
            }
        }
        return ranges
    }

    /// The text as comparable characters, each with the range it came from. A run of whitespace becomes one
    /// space; leading and trailing whitespace is dropped.
    private static func fold(_ text: String) -> [(character: Character, range: Range<String.Index>)] {
        var result: [(character: Character, range: Range<String.Index>)] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            if character.isWhitespace {
                if let last = result.last, last.character == " " {
                    result[result.count - 1].range = last.range.lowerBound..<next
                } else if !result.isEmpty {
                    result.append((" ", index..<next))
                }
            } else {
                let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                for (offset, piece) in folded.enumerated() {
                    // A character that folds into several (ß -> ss) keeps one source range.
                    result.append((piece, offset == 0 ? index..<next : next..<next))
                }
            }
            index = next
        }
        if let last = result.last, last.character == " " { result.removeLast() }
        return result
    }
}
