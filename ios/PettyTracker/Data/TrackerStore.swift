import Foundation
import Observation

struct TrackerData: Codable, Hashable, Sendable {
    var products: [Product] = []
    var subscriptions: [Subscription] = []
    var documents: [Document] = []
    var receipts: [Receipt] = []
    var attachments: [Attachment] = []
    var links: [RecordLink] = []
    var settings = Settings()

    private enum CodingKeys: String, CodingKey {
        case products, subscriptions, documents, receipts, attachments, links, settings
    }
}

extension TrackerData {
    // tracker.json files written before receipts or links existed have no "receipts" or "links" key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        products = try c.decode([Product].self, forKey: .products)
        subscriptions = try c.decode([Subscription].self, forKey: .subscriptions)
        documents = try c.decode([Document].self, forKey: .documents)
        receipts = try c.decodeIfPresent([Receipt].self, forKey: .receipts) ?? []
        attachments = try c.decode([Attachment].self, forKey: .attachments)
        links = try c.decodeIfPresent([RecordLink].self, forKey: .links) ?? []
        settings = try c.decode(Settings.self, forKey: .settings)
    }
}

/// All records live in one JSON file written atomically; attachment files sit beside it.
@MainActor
@Observable
final class TrackerStore {
    private(set) var data: TrackerData {
        didSet { index = Index(data) }
    }
    private(set) var today = Day.today()
    /// Lookups rebuilt whenever `data` changes, so list rows don't scan every attachment and receipt.
    private var index: Index

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

        var loaded = TrackerData()
        if let bytes = try? Data(contentsOf: fileURL) {
            do {
                loaded = try JSONDecoder().decode(TrackerData.self, from: bytes)
            } catch {
                // Keep the unreadable file for recovery instead of overwriting it on the next save.
                let aside = root.appending(path: "tracker-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fileManager.moveItem(at: fileURL, to: aside)
            }
        }
        data = loaded
        index = Index(loaded)
        BackupService.recoverInterruptedImport(root: root, referenced: Set(data.attachments.map(\.fileName)))
        try? fileManager.createDirectory(at: attachmentStore.directory, withIntermediateDirectories: true)
    }

    func refreshToday() {
        let now = Day.today()
        if now != today { today = now }
    }

    var settings: Settings { data.settings }

    func product(_ id: Int64) -> Product? { index.products[id].map { data.products[$0] } }
    func subscription(_ id: Int64) -> Subscription? { index.subscriptions[id].map { data.subscriptions[$0] } }
    func document(_ id: Int64) -> Document? { index.documents[id].map { data.documents[$0] } }
    func receipt(_ id: Int64) -> Receipt? { index.receipts[id].map { data.receipts[$0] } }

    func attachments(_ ownerType: OwnerType, _ ownerId: Int64) -> [Attachment] {
        index.attachments[Index.Owner(type: ownerType, id: ownerId)] ?? []
    }

    /// Every record linked to `ref`, with the link that joins them.
    func related(to ref: RecordRef) -> [(link: RecordLink, other: RecordRef)] {
        data.links.compactMap { link in link.other(than: ref).map { (link, $0) } }
    }

    func exists(_ ref: RecordRef) -> Bool {
        switch ref.type {
        case .product: product(ref.id) != nil
        case .subscription: subscription(ref.id) != nil
        case .document: document(ref.id) != nil
        case .receipt: receipt(ref.id) != nil
        }
    }

    func receiptCovering(_ productId: Int64) -> Receipt? {
        index.receiptByProduct[productId].flatMap(receipt)
    }

    func products(coveredBy receipt: Receipt) -> [Product] {
        receipt.productIds.compactMap(product)
    }

    /// Page file names of every receipt, in page order.
    var receiptPages: [Int64: [String]] { index.receiptPages }

    /// Saves the product and makes `receiptId` its only linked receipt, or unlinks it when nil.
    @discardableResult
    func saveProduct(_ product: Product, added: [Attachment], removed: [Attachment], receiptId: Int64?) throws -> Int64 {
        try saveOwned(.product, added: added, removed: removed) { data in
            let id = upsert(product, into: &data.products)
            link(id, to: receiptId, in: &data)
            return id
        }
    }

    /// Attaches files already copied into the attachment store, deleting the copies if the save fails.
    func addAttachments(_ added: [Attachment], to ownerType: OwnerType, _ ownerId: Int64) throws {
        do {
            _ = try saveOwned(ownerType, added: added, removed: []) { _ in ownerId }
        } catch {
            attachmentStore.delete(added.map(\.fileName))
            throw error
        }
    }

    func removeAttachment(_ attachment: Attachment) throws {
        _ = try saveOwned(attachment.ownerType, added: [], removed: [attachment]) { _ in attachment.ownerId }
    }

    func setLabel(_ label: AttachmentLabel, forAttachment attachmentId: Int64) throws {
        try mutate { data in
            guard let index = data.attachments.firstIndex(where: { $0.id == attachmentId }) else { return }
            data.attachments[index].label = label
        }
    }

    /// Links two records once; linking a pair again only updates the note.
    func addLink(_ from: RecordRef, to: RecordRef, note: String) throws {
        guard from != to else { return }
        try mutate { data in
            if let index = data.links.firstIndex(where: { $0.other(than: from) == to }) {
                data.links[index].note = note
            } else {
                data.links.append(RecordLink(id: nextId(data.links), from: from, to: to, note: note))
            }
        }
    }

    func unlink(_ linkId: Int64) throws {
        try mutate { $0.links.removeAll { $0.id == linkId } }
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
            data.removeLinks(to: RecordRef(type: .product, id: id))
        }
    }

    func deleteDocument(_ id: Int64) throws {
        try deleteOwned(.document, id) { data in
            data.documents.removeAll { $0.id == id }
            data.removeLinks(to: RecordRef(type: .document, id: id))
        }
    }

    func deleteReceipt(_ id: Int64) throws {
        try deleteOwned(.receipt, id) { data in
            data.receipts.removeAll { $0.id == id }
            data.removeLinks(to: RecordRef(type: .receipt, id: id))
        }
    }

    func deleteSubscription(_ id: Int64) throws {
        try mutate { data in
            data.subscriptions.removeAll { $0.id == id }
            data.removeLinks(to: RecordRef(type: .subscription, id: id))
        }
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

private struct Index {
    struct Owner: Hashable {
        let type: OwnerType
        let id: Int64
    }

    let attachments: [Owner: [Attachment]]
    let receiptByProduct: [Int64: Int64]
    let receiptPages: [Int64: [String]]
    /// Array positions by record id.
    let products: [Int64: Int]
    let subscriptions: [Int64: Int]
    let documents: [Int64: Int]
    let receipts: [Int64: Int]

    init(_ data: TrackerData) {
        func positions<T: Identifiable>(_ items: [T]) -> [Int64: Int] where T.ID == Int64 {
            Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        products = positions(data.products)
        subscriptions = positions(data.subscriptions)
        documents = positions(data.documents)
        receipts = positions(data.receipts)
        attachments = Dictionary(grouping: data.attachments) { Owner(type: $0.ownerType, id: $0.ownerId) }
        var receiptByProduct: [Int64: Int64] = [:]
        for receipt in data.receipts {
            for productId in receipt.productIds where receiptByProduct[productId] == nil {
                receiptByProduct[productId] = receipt.id
            }
        }
        self.receiptByProduct = receiptByProduct
        receiptPages = attachments.reduce(into: [:]) { pages, entry in
            if entry.key.type == .receipt { pages[entry.key.id] = entry.value.map(\.fileName) }
        }
    }
}

private extension TrackerData {
    mutating func removeLinks(to ref: RecordRef) {
        links.removeAll { $0.other(than: ref) != nil }
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
