import Foundation
import Observation

struct TrackerData: Codable, Hashable, Sendable {
    var products: [Product] = []
    var subscriptions: [Subscription] = []
    var documents: [Document] = []
    var receipts: [Receipt] = []
    var attachments: [Attachment] = []
    var settings = Settings()

    private enum CodingKeys: String, CodingKey {
        case products, subscriptions, documents, receipts, attachments, settings
    }
}

extension TrackerData {
    // tracker.json files written before receipts existed have no "receipts" key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        products = try c.decode([Product].self, forKey: .products)
        subscriptions = try c.decode([Subscription].self, forKey: .subscriptions)
        documents = try c.decode([Document].self, forKey: .documents)
        receipts = try c.decodeIfPresent([Receipt].self, forKey: .receipts) ?? []
        attachments = try c.decode([Attachment].self, forKey: .attachments)
        settings = try c.decode(Settings.self, forKey: .settings)
    }
}

/// All records live in one JSON file written atomically; attachment files sit beside it.
@MainActor
@Observable
final class TrackerStore {
    private(set) var data: TrackerData
    private(set) var today = Day.today()

    let root: URL
    let attachmentStore: AttachmentStore
    @ObservationIgnored private let fileURL: URL

    static func appDefault() -> TrackerStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TrackerStore(root: support.appending(path: "PettyTracker", directoryHint: .isDirectory))
    }

    init(root: URL) {
        self.root = root
        fileURL = root.appending(path: "tracker.json")
        attachmentStore = AttachmentStore(directory: root.appending(path: "attachments", directoryHint: .isDirectory))
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = root
        try? excluded.setResourceValues(values)

        data = TrackerData()
        if let bytes = try? Data(contentsOf: fileURL) {
            do {
                data = try JSONDecoder().decode(TrackerData.self, from: bytes)
            } catch {
                // Keep the unreadable file for recovery instead of overwriting it on the next save.
                let aside = root.appending(path: "tracker-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fileManager.moveItem(at: fileURL, to: aside)
            }
        }
        BackupService.recoverInterruptedImport(root: root, referenced: Set(data.attachments.map(\.fileName)))
        try? fileManager.createDirectory(at: attachmentStore.directory, withIntermediateDirectories: true)
    }

    func refreshToday() {
        let now = Day.today()
        if now != today { today = now }
    }

    var settings: Settings { data.settings }

    func product(_ id: Int64) -> Product? { data.products.first { $0.id == id } }
    func subscription(_ id: Int64) -> Subscription? { data.subscriptions.first { $0.id == id } }
    func document(_ id: Int64) -> Document? { data.documents.first { $0.id == id } }
    func receipt(_ id: Int64) -> Receipt? { data.receipts.first { $0.id == id } }

    func attachments(_ ownerType: OwnerType, _ ownerId: Int64) -> [Attachment] {
        data.attachments.filter { $0.ownerType == ownerType && $0.ownerId == ownerId }
    }

    func receiptCovering(_ productId: Int64) -> Receipt? {
        data.receipts.first { $0.productIds.contains(productId) }
    }

    func products(coveredBy receipt: Receipt) -> [Product] {
        receipt.productIds.compactMap(product)
    }

    /// Page file names of every receipt, in page order.
    var receiptPages: [Int64: [String]] {
        Dictionary(grouping: data.attachments.filter { $0.ownerType == .receipt }, by: \.ownerId)
            .mapValues { $0.map(\.fileName) }
    }

    /// Saves the product and makes `receiptId` its only linked receipt, or unlinks it when nil.
    @discardableResult
    func saveProduct(_ product: Product, added: [Attachment], removed: [Attachment], receiptId: Int64?) throws -> Int64 {
        try saveOwned(.product, added: added, removed: removed) { data in
            let id = upsert(product, into: &data.products)
            link(id, to: receiptId, in: &data)
            return id
        }
    }

    func linkProduct(_ productId: Int64, toReceipt receiptId: Int64?) throws {
        try mutate { link(productId, to: receiptId, in: &$0) }
    }

    /// Resolves every current review flag; they come back only if the values behind them change.
    func markReviewed(_ receiptId: Int64) throws {
        guard let receipt = receipt(receiptId) else { return }
        let pages = attachments(.receipt, receiptId).map(\.fileName)
        let flags = ReceiptReview.flags(for: receipt, pages: pages, among: data.receipts)
        try setResolvedFlags(flags.map(\.id), forReceipt: receiptId)
    }

    func setResolvedFlags(_ flags: [String], forReceipt receiptId: Int64) throws {
        try mutate { data in
            guard let index = data.receipts.firstIndex(where: { $0.id == receiptId }) else { return }
            data.receipts[index].resolvedFlags = flags
        }
    }

    @discardableResult
    func saveDocument(_ document: Document, added: [Attachment], removed: [Attachment]) throws -> Int64 {
        try saveOwned(.document, added: added, removed: removed) { data in
            upsert(document, into: &data.documents)
        }
    }

    /// Per-page scan data is kept only for pages that remain attached after the save.
    @discardableResult
    func saveReceipt(_ receipt: Receipt, added: [Attachment], removed: [Attachment]) throws -> Int64 {
        let removedFiles = Set(removed.map(\.fileName))
        let pages = Set(attachments(.receipt, receipt.id).map(\.fileName).filter { !removedFiles.contains($0) })
            .union(added.map(\.fileName))
        var pruned = receipt
        pruned.recognizedText = receipt.recognizedText.filter { pages.contains($0.key) }
        pruned.pageConfidence = receipt.pageConfidence.filter { pages.contains($0.key) }
        pruned.pageDigests = receipt.pageDigests.filter { pages.contains($0.key) }
        return try saveOwned(.receipt, added: added, removed: removed) { data in
            upsert(pruned, into: &data.receipts)
        }
    }

    @discardableResult
    func saveSubscription(_ subscription: Subscription) throws -> Int64 {
        try mutate { upsert(subscription, into: &$0.subscriptions) }
    }

    func updateSubscription(_ id: Int64, _ transform: (Subscription) -> Subscription) throws {
        try mutate { data in
            guard let index = data.subscriptions.firstIndex(where: { $0.id == id }) else { return }
            data.subscriptions[index] = transform(data.subscriptions[index])
        }
    }

    func deleteProduct(_ id: Int64) throws {
        try deleteOwned(.product, id) { data in
            data.products.removeAll { $0.id == id }
            link(id, to: nil, in: &data)
        }
    }

    func deleteDocument(_ id: Int64) throws {
        try deleteOwned(.document, id) { $0.documents.removeAll { $0.id == id } }
    }

    func deleteReceipt(_ id: Int64) throws {
        try deleteOwned(.receipt, id) { $0.receipts.removeAll { $0.id == id } }
    }

    func deleteSubscription(_ id: Int64) throws {
        try mutate { $0.subscriptions.removeAll { $0.id == id } }
    }

    func updateSettings(_ transform: (inout Settings) -> Void) throws {
        try mutate { transform(&$0.settings) }
    }

    /// Swaps in imported records; the caller has already put the matching attachment files in place.
    func replaceAll(with imported: TrackerData) throws {
        try mutate { $0 = imported }
    }

    func deleteOrphanedAttachments() {
        attachmentStore.deleteOrphans(referenced: Set(data.attachments.map(\.fileName)))
    }

    /// Fills in page digests for receipts scanned before digests were recorded or restored from such backups.
    func backfillPageDigests() async {
        let missing = data.attachments.filter { page in
            page.ownerType == .receipt && receipt(page.ownerId)?.pageDigests[page.fileName] == nil
        }
        var digests: [String: String] = [:]
        for page in missing {
            digests[page.fileName] = try? await attachmentStore.digest(of: page.fileName)
        }
        guard !digests.isEmpty else { return }
        try? mutate { data in
            for (fileName, digest) in digests {
                guard let page = data.attachments.first(where: { $0.fileName == fileName }), page.ownerType == .receipt,
                      let index = data.receipts.firstIndex(where: { $0.id == page.ownerId }),
                      data.receipts[index].pageDigests[fileName] == nil
                else { continue }
                data.receipts[index].pageDigests[fileName] = digest
            }
        }
    }

    // MARK: - Private

    private func mutate<T>(_ body: (inout TrackerData) throws -> T) throws -> T {
        var next = data
        let result = try body(&next)
        guard next != data else { return result }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try encoder.encode(next).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        data = next
        return result
    }

    private func saveOwned(
        _ ownerType: OwnerType,
        added: [Attachment],
        removed: [Attachment],
        upsert: (inout TrackerData) -> Int64
    ) throws -> Int64 {
        let removedIds = Set(removed.map(\.id))
        let id = try mutate { data in
            let id = upsert(&data)
            var attachmentId = nextId(data.attachments)
            for attachment in added {
                var owned = attachment
                owned.id = attachmentId
                owned.ownerType = ownerType
                owned.ownerId = id
                data.attachments.append(owned)
                attachmentId += 1
            }
            data.attachments.removeAll { removedIds.contains($0.id) }
            return id
        }
        attachmentStore.delete(removed.map(\.fileName))
        return id
    }

    private func deleteOwned(_ ownerType: OwnerType, _ id: Int64, delete: (inout TrackerData) -> Void) throws {
        let files = attachments(ownerType, id).map(\.fileName)
        try mutate { data in
            data.attachments.removeAll { $0.ownerType == ownerType && $0.ownerId == id }
            delete(&data)
        }
        attachmentStore.delete(files)
    }
}

private protocol Record: Identifiable where ID == Int64 {
    var id: Int64 { get set }
}

extension Product: Record {}
extension Subscription: Record {}
extension Document: Record {}
extension Receipt: Record {}

private func nextId<T: Identifiable>(_ items: [T]) -> Int64 where T.ID == Int64 {
    (items.map(\.id).max() ?? 0) + 1
}

private func link(_ productId: Int64, to receiptId: Int64?, in data: inout TrackerData) {
    guard data.receipts.first(where: { $0.productIds.contains(productId) })?.id != receiptId else { return }
    for index in data.receipts.indices {
        data.receipts[index].productIds.removeAll { $0 == productId }
    }
    if let receiptId, let index = data.receipts.firstIndex(where: { $0.id == receiptId }) {
        data.receipts[index].productIds.append(productId)
    }
}

private func upsert<T: Record>(_ record: T, into items: inout [T]) -> Int64 {
    if record.id != 0, let index = items.firstIndex(where: { $0.id == record.id }) {
        items[index] = record
        return record.id
    }
    var inserted = record
    inserted.id = nextId(items)
    items.append(inserted)
    return inserted.id
}
