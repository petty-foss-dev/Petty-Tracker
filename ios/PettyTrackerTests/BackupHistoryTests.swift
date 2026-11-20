import Foundation
import Testing
@testable import PettyTracker

@MainActor
struct BackupHistoryTests {
    @Test func preparationAndCancellationLeaveHistoryAloneAndOnlySavedSnapshotCounts() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackerStore(root: root)
        let first = try store.saveDocument(Document(title: "Lease"), added: [], removed: [])
        let prepared = try await BackupService(store: store).export()
        defer { prepared.discard() }
        #expect(store.data.backupHistory == nil)

        var document = try #require(store.document(first))
        document.title = "Lease renewal"
        try store.saveDocument(document, added: [], removed: [])
        document.notes = "Final copy"
        try store.saveDocument(document, added: [], removed: [])
        let saved = Date.now
        try store.recordExport(prepared, at: saved)
        let history = try #require(TrackerStore(root: root).data.backupHistory)
        #expect(history.lastExport == saved)
        #expect(try BackupFingerprint(store.data).changes(since: history.baseline) == BackupDifference(edited: 1))

        let canceled = try await BackupService(store: store).export()
        canceled.discard()
        #expect(!FileManager.default.fileExists(atPath: canceled.url.path))
        #expect(FileManager.default.fileExists(atPath: prepared.url.path))
        #expect(store.data.backupHistory == history)
    }

    @Test func attachmentEditsDeletionsAndSettingsAreCountedSeparately() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackerStore(root: root)
        let productID = try store.saveProduct(Product(name: "Monitor", currency: "USD"), added: [], removed: [], receiptId: nil)
        let oldDoc = try store.saveDocument(Document(title: "Old policy"), added: [], removed: [])
        let exported = try await BackupService(store: store).export()
        defer { exported.discard() }
        try store.recordExport(exported)
        let before = exported.fingerprint
        let manual = Attachment(ownerType: .product, ownerId: productID, displayName: "Manual", mimeType: "application/pdf", fileName: "manual.pdf", sizeBytes: 2)
        try Data([1, 2]).write(to: store.attachmentStore.url(for: manual.fileName))
        try store.addAttachments([manual], to: .product, productID)
        let stored = try #require(store.attachments(.product, productID).first)
        try store.setLabel(.instructions, forAttachment: stored.id)
        try store.deleteDocument(oldDoc)
        try store.saveReceipt(Receipt(merchant: "Grocer", currency: "USD", addedOn: day("2026-01-01")), added: [], removed: [])
        try store.updateSettings { $0.remindersEnabled.toggle() }

        #expect(try BackupFingerprint(store.data).changes(since: before) == BackupDifference(added: 1, edited: 1, removed: 1, settingsChanged: true))
        try store.removeAttachment(stored)
        #expect(try BackupFingerprint(store.data).changes(since: before).edited == 0)
    }

    @Test func linksMarkBothEndpointsAndRestoringRebasesWithoutClaimingAnExport() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackerStore(root: root)
        let product = try store.saveProduct(Product(name: "Pen", currency: "USD"), added: [], removed: [], receiptId: nil)
        let doc = try store.saveDocument(Document(title: "Certificate"), added: [], removed: [])
        let service = BackupService(store: store)
        let prepared = try await service.export()
        defer { prepared.discard() }
        try store.addLink(RecordRef(type: .product, id: product), to: RecordRef(type: .document, id: doc), note: "Certificate")
        #expect(try BackupFingerprint(store.data).changes(since: prepared.fingerprint).edited == 2)

        let staged = try await service.stage(prepared.url)
        #expect(store.data.backupHistory == nil)
        try service.commit(staged)
        let restored = try #require(store.data.backupHistory)
        #expect(restored.lastExport == nil)
        #expect(restored.restored != nil)
        #expect(try BackupFingerprint(store.data).changes(since: restored.baseline) == BackupDifference())
        try store.recordExport(prepared)
        #expect(store.data.backupHistory?.restored == restored.restored)
        let current = try await service.export()
        defer { current.discard() }
        try store.recordExport(current)
        #expect(store.data.backupHistory?.lastExport != nil)
        #expect(store.data.backupHistory?.restored == nil)
    }

    @Test func olderStoreOpensAndFailedPreparationPreservesRecordedExport() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldJSON = #"{"products":[],"subscriptions":[],"documents":[],"attachments":[],"settings":{}}"#
        try Data(oldJSON.utf8).write(to: root.appending(path: "tracker.json"))
        let store = TrackerStore(root: root)
        #expect(store.data.backupHistory == nil)
        let good = try await BackupService(store: store).export()
        defer { good.discard() }
        try store.recordExport(good)
        let saved = store.data.backupHistory
        let missing = Attachment(ownerType: .document, ownerId: 0, displayName: "Scan", mimeType: "image/jpeg", fileName: "missing.jpg", sizeBytes: 20)
        try store.saveDocument(Document(title: "Permit"), added: [missing], removed: [])
        await #expect(throws: (any Error).self) { try await BackupService(store: store).export() }
        #expect(store.data.backupHistory == saved)
        #expect(try BackupFingerprint(store.data).changes(since: good.fingerprint).added == 1)
    }
}
