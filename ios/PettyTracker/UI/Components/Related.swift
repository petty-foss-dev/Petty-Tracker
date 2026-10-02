import SwiftUI

extension RecordType {
    var label: String {
        switch self {
        case .product: String(localized: "Product")
        case .subscription: String(localized: "Subscription")
        case .document: String(localized: "Document")
        case .receipt: String(localized: "Receipt")
        }
    }

    var symbol: String {
        switch self {
        case .product: RecordKind.warranty.symbol
        case .subscription: RecordKind.subscription.symbol
        case .document: RecordKind.document.symbol
        case .receipt: Receipt.symbol
        }
    }
}

extension RecordRef {
    var route: Route {
        switch type {
        case .product: .product(id)
        case .subscription: .subscription(id)
        case .document: .document(id)
        case .receipt: .receipt(id)
        }
    }
}

extension TrackerStore {
    func title(of ref: RecordRef) -> String {
        switch ref.type {
        case .product: product(ref.id)?.name ?? ""
        case .subscription: subscription(ref.id)?.name ?? ""
        case .document: document(ref.id)?.title ?? ""
        case .receipt: receipt(ref.id)?.merchant ?? ""
        }
    }

    /// Every record that can be linked, newest kinds of paperwork last.
    var linkableRecords: [RecordRef] {
        data.products.map { RecordRef(type: .product, id: $0.id) }
            + data.documents.map { RecordRef(type: .document, id: $0.id) }
            + data.subscriptions.map { RecordRef(type: .subscription, id: $0.id) }
            + data.receipts.map { RecordRef(type: .receipt, id: $0.id) }
    }
}

/// Cross-references to other records, shown on every detail screen.
struct RelatedSection: View {
    let ref: RecordRef
    @Environment(TrackerStore.self) private var store
    @State private var picking = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ForEach(store.related(to: ref), id: \.link.id) { entry in
                NavigationLink(value: entry.other.route) {
                    RelatedRow(ref: entry.other, note: entry.link.note)
                }
                .swipeActions {
                    Button("Unlink", systemImage: "link.badge.minus", role: .destructive) { unlink(entry.link) }
                }
                .contextMenu {
                    Button("Unlink", systemImage: "link.badge.minus", role: .destructive) { unlink(entry.link) }
                }
            }
            // The picker sheet hangs off this single row so it isn't repeated for every link.
            Button("Link to another record", systemImage: "link") { picking = true }
                .sheet(isPresented: $picking) {
                    RecordLinkPicker(ref: ref)
                }
                .errorAlert($errorMessage)
        } header: {
            Overline("Related")
        } footer: {
            Text("Link the policy that insures this, its manual, a matching subscription or any other record.")
        }
    }

    private func unlink(_ link: RecordLink) {
        do {
            try store.unlink(link.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RelatedRow: View {
    let ref: RecordRef
    let note: String
    @Environment(TrackerStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            RecordIcon(symbol: ref.type.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.title(of: ref)).font(.body.weight(.medium))
                Text(note.isEmpty ? ref.type.label : "\(ref.type.label) · \(note)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecordLinkPicker: View {
    let ref: RecordRef
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        let linked = Set(store.related(to: ref).map(\.other))
        let candidates = store.linkableRecords.filter { candidate in
            candidate != ref && !linked.contains(candidate) && Search.matches(query, store.title(of: candidate))
        }
        NavigationStack {
            TrackerList {
                Section {
                    FormTextField("Note", text: $note, prompt: "Insurance, manual…")
                } footer: {
                    Text("Optional. Says how the records relate.")
                }
                ForEach([RecordType.product, .document, .subscription, .receipt], id: \.self) { type in
                    let matches = candidates.filter { $0.type == type }
                    if !matches.isEmpty {
                        Section {
                            ForEach(matches, id: \.self) { candidate in
                                Button {
                                    link(candidate)
                                } label: {
                                    RelatedRow(ref: candidate, note: "")
                                }
                                .foregroundStyle(.primary)
                            }
                        } header: {
                            Overline(verbatim: type.label)
                        }
                    }
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Nothing to link", systemImage: "link", description: Text("Add more records, or try a different search."))
                }
            }
            .navigationTitle("Link a record")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func link(_ other: RecordRef) {
        do {
            try store.addLink(ref, to: other, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
