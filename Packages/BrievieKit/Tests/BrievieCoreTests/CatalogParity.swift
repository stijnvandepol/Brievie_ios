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
    /// `Text("key", bundle:` and `String(localized: "key"` in every Swift file of `Sources/<target>`.
    static func usedKeys(target: String, sourceFile: String = #filePath) throws -> Set<String> {
        let directory = packageRoot(sourceFile).appending(path: "Sources/\(target)")
        let patterns = [#"Text\(\s*"([^"\\]+)"\s*,\s*bundle:"#, #"String\(\s*localized:\s*"([^"\\]+)""#]
        let expressions = try patterns.map { try NSRegularExpression(pattern: $0) }
        var keys: Set<String> = []
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for expression in expressions {
                for match in expression.matches(in: source, range: range) {
                    if let key = Range(match.range(at: 1), in: source) {
                        keys.insert(String(source[key]))
                    }
                }
            }
        }
        return keys
    }

    static func catalogKeys(target: String, sourceFile: String = #filePath) throws -> [String: String] {
        let url = packageRoot(sourceFile).appending(path: "Sources/\(target)/Resources/Localizable.xcstrings")
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
}
