import Foundation
import Testing
@testable import PettyTracker

@MainActor
struct RecordLinkTests {
    private func store() throws -> (TrackerStore, product: RecordRef, document: RecordRef) {
        let store = TrackerStore(root: try temporaryDirectory())
        try Data([1, 2]).write(to: store.attachmentStore.url(for: "part.jpg"))
        var product = Product(name: "Desk", currency: "USD")
        product.productUrl = "https://example.com/desk"
        let productId = try store.saveProduct(product, added: [
            PettyTracker.Attachment(ownerType: .product, ownerId: 0, displayName: "Leg.jpg", mimeType: "image/jpeg",
                                    fileName: "part.jpg", sizeBytes: 2, label: .part),
        ], removed: [], receiptId: nil)
        let documentId = try store.saveDocument(Document(title: "Home insurance"), added: [], removed: [])
        return (store, RecordRef(type: .product, id: productId), RecordRef(type: .document, id: documentId))
    }

    @Test func linksShowOnBothRecordsAndLinkingAgainOnlyUpdatesTheNote() throws {
        let (store, product, document) = try store()
        try store.addLink(product, to: document, note: "Insured")
        try store.addLink(document, to: product, note: "Covers")

        #expect(store.data.links.count == 1)
        #expect(store.related(to: product).map(\.other) == [document])
        #expect(store.related(to: document).map(\.other) == [product])
        #expect(store.related(to: product).first?.link.note == "Covers")
    }

    @Test func deletingARecordRemovesItsLinks() throws {
        let (store, product, document) = try store()
        try store.addLink(product, to: document, note: "")
        try store.deleteDocument(document.id)

        #expect(store.data.links.isEmpty)
        #expect(store.related(to: product).isEmpty)
    }

    @Test func backupKeepsLinksLabelsAndProductPages() async throws {
        let (store, product, document) = try store()
        try store.addLink(product, to: document, note: "Insured")
        let staging = try temporaryDirectory()
        let manifest = try BackupArchive.read(from: try await BackupService(store: store).export(), staging: staging)

        #expect(manifest.links.map(\.note) == ["Insured"])
        #expect(manifest.links.first.map { [$0.from, $0.to] } == [product, document])
        #expect(manifest.attachments.map(\.label) == [.part])
        #expect(manifest.products.map(\.productUrl) == ["https://example.com/desk"])
    }

    @Test func rejectsLinksToMissingRecords() throws {
        var manifest = BackupManifest(exportedAt: "x", documents: [Document(id: 1, title: "Passport")])
        manifest.links = [RecordLink(id: 1, from: RecordRef(type: .document, id: 1), to: RecordRef(type: .product, id: 9))]

        #expect(throws: BackupError.invalid("Invalid links between records")) {
            try BackupArchive.validate(manifest, files: [])
        }
    }

    @Test func readsFilesAndProductsSavedBeforeLabelsAndPages() throws {
        let attachment = try JSONDecoder().decode(PettyTracker.Attachment.self, from: Data(#"{"id":1,"ownerType":"PRODUCT","ownerId":1,"displayName":"a","mimeType":"image/jpeg","fileName":"a.jpg","sizeBytes":1}"#.utf8))
        let product = try JSONDecoder().decode(Product.self, from: Data(#"{"id":1,"name":"Desk","currency":"USD"}"#.utf8))

        #expect(attachment.label == .other)
        #expect(product.productUrl == "")
    }
}
