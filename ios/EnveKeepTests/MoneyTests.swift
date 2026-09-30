import Foundation
import Testing
@testable import EnveKeep

struct MoneyTests {
    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test func parsesCommonFormats() {
        #expect(Money.parse("12.50", locale: us) == Decimal(string: "12.50"))
        #expect(Money.parse("12,50", locale: us) == Decimal(string: "12.50"))
        #expect(Money.parse("1,234.56", locale: us) == Decimal(string: "1234.56"))
        #expect(Money.parse("1.234,56", locale: us) == Decimal(string: "1234.56"))
        #expect(Money.parse("1.234.567", locale: us) == Decimal(string: "1234567"))
        #expect(Money.parse(" 1 500 ", locale: us) == Decimal(string: "1500"))
    }

    @Test func ambiguousGroupingFollowsLocale() {
        #expect(Money.parse("1,234", locale: us) == Decimal(string: "1234"))
        #expect(Money.parse("1,234", locale: germany) == Decimal(string: "1.234"))
    }

    @Test func rejectsInvalidInput() {
        #expect(Money.parse("", locale: us) == nil)
        #expect(Money.parse("abc", locale: us) == nil)
        #expect(Money.parse("-5", locale: us) == nil)
        #expect(Money.parse("1.23456", locale: us) == nil)
        #expect(Money.parse("١٢", locale: us) == nil)
    }

    @Test func amountsSerializeAsPlainStrings() {
        #expect(AmountCoding.string(Decimal(string: "499.99")!) == "499.99")
        #expect(AmountCoding.string(Decimal(string: "1000")!) == "1000")
        #expect(AmountCoding.string(Decimal(string: "0.05")!) == "0.05")
        #expect(AmountCoding.parse("1E+3") == 1000)
        #expect(AmountCoding.parse("12abc") == nil)
        #expect(AmountCoding.parse("1,5") == nil)
    }
}
