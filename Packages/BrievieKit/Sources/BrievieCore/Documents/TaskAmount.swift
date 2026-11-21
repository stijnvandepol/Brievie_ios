import Foundation

/// The amount of a task (a payment) as the API writes it: a decimal string with a point and at most two
/// decimals ("1234.56"), empty when unknown. Never a `Double`, never the phone's notation on the wire.
public enum TaskAmount {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// The API's text as a number; `nil` for an empty or unreadable text (never 0).
    public static func parse(api text: String) -> Decimal? {
        guard text.wholeMatch(of: /\d{1,10}(\.\d{1,2})?/) != nil else { return nil }
        return Decimal(string: text, locale: posix)
    }

    /// The amount as the API reads it: two decimals, a point, no grouping.
    public static func api(_ amount: Decimal) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(posix))
    }

    /// An amount the user typed in their own notation ("1.234,56" on a Dutch phone, "1,234.56" on an English
    /// one), with or without the euro sign; `nil` for text that is not a positive amount with at most two
    /// decimals.
    public static func parse(input: String, locale: Locale) -> Decimal? {
        let text = String(input.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) && $0 != "€" })
        guard !text.isEmpty else { return nil }
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let parts = text.components(separatedBy: decimal)
        guard parts.count <= 2, var whole = parts.first else { return nil }
        var fraction = parts.count == 2 ? parts[1] : nil
        var groups = whole.components(separatedBy: grouping)
        // "12.50" on a Dutch phone: one grouping mark followed by one or two digits is meant as the decimals.
        if fraction == nil, groups.count == 2, let last = groups.last, (1...2).contains(last.count) {
            fraction = last
            groups = [groups[0]]
        }
        if groups.count > 1 {
            guard let first = groups.first, (1...3).contains(first.count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        whole = groups.joined()
        let canonical = fraction.map { "\(whole).\($0)" } ?? whole
        return parse(api: canonical)
    }
}
