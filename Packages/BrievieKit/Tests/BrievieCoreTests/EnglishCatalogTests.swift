import Foundation
import Testing

/// English is a full language of the app, not a bonus: a key without an English value, or an English value
/// whose placeholders differ from the Dutch one (a wrong `%@` crashes at run time), fails here and so fails CI.
@Suite struct EnglishCatalogTests {
    private struct Catalog {
        let name: String
        let strings: [String: [String: Any]]

        /// Every text of one language for a key: the plain value, or each plural form.
        func texts(_ key: String, language: String) -> [String: String] {
            let localization = (strings[key]?["localizations"] as? [String: Any])?[language] as? [String: Any]
            if let value = (localization?["stringUnit"] as? [String: Any])?["value"] as? String { return ["": value] }
            let plural = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
            return plural.compactMapValues { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
                .compactMapValues { $0["value"] as? String }
        }
    }

    private static func catalogs(sourceFile: String = #filePath) throws -> [Catalog] {
        var package = URL(fileURLWithPath: sourceFile)
        for _ in 0..<3 { package.deleteLastPathComponent() } // Tests/BrievieCoreTests -> package root
        let app = package.deletingLastPathComponent().deletingLastPathComponent().appending(path: "App")
        let urls = ["BrievieCore", "FeatureDocuments", "FeaturePairing", "FeatureWorkspace"]
            .map { package.appending(path: "Sources/\($0)/Resources/Localizable.xcstrings") }
            + [app.appending(path: "Localizable.xcstrings"), app.appending(path: "InfoPlist.xcstrings")]
        return try urls.map { url in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = object?["strings"] as? [String: [String: Any]] ?? [:]
            return Catalog(name: url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent,
                           strings: strings)
        }
    }

    /// `%@`, `%d`, `%lld`, `%1$@`, `%2$d`, `%.1f`, sorted, so the order of words in a sentence may differ.
    static func placeholders(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUf]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    @Test func theCatalogsAreFound() throws {
        let catalogs = try Self.catalogs()
        #expect(catalogs.count == 6)
        for catalog in catalogs { #expect(!catalog.strings.isEmpty, "\(catalog.name) has no keys") }
    }

    @Test func everyKeyHasAnEnglishValue() throws {
        for catalog in try Self.catalogs() {
            for key in catalog.strings.keys.sorted() {
                let dutch = catalog.texts(key, language: "nl")
                let english = catalog.texts(key, language: "en")
                #expect(!english.isEmpty, "\(catalog.name): \(key) has no English value")
                #expect(english.values.allSatisfy { !$0.isEmpty }, "\(catalog.name): \(key) has an empty English value")
                #expect(Set(english.keys) == Set(dutch.keys), "\(catalog.name): \(key) has other plural forms")
            }
        }
    }

    @Test func englishKeepsTheDutchPlaceholders() throws {
        for catalog in try Self.catalogs() {
            for key in catalog.strings.keys.sorted() {
                let dutch = catalog.texts(key, language: "nl")
                let english = catalog.texts(key, language: "en")
                let expected = Self.placeholders(in: dutch["other"] ?? dutch[""] ?? "")
                for (form, text) in english {
                    #expect(
                        Self.placeholders(in: text) == expected,
                        "\(catalog.name): \(key) [\(form)] has other placeholders than Dutch \(expected)"
                    )
                }
            }
        }
    }

    @Test func thePlaceholderReaderSeesEveryKind() {
        #expect(Self.placeholders(in: "%1$@ en %2$d, %lld, %@, %d") == ["%1$@", "%2$d", "%@", "%d", "%lld"])
        #expect(Self.placeholders(in: "100% sure, 50 %").isEmpty)
        #expect(Self.placeholders(in: "%.1f en %3$@") == ["%.1f", "%3$@"])
        #expect(Self.placeholders(in: "plain text").isEmpty)
    }
}
