import Foundation
import Testing
import UIKit
@testable import PettyTracker

struct ReceiptReviewTests {
    private func scanned(_ id: Int64, merchant: String = "Corner Cafe", date: String? = "2026-09-01",
                         total: String? = "5.75", digest: String? = nil) -> Receipt {
        var receipt = Receipt(id: id, merchant: merchant, purchaseDate: date.map(day), currency: "USD",
                              total: total.flatMap { Decimal(string: $0) }, addedOn: day("2026-09-02"))
        receipt.recognizedText = ["p\(id).jpg": "CORNER CAFE"]
        receipt.pageConfidence = ["p\(id).jpg": 0.95]
        if let digest { receipt.pageDigests = ["p\(id).jpg": digest] }
        return receipt
    }

    private func kinds(_ receipt: Receipt, among others: [Receipt] = []) -> [ReviewFlag.Kind] {
        ReceiptReview.flags(for: receipt, pages: Array(receipt.recognizedText.keys.sorted()), among: others + [receipt]).map(\.kind)
    }

    @Test func flagsMissingFieldsOnlyOnScans() {
        #expect(kinds(scanned(1, date: nil, total: nil)) == [.missingDate, .missingTotal])
        let manual = Receipt(id: 2, merchant: "Market", currency: "USD", addedOn: day("2026-09-02"))
        #expect(ReceiptReview.flags(for: manual, pages: [], among: [manual]).isEmpty)
    }

    @Test func flagsPagesWithLowVisionConfidenceByPageNumber() {
        var receipt = scanned(1)
        receipt.recognizedText["p1b.jpg"] = "?"
        receipt.pageConfidence["p1b.jpg"] = 0.42
        #expect(kinds(receipt) == [.uncertainText(page: 2, fileName: "p1b.jpg", confidence: 0.42)])
    }

    @Test func flagsScannedPagesWithNoRecognizedTextEvenWhenOtherFieldsWereEntered() {
        var receipt = scanned(1)
        receipt.recognizedText["p1.jpg"] = "  \n"
        receipt.pageConfidence.removeAll()
        #expect(kinds(receipt) == [.noText(page: 1, fileName: "p1.jpg")])
    }

    @Test func flagsTotalsThatDontAddUpButAcceptsTaxIncludedTotals() {
        var receipt = scanned(1, total: "12.00")
        receipt.items = [ReceiptItem(description: "A", amount: 6), ReceiptItem(description: "B", amount: 4)]
        receipt.subtotal = 11
        receipt.tax = 1
        #expect(kinds(receipt) == [
            .itemsDontMatchSubtotal(itemsSum: 10, subtotal: 11),
        ])

        receipt.subtotal = nil
        #expect(kinds(receipt) == [.totalDoesntAddUp(expected: 11, total: 12)])

        receipt.total = 10
        #expect(kinds(receipt).isEmpty, "Items already include tax")
        receipt.total = 11
        #expect(kinds(receipt).isEmpty)
    }

    @Test func detectsIdenticalScansAndLikelyDuplicatesWithoutDoubleReporting() {
        let original = scanned(1, digest: "same")
        let rescan = scanned(2, merchant: "CORNER CAFÉ!", digest: "same")
        let retyped = scanned(3, merchant: "corner cafe", digest: "other")
        var otherCurrency = scanned(4, digest: "x")
        otherCurrency.currency = "EUR"
        let all = [original, rescan, retyped, otherCurrency]

        #expect(kinds(original, among: all) == [.sameScan(as: 2), .possibleDuplicate(of: 3)])
        #expect(kinds(retyped, among: all) == [.possibleDuplicate(of: 1), .possibleDuplicate(of: 2)])
        #expect(kinds(otherCurrency, among: all).isEmpty)
    }

    @Test func pendingIgnoresDigestsOfPagesNoLongerAttached() {
        let first = scanned(1, digest: "same")
        let second = scanned(2, digest: "same")
        let pending = ReceiptReview.pending([first, second], pages: [1: ["p1.jpg"], 2: []])
        #expect(pending[1]?.map(\.kind) == [.possibleDuplicate(of: 2)])
    }
}

@MainActor
struct ReceiptReviewStoreTests {
    @Test func resolvedFlagsPersistAndReturnWhenValuesChange() throws {
        let store = TrackerStore(root: try temporaryDirectory())
        try Data([1]).write(to: store.attachmentStore.url(for: "p.jpg"))
        var draft = Receipt(merchant: "Cafe", purchaseDate: day("2026-09-01"), currency: "USD", addedOn: day("2026-09-01"))
        draft.items = [ReceiptItem(description: "Tea", amount: 3)]
        draft.total = 5
        draft.recognizedText = ["p.jpg": "CAFE"]
        let id = try store.saveReceipt(draft, added: [
            PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "p", mimeType: "image/jpeg", fileName: "p.jpg", sizeBytes: 1),
        ], removed: [])
        #expect(ReceiptReview.pending(store.data.receipts, pages: store.receiptPages)[id] != nil)

        try store.markReviewed(id)
        #expect(ReceiptReview.pending(store.data.receipts, pages: store.receiptPages).isEmpty)
        let reloaded = TrackerStore(root: store.root)
        #expect(ReceiptReview.pending(reloaded.data.receipts, pages: reloaded.receiptPages).isEmpty)

        var edited = try #require(store.receipt(id))
        edited.total = 6
        try store.saveReceipt(edited, added: [], removed: [])
        #expect(ReceiptReview.pending(store.data.receipts, pages: store.receiptPages)[id]?.map(\.kind) == [
            .totalDoesntAddUp(expected: 3, total: 6),
        ])
    }
}

struct RecognitionConfidenceTests {
    @Test func blankPageHasNoConfidence() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
        let page = try TextRecognizer.recognizeText(in: image.cgImage!)
        #expect(page.text.isEmpty)
        #expect(page.confidence == nil)
    }
}
