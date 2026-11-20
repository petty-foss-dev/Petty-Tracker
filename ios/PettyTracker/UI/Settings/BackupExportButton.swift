import SwiftUI
import UniformTypeIdentifiers

struct BackupExportButton: View {
    @Environment(TrackerStore.self) private var store
    @State private var prepared: PreparedBackup?
    @State private var showingExporter = false
    @State private var preparing = false
    @State private var errorMessage: String?
    @State private var comparison: BackupDifference?
    @State private var comparedRevision: Int?

    var body: some View {
        Button(action: export) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.trackerAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Export backup").font(.headline)
                    if let date = store.data.backupHistory?.lastExport {
                        Text("Last export \(date.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("No export recorded on this device")
                    }
                    if let restored = store.data.backupHistory?.restored {
                        Text("Restored \(restored.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Text(status)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.trackerAccent)
                }
                .font(.subheadline)
                Spacer(minLength: 4)
                if preparing {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(Color.trackerAccent)
                }
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("backup.export")
        .disabled(preparing)
        .task(id: store.revision) { await countChanges() }
        .fileExporter(
            isPresented: $showingExporter,
            document: prepared.map { BackupFile(url: $0.url) },
            contentTypes: [.zip],
            defaultFilename: prepared?.url.deletingPathExtension().lastPathComponent,
            onCompletion: complete,
            onCancellation: discard
        )
        .errorAlert($errorMessage)
    }

    private var status: String {
        if preparing { return String(localized: "Preparing ZIP…") }
        guard let history = store.data.backupHistory else {
            let data = store.data
            let count = data.products.count + data.subscriptions.count + data.documents.count + data.receipts.count
            return String(localized: "\(Formats.count(count, "record", "records")) to back up")
        }
        guard comparedRevision == store.revision else { return String(localized: "Checking for changes…") }
        guard let comparison else { return String(localized: "Change count unavailable") }
        var parts: [String] = []
        if comparison.added > 0 { parts.append(String(localized: "\(comparison.added) added")) }
        if comparison.edited > 0 { parts.append(String(localized: "\(comparison.edited) edited")) }
        if comparison.removed > 0 { parts.append(String(localized: "\(comparison.removed) removed")) }
        if comparison.settingsChanged { parts.append(String(localized: "Settings changed")) }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return history.restored == nil ? String(localized: "No changes since export") : String(localized: "No changes since restore")
    }

    private func countChanges() async {
        let data = store.data
        guard let history = data.backupHistory else { return }
        let revision = store.revision
        let diff = await Task.detached(priority: .utility) {
            try? BackupFingerprint(data).changes(since: history.baseline)
        }.value
        guard !Task.isCancelled, revision == store.revision else { return }
        comparison = diff
        comparedRevision = revision
    }

    private func export() {
        preparing = true
        Task {
            defer { preparing = false }
            do {
                prepared = try await BackupService(store: store).export()
                showingExporter = true
            } catch {
                errorMessage = String(localized: "The backup could not be prepared. \(error.localizedDescription)")
            }
        }
    }

    private func complete(_ result: Result<URL, Error>) {
        defer { discard() }
        switch result {
        case .success:
            guard let prepared else { return }
            do {
                try store.recordExport(prepared)
                Haptics.success()
            } catch {
                errorMessage = String(localized: "Your ZIP was saved. Tracker could not update the backup status. \(error.localizedDescription)")
            }
        case .failure(let error):
            if (error as NSError).domain != NSCocoaErrorDomain || (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func discard() {
        prepared?.discard()
        prepared = nil
    }
}

private struct BackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.zip]
    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}
