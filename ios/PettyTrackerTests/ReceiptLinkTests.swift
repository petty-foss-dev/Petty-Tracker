import Foundation
import Testing
@testable import PettyTracker

@MainActor
struct ReceiptLinkTests {
    private func page(_ store: TrackerStore, _ name: String) throws -> PettyTracker.Attachment {
        try Data([1, 2, 3]).write(to: store.attachmentStore.url(for: name))
        return PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Scan.jpg",
                                       mimeType: "image/jpeg", fileName: name, sizeBytes: 3)
    }

    private func receipt(_ store: TrackerStore, _ merchant: String, page name: String? = nil) throws -> Int64 {
        try store.saveReceipt(
            Receipt(merchant: merchant, currency: "USD", addedOn: day("2026-09-01")),
            added: try name.map { [try page(store, $0)] } ?? [],
            removed: []
        )
    }

    private func product(_ store: TrackerStore, _ name: String, receiptId: Int64? = nil, file: String? = nil) throws -> Int64 {
        try store.saveProduct(
            Product(name: name, currency: "USD"),
            added: try file.map { [try page(store, $0)] } ?? [],
            removed: [],
            receiptId: receiptId
        )
    }

    @Test func receiptCoversSeveralProductsAndEachProductHasOneReceipt() throws {
        let store = TrackerStore(root: try temporaryDirectory())
        let first = try receipt(store, "Electronics Hub")
        let second = try receipt(store, "Outlet")
        let tv = try product(store, "TV", receiptId: first)
        let soundbar = try product(store, "Soundbar", receiptId: first)

        #expect(store.products(coveredBy: store.receipt(first)!).map(\.name) == ["TV", "Soundbar"])
        #expect(store.receiptCovering(tv)?.id == first)

        try store.linkProduct(tv, toReceipt: second)
        #expect(store.receipt(first)?.productIds == [soundbar])
        #expect(store.receipt(second)?.productIds == [tv])

        // Re-saving the product through the editor with the same receipt must not reorder or duplicate links.
        try store.saveProduct(store.product(soundbar)!, added: [], removed: [], receiptId: first)
        #expect(store.receipt(first)?.productIds == [soundbar])

        try store.linkProduct(tv, toReceipt: nil)
        #expect(store.receiptCovering(tv) == nil)
        #expect(store.data.receipts.allSatisfy { !$0.productIds.contains(tv) })
        #expect(TrackerStore(root: store.root).data == store.data)
    }

    @Test func deletingProductDropsOnlyItsLink() throws {
        let store = TrackerStore(root: try temporaryDirectory())
        let receiptId = try receipt(store, "Hardware", page: "scan.jpg")
        let drill = try product(store, "Drill", receiptId: receiptId, file: "manual.pdf")
        let saw = try product(store, "Saw", receiptId: receiptId)

        try store.deleteProduct(drill)

        #expect(store.receipt(receiptId)?.productIds == [saw])
        #expect(store.attachments(.receipt, receiptId).map(\.fileName) == ["scan.jpg"])
        #expect(FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "scan.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "manual.pdf").path))
    }

    @Test func deletingReceiptKeepsProductsAndTheirFiles() throws {
        let store = TrackerStore(root: try temporaryDirectory())
        let receiptId = try receipt(store, "Hardware", page: "scan.jpg")
        let drill = try product(store, "Drill", receiptId: receiptId, file: "manual.pdf")

        try store.deleteReceipt(receiptId)

        #expect(store.product(drill) != nil)
        #expect(store.receiptCovering(drill) == nil)
        #expect(store.attachments(.product, drill).map(\.fileName) == ["manual.pdf"])
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "scan.jpg").path))
        #expect(FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "manual.pdf").path))
    }

    @Test func removingPagePrunesItsScanData() throws {
        let store = TrackerStore(root: try temporaryDirectory())
        var draft = Receipt(merchant: "Cafe", currency: "USD", addedOn: day("2026-09-01"))
        draft.pageConfidence = ["a.jpg": 0.9, "b.jpg": 0.4]
        draft.pageDigests = ["a.jpg": "aa", "b.jpg": "bb"]
        let id = try store.saveReceipt(draft, added: [try page(store, "a.jpg"), try page(store, "b.jpg")], removed: [])

        let pageB = store.attachments(.receipt, id)[1]
        try store.saveReceipt(store.receipt(id)!, added: [], removed: [pageB])

        #expect(store.receipt(id)?.pageConfidence == ["a.jpg": 0.9])
        #expect(store.receipt(id)?.pageDigests == ["a.jpg": "aa"])
    }

    @Test func backfillsDigestsForPagesScannedBeforeDigestsExisted() async throws {
        let store = TrackerStore(root: try temporaryDirectory())
        let id = try receipt(store, "Deli", page: "old.jpg")
        #expect(store.receipt(id)?.pageDigests.isEmpty == true)

        await store.backfillPageDigests()

        // SHA-256 of the bytes 01 02 03.
        #expect(store.receipt(id)?.pageDigests["old.jpg"] == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
    }

    @Test func productPrefilledFromLineItem() {
        let receipt = Receipt(merchant: "Electronics Hub", purchaseDate: day("2026-08-14"), currency: "EUR", addedOn: day("2026-08-15"))
        let product = Product(receipt: receipt, item: ReceiptItem(description: "USB-C CABLE", quantity: 3, amount: 10))

        #expect(product.name == "USB-C CABLE")
        #expect(product.retailer == "Electronics Hub")
        #expect(product.purchaseDate == day("2026-08-14"))
        #expect(product.currency == "EUR")
        #expect(product.price == Decimal(string: "3.33"))
        #expect(ReceiptItem(description: "Coupon", quantity: nil, amount: -5).unitPrice == nil)
        #expect(ReceiptItem(description: "Kettle", quantity: 1, amount: Decimal(string: "39.99")).unitPrice == Decimal(string: "39.99"))
    }
}

@MainActor
struct ReceiptLinkBackupTests {
    private func linkedStore() throws -> TrackerStore {
        let store = TrackerStore(root: try temporaryDirectory())
        try Data([9, 9]).write(to: store.attachmentStore.url(for: "scan.jpg"))
        var receipt = Receipt(merchant: "Kitchen Shop", purchaseDate: day("2026-09-01"), currency: "USD",
                              total: Decimal(string: "49.99"), addedOn: day("2026-09-02"))
        receipt.recognizedText = ["scan.jpg": "KITCHEN SHOP"]
        receipt.pageConfidence = ["scan.jpg": 0.5]
        receipt.pageDigests = ["scan.jpg": "abc123"]
        receipt.resolvedFlags = ["uncertain-text:scan.jpg"]
        let receiptId = try store.saveReceipt(receipt, added: [
            PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Scan.jpg",
                                    mimeType: "image/jpeg", fileName: "scan.jpg", sizeBytes: 2),
        ], removed: [])
        try store.saveProduct(Product(name: "Blender", serialNumber: "BL-1", currency: "USD"), added: [], removed: [], receiptId: receiptId)
        return store
    }

    @Test func versionThreeRoundTripsLinksAndReviewState() async throws {
        let store = try linkedStore()
        let service = BackupService(store: store)
        let exported = try await service.export()
        let staging = try temporaryDirectory()
        #expect(try BackupArchive.read(from: exported, staging: staging).version == BackupManifest.detailsVersion)
        let snapshot = store.data

        try store.deleteProduct(store.data.products[0].id)
        try store.deleteReceipt(store.data.receipts[0].id)
        try service.commit(try await service.stage(exported))

        #expect(store.data == snapshot)
        #expect(store.data.receipts[0].productIds == [store.data.products[0].id])
        #expect(store.data.receipts[0].resolvedFlags == ["uncertain-text:scan.jpg"])
    }

    @Test func productJSONKeepsAndroidShapeWhenLinked() async throws {
        let store = try linkedStore()
        let staging = try temporaryDirectory()
        let manifest = try BackupArchive.read(from: try await BackupService(store: store).export(), staging: staging)
        let json = try JSONSerialization.jsonObject(with: BackupArchive.encodeManifest(manifest)) as! [String: Any]

        let product = (json["products"] as! [[String: Any]])[0]
        #expect(product.keys.sorted() == [
            "brand", "currency", "id", "model", "name", "notes", "price", "productUrl", "purchaseDate", "retailer", "serialNumber",
            "warrantyExpires",
        ])
        let receipt = (json["receipts"] as! [[String: Any]])[0]
        #expect(receipt["productIds"] as? [Int] == [1])
    }

    @Test func decodesReceiptsSavedBeforeLinksAndReview() throws {
        let root = try temporaryDirectory()
        let earlier = #"{"products":[],"subscriptions":[],"documents":[],"receipts":[{"id":1,"merchant":"Deli","purchaseDate":null,"currency":"USD","items":[],"subtotal":null,"tax":null,"tip":null,"total":"4.50","category":"","tags":[],"notes":"","recognizedText":{},"addedOn":"2026-09-01"}],"attachments":[],"settings":{"themeMode":"SYSTEM","remindersEnabled":true,"warrantyLeadDays":30,"subscriptionLeadDays":7,"documentLeadDays":60,"defaultCurrency":"USD","reminderPromptDismissed":true}}"#
        try Data(earlier.utf8).write(to: root.appending(path: "tracker.json"))

        let receipt = try #require(TrackerStore(root: root).receipt(1))

        #expect(receipt.total == Decimal(string: "4.50"))
        #expect(receipt.productIds.isEmpty)
        #expect(receipt.resolvedFlags.isEmpty)
        #expect(receipt.pageDigests.isEmpty)
        #expect(receipt.pageConfidence.isEmpty)
    }

    @Test func rejectsInconsistentLinksAndScanData() throws {
        let receipt = Receipt(id: 4, merchant: "Deli", currency: "USD", productIds: [1], addedOn: day("2026-09-01"))
        let page = PettyTracker.Attachment(id: 9, ownerType: .receipt, ownerId: 4, displayName: "Scan.jpg",
                                           mimeType: "image/jpeg", fileName: "page.jpg", sizeBytes: 1)
        let valid = BackupManifest(version: 2, exportedAt: "x", products: [Product(id: 1, name: "P", currency: "USD")],
                                   receipts: [receipt], receiptAttachments: [page])
        try BackupArchive.validate(valid, files: ["page.jpg"])

        var danglingLink = valid
        danglingLink.receipts[0].productIds = [2]
        var linkedTwice = valid
        linkedTwice.receipts.append(Receipt(id: 5, merchant: "Other", currency: "USD", productIds: [1], addedOn: day("2026-09-01")))
        var foreignConfidence = valid
        foreignConfidence.receipts[0].pageConfidence = ["other.jpg": 0.5]
        var badConfidence = valid
        badConfidence.receipts[0].pageConfidence = ["page.jpg": 1.5]
        var foreignDigest = valid
        foreignDigest.receipts[0].pageDigests = ["other.jpg": "aa"]

        for invalid in [danglingLink, linkedTwice, foreignConfidence, badConfidence, foreignDigest] {
            #expect(throws: BackupError.self) { try BackupArchive.validate(invalid, files: ["page.jpg"]) }
        }
    }
}
