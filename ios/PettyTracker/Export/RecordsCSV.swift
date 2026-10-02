import Foundation

/// One spreadsheet of every product, subscription and document, with the columns petty: Tracker for Android
/// writes too. Dates are ISO `yyyy-MM-dd` and amounts plain decimals so any spreadsheet locale reads them.
enum RecordsCSV {
    static let header = [
        "Type", "Name", "Due Date", "Status", "Brand", "Model", "Serial Number", "Purchase Date", "Retailer",
        "Price", "Currency", "Billing Cycle", "Per Month", "Canceled On", "Issued By", "Document Number",
        "Issued On", "Product Page", "Notes",
    ]

    static func make(_ data: TrackerData, today: Day) -> String {
        let settings = data.settings
        var rows = [header.map(ReceiptCSV.field)]
        for product in data.products.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let status = deadlineStatus(product.warrantyExpires, today: today, leadDays: settings.warrantyLeadDays)
            rows.append(row(
                type: String(localized: "Product"), name: product.name, due: product.warrantyExpires,
                status: statusText(status, kind: .warranty),
                brand: product.brand, model: product.model, serial: product.serialNumber,
                purchased: product.purchaseDate, retailer: product.retailer,
                price: product.price, currency: product.currency,
                productPage: product.productUrl, notes: product.notes
            ))
        }
        for subscription in data.subscriptions.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let status = subscription.isActive
                ? statusText(deadlineStatus(subscription.nextRenewal, today: today, leadDays: settings.subscriptionLeadDays), kind: .subscription)
                : String(localized: "Canceled")
            let monthly = subscription.price.map {
                Renewals.monthlyCost(price: $0, count: subscription.cycleCount, unit: subscription.cycleUnit)
            }
            rows.append(row(
                type: String(localized: "Subscription"), name: subscription.name,
                due: subscription.isActive ? subscription.nextRenewal : nil, status: status,
                price: subscription.price, currency: subscription.currency,
                cycle: Formats.cycle(count: subscription.cycleCount, unit: subscription.cycleUnit),
                monthly: monthly, canceled: subscription.canceledOn, notes: subscription.notes
            ))
        }
        for document in data.documents.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
            let status = deadlineStatus(document.expiresOn, today: today, leadDays: settings.documentLeadDays)
            rows.append(row(
                type: String(localized: "Document"), name: document.title, due: document.expiresOn,
                status: statusText(status, kind: .document),
                issuer: document.issuer, reference: document.reference, issued: document.issuedOn,
                notes: document.notes
            ))
        }
        return rows.map { $0.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes a UTF-8 file with a byte order mark, which Excel needs to detect the encoding.
    static func write(_ data: TrackerData, today: Day) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "records", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Petty Tracker records \(today.iso).csv")
        try Data(("\u{FEFF}" + make(data, today: today)).utf8).write(to: url, options: .atomic)
        return url
    }

    static func statusText(_ status: DeadlineStatus, kind: RecordKind) -> String {
        switch (status, kind) {
        case (.none, _): String(localized: "No date")
        case (.past, .warranty): String(localized: "Ended")
        case (.past, .subscription): String(localized: "Renewal overdue")
        case (.past, .document): String(localized: "Expired")
        case (.today, _), (.soon, _): String(localized: "Due soon")
        case (.ok, .warranty): String(localized: "Covered")
        case (.ok, .subscription): String(localized: "Active")
        case (.ok, .document): String(localized: "Valid")
        }
    }

    private static func row(
        type: String, name: String, due: Day?, status: String,
        brand: String = "", model: String = "", serial: String = "", purchased: Day? = nil, retailer: String = "",
        price: Decimal? = nil, currency: String = "", cycle: String = "", monthly: Decimal? = nil, canceled: Day? = nil,
        issuer: String = "", reference: String = "", issued: Day? = nil, productPage: String = "", notes: String
    ) -> [String] {
        [
            type, text(name), due?.iso ?? "", status, text(brand), text(model), text(serial), purchased?.iso ?? "",
            text(retailer), amount(price), currency, cycle, amount(monthly.map(rounded)), canceled?.iso ?? "",
            text(issuer), text(reference), issued?.iso ?? "", text(productPage), text(notes),
        ].map(ReceiptCSV.field)
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .bankers)
        return result
    }

    private static func amount(_ value: Decimal?) -> String {
        value.map(AmountCoding.string) ?? ""
    }

    /// Names and notes typed by people could start like a spreadsheet formula; a leading apostrophe keeps them text.
    private static func text(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return value }
        return "'" + value
    }
}
