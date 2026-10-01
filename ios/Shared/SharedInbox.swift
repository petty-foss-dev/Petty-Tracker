import Foundation
import UniformTypeIdentifiers

/// Files shared from other apps, kept in the App Group container until petty: Tracker turns them into receipts.
/// The share extension only adds complete batches here; it never touches `tracker.json`.
struct SharedInbox: Sendable {
    static let appGroup = "group.com.isaaclamb.PettyTracker"
    static let maxItemsPerShare = 20

    struct Item: Hashable, Identifiable, Sendable {
        /// "<batch>/<slot>", which sorts in share order.
        let id: String
        let file: URL
    }

    /// A share being copied into the inbox; the app sees none of it until `commit`.
    struct Batch: Sendable {
        let folder: URL
        let destination: URL

        /// Copies a file that may only exist for the duration of this call.
        func add(_ file: URL, index: Int, type: UTType? = nil) throws {
            let slot = folder.appending(path: String(format: "%03d", index), directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: false, attributes: SharedInbox.protection)
            let name: String
            if file.pathExtension.isEmpty, let ext = type?.preferredFilenameExtension {
                name = file.lastPathComponent + "." + ext
            } else {
                name = file.lastPathComponent
            }
            let target = slot.appending(path: name)
            try FileManager.default.copyItem(at: file, to: target)
            try FileManager.default.setAttributes(SharedInbox.protection, ofItemAtPath: target.path)
        }

        func commit() throws {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: SharedInbox.protection
            )
            try FileManager.default.moveItem(at: folder, to: destination)
        }

        func discard() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private static var protection: [FileAttributeKey: Any] { [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication] }

    let root: URL

    private var staging: URL { root.appending(path: "Staging", directoryHint: .isDirectory) }
    private var pending: URL { root.appending(path: "Pending", directoryHint: .isDirectory) }

    static func appGroupInbox() -> SharedInbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { SharedInbox(root: $0.appending(path: "Inbox", directoryHint: .isDirectory)) }
    }

    /// The type to load from a shared item: PDF first, then any image.
    static func receiptType(in identifiers: [String]) -> UTType? {
        let types = identifiers.compactMap { UTType($0) }
        return types.first { $0.conforms(to: .pdf) } ?? types.first { $0.conforms(to: .image) }
    }

    func beginBatch() throws -> Batch {
        let name = String(format: "%013lld-", Int64(Date.now.timeIntervalSince1970 * 1000)) + UUID().uuidString
        let folder = staging.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: Self.protection)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = root
        try? excluded.setResourceValues(values)
        return Batch(folder: folder, destination: pending.appending(path: name, directoryHint: .isDirectory))
    }

    /// Committed files, oldest share first.
    func items() -> [Item] {
        Self.children(of: pending).flatMap { batch in
            Self.children(of: batch).compactMap { slot in
                Self.children(of: slot).first.map { Item(id: "\(batch.lastPathComponent)/\(slot.lastPathComponent)", file: $0) }
            }
        }
    }

    func remove(_ item: Item) {
        let fileManager = FileManager.default
        let slot = pending.appending(path: item.id, directoryHint: .isDirectory)
        try? fileManager.removeItem(at: slot)
        let batch = slot.deletingLastPathComponent()
        if Self.children(of: batch).isEmpty { try? fileManager.removeItem(at: batch) }
    }

    /// Removes shares whose extension was killed before committing.
    func removeAbandonedBatches(olderThan cutoff: Date) {
        for batch in Self.children(of: staging) {
            let created = (try? batch.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? FileManager.default.removeItem(at: batch) }
        }
    }

    private static func children(of folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
