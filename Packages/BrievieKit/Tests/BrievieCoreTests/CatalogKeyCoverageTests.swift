import Foundation
import Testing

/// A key used in a view without a default value shows up as the raw key when the catalog lacks it
/// (`swift test` does not compile catalogs, so this scans the sources and reads the catalogs directly).
@Suite struct CatalogKeyCoverageTests {
    @Test(arguments: ["BrievieCore", "FeatureDocuments", "FeaturePairing", "FeatureWorkspace"])
    func everyKeyTheCodeUsesHasADutchValueInItsCatalog(target: String) throws {
        let used = try CatalogKeyScan.usedKeys(target: target)
        let catalog = try CatalogKeyScan.catalogKeys(target: target)

        #expect(!used.isEmpty, "The scan found no keys in \(target): the patterns or the path are wrong")
        for key in used.sorted() {
            let value = catalog[key]
            #expect(value?.isEmpty == false, "\(target): key \(key) has no Dutch value in its catalog")
        }
    }

    @Test func theAppTargetsKeysHaveADutchValueInTheAppCatalog() throws {
        let used = try CatalogKeyScan.usedAppKeys()
        let catalog = try CatalogKeyScan.appCatalogKeys()

        #expect(used.contains("lock.title"), "The scan found no keys in App/: the patterns or the path are wrong")
        for key in used.sorted() {
            #expect(catalog[key]?.isEmpty == false, "App: key \(key) has no Dutch value in App/Localizable.xcstrings")
        }
    }

    @Test func theScanFindsBothKeysOfATernary() {
        let source = """
            Text(isManual ? "pairing.instructions.manual" : "pairing.instructions", bundle: .module)
            Text(flag ? "plain text" : "other text")
            """

        #expect(CatalogKeyScan.keys(in: source) == ["pairing.instructions.manual", "pairing.instructions"])
    }

    @Test func theScanSeesViewKeysAndStringKeysAlike() throws {
        let pairing = try CatalogKeyScan.usedKeys(target: "FeaturePairing")

        #expect(pairing.contains("pairing.title"))
        #expect(pairing.contains("pairing.retry"))
        #expect(pairing.contains("pairing.error.notBrievie"))
    }
}
