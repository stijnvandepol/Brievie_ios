import Foundation

/// The `Accept-Language` every request to the server carries, so the server's error messages and texts come in
/// the language the user reads (the server honours it; it falls back to Dutch for a language it does not know).
public enum AcceptLanguageHeader {
    static let name = "Accept-Language"
    /// A short list is enough: the server picks the first language it speaks.
    static let maximumLanguages = 4

    /// `"en-GB, nl-NL;q=0.9"` for the user's preferred languages in order of preference. `nil` when none is a
    /// well-formed language tag: the app sends nothing rather than a value the server would ignore.
    public static func value(preferred languages: [String]) -> String? {
        let tags = languages.filter(isLanguageTag).prefix(maximumLanguages)
        guard !tags.isEmpty else { return nil }
        return tags.enumerated().map { index, tag in
            index == 0 ? tag : "\(tag);q=\(String(format: "%.1f", max(0.1, 1.0 - 0.1 * Double(index))))"
        }.joined(separator: ", ")
    }

    /// The header for the languages in the iPhone's settings right now.
    public static func current() -> String? {
        value(preferred: Locale.preferredLanguages)
    }

    /// BCP 47 shape: letters and digits in groups of one to eight, joined by hyphens (`en`, `en-GB`, `zh-Hans-CN`).
    private static func isLanguageTag(_ tag: String) -> Bool {
        tag.range(of: #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$"#, options: .regularExpression) != nil
    }
}
