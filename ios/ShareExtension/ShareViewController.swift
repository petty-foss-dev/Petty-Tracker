import AppIntents
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        } onCancel: { [weak self] in
            self?.model.cancel()
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        model.save(items.flatMap { $0.attachments ?? [] })
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase {
        case saving
        case saved(count: Int, skipped: Int)
        case failed(String)
    }

    private(set) var phase = Phase.saving
    private var work: Task<Void, Never>?

    func save(_ providers: [NSItemProvider]) {
        work = Task {
            do {
                phase = try await stage(providers)
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        work?.cancel()
    }

    private func stage(_ providers: [NSItemProvider]) async throws -> Phase {
        let supported = providers.compactMap { provider in
            SharedInbox.receiptType(in: provider.registeredTypeIdentifiers).map { (provider, $0) }
        }
        guard !supported.isEmpty else {
            return .failed(String(localized: "Only images and PDF files can be saved as receipts."))
        }
        guard supported.count <= SharedInbox.maxItemsPerShare else {
            return .failed(String(localized: "Share up to \(SharedInbox.maxItemsPerShare) files at a time."))
        }
        guard let inbox = SharedInbox.appGroupInbox() else {
            return .failed(String(localized: "Enve Keep's shared storage is unavailable. Reinstall Enve Keep and try again."))
        }
        let batch = try inbox.beginBatch()
        do {
            for (index, (provider, type)) in supported.enumerated() {
                try Task.checkCancellation()
                try await Self.copy(provider, as: type, into: batch, index: index)
            }
            try Task.checkCancellation()
            try batch.commit()
        } catch {
            batch.discard()
            throw error
        }
        return .saved(count: supported.count, skipped: providers.count - supported.count)
    }

    /// The provider's file only exists until its handler returns, so it is copied inside the handler.
    private static func copy(_ provider: NSItemProvider, as type: UTType, into batch: SharedInbox.Batch, index: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { @Sendable url, error in
                do {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    try batch.add(url, index: index, type: type)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct ShareView: View {
    let model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                switch model.phase {
                case .saving:
                    ProgressView()
                    Text("Saving to Enve Keep…")
                        .foregroundStyle(.secondary)
                case .saved(let count, let skipped):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(count == 1 ? "Saved 1 file" : "Saved \(count) files")
                        .font(.headline)
                    Text("Open Enve Keep to check each receipt before it is added.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if skipped > 0 {
                        Text(skipped == 1
                            ? "1 item is not an image or PDF and was skipped."
                            : "\(skipped) items are not images or PDFs and were skipped.")
                            .multilineTextAlignment(.center)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Nothing was saved")
                        .font(.headline)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Save to Enve Keep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .saving = model.phase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
            }
        }
    }
}
