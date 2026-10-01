import Foundation
import Testing
import UIKit
@testable import PettyTracker

@MainActor
struct ReceiptStoreTests {
    private func page(_ store: TrackerStore, _ name: String) throws -> PettyTracker.Attachment {
        try Data([1, 2, 3]).write(to: store.attachmentStore.url(for: name))
        return PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Scan.jpg",
                                       mimeType: "image/jpeg", fileName: name, sizeBytes: 3)
    }

    @Test func decodesKeepFileWrittenBeforeReceipts() throws {
        let root = try temporaryDirectory()
        let legacy = #"{"products":[{"id":1,"name":"Kettle","brand":"","model":"","serialNumber":"","purchaseDate":null,"retailer":"","price":null,"currency":"USD","warrantyExpires":null,"notes":""}],"subscriptions":[],"documents":[],"attachments":[],"settings":{"themeMode":"DARK","remindersEnabled":true,"warrantyLeadDays":30,"subscriptionLeadDays":7,"documentLeadDays":60,"defaultCurrency":"USD","reminderPromptDismissed":true}}"#
        try Data(legacy.utf8).write(to: root.appending(path: "tracker.json"))

        let store = TrackerStore(root: root)

        #expect(store.data.products.map(\.name) == ["Kettle"])
        #expect(store.data.receipts.isEmpty)
        #expect(store.settings.themeMode == .dark)
        let unreadable = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("tracker-unreadable") }
        #expect(unreadable.isEmpty)
    }

    @Test func savesReceiptWithPagesAndReloads() throws {
        let store = TrackerStore(root: try temporaryDirectory())
        let first = try page(store, "p1.jpg")
        let second = try page(store, "p2.jpg")
        var receipt = Receipt(merchant: "Cafe", currency: "USD", addedOn: day("2026-09-29"))
        receipt.items = [ReceiptItem(description: "Tea", quantity: 2, amount: Decimal(string: "-1.25"))]
        receipt.recognizedText = ["p1.jpg": "CAFE\nTEA 2.50", "p2.jpg": "THANK YOU", "gone.jpg": "stale"]

        let id = try store.saveReceipt(receipt, added: [first, second], removed: [])

        let saved = try #require(store.receipt(id))
        #expect(saved.recognizedText.keys.sorted() == ["p1.jpg", "p2.jpg"])
        #expect(store.attachments(.receipt, id).map(\.fileName) == ["p1.jpg", "p2.jpg"])
        #expect(TrackerStore(root: store.root).data == store.data)

        let pageToRemove = store.attachments(.receipt, id)[1]
        try store.saveReceipt(saved, added: [], removed: [pageToRemove])
        #expect(store.receipt(id)?.recognizedText.keys.sorted() == ["p1.jpg"])
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "p2.jpg").path))

        try store.deleteReceipt(id)
        #expect(store.data.receipts.isEmpty)
        #expect(store.data.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "p1.jpg").path))
    }
}

struct ReceiptPageImportTests {
    @Test func picksImageFilesAsJPEGPages() async throws {
        let directory = try temporaryDirectory()
        let store = AttachmentStore(directory: directory.appending(path: "attachments"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let png = directory.appending(path: "Till slip.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        try image.pngData()!.write(to: png)

        let page = try await store.importImage(at: png)

        #expect(page.displayName == "Till slip.jpg")
        #expect(page.mimeType == "image/jpeg")
        #expect(page.fileName.hasSuffix(".jpg"))
        let stored = try Data(contentsOf: store.url(for: page.fileName))
        #expect(stored.starts(with: [0xFF, 0xD8]))
    }
}

@MainActor
struct ReceiptBackupTests {
    private func storeWithProductAndReceipt(receipt: Bool) throws -> TrackerStore {
        let store = TrackerStore(root: try temporaryDirectory())
        try Data([7]).write(to: store.attachmentStore.url(for: "manual.pdf"))
        try store.saveProduct(Product(name: "Blender", currency: "USD"), added: [
            PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Manual.pdf",
                                    mimeType: "application/pdf", fileName: "manual.pdf", sizeBytes: 1),
        ], removed: [], receiptId: nil)
        if receipt {
            try Data([9, 9]).write(to: store.attachmentStore.url(for: "scan.jpg"))
            var receipt = Receipt(merchant: "Kitchen Shop", purchaseDate: day("2026-09-01"), currency: "USD",
                                  total: Decimal(string: "49.99"), addedOn: day("2026-09-02"))
            receipt.recognizedText = ["scan.jpg": "KITCHEN SHOP\nTOTAL 49.99"]
            receipt.purchaseTime = ClockTime(hour: 18, minute: 42)
            receipt.origin = "San Francisco"
            receipt.destination = "Los Angeles"
            receipt.fuelVolume = Decimal(string: "10.543")
            receipt.fuelUnit = .gallons
            receipt.customFields = [ReceiptField(name: "Vehicle", value: "Civic"), ReceiptField(name: "Vehicle", value: "")]
            try store.saveReceipt(receipt, added: [
                PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Scan.jpg",
                                        mimeType: "image/jpeg", fileName: "scan.jpg", sizeBytes: 2),
            ], removed: [])
        }
        return store
    }

    private func manifestJSON(in archive: URL) throws -> [String: Any] {
        let staging = try temporaryDirectory()
        let manifest = try BackupArchive.read(from: archive, staging: staging)
        return try JSONSerialization.jsonObject(with: BackupArchive.encodeManifest(manifest)) as! [String: Any]
    }

    @Test func exportWithoutReceiptsStaysAndroidVersionOne() async throws {
        let store = try storeWithProductAndReceipt(receipt: false)
        let json = try manifestJSON(in: try await BackupService(store: store).export())

        #expect(json["version"] as? Int == 1)
        #expect(json.keys.sorted() == ["attachments", "documents", "exportedAt", "format", "products", "settings", "subscriptions", "version"])
    }

    @Test func exportWithReceiptsIsVersionThreeAndKeepsVersionOneShapeReadable() async throws {
        let store = try storeWithProductAndReceipt(receipt: true)
        let json = try manifestJSON(in: try await BackupService(store: store).export())

        #expect(json["version"] as? Int == 3)
        // Android's version 1 decoder must still parse every known key so it reaches its version check.
        let attachments = json["attachments"] as! [[String: Any]]
        #expect(attachments.map { $0["ownerType"] as? String } == ["PRODUCT"])
        let receiptPages = json["receiptAttachments"] as! [[String: Any]]
        #expect(receiptPages.map { $0["ownerType"] as? String } == ["RECEIPT"])
        let receipt = (json["receipts"] as! [[String: Any]])[0]
        #expect(receipt["total"] as? String == "49.99")
        #expect(receipt["purchaseDate"] as? String == "2026-09-01")
        #expect(receipt["tip"] is NSNull)
        #expect((receipt["recognizedText"] as? [String: String])?["scan.jpg"] == "KITCHEN SHOP\nTOTAL 49.99")
    }

    @Test func versionThreeRoundTripsThroughImport() async throws {
        let store = try storeWithProductAndReceipt(receipt: true)
        let service = BackupService(store: store)
        let exported = try await service.export()
        let snapshot = store.data

        try store.deleteReceipt(store.data.receipts[0].id)
        try store.deleteProduct(store.data.products[0].id)
        let staged = try await service.stage(exported)
        #expect(staged.recordCount == 2)
        #expect(staged.attachmentCount == 2)
        try service.commit(staged)

        #expect(store.data == snapshot)
        #expect(try Data(contentsOf: store.attachmentStore.url(for: "scan.jpg")) == Data([9, 9]))
        #expect(TrackerStore(root: store.root).data == snapshot)
    }

    @Test func androidVersionOneBackupReplacesReceipts() async throws {
        let store = try storeWithProductAndReceipt(receipt: true)
        let service = BackupService(store: store)

        try service.commit(try await service.stage(Fixtures.url("android-device-backup.zip")))

        #expect(store.data.receipts.isEmpty)
        #expect(store.data.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "scan.jpg").path))
    }

    @Test func invalidVersionTwoLeavesReceiptsUntouched() async throws {
        let store = try storeWithProductAndReceipt(receipt: true)
        let before = store.data
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, #"{"format":"enve-keep-backup","version":2,"exportedAt":"x","receipts":[{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-01-01"}],"receiptAttachments":[{"id":1,"ownerType":"RECEIPT","ownerId":1,"displayName":"x","mimeType":"image/jpeg","fileName":"missing.jpg","sizeBytes":1}]}"#)

        await #expect(throws: BackupError.self) {
            try await BackupService(store: store).stage(zip.write(in: try temporaryDirectory()))
        }
        #expect(store.data == before)
        #expect(FileManager.default.fileExists(atPath: store.attachmentStore.url(for: "scan.jpg").path))
    }
}

struct ReceiptManifestValidationTests {
    private let receipt = Receipt(id: 4, merchant: "Deli", currency: "USD", recognizedText: ["page.jpg": "DELI"],
                                  addedOn: day("2026-09-01"))
    private let page = PettyTracker.Attachment(id: 9, ownerType: .receipt, ownerId: 4, displayName: "Scan.jpg",
                                               mimeType: "image/jpeg", fileName: "page.jpg", sizeBytes: 1)

    private var valid: BackupManifest {
        BackupManifest(version: 2, exportedAt: "x", receipts: [receipt], receiptAttachments: [page])
    }

    @Test func acceptsWellFormedVersionTwo() throws {
        try BackupArchive.validate(valid, files: ["page.jpg"])
    }

    @Test func rejectsInconsistentReceiptData() {
        var versionOne = valid
        versionOne.version = 1
        var pageInMainList = valid
        pageInMainList.attachments = [page]
        pageInMainList.receiptAttachments = []
        var wrongOwnerType = valid
        wrongOwnerType.receiptAttachments[0].ownerType = .document
        var orphanPage = valid
        orphanPage.receiptAttachments[0].ownerId = 5
        var foreignText = valid
        foreignText.receipts[0].recognizedText["other.jpg"] = "?"
        var duplicateIds = valid
        duplicateIds.receipts.append(receipt)
        var clashingAttachmentIds = valid
        clashingAttachmentIds.products = [Product(id: 1, name: "P", currency: "USD")]
        clashingAttachmentIds.attachments = [PettyTracker.Attachment(id: 9, ownerType: .product, ownerId: 1, displayName: "p",
                                                                     mimeType: "image/jpeg", fileName: "p.jpg", sizeBytes: 1)]
        var badCurrency = valid
        badCurrency.receipts[0].currency = "ZZZ"

        for invalid in [versionOne, pageInMainList, wrongOwnerType, orphanPage, foreignText, duplicateIds,
                        clashingAttachmentIds, badCurrency] {
            #expect(throws: BackupError.self) { try BackupArchive.validate(invalid, files: ["page.jpg", "p.jpg"]) }
        }
    }

    @Test func versionOneManifestEncodesWithoutReceiptKeys() throws {
        let json = try JSONSerialization.jsonObject(with: BackupArchive.encodeManifest(BackupManifest(exportedAt: "x"))) as! [String: Any]
        #expect(json["receipts"] == nil)
        #expect(json["receiptAttachments"] == nil)
    }
}
