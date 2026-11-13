@testable import BrievieCore
import Foundation
import Testing

@Suite struct PairingPayloadTests {
    private let hash = String(repeating: "ab", count: 32)

    @Test func parsesPayloadWithCAHash() throws {
        let text = """
        {"v":1,"urls":["https://brievie.local:8443","https://brievie.example.nl"],\
        "code":"ABCD-EFGH","ca_sha256":"\(hash)"}
        """

        let payload = try PairingPayload.parse(text)

        #expect(payload.urls == [
            try #require(URL(string: "https://brievie.local:8443")),
            try #require(URL(string: "https://brievie.example.nl"))
        ])
        #expect(payload.code == "ABCD-EFGH")
        #expect(payload.caSHA256 == hash)
    }

    @Test func parsesPayloadWithNullCAHash() throws {
        let text = #"{"v":1,"urls":["https://brievie.example.nl"],"code":"ABCD-EFGH","ca_sha256":null}"#

        let payload = try PairingPayload.parse(text)

        #expect(payload.urls == [try #require(URL(string: "https://brievie.example.nl"))])
        #expect(payload.caSHA256 == nil)
    }

    @Test func parsesPayloadWithoutCAHashKey() throws {
        let text = #"{"v":1,"urls":["https://brievie.example.nl"],"code":"ABCD-EFGH"}"#

        #expect(try PairingPayload.parse(text).caSHA256 == nil)
    }

    @Test func normalisesUpperCaseHashToLowerCase() throws {
        let upper = hash.uppercased()
        let text = #"{"v":1,"urls":["https://a.nl"],"code":"ABCD-EFGH","ca_sha256":"\#(upper)"}"#

        #expect(try PairingPayload.parse(text).caSHA256 == hash)
    }

    @Test(arguments: [
        "https://nos.nl",
        "WIFI:S:thuis;;",
        "",
        "random text",
        "[1, 2, 3]",
        #"{"urls":["https://a.nl"],"code":"ABCD-EFGH"}"#
    ])
    func rejectsNonBrievieCodes(text: String) {
        #expect(throws: PairingPayloadError.notBrievie) {
            try PairingPayload.parse(text)
        }
    }

    @Test(arguments: [
        #"{"v":2,"urls":["https://a.nl"],"code":"ABCD-EFGH","ca_sha256":null}"#,
        #"{"v":0,"urls":["https://a.nl"],"code":"ABCD-EFGH","ca_sha256":null}"#
    ])
    func rejectsUnsupportedVersion(text: String) {
        #expect(throws: PairingPayloadError.unsupportedVersion) {
            try PairingPayload.parse(text)
        }
    }

    @Test(arguments: [
        // http URL
        #"{"v":1,"urls":["http://brievie.local"],"code":"ABCD-EFGH","ca_sha256":null}"#,
        // one https and one http URL
        #"{"v":1,"urls":["https://a.nl","http://b.nl"],"code":"ABCD-EFGH","ca_sha256":null}"#,
        // URL with userinfo
        #"{"v":1,"urls":["https://u:p@brievie.local"],"code":"ABCD-EFGH","ca_sha256":null}"#,
        #"{"v":1,"urls":["https://u@brievie.local"],"code":"ABCD-EFGH","ca_sha256":null}"#,
        // URL without host
        #"{"v":1,"urls":["https://"],"code":"ABCD-EFGH","ca_sha256":null}"#,
        // empty urls
        #"{"v":1,"urls":[],"code":"ABCD-EFGH","ca_sha256":null}"#,
        // missing urls
        #"{"v":1,"code":"ABCD-EFGH","ca_sha256":null}"#,
        // missing code
        #"{"v":1,"urls":["https://a.nl"],"ca_sha256":null}"#,
        // empty code
        #"{"v":1,"urls":["https://a.nl"],"code":"","ca_sha256":null}"#,
        // code not in XXXX-XXXX form
        #"{"v":1,"urls":["https://a.nl"],"code":"ABCDEFGH","ca_sha256":null}"#,
        // wrong type for urls
        #"{"v":1,"urls":"https://a.nl","code":"ABCD-EFGH","ca_sha256":null}"#
    ])
    func rejectsInvalidPayloads(text: String) {
        #expect(throws: PairingPayloadError.invalid) {
            try PairingPayload.parse(text)
        }
    }

    @Test(arguments: [
        String(repeating: "a", count: 63),
        String(repeating: "a", count: 65),
        String(repeating: "a", count: 62) + "zz",
        String(repeating: "a", count: 62) + "  ",
        ""
    ])
    func rejectsMalformedHash(badHash: String) {
        let text = #"{"v":1,"urls":["https://a.nl"],"code":"ABCD-EFGH","ca_sha256":"\#(badHash)"}"#

        #expect(throws: PairingPayloadError.invalid) {
            try PairingPayload.parse(text)
        }
    }
}
