import Foundation
import Testing
@testable import PettyTracker

/// Invented fixtures for the printed details beyond merchant, date, items and totals.
struct ReceiptDetailsParserTests {
    private let today = day("2026-09-29")

    private func parse(_ text: String, locale: String = "en_US") -> ParsedReceipt {
        ReceiptParser.parse(text, today: today, locale: Locale(identifier: locale), defaultCurrency: "USD")
    }

    private func amount(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    private let gasStation = """
    SHELL
    STATION #4412
    1500 MARKET ST
    SAN FRANCISCO, CA 94103
    (415) 555-0199
    09/14/2026  06:42 PM
    TRANS# 004521
    PUMP# 07
    UNLEADED
    10.543 GAL @ $3.459/GAL
    FUEL TOTAL          $36.47
    TOTAL               $36.47
    VISA ****1234       $36.47
    AUTH# 118822
    ODOMETER 45,210
    THANK YOU
    """

    @Test func gasStationReceipt() {
        let receipt = parse(gasStation)

        #expect(receipt.merchant == "SHELL")
        #expect(receipt.purchaseDate == day("2026-09-14"))
        #expect(receipt.purchaseTime == ClockTime(hour: 18, minute: 42))
        #expect(receipt.storeAddress == "1500 MARKET ST, SAN FRANCISCO, CA 94103")
        #expect(receipt.storePhone == "(415) 555-0199")
        #expect(receipt.transactionId == "004521", "The authorization code is not the transaction number")
        #expect(receipt.paymentMethod == "Visa")
        #expect(receipt.cardLastFour == "1234")
        #expect(receipt.isFuel)
        #expect(receipt.fuelGrade == "Unleaded")
        #expect(receipt.fuelVolume == amount("10.543"))
        #expect(receipt.fuelUnit == .gallons)
        #expect(receipt.fuelUnitPrice == amount("3.459"))
        #expect(receipt.pumpNumber == "07")
        #expect(receipt.odometer == "45210")
        #expect(receipt.total == amount("36.47"))
    }

    @Test func europeanFuelInLiters() {
        let receipt = parse("""
        ARAL Tankstelle
        Berliner Allee 40
        40212 Düsseldorf
        Tel. 0211 123456
        14.09.2026 17:05
        Zapfsäule 4
        Super E10  42,31 l
        Preis/l 1,799 EUR
        Summe EUR 76,11
        Girocard
        Beleg-Nr. 8841
        """, locale: "de_DE")

        #expect(receipt.storeAddress == "Berliner Allee 40, 40212 Düsseldorf")
        #expect(receipt.storePhone == "0211 123456")
        #expect(receipt.purchaseTime == ClockTime(hour: 17, minute: 5))
        #expect(receipt.isFuel)
        #expect(receipt.fuelGrade == "Super E10")
        #expect(receipt.fuelVolume == amount("42.31"))
        #expect(receipt.fuelUnit == .liters)
        #expect(receipt.fuelUnitPrice == amount("1.799"))
        #expect(receipt.pumpNumber == "4")
        #expect(receipt.paymentMethod == "girocard")
        #expect(receipt.transactionId == "8841")
    }

    @Test func groceryReceiptHasStoreDetailsButIsNotFuel() {
        let receipt = parse("""
        TRADER BOB'S MARKET
        123 Harbor Ave
        Portland, OR 97201
        (503) 555-0147
        09/14/2026  6:42 PM
        WHOLE MILK 1GAL       4.49 F
        OAT MILK 1.75 L       3.99 F
        TOTAL                 8.48
        MASTERCARD XXXX XXXX XXXX 9876   8.48
        """)

        #expect(receipt.storeAddress == "123 Harbor Ave, Portland, OR 97201")
        #expect(receipt.storePhone == "(503) 555-0147")
        #expect(receipt.purchaseTime == ClockTime(hour: 18, minute: 42))
        #expect(receipt.paymentMethod == "Mastercard")
        #expect(receipt.cardLastFour == "9876")
        #expect(!receipt.isFuel, "A bottle size alone is not fuel evidence")
        #expect(receipt.fuelVolume == nil)
        #expect(receipt.fuelGrade == nil)
        #expect(receipt.transactionId == nil)
    }

    @Test func weakCuesStayBlank() {
        let hardware = parse("""
        Cash & Carry Hardware
        SUMP PUMP 1          89.99
        Premium hose         24.00
        Open daily 9:00
        """)
        #expect(!hardware.isFuel)
        #expect(hardware.pumpNumber == nil)
        #expect(hardware.fuelGrade == nil)
        #expect(hardware.paymentMethod == nil, "The merchant name is not a payment line")
        #expect(hardware.purchaseTime == nil, "Opening hours are not the purchase time")
        #expect(hardware.storeAddress == nil)

        let diesel = parse("Farm Supply\nDiesel exhaust fluid  12.99\nTOTAL 12.99")
        #expect(!diesel.isFuel, "A fuel word alone is not enough")
    }

    @Test func labeledTimeAndTransactionVariants() {
        let receipt = parse("""
        Harbor Cafe
        Date: 2026-09-10
        Time: 07:05
        Order #A1042
        Latte    4.50
        TOTAL    4.50
        Apple Pay  4.50
        """)
        #expect(receipt.purchaseTime == ClockTime(hour: 7, minute: 5))
        #expect(receipt.transactionId == "A1042")
        #expect(receipt.paymentMethod == "Apple Pay")

        #expect(parse("Shop\nInvoice No. INV-2231\nTea 2.00").transactionId == "INV-2231")
        #expect(parse("Shop\nOrder total 12.00").transactionId == nil)
        #expect(parse("Shop\nOpen 8:00 AM\n09/01/2026 12:30 AM").purchaseTime == ClockTime(hour: 0, minute: 30))
    }

    @Test func fillBlanksAddsDetailsAndFuelCategoryWithoutOverwriting() {
        var form = ReceiptForm(nil, defaultCurrency: "USD")
        form.pumpNumber = "3"
        form.origin = "San Francisco"
        form.fillBlanks(from: parse(gasStation))

        #expect(form.category == Receipt.fuelCategory)
        #expect(form.pumpNumber == "3")
        #expect(form.origin == "San Francisco")
        #expect(form.destination.isEmpty, "Routes are never read from the receipt")
        #expect(form.storeAddress == "1500 MARKET ST, SAN FRANCISCO, CA 94103")
        #expect(form.fuelUnit == .gallons)
        #expect(form.purchaseTime == ClockTime(hour: 18, minute: 42))

        let receipt = form.receipt(updating: nil, today: today)
        #expect(receipt.fuelVolume == amount("10.543"))
        #expect(receipt.fuelUnitPrice == amount("3.459"))
        #expect(receipt.cardLastFour == "1234")

        var chosen = ReceiptForm(nil, defaultCurrency: "USD")
        chosen.category = "Travel"
        chosen.fillBlanks(from: parse(gasStation))
        #expect(chosen.category == "Travel")
    }

    @Test func formValidatesCardDigitsFuelNumbersAndCustomFieldNames() {
        var form = ReceiptForm(nil, defaultCurrency: "USD")
        form.merchant = "Shell"
        #expect(form.isValid)

        form.cardLastFour = "12a4"
        #expect(!form.isValid)
        form.cardLastFour = "1234"
        form.fuelVolume = "ten"
        #expect(!form.isValid)
        form.fuelVolume = "10.5"

        var nameless = ReceiptFieldDraft()
        nameless.value = "Civic"
        form.customFields = [nameless, ReceiptFieldDraft()]
        #expect(!form.isValid)
        form.customFields[0].name = " Vehicle "
        #expect(form.isValid)

        let receipt = form.receipt(updating: nil, today: today)
        #expect(receipt.customFields == [ReceiptField(name: "Vehicle", value: "Civic")], "Blank rows are dropped and text trimmed")
        #expect(receipt.fuelUnit == nil)
    }
}
