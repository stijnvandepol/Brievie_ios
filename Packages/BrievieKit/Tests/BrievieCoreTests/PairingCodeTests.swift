import BrievieCore
import Testing

/// The code the user types from the web page, as the host's `normalise_code` reads it.
@Suite struct PairingCodeTests {
    @Test(arguments: ["abcd-2345", " ABCD 2345 ", "abcd2345\n", "ABCD-2345", "a b c d - 2 3 4 5"])
    func normalisesWhatPeopleType(typed: String) throws {
        let code = try #require(PairingCode(typed: typed))

        #expect(code.text == "ABCD-2345")
        #expect(code.normalised == "ABCD2345")
    }

    @Test(arguments: ["ABCD-234", "ABCD-23456", "", "   ", "ABCD-23!5", "ÀBCD-2345", "ABCD_2345", "ABCD\u{0}2345"])
    func refusesAnythingButEightLettersOrDigits(typed: String) {
        #expect(PairingCode(typed: typed) == nil)
    }
}
