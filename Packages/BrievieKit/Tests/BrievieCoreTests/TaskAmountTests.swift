import BrievieCore
import Foundation
import Testing

/// The amount of a task: the API's decimal string, and what a user types in their own notation.
@Suite struct TaskAmountTests {
    private static let posix = Locale(identifier: "en_US_POSIX")

    @Test func apiStringsParseLocaleFree() {
        #expect(TaskAmount.parse(api: "1234.56") == Decimal(string: "1234.56", locale: Self.posix))
        #expect(TaskAmount.parse(api: "1234.5") == Decimal(string: "1234.50", locale: Self.posix))
        #expect(TaskAmount.parse(api: "") == nil)
        #expect(TaskAmount.parse(api: "abc") == nil)
        #expect(TaskAmount.parse(api: "1,5") == nil)
    }

    @Test func amountsGoOutWithTwoDecimalsAndAPoint() {
        #expect(TaskAmount.api(Decimal(string: "1234.5", locale: Self.posix) ?? 0) == "1234.50")
        #expect(TaskAmount.api(Decimal(string: "1234567.891", locale: Self.posix) ?? 0) == "1234567.89")
    }

    @Test(arguments: [
        ("1.234,56", "nl_NL"), ("1234,56", "nl_NL"), ("€ 1.234,56", "nl_NL"), ("1,234.56", "en_GB"),
        ("1234.56", "en_US"), ("€1,234.56", "en_GB")
    ])
    func typedAmountsReadInTheUsersNotation(text: String, locale: String) {
        #expect(TaskAmount.parse(input: text, locale: Locale(identifier: locale)).map(TaskAmount.api) == "1234.56")
    }

    @Test func aPointWithTwoDigitsOnADutchPhoneIsTheDecimals() {
        let dutch = Locale(identifier: "nl_NL")
        #expect(TaskAmount.parse(input: "12.50", locale: dutch).map(TaskAmount.api) == "12.50")
        #expect(TaskAmount.parse(input: "1.234", locale: dutch).map(TaskAmount.api) == "1234.00")
    }

    @Test func typedGarbageOrNegativeIsNil() {
        let dutch = Locale(identifier: "nl_NL")
        #expect(TaskAmount.parse(input: "twaalf", locale: dutch) == nil)
        #expect(TaskAmount.parse(input: "-5", locale: dutch) == nil)
        #expect(TaskAmount.parse(input: "", locale: dutch) == nil)
        #expect(TaskAmount.parse(input: "12,345", locale: dutch) == nil)
        #expect(TaskAmount.parse(input: "1.23.4", locale: dutch) == nil)
    }
}
