import CryptoKit
import Foundation

struct BackupHistory: Codable, Hashable, Sendable {
    let lastExport: Date?
    let restored: Date?
    let baseline: BackupFingerprint
}

struct BackupDifference: Equatable, Sendable {
    var added = 0
    var edited = 0
    var removed = 0
    var settingsChanged = false
}

struct BackupFingerprint: Codable, Hashable, Sendable {
    private let records: [String: Data]
    private let settings: Data

    init(_ data: TrackerData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func digest(_ value: some Encodable) throws -> Data {
            Data(SHA256.hash(data: try encoder.encode(value)))
        }

        var components: [RecordRef: [Data]] = [:]
        func addRecords<T: Identifiable & Encodable>(_ records: [T], type: RecordType) throws where T.ID == Int64 {
            for record in records {
                components[RecordRef(type: type, id: record.id)] = [try digest(record)]
            }
        }

        try addRecords(data.products, type: .product)
        try addRecords(data.subscriptions, type: .subscription)
        try addRecords(data.documents, type: .document)
        try addRecords(data.receipts, type: .receipt)
        for attachment in data.attachments {
            let type: RecordType = switch attachment.ownerType {
            case .document: .document
            case .receipt: .receipt
            case .product: .product
            }
            components[RecordRef(type: type, id: attachment.ownerId)]?.append(try digest(attachment))
        }
        for link in data.links {
            let hash = try digest(link)
            components[link.from]?.append(hash)
            components[link.to]?.append(hash)
        }
        for receipt in data.receipts where !receipt.productIds.isEmpty {
            let hash = try digest(receipt.id)
            for id in receipt.productIds {
                components[RecordRef(type: .product, id: id)]?.append(hash)
            }
        }
        var records: [String: Data] = [:]
        for (key, parts) in components {
            var hasher = SHA256()
            for part in parts { hasher.update(data: part) }
            records["\(key.type.rawValue)/\(key.id)"] = Data(hasher.finalize())
        }
        self.records = records
        self.settings = try digest(data.settings)
    }

    func changes(since previous: Self) -> BackupDifference {
        var difference = BackupDifference(settingsChanged: settings != previous.settings)
        for (id, digest) in records {
            if let old = previous.records[id] {
                if old != digest { difference.edited += 1 }
            } else {
                difference.added += 1
            }
        }
        difference.removed = previous.records.keys.reduce(0) { $0 + (records[$1] == nil ? 1 : 0) }
        return difference
    }
}
