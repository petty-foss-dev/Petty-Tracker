import Foundation

/// RFC 4180 CSV with one row per line item, or a single row for a receipt without items.
/// Amounts are plain decimal strings, dates ISO `yyyy-MM-dd` and times `HH:mm`, so spreadsheets in any locale read them.
/// Each custom field name gets its own column after the fixed ones; a name used twice on one receipt gets a second column.
enum ReceiptCSV {
    static let header = [
        "Receipt ID", "Merchant", "Purchase Date", "Purchase Time", "Added On", "Currency", "Category", "Tags",
        "Store Address", "Store Phone", "Transaction ID", "Payment Method", "Card Last Four", "Trip From", "Trip To",
        "Fuel Grade", "Fuel Volume", "Fuel Unit", "Fuel Unit Price", "Pump", "Odometer",
        "Item", "Quantity", "Amount", "Subtotal", "Tax", "Tip", "Total", "Notes", "Recognized Text",
    ]

    static func make(_ receipts: [Receipt]) -> String {
        let columns = customColumns(receipts)
        let customHeader = columns.map { $0.occurrence == 1 ? "Custom: \($0.name)" : "Custom: \($0.name) (\($0.occurrence))" }
        var rows = [(header + customHeader).map(field)]
        for receipt in receipts {
            let custom = columns.map { column in
                text(receipt.customFields.filter { $0.name == column.name }.dropFirst(column.occurrence - 1).first?.value ?? "")
            }
            let items: [ReceiptItem?] = receipt.items.isEmpty ? [nil] : receipt.items
            for item in items {
                rows.append([
                    String(receipt.id),
                    text(receipt.merchant),
                    receipt.purchaseDate?.iso ?? "",
                    receipt.purchaseTime?.iso ?? "",
                    receipt.addedOn.iso,
                    receipt.currency,
                    text(receipt.category),
                    text(receipt.tags.joined(separator: ", ")),
                    text(receipt.storeAddress),
                    text(receipt.storePhone),
                    text(receipt.transactionId),
                    text(receipt.paymentMethod),
                    text(receipt.cardLastFour),
                    text(receipt.origin),
                    text(receipt.destination),
                    text(receipt.fuelGrade),
                    amount(receipt.fuelVolume),
                    receipt.fuelUnit.map { $0 == .gallons ? "gal" : "L" } ?? "",
                    amount(receipt.fuelUnitPrice),
                    text(receipt.pumpNumber),
                    text(receipt.odometer),
                    text(item?.description ?? ""),
                    amount(item?.quantity),
                    amount(item?.amount),
                    amount(receipt.subtotal),
                    amount(receipt.tax),
                    amount(receipt.tip),
                    amount(receipt.total),
                    text(receipt.notes),
                    text(receipt.recognizedText.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n\n")),
                ] + custom)
            }
        }
        return rows.map { $0.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Custom field names in first-seen order, each repeated as often as it appears on any one receipt.
    static func customColumns(_ receipts: [Receipt]) -> [(name: String, occurrence: Int)] {
        var names: [String] = []
        var most: [String: Int] = [:]
        for receipt in receipts {
            var counts: [String: Int] = [:]
            for field in receipt.customFields {
                counts[field.name, default: 0] += 1
                if most[field.name] == nil { names.append(field.name) }
                most[field.name] = max(most[field.name] ?? 0, counts[field.name]!)
            }
        }
        return names.flatMap { name in (1...most[name]!).map { (name, $0) } }
    }

    /// Writes a UTF-8 file with a byte order mark, which Excel needs to detect the encoding.
    static func write(_ receipts: [Receipt], today: Day) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "csv", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Petty Tracker receipts \(today.iso).csv")
        try Data(("\u{FEFF}" + make(receipts)).utf8).write(to: url, options: .atomic)
        return url
    }

    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func amount(_ value: Decimal?) -> String {
        value.map(AmountCoding.string) ?? ""
    }

    /// Free text from scans could start like a spreadsheet formula; a leading apostrophe keeps it text.
    private static func text(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return field(value) }
        return field("'" + value)
    }
}
