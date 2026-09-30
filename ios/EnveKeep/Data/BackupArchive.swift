import Foundation
import ZIPFoundation

/// Receipt pages start in version 2; version 3 adds searchable receipt details.
struct BackupManifest: Hashable, Sendable {
    static let format = "enve-keep-backup"
    static let androidVersion = 1
    static let receiptsVersion = 2
    static let detailsVersion = 3

    var format = BackupManifest.format
    var version = BackupManifest.androidVersion
    var exportedAt: String
    var products: [Product] = []
    var subscriptions: [Subscription] = []
    var documents: [Document] = []
    var attachments: [Attachment] = []
    var receipts: [Receipt] = []
    var receiptAttachments: [Attachment] = []
    var settings: Settings?
}

extension BackupManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, products, subscriptions, documents, attachments, receipts,
             receiptAttachments, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? Self.format
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.androidVersion
        exportedAt = try c.decode(String.self, forKey: .exportedAt)
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        documents = try c.decodeIfPresent([Document].self, forKey: .documents) ?? []
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        receipts = try c.decodeIfPresent([Receipt].self, forKey: .receipts) ?? []
        receiptAttachments = try c.decodeIfPresent([Attachment].self, forKey: .receiptAttachments) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(version, forKey: .version)
        try c.encode(exportedAt, forKey: .exportedAt)
        try c.encode(products, forKey: .products)
        try c.encode(subscriptions, forKey: .subscriptions)
        try c.encode(documents, forKey: .documents)
        try c.encode(attachments, forKey: .attachments)
        if version >= Self.receiptsVersion {
            try c.encode(receipts, forKey: .receipts)
            try c.encode(receiptAttachments, forKey: .receiptAttachments)
        }
        try c.encode(settings, forKey: .settings)
    }
}

enum BackupError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        }
    }
}

/// ZIP layout shared with petty: Tracker Android: `backup.json` plus flat `attachments/<safe name>` entries.
enum BackupArchive {
    static let manifestName = "backup.json"
    static let attachmentPrefix = "attachments/"
    static let maxManifestBytes: UInt64 = 64 * 1024 * 1024
    static let maxTotalBytes: UInt64 = 4 * 1024 * 1024 * 1024

    static func isSafeFileName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9_\-]{0,127}(\.[A-Za-z0-9]{1,10})?/) != nil
    }

    static func encodeManifest(_ manifest: BackupManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    static func write(_ manifest: BackupManifest, attachmentsDirectory: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        let archive = try Archive(url: destination, accessMode: .create)
        let json = try encodeManifest(manifest)
        try archive.addEntry(
            with: manifestName, type: .file, uncompressedSize: Int64(json.count), compressionMethod: .deflate
        ) { position, size in
            json.subdata(in: Int(position)..<Int(position) + size)
        }
        for attachment in manifest.attachments + manifest.receiptAttachments {
            try archive.addEntry(
                with: attachmentPrefix + attachment.fileName,
                fileURL: attachmentsDirectory.appending(path: attachment.fileName),
                compressionMethod: .deflate
            )
        }
    }

    /// Extracts attachments into `staging/attachments` and returns the validated manifest. Only the
    /// manifest and flat, safely named attachment files are accepted, so nothing lands outside staging.
    static func read(from source: URL, staging: URL) throws -> BackupManifest {
        let fileManager = FileManager.default
        let attachmentsDir = staging.appending(path: "attachments", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        let archive: Archive
        do {
            archive = try Archive(url: source, accessMode: .read)
        } catch {
            throw BackupError.invalid("Corrupt archive")
        }

        var manifestData: Data?
        var extracted = Set<String>()
        var total: UInt64 = 0

        func consume(_ entry: Entry, limit: UInt64, into write: (Data) throws -> Void) throws {
            guard entry.uncompressedSize <= limit else { throw BackupError.invalid("Backup is too large") }
            var written: UInt64 = 0
            let checksum: CRC32
            do {
                checksum = try archive.extract(entry) { chunk in
                    written += UInt64(chunk.count)
                    guard written <= limit else { throw BackupError.invalid("Backup is too large") }
                    try write(chunk)
                }
            } catch let error as BackupError {
                throw error
            } catch {
                throw BackupError.invalid("Corrupt archive")
            }
            guard checksum == entry.checksum else { throw BackupError.invalid("Corrupt archive") }
            total += written
        }

        for entry in archive {
            let name = entry.path
            if entry.type == .directory && name == attachmentPrefix { continue }
            guard entry.type == .file else { throw BackupError.invalid("Unexpected entry: \(name)") }

            if name == manifestName {
                guard manifestData == nil else { throw BackupError.invalid("Duplicate manifest") }
                var bytes = Data()
                try consume(entry, limit: min(maxManifestBytes, maxTotalBytes - total)) { bytes.append($0) }
                manifestData = bytes
            } else if name.hasPrefix(attachmentPrefix) {
                let fileName = String(name.dropFirst(attachmentPrefix.count))
                guard isSafeFileName(fileName), extracted.insert(fileName).inserted else {
                    throw BackupError.invalid("Unexpected entry: \(name)")
                }
                let target = attachmentsDir.appending(path: fileName)
                guard target.deletingLastPathComponent().standardizedFileURL == attachmentsDir.standardizedFileURL,
                      fileManager.createFile(atPath: target.path, contents: nil)
                else { throw BackupError.invalid("Unexpected entry: \(name)") }
                let handle = try FileHandle(forWritingTo: target)
                defer { try? handle.close() }
                try consume(entry, limit: maxTotalBytes - total) { try handle.write(contentsOf: $0) }
            } else {
                throw BackupError.invalid("Unexpected entry: \(name)")
            }
        }

        guard let manifestData else { throw BackupError.invalid("Missing \(manifestName)") }
        let manifest: BackupManifest
        do {
            manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        } catch {
            throw BackupError.invalid("Unreadable manifest")
        }
        try validate(manifest, files: extracted)
        let referenced = Set((manifest.attachments + manifest.receiptAttachments).map(\.fileName))
        for stray in extracted.subtracting(referenced) {
            try? fileManager.removeItem(at: attachmentsDir.appending(path: stray))
        }
        return manifest
    }

    static func validate(_ manifest: BackupManifest, files: Set<String>) throws {
        guard manifest.format == BackupManifest.format else { throw BackupError.invalid("Not a petty: Tracker backup") }
        guard manifest.version <= BackupManifest.detailsVersion else {
            throw BackupError.invalid("Backup was made by a newer version of petty: Tracker")
        }
        guard manifest.version >= BackupManifest.receiptsVersion
                || (manifest.receipts.isEmpty && manifest.receiptAttachments.isEmpty)
        else { throw BackupError.invalid("Receipts need backup version \(BackupManifest.receiptsVersion)") }
        func requireUnique(_ ids: [Int64], _ label: String) throws {
            guard Set(ids).count == ids.count, ids.allSatisfy({ $0 > 0 }) else {
                throw BackupError.invalid("Invalid \(label) ids")
            }
        }
        let allAttachments = manifest.attachments + manifest.receiptAttachments
        try requireUnique(manifest.products.map(\.id), "product")
        try requireUnique(manifest.subscriptions.map(\.id), "subscription")
        try requireUnique(manifest.documents.map(\.id), "document")
        try requireUnique(manifest.receipts.map(\.id), "receipt")
        try requireUnique(allAttachments.map(\.id), "attachment")
        let productIds = Set(manifest.products.map(\.id))
        let documentIds = Set(manifest.documents.map(\.id))
        let receiptIds = Set(manifest.receipts.map(\.id))
        for attachment in manifest.attachments {
            let ownerExists = switch attachment.ownerType {
            case .product: productIds.contains(attachment.ownerId)
            case .document: documentIds.contains(attachment.ownerId)
            case .receipt: false
            }
            guard ownerExists, files.contains(attachment.fileName) else {
                throw BackupError.invalid("Attachment \(attachment.displayName) is missing")
            }
        }
        for attachment in manifest.receiptAttachments {
            guard attachment.ownerType == .receipt, receiptIds.contains(attachment.ownerId),
                  files.contains(attachment.fileName)
            else { throw BackupError.invalid("Receipt page \(attachment.displayName) is missing") }
        }
        guard Set(allAttachments.map(\.fileName)).count == allAttachments.count else {
            throw BackupError.invalid("Duplicate attachment files")
        }
        guard manifest.subscriptions.allSatisfy({ $0.cycleCount >= 1 }) else {
            throw BackupError.invalid("Invalid billing cycle")
        }
        for receipt in manifest.receipts {
            let pages = Set(manifest.receiptAttachments.filter { $0.ownerId == receipt.id }.map(\.fileName))
            guard Money.isValidCurrency(receipt.currency),
                  Set(receipt.recognizedText.keys).isSubset(of: pages),
                  Set(receipt.pageConfidence.keys).isSubset(of: pages),
                  Set(receipt.pageDigests.keys).isSubset(of: pages),
                  receipt.pageConfidence.values.allSatisfy({ (0...1).contains($0) }),
                  receipt.customFields.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  Receipt.isValidCardLastFour(receipt.cardLastFour),
                  [receipt.fuelVolume, receipt.fuelUnitPrice].allSatisfy({ ($0 ?? 0) >= 0 })
            else { throw BackupError.invalid("Invalid receipt \(receipt.merchant)") }
        }
        let linkedProducts = manifest.receipts.flatMap(\.productIds)
        guard Set(linkedProducts).count == linkedProducts.count, Set(linkedProducts).isSubset(of: productIds) else {
            throw BackupError.invalid("Invalid receipt links")
        }
    }
}
