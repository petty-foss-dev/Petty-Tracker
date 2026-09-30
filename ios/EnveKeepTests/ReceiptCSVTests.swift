import Foundation
import Testing
@testable import EnveKeep

struct ReceiptCSVTests {
    /// Minimal RFC 4180 reader, so tests check what a spreadsheet would actually see.
    private func parse(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(csv)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\r\n" || c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
        }
        return rows
    }

    private let receipts: [Receipt] = {
        var groceries = Receipt(id: 7, merchant: "Smith, Jones & \"Co\"", purchaseDate: day("2026-09-01"), currency: "EUR",
                                subtotal: Decimal(string: "1234.5"), tax: Decimal(string: "0.10"), total: Decimal(string: "1234.6"),
                                addedOn: day("2026-09-02"))
        groceries.items = [
            ReceiptItem(description: "Milk\n2 L", quantity: Decimal(string: "1.5"), amount: Decimal(string: "1236.50")),
            ReceiptItem(description: "=COUPON", quantity: nil, amount: -2),
        ]
        groceries.tags = ["food", "weekly"]
        let parking = Receipt(id: 8, merchant: "Parking", currency: "USD", total: 3, notes: "Meter 12", addedOn: day("2026-09-03"))
        return [groceries, parking]
    }()

    private func column(_ name: String, in rows: [[String]]) -> Int { rows[0].firstIndex(of: name)! }

    @Test func writesOneRowPerItemAndOneForReceiptsWithoutItems() {
        let csv = ReceiptCSV.make(receipts)
        let rows = parse(csv)
        let value = { (row: Int, name: String) in rows[row][column(name, in: rows)] }

        #expect(csv.hasSuffix("\r\n"))
        #expect(rows[0] == ReceiptCSV.header)
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { $0.count == ReceiptCSV.header.count })
        let fixed: [(String, String)] = [
            ("Receipt ID", "7"), ("Merchant", "Smith, Jones & \"Co\""), ("Purchase Date", "2026-09-01"), ("Purchase Time", ""),
            ("Added On", "2026-09-02"), ("Currency", "EUR"), ("Tags", "food, weekly"), ("Item", "Milk\n2 L"),
            ("Quantity", "1.5"), ("Amount", "1236.5"), ("Subtotal", "1234.5"), ("Tax", "0.1"), ("Tip", ""), ("Total", "1234.6"),
        ]
        for (name, expected) in fixed {
            #expect(value(1, name) == expected, "\(name)")
        }
        #expect(value(2, "Item") == "'=COUPON", "Formula-like text is neutralized")
        #expect(value(2, "Amount") == "-2", "Negative amounts stay numeric")
        #expect(value(3, "Merchant") == "Parking")
        #expect(value(3, "Total") == "3")
        #expect(value(3, "Notes") == "Meter 12")
        #expect(value(3, "Item").isEmpty)
    }

    @Test func writesStructuredDetailsAndOneColumnPerCustomFieldOccurrence() {
        var fuel = Receipt(id: 1, merchant: "Shell", purchaseDate: day("2026-09-14"), currency: "USD",
                           total: Decimal(string: "36.47"), category: "Fuel", addedOn: day("2026-09-14"))
        fuel.purchaseTime = ClockTime(hour: 18, minute: 42)
        fuel.storeAddress = "1500 Market St, San Francisco"
        fuel.transactionId = "-004521"
        fuel.cardLastFour = "1234"
        fuel.origin = "San Francisco"
        fuel.destination = "Los Angeles"
        fuel.fuelGrade = "Unleaded"
        fuel.fuelVolume = Decimal(string: "10.543")
        fuel.fuelUnit = .gallons
        fuel.fuelUnitPrice = Decimal(string: "3.459")
        fuel.pumpNumber = "07"
        fuel.customFields = [
            ReceiptField(name: "Passenger", value: "Ana"),
            ReceiptField(name: "Vehicle", value: "Civic, blue"),
            ReceiptField(name: "Passenger", value: "=Ben"),
        ]
        fuel.recognizedText = ["scan.jpg": "=SHELL\nPUMP 07\nTOTAL 36.47"]
        var lunch = Receipt(id: 2, merchant: "Cafe", currency: "EUR", addedOn: day("2026-09-15"))
        lunch.customFields = [ReceiptField(name: "+Project", value: "Offsite"), ReceiptField(name: "Vehicle", value: "")]
        lunch.items = [ReceiptItem(description: "Soup", quantity: nil, amount: 5), ReceiptItem(description: "Tea", quantity: nil, amount: 2)]

        let rows = parse(ReceiptCSV.make([fuel, lunch]))
        let value = { (row: Int, name: String) in rows[row][column(name, in: rows)] }

        #expect(Array(rows[0].dropFirst(ReceiptCSV.header.count)) == [
            "Custom: Passenger", "Custom: Passenger (2)", "Custom: Vehicle", "Custom: +Project",
        ])
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { $0.count == ReceiptCSV.header.count + 4 })
        #expect(value(1, "Purchase Time") == "18:42")
        #expect(value(1, "Store Address") == "1500 Market St, San Francisco")
        #expect(value(1, "Transaction ID") == "'-004521")
        #expect(value(1, "Card Last Four") == "1234")
        #expect(value(1, "Trip From") == "San Francisco")
        #expect(value(1, "Trip To") == "Los Angeles")
        #expect(value(1, "Fuel Grade") == "Unleaded")
        #expect(value(1, "Fuel Volume") == "10.543")
        #expect(value(1, "Fuel Unit") == "gal")
        #expect(value(1, "Fuel Unit Price") == "3.459")
        #expect(value(1, "Pump") == "07")
        #expect(value(1, "Recognized Text") == "'=SHELL\nPUMP 07\nTOTAL 36.47")
        #expect(value(1, "Custom: Passenger") == "Ana")
        #expect(value(1, "Custom: Passenger (2)") == "'=Ben")
        #expect(value(1, "Custom: Vehicle") == "Civic, blue")
        #expect(value(1, "Custom: +Project") == "")
        #expect(value(2, "Custom: +Project") == "Offsite")
        #expect(value(3, "Custom: +Project") == "Offsite", "Receipt-level values repeat on every item row")
        #expect(value(2, "Custom: Passenger").isEmpty)
    }

    @Test func escapesOnlyWhenNeeded() {
        #expect(ReceiptCSV.field("plain") == "plain")
        #expect(ReceiptCSV.field("a,b") == "\"a,b\"")
        #expect(ReceiptCSV.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(ReceiptCSV.field("two\r\nlines") == "\"two\r\nlines\"")
    }

    @Test func fileIsUTF8WithByteOrderMark() throws {
        let url = try ReceiptCSV.write(receipts, today: day("2026-09-29"))
        let data = try Data(contentsOf: url)

        #expect(url.lastPathComponent == "Enve Keep receipts 2026-09-29.csv")
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == ReceiptCSV.make(receipts))
    }
}
