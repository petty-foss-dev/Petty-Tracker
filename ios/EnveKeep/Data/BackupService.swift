import Foundation

struct StagedImport: Identifiable, Sendable {
    let id = UUID()
    let manifest: BackupManifest
    let staging: URL

    var recordCount: Int {
        manifest.products.count + manifest.subscriptions.count + manifest.documents.count + manifest.receipts.count
    }
    var attachmentCount: Int { manifest.attachments.count + manifest.receiptAttachments.count }
}

@MainActor
struct BackupService {
    let store: KeepStore

    private var stagingRoot: URL { store.root.appending(path: "import-staging", directoryHint: .isDirectory) }
    private nonisolated static let previousName = "attachments-previous"

    /// Writes Android-compatible version 1 without receipts; detailed receipts use version 3.
    func export() async throws -> URL {
        let data = store.data
        let manifest = BackupManifest(
            version: data.receipts.isEmpty ? BackupManifest.androidVersion : BackupManifest.detailsVersion,
            exportedAt: Date.now.formatted(.iso8601),
            products: data.products,
            subscriptions: data.subscriptions,
            documents: data.documents,
            attachments: data.attachments.filter { $0.ownerType != .receipt },
            receipts: data.receipts,
            receiptAttachments: data.attachments.filter { $0.ownerType == .receipt },
            settings: data.settings
        )
        let folder = FileManager.default.temporaryDirectory.appending(path: "export", directoryHint: .isDirectory)
        let destination = folder.appending(path: "enve-keep-backup-\(store.today.iso).zip")
        let attachmentsDirectory = store.attachmentStore.directory
        try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try BackupArchive.write(manifest, attachmentsDirectory: attachmentsDirectory, to: destination)
        }.value
        return destination
    }

    /// Reads and validates a picked archive into a staging folder without touching live data.
    func stage(_ source: URL) async throws -> StagedImport {
        let staging = stagingRoot
        let manifest = try await Task.detached(priority: .userInitiated) {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.removeItem(at: staging)
            do {
                return try BackupArchive.read(from: source, staging: staging)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        }.value
        return StagedImport(manifest: manifest, staging: staging)
    }

    func discard(_ staged: StagedImport) {
        try? FileManager.default.removeItem(at: staged.staging)
    }

    /// Replaces all local data with a staged backup. On any failure the previous data stays in place.
    func commit(_ staged: StagedImport) throws {
        let fileManager = FileManager.default
        let live = store.attachmentStore.directory
        let previous = store.root.appending(path: Self.previousName, directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staged.staging) }

        try? fileManager.removeItem(at: previous)
        try fileManager.moveItem(at: live, to: previous)
        do {
            try fileManager.moveItem(at: staged.staging.appending(path: "attachments"), to: live)
        } catch {
            try fileManager.moveItem(at: previous, to: live)
            throw error
        }

        var imported = KeepData(
            products: staged.manifest.products,
            subscriptions: staged.manifest.subscriptions,
            documents: staged.manifest.documents,
            receipts: staged.manifest.receipts,
            attachments: staged.manifest.attachments + staged.manifest.receiptAttachments,
            settings: store.settings
        )
        if var settings = staged.manifest.settings {
            settings.reminderPromptDismissed = store.settings.reminderPromptDismissed
            imported.settings = settings
        }
        do {
            try store.replaceAll(with: imported)
        } catch {
            try? fileManager.removeItem(at: live)
            try? fileManager.moveItem(at: previous, to: live)
            throw error
        }
        try? fileManager.removeItem(at: previous)
    }

    /// Resolves an import interrupted between swapping attachment folders and saving records.
    nonisolated static func recoverInterruptedImport(root: URL, referenced: Set<String>) {
        let fileManager = FileManager.default
        let live = root.appending(path: "attachments", directoryHint: .isDirectory)
        let previous = root.appending(path: previousName, directoryHint: .isDirectory)
        try? fileManager.removeItem(at: root.appending(path: "import-staging"))
        guard fileManager.fileExists(atPath: previous.path) else { return }
        let liveComplete = referenced.allSatisfy { fileManager.fileExists(atPath: live.appending(path: $0).path) }
        if liveComplete {
            try? fileManager.removeItem(at: previous)
        } else {
            try? fileManager.removeItem(at: live)
            try? fileManager.moveItem(at: previous, to: live)
        }
    }
}
