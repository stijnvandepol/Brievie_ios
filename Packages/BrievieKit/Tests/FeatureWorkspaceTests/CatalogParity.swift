import Foundation

/// Reads a String Catalog straight from the source tree: `swift test` does not compile catalogs.
enum CatalogParity {
    static func dutchValue(forKey key: String, target: String, sourceFile: String = #filePath) throws -> String? {
        var url = URL(fileURLWithPath: sourceFile)
        for _ in 0..<3 { url.deleteLastPathComponent() } // Tests/<Target>Tests/File.swift -> package root
        url.append(path: "Sources/\(target)/Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (object as? [String: Any])?["strings"] as? [String: Any]
        let entry = strings?[key] as? [String: Any]
        let dutch = (entry?["localizations"] as? [String: Any])?["nl"] as? [String: Any]
        return (dutch?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// The plural forms (`one`, `other`, ...) of a key with plural variations.
    static func dutchPlural(
        forKey key: String, target: String, sourceFile: String = #filePath
    ) throws -> [String: String] {
        var url = URL(fileURLWithPath: sourceFile)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        url.append(path: "Sources/\(target)/Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (object as? [String: Any])?["strings"] as? [String: Any]
        let dutch = ((strings?[key] as? [String: Any])?["localizations"] as? [String: Any])?["nl"] as? [String: Any]
        let plural = (dutch?["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        return plural.compactMapValues { form in
            ((form as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }
}
