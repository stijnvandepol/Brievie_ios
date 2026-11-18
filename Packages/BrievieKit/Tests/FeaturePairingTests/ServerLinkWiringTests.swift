import BrievieCore
import Foundation
import Testing

/// What the link sheet relies on outside its model: the URL scheme, the routing rule and the agreed texts.
/// (The view and `RootView` have no unit tests, as for the other screens.)
@Suite struct ServerLinkWiringTests {
    private static func repositoryRoot(sourceFile: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: sourceFile)
        // <root>/Packages/BrievieKit/Tests/FeaturePairingTests/File.swift
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    @Test func theBrievieSchemeIsRegistered() throws {
        let data = try Data(contentsOf: Self.repositoryRoot().appending(path: "App/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let types = try #require(plist?["CFBundleURLTypes"] as? [[String: Any]])

        #expect(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.contains("brievie"))
    }

    @Test func taskLinksAreNotServerLinks() throws {
        let task = try #require(URL(string: "brievie://task/0b7e2f4c-5d1a-4e8b-9c3f-6a2d8e1f4b70"))
        let server = try #require(URL(string: "brievie://server#v=1"))

        #expect(!ServerLink.isServerLink(task))
        #expect(ServerLink.isServerLink(server))
    }

    @Test func viewTextsInTheCatalogUseTheAgreedWording() throws {
        let expected = [
            "pairing.link.title": "Koppelen met je server",
            "pairing.link.intro": "Je hebt een link van je Brievie-server geopend. Hiermee koppel je deze telefoon.",
            "pairing.link.address.label": "Adres van de server",
            "pairing.link.address.check":
                "Is dit niet het adres van jouw server? Sluit dan dit scherm. Er is dan niets verstuurd.",
            "pairing.link.code.label": "Koppelcode",
            "pairing.link.code.prompt": "8 tekens",
            "pairing.link.code.footer": "Typ de code die op de webpagina staat. Hoofdletters en het streepje maken "
                + "niet uit. De code zelf gaat niet over het netwerk.",
            "pairing.link.code.hint": "Typ de acht tekens van de koppelcode.",
            "pairing.link.submit": "Koppel",
            "pairing.link.close": "Sluit",
            "pairing.link.searching": "Server zoeken…"
        ]
        for (key, value) in expected {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeaturePairing") == value, "\(key)")
        }
    }
}
