import Foundation

/// Something on a receipt worth a second look. The id encodes the values involved, so a flag the
/// user resolved comes back if those values change.
struct ReviewFlag: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case missingDate
        case missingTotal
        case noText(page: Int, fileName: String)
        case uncertainText(page: Int, fileName: String, confidence: Double)
        case itemsDontMatchSubtotal(itemsSum: Decimal, subtotal: Decimal)
        case totalDoesntAddUp(expected: Decimal, total: Decimal)
        case sameScan(as: Int64)
        case possibleDuplicate(of: Int64)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .missingDate: "missing-date"
        case .missingTotal: "missing-total"
        case .noText(_, let fileName): "no-text:\(fileName)"
        case .uncertainText(_, let fileName, _): "uncertain-text:\(fileName)"
        case .itemsDontMatchSubtotal(let sum, let subtotal):
            "items-sum:\(AmountCoding.string(sum)):\(AmountCoding.string(subtotal))"
        case .totalDoesntAddUp(let expected, let total):
            "total:\(AmountCoding.string(expected)):\(AmountCoding.string(total))"
        case .sameScan(let id): "same-scan:\(id)"
        case .possibleDuplicate(let id): "duplicate:\(id)"
        }
    }
}

enum ReceiptReview {
    /// Pages whose mean Vision confidence is below this are called out as hard to read.
    static let uncertainConfidence = 0.6

    /// Every flag for `receipt`, resolved or not. `pages` lists its page file names in order.
    static func flags(for receipt: Receipt, pages: [String], among receipts: [Receipt]) -> [ReviewFlag] {
        flags(for: receipt, pages: pages, index: DuplicateIndex(receipts, pages: [receipt.id: pages]))
    }

    /// Flags the user hasn't resolved yet, for receipts that have any.
    static func pending(_ receipts: [Receipt], pages: [Int64: [String]]) -> [Int64: [ReviewFlag]] {
        let index = DuplicateIndex(receipts, pages: pages)
        var result: [Int64: [ReviewFlag]] = [:]
        for receipt in receipts {
            let open = unresolved(flags(for: receipt, pages: pages[receipt.id] ?? [], index: index), in: receipt)
            if !open.isEmpty { result[receipt.id] = open }
        }
        return result
    }

    static func unresolved(_ flags: [ReviewFlag], in receipt: Receipt) -> [ReviewFlag] {
        flags.filter { !receipt.resolvedFlags.contains($0.id) }
    }

    private static func flags(for receipt: Receipt, pages: [String], index: DuplicateIndex) -> [ReviewFlag] {
        var kinds: [ReviewFlag.Kind] = []
        // Blank fields on a hand-entered receipt are the user's choice; on a scan they mean the text was unclear.
        if pages.contains(where: { receipt.recognizedText[$0] != nil }) {
            if receipt.purchaseDate == nil { kinds.append(.missingDate) }
            if receipt.total == nil { kinds.append(.missingTotal) }
        }
        for (number, fileName) in pages.enumerated() {
            if let text = receipt.recognizedText[fileName], text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                kinds.append(.noText(page: number + 1, fileName: fileName))
            }
            if let confidence = receipt.pageConfidence[fileName], confidence < uncertainConfidence {
                kinds.append(.uncertainText(page: number + 1, fileName: fileName, confidence: confidence))
            }
        }
        if let subtotal = receipt.subtotal, let sum = receipt.itemsSum, sum != subtotal {
            kinds.append(.itemsDontMatchSubtotal(itemsSum: sum, subtotal: subtotal))
        }
        if let total = receipt.total, let base = receipt.subtotal ?? receipt.itemsSum {
            let expected = base + (receipt.tax ?? 0) + (receipt.tip ?? 0)
            // Tax is often already included in item prices, so base plus tip also adds up.
            if total != expected && total != base + (receipt.tip ?? 0) {
                kinds.append(.totalDoesntAddUp(expected: expected, total: total))
            }
        }
        let sameScan = index.sameScan(as: receipt, pages: pages)
        kinds += sameScan.map { .sameScan(as: $0) }
        kinds += index.sameDetails(as: receipt).filter { !sameScan.contains($0) }.map { .possibleDuplicate(of: $0) }
        return kinds.map(ReviewFlag.init)
    }
}

/// Finds other receipts with an identical page image, or the same merchant, date, total and currency.
private struct DuplicateIndex {
    private struct Details: Hashable {
        let merchant: String
        let date: Day
        let total: Decimal
        let currency: String
    }

    private var byDigest: [String: Set<Int64>] = [:]
    private var byDetails: [Details: Set<Int64>] = [:]

    init(_ receipts: [Receipt], pages: [Int64: [String]]) {
        for receipt in receipts {
            for digest in Self.digests(receipt, pages: pages[receipt.id]) { byDigest[digest, default: []].insert(receipt.id) }
            if let details = Self.details(receipt) { byDetails[details, default: []].insert(receipt.id) }
        }
    }

    func sameScan(as receipt: Receipt, pages: [String]) -> [Int64] {
        let ids = Self.digests(receipt, pages: pages).reduce(into: Set<Int64>()) { $0.formUnion(byDigest[$1] ?? []) }
        return ids.subtracting([receipt.id]).sorted()
    }

    func sameDetails(as receipt: Receipt) -> [Int64] {
        guard let details = Self.details(receipt) else { return [] }
        return (byDetails[details] ?? []).subtracting([receipt.id]).sorted()
    }

    /// Digests of pages still attached; when the page list is unknown, all recorded digests.
    private static func digests(_ receipt: Receipt, pages: [String]?) -> Set<String> {
        guard let pages else { return Set(receipt.pageDigests.values) }
        return Set(pages.compactMap { receipt.pageDigests[$0] })
    }

    private static func details(_ receipt: Receipt) -> Details? {
        let merchant = receipt.merchant
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
        guard !merchant.isEmpty, let date = receipt.purchaseDate, let total = receipt.total else { return nil }
        return Details(merchant: merchant, date: date, total: total, currency: receipt.currency)
    }
}
