import Foundation
import Testing
@testable import PettyTracker

/// Invented fixtures model printed rows and OCR errors.
struct ReceiptParserTests {
    private let today = day("2026-09-29")
    private let us = Locale(identifier: "en_US")

    private func parse(_ text: String, locale: Locale? = nil, currency: String = "USD") -> ParsedReceipt {
        ReceiptParser.parse(text, today: today, locale: locale ?? us, defaultCurrency: currency)
    }

    private func amount(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    @Test func printedGroceryReceipt() {
        let receipt = parse("""
        TRADER BOB'S MARKET
        123 Harbor Ave
        Portland, OR 97201
        (503) 555-0147
        09/14/2026  6:42 PM
        ORGANIC BANANAS
          3 @ 0.29            0.87
        WHOLE MILK 1GAL       4.49 F
        SOURDOUGH BREAD       5.99 F
        2 x ALMOND BUTTER    13.98
        COFFEE BEANS  $11.99
        COUPON COFFEE        -2.00
        SUBTOTAL             35.32
        TAX                   1.08
        TOTAL               $36.40
        VISA ****1234        36.40
        CHANGE DUE            0.00
        THANK YOU FOR SHOPPING
        """)

        #expect(receipt.merchant == "TRADER BOB'S MARKET")
        #expect(receipt.purchaseDate == day("2026-09-14"))
        #expect(receipt.currency == "USD")
        #expect(receipt.items == [
            ReceiptItem(description: "ORGANIC BANANAS", quantity: 3, amount: amount("0.87")),
            ReceiptItem(description: "WHOLE MILK 1GAL", quantity: nil, amount: amount("4.49")),
            ReceiptItem(description: "SOURDOUGH BREAD", quantity: nil, amount: amount("5.99")),
            ReceiptItem(description: "ALMOND BUTTER", quantity: 2, amount: amount("13.98")),
            ReceiptItem(description: "COFFEE BEANS", quantity: nil, amount: amount("11.99")),
            ReceiptItem(description: "COUPON COFFEE", quantity: nil, amount: amount("-2.00")),
        ])
        #expect(receipt.subtotal == amount("35.32"))
        #expect(receipt.tax == amount("1.08"))
        #expect(receipt.tip == nil)
        #expect(receipt.total == amount("36.40"))
    }

    @Test func europeanReceiptWithDecimalCommas() {
        let receipt = parse("""
        Bäckerei Sonnenschein
        Hauptstraße 12
        10115 Berlin
        Datum: 14.09.2026 08:15
        Brötchen 4 x 0,45      1,80 A
        Kaffee Crema           2,90 A
        Rabatt                 0,50-
        Zwischensumme          4,20
        MwSt 7% 0,27
        Summe EUR              4,20
        Bar                    5,00
        Rückgeld               0,80
        """, locale: Locale(identifier: "de_DE"), currency: "USD")

        #expect(receipt.merchant == "Bäckerei Sonnenschein")
        #expect(receipt.purchaseDate == day("2026-09-14"))
        #expect(receipt.currency == "EUR")
        #expect(receipt.items == [
            ReceiptItem(description: "Brötchen", quantity: 4, amount: amount("1.80")),
            ReceiptItem(description: "Kaffee Crema", quantity: nil, amount: amount("2.90")),
            ReceiptItem(description: "Rabatt", quantity: nil, amount: amount("-0.50")),
        ])
        #expect(receipt.subtotal == amount("4.20"))
        #expect(receipt.tax == amount("0.27"))
        #expect(receipt.total == amount("4.20"))
    }

    @Test func handwrittenStyleTranscription() {
        // Handwriting-like OCR errors include mistaken digits and an ambiguous tip.
        let text = """
        Rosa's Taqueria
        Sept 3 2026
        2 tacos al pastor   9.00
        horchata 3,5O
        chips + salsa 4.25
        Subt0tal 16.75
        tax 1.34
        tip 3
        Total 21.09
        """
        let receipt = parse(text)

        #expect(receipt.merchant == "Rosa's Taqueria")
        #expect(receipt.purchaseDate == day("2026-09-03"))
        #expect(receipt.items.map(\.description) == ["2 tacos al pastor", "horchata", "chips + salsa"])
        #expect(receipt.items.map(\.amount) == [amount("9.00"), amount("3.50"), amount("4.25")])
        #expect(receipt.subtotal == amount("16.75"))
        #expect(receipt.tax == amount("1.34"))
        #expect(receipt.tip == nil)
        #expect(receipt.total == amount("21.09"))
    }

    @Test func missingTotalStaysBlank() {
        let receipt = parse("""
        Corner Hardware
        Wood screws      6.49
        Sandpaper        3.25
        """)
        #expect(receipt.items.count == 2)
        #expect(receipt.subtotal == nil)
        #expect(receipt.total == nil)
        #expect(receipt.purchaseDate == nil)
        #expect(receipt.currency == nil)
    }

    @Test func conflictingTotalsStayBlank() {
        let receipt = parse("""
        Harbor Cafe
        Latte            4.50
        TOTAL           12.00
        TOTAL           15.00
        """)
        #expect(receipt.total == nil)
        #expect(receipt.items.map(\.description) == ["Latte"])
    }

    @Test func tipWrittenAfterPrintedTotalUsesFinalTotal() {
        let receipt = parse("""
        Blue Door Bistro
        Soup of the day      9.00
        Subtotal             9.00
        Tax                  0.72
        Total                9.72
        Tip                  2.00
        Total               11.72
        """)
        #expect(receipt.tip == amount("2.00"))
        #expect(receipt.total == amount("11.72"))
        #expect(receipt.items.count == 1)
    }

    @Test func conflictingTotalsResolvedByArithmetic() {
        let receipt = parse("""
        Garden Supply
        Seeds                5.00
        Subtotal             5.00
        Tax                  0.40
        TOTAL                5.40
        Total                7.50
        """)
        #expect(receipt.total == amount("5.40"))
    }

    @Test func totalOnTheLineBelowItsLabel() {
        let receipt = parse("""
        Night Market
        Dumplings            8.00
        TOTAL
        8.00
        """)
        #expect(receipt.total == amount("8.00"))
        #expect(receipt.items.count == 1)
    }

    @Test func summaryAndPaymentLinesNeverBecomeItems() {
        let receipt = parse("""
        Pine Street Pharmacy
        Bandages             4.99
        Total savings        1.00
        You saved            1.00
        Sub-total            4.99
        Sales tax            0.40
        Amount due           5.39
        Debit               5.39
        Loyalty points      12.00
        Bottle deposit       0.10
        """)
        #expect(receipt.items.map(\.description) == ["Bandages"])
        #expect(receipt.total == amount("5.39"))
    }

    @Test func descriptionOnOneLineAndPriceOnTheNext() {
        let receipt = parse("""
        Farm Stand
        Heirloom tomatoes
        1.25 lb @ 2.99/lb     3.74
        Honey
        12.00
        TOTAL 15.74
        """)
        #expect(receipt.items == [
            ReceiptItem(description: "Heirloom tomatoes", quantity: amount("1.25"), amount: amount("3.74")),
            ReceiptItem(description: "Honey", quantity: nil, amount: amount("12.00")),
        ])
    }

    @Test func quantityLineAfterItsItem() {
        let receipt = parse("""
        Markt
        Milch               3,98 B
          2 x 1,99
        Summe               3,98
        """, locale: Locale(identifier: "de_DE"))
        #expect(receipt.items == [ReceiptItem(description: "Milch", quantity: 2, amount: amount("3.98"))])
    }

    @Test(arguments: [
        ("Refund (2.00)", "-2.00"),
        ("Refund 2.00-", "-2.00"),
        ("Refund −2.00", "-2.00"),
        ("Refund -$2.00", "-2.00"),
        ("TV stand $1,234.56", "1234.56"),
        ("TV stand 1.234,56 €", "1234.56"),
        ("TV stand 1'234.50", "1234.50"),
        ("Coffee 3. 50", "3.50"),
    ])
    func amountVariants(line: String, expected: String) {
        let receipt = parse("Shop\n\(line)\nTOTAL 99.99")
        #expect(receipt.items.first?.amount == amount(expected))
    }

    @Test func percentagesDatesAndPhoneNumbersAreNotAmounts() {
        let receipt = parse("""
        Shop
        Date 14.09.26
        Call 555.123.4567
        VAT 20.00%
        """, locale: Locale(identifier: "en_GB"))
        #expect(receipt.items.isEmpty)
        #expect(receipt.tax == nil)
        #expect(receipt.purchaseDate == day("2026-09-14"))
    }

    @Test func combinesDistinctTaxesAndDropsRepeatedOnes() {
        let canada = parse("Shop\nBook 20.00\nSubtotal 20.00\nGST 5% 1.00\nPST 7% 1.40\nTotal 22.40")
        #expect(canada.tax == amount("2.40"))

        let repeated = parse("Shop\nBook 20.00\nVAT 20% 3.33\nTotal 20.00\nVAT 3.33")
        #expect(repeated.tax == amount("3.33"))

        let included = parse("Shop\nBook 20.00\nTotal incl. VAT 20.00\nVAT 3.33")
        #expect(included.total == amount("20.00"))
        #expect(included.tax == amount("3.33"))
    }

    @Test func ambiguousNumericDatesFollowTheLocale() {
        #expect(parse("Shop\n03/04/2026").purchaseDate == day("2026-03-04"))
        #expect(parse("Shop\n03/04/2026", locale: Locale(identifier: "en_GB")).purchaseDate == day("2026-04-03"))
        #expect(parse("Shop\n2026-04-03").purchaseDate == day("2026-04-03"))
        #expect(parse("Shop\n3 Apr 2026").purchaseDate == day("2026-04-03"))
    }

    @Test func skipsFutureAndReturnByDates() {
        let receipt = parse("""
        Shop
        Return by 10/30/2026
        12/01/2030
        09/20/2026
        """)
        #expect(receipt.purchaseDate == day("2026-09-20"))
    }

    @Test func currencyNeedsClearEvidence() {
        #expect(parse("Shop\nTea £2.50").currency == "GBP")
        #expect(parse("Shop\nTea $2.50", currency: "CAD").currency == "CAD")
        #expect(parse("Shop\nTea $2.50", currency: "EUR").currency == nil)
        #expect(parse("Shop\nTea 2.50 USD\nTee 2,30 EUR").currency == nil)
        #expect(parse("Shop\nTea 2.50 CHF", currency: "EUR").currency == "CHF")
    }

    @Test func merchantSkipsHeaderNoise() {
        #expect(parse("Welcome to Maple Books\nStore #42\nNovel 12.00").merchant == "Maple Books")
        #expect(parse("Receipt\nTel: 555 0101\n*** Lakeside Deli ***\nSoup 5.00").merchant == "Lakeside Deli")
        #expect(parse("12.00\nTOTAL 12.00").merchant == nil)
    }

    @Test func emptyTextParsesToNothing() {
        #expect(parse("") == ParsedReceipt())
    }
}

struct ReceiptFormTests {
    @Test func fillBlanksNeverOverwritesEdits() {
        var form = ReceiptForm(nil, defaultCurrency: "USD")
        form.merchant = "My name"
        form.total = "10"
        var parsed = ParsedReceipt()
        parsed.merchant = "OCR NAME"
        parsed.purchaseDate = day("2026-09-01")
        parsed.currency = "EUR"
        parsed.items = [ReceiptItem(description: "Tea", quantity: nil, amount: Decimal(string: "2.5"))]
        parsed.total = 12
        parsed.tax = 1

        form.fillBlanks(from: parsed)

        #expect(form.merchant == "My name")
        #expect(form.total == "10")
        #expect(form.currency == "USD")
        #expect(form.purchaseDate == day("2026-09-01"))
        #expect(form.tax == "1")
        #expect(form.items.map(\.description) == ["Tea"])
    }

    @Test func buildsReceiptWithSignedAmountsAndCleanTags() throws {
        var form = ReceiptForm(nil, defaultCurrency: "EUR")
        form.merchant = "  Kiosk "
        form.tags = "work, Travel ,, work"
        form.items = [ReceiptItemDraft(), ReceiptItemDraft()]
        form.items[0].description = "Discount"
        form.items[0].amount = "-1,50"
        form.total = "3"
        #expect(form.isValid)

        let receipt = form.receipt(updating: nil, today: day("2026-09-29"))
        #expect(receipt.merchant == "Kiosk")
        #expect(receipt.tags == ["work", "Travel"])
        #expect(receipt.items == [ReceiptItem(description: "Discount", quantity: nil, amount: Decimal(string: "-1.5"))])
        #expect(receipt.addedOn == day("2026-09-29"))

        form.tax = "abc"
        #expect(!form.isValid)
    }

    @Test func signedMoneyParsing() {
        let us = Locale(identifier: "en_US")
        #expect(Money.parseSigned("-2.50", locale: us) == Decimal(string: "-2.5"))
        #expect(Money.parseSigned("−2,50", locale: us) == Decimal(string: "-2.5"))
        #expect(Money.parseSigned("2.50", locale: us) == Decimal(string: "2.5"))
        #expect(Money.parseSigned("--2", locale: us) == nil)
        #expect(Money.parseSigned("-", locale: us) == nil)
    }
}

struct ReceiptOrganizerTests {
    private func receipt(_ id: Int64, _ merchant: String, _ date: String?, total: String?, category: String = "",
                         currency: String = "USD") -> Receipt {
        Receipt(id: id, merchant: merchant, purchaseDate: date.map(day), currency: currency,
                total: total.flatMap { Decimal(string: $0) }, category: category, addedOn: day("2026-09-29"))
    }

    private var receipts: [Receipt] {
        [
            receipt(1, "Cafe", "2026-08-03", total: "4.50", category: "Dining"),
            receipt(2, "Grocer", "2026-09-10", total: "52.10", category: "Groceries"),
            receipt(3, "bakery", "2026-09-12", total: nil),
            receipt(4, "Airline", "2026-09-01", total: "310", category: "Travel", currency: "EUR"),
        ]
    }

    @Test func groupsByMonthNewestFirstWithTotalsPerCurrency() {
        let groups = ReceiptOrganizer.groups(receipts, sort: .newest, grouping: .month)
        #expect(groups.map { $0.receipts.map(\.id) } == [[3, 2, 4], [1]])
        #expect(groups[0].totals.map(\.currency) == ["EUR", "USD"])
        #expect(groups[0].totals.map(\.amount) == [310, Decimal(string: "52.1")!])
    }

    @Test func groupsByCategoryWithUncategorizedLast() {
        let groups = ReceiptOrganizer.groups(receipts, sort: .newest, grouping: .category)
        #expect(groups.map(\.title) == ["Dining", "Groceries", "Travel", ""])
    }

    @Test func sortsByTotalAndMerchant() {
        let byTotal = ReceiptOrganizer.groups(receipts, sort: .highestTotal, grouping: .none)
        #expect(byTotal.first?.receipts.map(\.id) == [4, 2, 1, 3])
        let byMerchant = ReceiptOrganizer.groups(receipts, sort: .merchant, grouping: .none)
        #expect(byMerchant.first?.receipts.map(\.merchant) == ["Airline", "bakery", "Cafe", "Grocer"])
    }

    @Test func searchCoversItemsTagsAndRecognizedText() {
        var receipt = receipt(1, "Cafe", nil, total: nil)
        receipt.items = [ReceiptItem(description: "Oat latte", quantity: nil, amount: nil)]
        receipt.tags = ["client-visit"]
        receipt.recognizedText = ["a.jpg": "TABLE 12 SERVER JO"]
        #expect(receipt.matches("latte"))
        #expect(receipt.matches("client"))
        #expect(receipt.matches("server jo"))
        #expect(!receipt.matches("espresso"))
    }
}
