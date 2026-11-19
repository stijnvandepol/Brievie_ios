import BrievieCore
import Foundation
import Testing

/// `brievie://server#v=1&url=…&ca_sha256=…&pairing=…`, as the host's `server_link` writes it (form-encoded).
@Suite struct ServerLinkTests {
    static let pairing = "0b7e2f4c-5d1a-4e8b-9c3f-6a2d8e1f4b70"
    static let pin = String(repeating: "ab", count: 32)
    static let local = "url=https%3A%2F%2Fbrievie.local"
    static let lan = "url=https%3A%2F%2F192.168.1.4"
    static let hostLink = "v=1&\(local)&\(lan)&ca_sha256=\(pin)&pairing=\(pairing)"

    private func link(_ fragment: String) throws -> URL {
        try #require(URL(string: "brievie://server#\(fragment)"))
    }

    private func parse(_ fragment: String) throws -> ServerLink {
        try ServerLink.parse(try link(fragment))
    }

    private func refusal(_ fragment: String) throws -> ServerLinkError? {
        let url = try link(fragment)
        do throws(ServerLinkError) {
            _ = try ServerLink.parse(url)
            return nil
        } catch {
            return error
        }
    }

    @Test func parsesTheHostsLink() throws {
        let parsed = try parse(Self.hostLink)

        #expect(parsed.urls == [
            try #require(URL(string: "https://brievie.local")), try #require(URL(string: "https://192.168.1.4"))
        ])
        #expect(parsed.caSHA256 == Self.pin)
        #expect(parsed.pairingID == UUID(uuidString: Self.pairing))
    }

    @Test func aLinkWithoutAPinIsAPublicCertificateServer() throws {
        let parsed = try parse("v=1&url=https%3A%2F%2Fbrievie.example.nl&pairing=\(Self.pairing)")

        #expect(parsed.caSHA256 == nil)
        #expect(parsed.urls.map(\.absoluteString) == ["https://brievie.example.nl"])
    }

    @Test func unknownKeysAreIgnored() throws {
        #expect(try parse(Self.hostLink + "&future=x&v2=3&novalue") == parse(Self.hostLink))
    }

    @Test func aCodeInTheLinkIsIgnored() throws {
        let parsed = try parse(Self.hostLink + "&code=ABCD-EFGH")

        #expect(parsed == (try parse(Self.hostLink)))
        let stored = Mirror(reflecting: parsed).children.map { String(describing: $0.value) }
        #expect(!stored.contains { $0.contains("ABCD-EFGH") || $0.contains("ABCDEFGH") })
    }

    @Test func theUpperCasePinIsStoredLowerCase() throws {
        let parsed = try parse("v=1&\(Self.local)&ca_sha256=\(Self.pin.uppercased())&pairing=\(Self.pairing)")

        #expect(parsed.caSHA256 == Self.pin)
    }

    @Test func theUpperCasePairingIdIsAccepted() throws {
        let parsed = try parse("v=1&\(Self.local)&pairing=\(Self.pairing.uppercased())")

        #expect(parsed.pairingID == UUID(uuidString: Self.pairing))
    }

    @Test(arguments: ["", "&pairing=", "&pairing=abc", "&pairing=\(pairing)&pairing=\(pairing)"])
    func pairingIdRules(pairing: String) throws {
        #expect(try refusal("v=1&\(Self.local)\(pairing)") == .invalid)
    }

    @Test(arguments: [
        "http%3A%2F%2Fbrievie.local", "https%3A%2F%2Fuser%3Apw%40brievie.local", "https%3A%2F%2Fuser%40brievie.local",
        "ftp%3A%2F%2Fx", "%20", "", "https%3A%2F%2F", "https%3A%2F%2Fbrievie+local"
    ])
    func aBadUrlRefusesTheWholeLink(url: String) throws {
        #expect(try refusal("v=1&url=\(url)&pairing=\(Self.pairing)") == .invalid)
        #expect(try refusal("v=1&\(Self.local)&url=\(url)&pairing=\(Self.pairing)") == .invalid)
    }

    @Test func versionRules() throws {
        let rest = "\(Self.local)&pairing=\(Self.pairing)"
        #expect(try refusal("") == .invalid)
        #expect(try refusal("v=2&\(rest)") == .unsupportedVersion)
        #expect(try refusal("v=1&v=1&\(rest)") == .invalid)
        #expect(try refusal(rest) == .invalid)
        #expect(try refusal("v=&\(rest)") == .invalid)
        #expect(try refusal("v=one&\(rest)") == .invalid)
    }

    @Test func pinRules() throws {
        let rest = "\(Self.local)&pairing=\(Self.pairing)"
        let pins = [
            String(repeating: "a", count: 63), String(repeating: "a", count: 65), String(repeating: "g", count: 64), ""
        ]
        for pin in pins {
            #expect(try refusal("v=1&\(rest)&ca_sha256=\(pin)") == .invalid, "pin \(pin)")
        }
        #expect(try refusal("v=1&\(rest)&ca_sha256=\(Self.pin)&ca_sha256=\(Self.pin)") == .invalid)
    }

    @Test func atMostEightAddressesAndABoundedFragment() throws {
        let eight = Array(repeating: Self.local, count: 8).joined(separator: "&")
        #expect(try parse("v=1&\(eight)&pairing=\(Self.pairing)").urls.count == 8)
        #expect(try refusal("v=1&\(eight)&\(Self.local)&pairing=\(Self.pairing)") == .invalid)

        let padding = "x=" + String(repeating: "a", count: 5000)
        #expect(try refusal("\(Self.hostLink)&\(padding)") == .invalid)
        let manyURLs = Array(repeating: Self.local, count: 500).joined(separator: "&")
        #expect(try refusal("v=1&\(manyURLs)&pairing=\(Self.pairing)") == .invalid)
    }

    @Test func aLongAddressIsRefused() throws {
        let long = "https%3A%2F%2F" + String(repeating: "a", count: 2050) + ".nl"
        #expect(try refusal("v=1&url=\(long)&pairing=\(Self.pairing)") == .invalid)
    }

    @Test func malformedPercentEscapesAreInvalidNotACrash() throws {
        // Foundation stores "%ZZ" as "%25ZZ"; "%E9" alone is not UTF-8 and cannot be decoded at all.
        #expect(try refusal("v=1&url=%ZZ&pairing=\(Self.pairing)") == .invalid)
        #expect(try refusal("v=1&url=%E9&pairing=\(Self.pairing)") == .invalid)
        #expect(try refusal("v=1&\(Self.local)&pairing=%E9") == .invalid)
    }

    @Test func otherLinksAreNotServerLinks() throws {
        let task = try #require(URL(string: "brievie://task/\(Self.pairing)"))
        let web = try #require(URL(string: "https://server#\(Self.hostLink)"))
        let upper = try #require(URL(string: "BRIEVIE://Server#\(Self.hostLink)"))

        #expect(!ServerLink.isServerLink(task))
        #expect(!ServerLink.isServerLink(web))
        #expect(ServerLink.isServerLink(upper))
        #expect(throws: ServerLinkError.notAServerLink) { try ServerLink.parse(task) }
        #expect(throws: ServerLinkError.notAServerLink) { try ServerLink.parse(web) }
        #expect(try ServerLink.parse(upper) == parse(Self.hostLink))
    }

    @Test func aPathOrQueryOnTheLinkIsIgnored() throws {
        let url = try #require(URL(string: "brievie://server/x?code=ABCD-EFGH#\(Self.hostLink)"))

        #expect(try ServerLink.parse(url) == parse(Self.hostLink))
    }

    /// The address form itself; the sheet shows it for the located address (`PairingServiceLinkTests`).
    @Test func displayAddressOfAURLShowsHostAndPortOnly() throws {
        let cases = [
            ("https://brievie.local:8443/pad", "brievie.local:8443"), ("https://brievie.example.nl:443", "brievie.example.nl"),
            ("https://[2001:db8::1]:8443", "[2001:db8::1]:8443"), ("https://bücher.example", "xn--bcher-kva.example")
        ]
        for (text, shown) in cases {
            #expect(ServerLink.displayAddress(of: try #require(URL(string: text))) == shown)
        }
    }
}
