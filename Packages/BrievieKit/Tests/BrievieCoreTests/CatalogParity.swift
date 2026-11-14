import Foundation

/// Reads a String Catalog straight from the source tree. `swift test` does not compile catalogs, so tests
/// compare the catalog's Dutch value with what the code resolves.
enum CatalogParity {
    static func dutchValue(forKey key: String, target: String, sourceFile: String = #filePath) throws -> String? {
        var url = URL(fileURLWithPath: sourceFile)
        for _ in 0..<3 { url.deleteLastPathComponent() } // Tests/BrievieCoreTests -> package root
        url.append(path: "Sources/\(target)/Resources/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (object as? [String: Any])?["strings"] as? [String: Any]
        let entry = strings?[key] as? [String: Any]
        let dutch = (entry?["localizations"] as? [String: Any])?["nl"] as? [String: Any]
        return (dutch?["stringUnit"] as? [String: Any])?["value"] as? String
    }
}

/// Finds the String Catalog keys the code asks for, so a key without an entry fails a test instead of
/// reaching the screen as a raw key.
enum CatalogKeyScan {
    private static let keyShape = #"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$"#

    /// The keys used in one Swift source: `Text("key"` (with or without `bundle:`), `String(localized: "key"`,
    /// and both branches of a ternary of two key-shaped literals (`cond ? "a.key" : "b.key"`).
    static func keys(in source: String) -> Set<String> {
        let range = NSRange(source.startIndex..., in: source)
        let patterns = [
            #"Text\(\s*"([^"\\]+)"\s*[,)]"#,
            #"String\(\s*localized:\s*"([^"\\]+)""#,
            #"\?\s*"([^"\\]+)"\s*:\s*"([^"\\]+)""#
        ]
        var keys: Set<String> = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: source, range: range) {
                for group in 1..<match.numberOfRanges {
                    if let found = Range(match.range(at: group), in: source) {
                        keys.insert(String(source[found]))
                    }
                }
            }
        }
        // Ternaries of ordinary strings are not keys.
        return keys.filter { $0.range(of: keyShape, options: .regularExpression) != nil }
    }

    /// Every key used in the Swift files under `Sources/<target>`.
    static func usedKeys(target: String, sourceFile: String = #filePath) throws -> Set<String> {
        try usedKeys(directory: packageRoot(sourceFile).appending(path: "Sources/\(target)"))
    }

    /// Every key used in the app target's Swift files (`App/*.swift`).
    static func usedAppKeys(sourceFile: String = #filePath) throws -> Set<String> {
        try usedKeys(directory: appRoot(sourceFile))
    }

    static func catalogKeys(target: String, sourceFile: String = #filePath) throws -> [String: String] {
        try catalog(at: packageRoot(sourceFile).appending(path: "Sources/\(target)/Resources/Localizable.xcstrings"))
    }

    static func appCatalogKeys(sourceFile: String = #filePath) throws -> [String: String] {
        try catalog(at: appRoot(sourceFile).appending(path: "Localizable.xcstrings"))
    }

    private static func usedKeys(directory: URL) throws -> Set<String> {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var keys: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            keys.formUnion(Self.keys(in: try String(contentsOf: file, encoding: .utf8)))
        }
        return keys
    }

    private static func catalog(at url: URL) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (object as? [String: Any])?["strings"] as? [String: Any] ?? [:]
        return strings.compactMapValues { entry in
            let dutch = ((entry as? [String: Any])?["localizations"] as? [String: Any])?["nl"] as? [String: Any]
            return (dutch?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }

    private static func packageRoot(_ sourceFile: String) -> URL {
        var url = URL(fileURLWithPath: sourceFile)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }

    /// `Packages/BrievieKit` -> repository root -> `App`.
    private static func appRoot(_ sourceFile: String) -> URL {
        packageRoot(sourceFile).deletingLastPathComponent().deletingLastPathComponent().appending(path: "App")
    }
}
