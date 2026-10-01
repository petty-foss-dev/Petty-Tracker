import Foundation
import Testing
@testable import PettyTracker

@MainActor
struct ImportTests {
    private func storeWithReceipt() throws -> (TrackerStore, PettyTracker.Attachment) {
        let store = TrackerStore(root: try temporaryDirectory())
        try Data([7, 7, 7]).write(to: store.attachmentStore.url(for: "receipt.pdf"))
        let receipt = PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Receipt.pdf",
                                              mimeType: "application/pdf", fileName: "receipt.pdf", sizeBytes: 3)
        try store.saveProduct(Product(name: "Laptop", currency: "USD"), added: [receipt], removed: [], receiptId: nil)
        try store.updateSettings { $0.reminderPromptDismissed = false }
        return (store, store.data.attachments[0])
    }

    @Test func invalidArchiveLeavesExistingDataUntouched() async throws {
        let (store, receipt) = try storeWithReceipt()
        let before = store.data
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, #"{"format":"enve-keep-backup","exportedAt":"x","attachments":[{"id":1,"ownerType":"PRODUCT","ownerId":9,"displayName":"x","mimeType":"x","fileName":"x.jpg","sizeBytes":1}]}"#)
        let archive = try zip.write(in: try temporaryDirectory())

        await #expect(throws: BackupError.self) { try await BackupService(store: store).stage(archive) }

        #expect(store.data == before)
        #expect(try Data(contentsOf: store.attachmentStore.url(for: receipt.fileName)) == Data([7, 7, 7]))
        #expect(!FileManager.default.fileExists(atPath: store.root.appending(path: "import-staging").path))
    }

    @Test func androidBackupReplacesEverythingButThePromptFlag() async throws {
        let (store, receipt) = try storeWithReceipt()
        let service = BackupService(store: store)

        let staged = try await service.stage(Fixtures.url("android-device-backup.zip"))
        #expect(store.data.products.count == 1)
        try service.commit(staged)

        #expect(store.data.products.isEmpty)
        #expect(store.data.attachments.isEmpty)
        #expect(store.data.documents.map(\.title) == ["Passport"])
        #expect(store.data.settings.defaultCurrency == "USD")
        #expect(store.data.settings.reminderPromptDismissed == false)
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: receipt.fileName).path))

        let reloaded = TrackerStore(root: store.root)
        #expect(reloaded.data == store.data)
    }

    @Test func exportThenImportRestoresAttachments() async throws {
        let (store, receipt) = try storeWithReceipt()
        let service = BackupService(store: store)
        let exported = try await service.export()
        let snapshot = store.data

        try store.deleteProduct(store.data.products[0].id)
        #expect(store.data.attachments.isEmpty)

        try service.commit(try await service.stage(exported))
        #expect(store.data == snapshot)
        #expect(try Data(contentsOf: store.attachmentStore.url(for: receipt.fileName)) == Data([7, 7, 7]))
    }

    @Test func interruptedImportRestoresPreviousAttachments() throws {
        let root = try temporaryDirectory()
        let live = root.appending(path: "attachments")
        let previous = root.appending(path: "attachments-previous")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data([1]).write(to: previous.appending(path: "kept.jpg"))

        BackupService.recoverInterruptedImport(root: root, referenced: ["kept.jpg"])

        #expect(FileManager.default.fileExists(atPath: live.appending(path: "kept.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: previous.path))
    }

    @Test func deletingRecordsRemovesTheirFiles() throws {
        let (store, receipt) = try storeWithReceipt()
        try store.deleteProduct(receipt.ownerId)
        #expect(!FileManager.default.fileExists(atPath: store.attachmentStore.url(for: receipt.fileName).path))
    }
}
