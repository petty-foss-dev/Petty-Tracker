import Foundation

extension Receipt {
    static let symbol = "receipt"
    static let fuelCategory = String(localized: "Fuel")

    static func isValidCardLastFour(_ text: String) -> Bool {
        text.isEmpty || text.wholeMatch(of: /[0-9]{4}/) != nil
    }

    /// Undated receipts sort by the day they were added.
    var sortDate: Day { purchaseDate ?? addedOn }

    var itemsSum: Decimal? {
        let amounts = items.compactMap(\.amount)
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    var routeLabel: String? {
        origin.isEmpty && destination.isEmpty ? nil : Self.routeLabel(origin: origin, destination: destination)
    }

    static func routeLabel(origin: String, destination: String) -> String {
        "\(origin.isEmpty ? "?" : origin) → \(destination.isEmpty ? "?" : destination)"
    }

    var hasFuelDetails: Bool {
        !fuelGrade.isEmpty || fuelVolume != nil || fuelUnitPrice != nil || !pumpNumber.isEmpty || !odometer.isEmpty
    }

    func matches(_ query: String) -> Bool {
        Search.matches(
            query, merchant, category, tags.joined(separator: " "), notes,
            items.map(\.description).joined(separator: " "),
            storeAddress, storePhone, transactionId, paymentMethod, cardLastFour, origin, destination,
            fuelGrade, pumpNumber, odometer,
            customFields.map { "\($0.name) \($0.value)" }.joined(separator: " "),
            recognizedText.values.joined(separator: " ")
        )
    }
}

enum ReceiptSort: CaseIterable, Sendable {
    case newest, oldest, highestTotal, lowestTotal, merchant, location, route
}

enum ReceiptGrouping: CaseIterable, Sendable {
    case month, category, merchant, none
}

struct ReceiptGroup: Identifiable, Sendable {
    let id: String
    /// Empty for the ungrouped list and for receipts without a category; the UI supplies a label.
    let title: String
    let receipts: [Receipt]

    var totals: [(currency: String, amount: Decimal)] { ReceiptOrganizer.totals(receipts) }
}

enum ReceiptFacetKind: CaseIterable, Hashable, Sendable {
    case category, merchant, route, location, tag, field
}

/// One value to drill into, such as a merchant or a route. Text compares case- and accent-insensitively.
enum ReceiptFacet: Hashable, Sendable {
    case category(String)
    case merchant(String)
    case location(String)
    case route(origin: String, destination: String)
    case tag(String)
    /// A custom field by name, optionally with one value.
    case field(name: String, value: String?)

    var kind: ReceiptFacetKind {
        switch self {
        case .category: .category
        case .merchant: .merchant
        case .location: .location
        case .route: .route
        case .tag: .tag
        case .field: .field
        }
    }

    var title: String {
        switch self {
        case .category(let text), .merchant(let text), .location(let text): text
        case .route(let origin, let destination): Receipt.routeLabel(origin: origin, destination: destination)
        case .tag(let tag): "#\(tag)"
        case .field(let name, let value): value.map { "\(name): \($0)" } ?? name
        }
    }

    func matches(_ receipt: Receipt) -> Bool {
        let same = { (lhs: String, rhs: String) in Search.key(lhs) == Search.key(rhs) }
        return switch self {
        case .category(let category): same(receipt.category, category)
        case .merchant(let merchant): same(receipt.merchant, merchant)
        case .location(let address): same(receipt.storeAddress, address)
        case .route(let origin, let destination): same(receipt.origin, origin) && same(receipt.destination, destination)
        case .tag(let tag): receipt.tags.contains { same($0, tag) }
        case .field(let name, let value):
            receipt.customFields.contains { field in same(field.name, name) && value.map { same(field.value, $0) } ?? true }
        }
    }

    /// The same facet with its text folded, for grouping spellings that `matches` treats as equal.
    fileprivate var key: ReceiptFacet {
        switch self {
        case .category(let text): .category(Search.key(text))
        case .merchant(let text): .merchant(Search.key(text))
        case .location(let text): .location(Search.key(text))
        case .route(let origin, let destination): .route(origin: Search.key(origin), destination: Search.key(destination))
        case .tag(let tag): .tag(Search.key(tag))
        case .field(let name, let value): .field(name: Search.key(name), value: value.map(Search.key))
        }
    }
}

struct ReceiptFacetSummary: Identifiable, Sendable {
    let facet: ReceiptFacet
    let count: Int
    let totals: [(currency: String, amount: Decimal)]

    var id: ReceiptFacet { facet }
}

/// Everything that narrows a receipt list. Facets must all match; the other conditions apply when set.
struct ReceiptFilter: Hashable, Sendable {
    var query = ""
    var facets: [ReceiptFacet] = []
    /// Free text matched within the route's start and end, so "san fran" finds "San Francisco".
    var origin = ""
    var destination = ""
    var fromDate: Day?
    var toDate: Day?
    /// Bounds apply to each receipt's total in its own currency.
    var minTotal: Decimal?
    var maxTotal: Decimal?
    var currency: String?

    /// Conditions other than the search text and facets, for showing how much is narrowed.
    var refinementCount: Int {
        [!origin.isEmpty, !destination.isEmpty, fromDate != nil || toDate != nil, minTotal != nil || maxTotal != nil, currency != nil]
            .filter { $0 }.count
    }

    func includes(_ receipt: Receipt) -> Bool {
        guard facets.allSatisfy({ $0.matches(receipt) }),
              Search.matches(origin, receipt.origin),
              Search.matches(destination, receipt.destination),
              currency.map({ receipt.currency == $0 }) ?? true
        else { return false }
        if let fromDate, receipt.sortDate < fromDate { return false }
        if let toDate, receipt.sortDate > toDate { return false }
        if minTotal != nil || maxTotal != nil {
            guard let total = receipt.total else { return false }
            if let minTotal, total < minTotal { return false }
            if let maxTotal, total > maxTotal { return false }
        }
        return receipt.matches(query)
    }
}

enum ReceiptOrganizer {
    static func groups(_ receipts: [Receipt], sort: ReceiptSort, grouping: ReceiptGrouping) -> [ReceiptGroup] {
        let sorted = receipts.sorted { isOrdered($0, before: $1, by: sort) }
        switch grouping {
        case .none:
            return sorted.isEmpty ? [] : [ReceiptGroup(id: "all", title: "", receipts: sorted)]
        case .month:
            let months = Dictionary(grouping: sorted) { $0.sortDate.year * 12 + $0.sortDate.month - 1 }
            let newestFirst = sort != .oldest
            return months.keys.sorted { newestFirst ? $0 > $1 : $0 < $1 }.map { key in
                let first = Day(year: key / 12, month: key % 12 + 1, day: 1)!
                let title = first.date().formatted(.dateTime.month(.wide).year())
                return ReceiptGroup(id: "month-\(key)", title: title, receipts: months[key]!)
            }
        case .category, .merchant:
            let key: (Receipt) -> String = grouping == .category ? \.category : \.merchant
            let buckets = Dictionary(grouping: sorted) { key($0).trimmingCharacters(in: .whitespaces) }
            return buckets.keys.sorted { lhs, rhs in
                if lhs.isEmpty != rhs.isEmpty { return rhs.isEmpty }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }.map { ReceiptGroup(id: "\(grouping)-\($0)", title: $0, receipts: buckets[$0]!) }
        }
    }

    static func totals(_ receipts: [Receipt]) -> [(currency: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for receipt in receipts {
            guard let total = receipt.total else { continue }
            totals[receipt.currency, default: 0] += total
        }
        return totals.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Distinct values of one kind with how many receipts have each, most used first. The first spelling seen names each value.
    static func facets(_ kind: ReceiptFacetKind, in receipts: [Receipt]) -> [ReceiptFacetSummary] {
        var buckets: [ReceiptFacet: (facet: ReceiptFacet, receipts: [Receipt])] = [:]
        for receipt in receipts {
            var seen = Set<ReceiptFacet>()
            for facet in facets(kind, of: receipt) where seen.insert(facet.key).inserted {
                buckets[facet.key, default: (facet, [])].receipts.append(receipt)
            }
        }
        return buckets.values
            .map { ReceiptFacetSummary(facet: $0.facet, count: $0.receipts.count, totals: totals($0.receipts)) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.facet.title.localizedStandardCompare(rhs.facet.title) == .orderedAscending
            }
    }

    private static func facets(_ kind: ReceiptFacetKind, of receipt: Receipt) -> [ReceiptFacet] {
        switch kind {
        case .category: receipt.category.isEmpty ? [] : [.category(receipt.category)]
        case .merchant: receipt.merchant.isEmpty ? [] : [.merchant(receipt.merchant)]
        case .location: receipt.storeAddress.isEmpty ? [] : [.location(receipt.storeAddress)]
        case .route: receipt.routeLabel == nil ? [] : [.route(origin: receipt.origin, destination: receipt.destination)]
        case .tag: receipt.tags.map(ReceiptFacet.tag)
        case .field:
            receipt.customFields.flatMap { field -> [ReceiptFacet] in
                let name = ReceiptFacet.field(name: field.name, value: nil)
                return field.value.isEmpty ? [name] : [name, .field(name: field.name, value: field.value)]
            }
        }
    }

    static func categories(_ receipts: [Receipt]) -> [String] {
        Set(receipts.map(\.category).filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func tags(_ receipts: [Receipt]) -> [String] {
        Set(receipts.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Distinct values of a text field for editor suggestions, most used first.
    static func suggestions(_ values: [String]) -> [String] {
        var counts: [String: (value: String, count: Int)] = [:]
        for value in values where !value.isEmpty {
            counts[Search.key(value), default: (value, 0)].count += 1
        }
        return counts.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.value.localizedStandardCompare(rhs.value) == .orderedAscending
        }.map(\.value)
    }

    /// Splits comma-separated tag input, dropping blanks and case-insensitive duplicates.
    static func tags(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func isOrdered(_ lhs: Receipt, before rhs: Receipt, by sort: ReceiptSort) -> Bool {
        let newer = (lhs.sortDate, lhs.id) > (rhs.sortDate, rhs.id)
        switch sort {
        case .newest:
            return newer
        case .oldest:
            return (lhs.sortDate, lhs.id) < (rhs.sortDate, rhs.id)
        case .highestTotal, .lowestTotal:
            // Blank totals last; mixed currencies compare by face value.
            switch (lhs.total, rhs.total) {
            case let (l?, r?) where l != r: return sort == .highestTotal ? l > r : l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return newer
            }
        case .merchant:
            return textOrder(lhs.merchant, rhs.merchant, tie: newer)
        case .location:
            return textOrder(lhs.storeAddress, rhs.storeAddress, tie: newer)
        case .route:
            return textOrder(lhs.routeLabel ?? "", rhs.routeLabel ?? "", tie: newer)
        }
    }

    /// Alphabetical with blanks last.
    private static func textOrder(_ lhs: String, _ rhs: String, tie: Bool) -> Bool {
        if lhs.isEmpty != rhs.isEmpty { return rhs.isEmpty }
        return switch lhs.localizedStandardCompare(rhs) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: tie
        }
    }
}

extension Product {
    /// A new product drafted from a receipt and, optionally, one of its line items.
    init(receipt: Receipt, item: ReceiptItem?) {
        self.init(name: item?.description ?? "", currency: receipt.currency)
        purchaseDate = receipt.purchaseDate
        retailer = receipt.merchant
        price = item?.unitPrice
    }
}

extension ReceiptItem {
    /// The price of one unit, or nil for discounts, returns and items without an amount.
    var unitPrice: Decimal? {
        guard let amount, amount > 0 else { return nil }
        guard let quantity, quantity > 0, quantity != 1 else { return amount }
        var exact = amount / quantity
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 2, .plain)
        return rounded
    }
}
