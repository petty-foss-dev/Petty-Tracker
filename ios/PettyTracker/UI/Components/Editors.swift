import SwiftUI

enum Editor: Identifiable {
    case product(Int64?)
    case subscription(Int64?)
    case document(Int64?)

    init(new kind: RecordKind) {
        self = switch kind {
        case .warranty: .product(nil)
        case .subscription: .subscription(nil)
        case .document: .document(nil)
        }
    }

    var id: String {
        switch self {
        case .product(let id): "product-\(id ?? 0)"
        case .subscription(let id): "subscription-\(id ?? 0)"
        case .document(let id): "document-\(id ?? 0)"
        }
    }
}

extension View {
    /// Presents the matching edit form; `onCreated` receives the route of a newly created record.
    func editorSheet(_ editor: Binding<Editor?>, onCreated: @escaping (Route) -> Void = { _ in }) -> some View {
        sheet(item: editor) { editor in
            switch editor {
            case .product(let id):
                ProductEditView(productId: id) { if id == nil { onCreated(.product($0)) } }
            case .subscription(let id):
                SubscriptionEditView(subscriptionId: id) { if id == nil { onCreated(.subscription($0)) } }
            case .document(let id):
                DocumentEditView(documentId: id) { if id == nil { onCreated(.document($0)) } }
            }
        }
    }
}

struct AddRecordMenu: View {
    let onSelect: (RecordKind) -> Void
    let onScanReceipt: () -> Void

    var body: some View {
        Menu {
            Button("Product and warranty", systemImage: RecordKind.warranty.symbol) { onSelect(.warranty) }
            Button("Subscription", systemImage: RecordKind.subscription.symbol) { onSelect(.subscription) }
            Button("Document", systemImage: RecordKind.document.symbol) { onSelect(.document) }
            Button("Receipt", systemImage: Receipt.symbol, action: onScanReceipt)
        } label: {
            Label("Add", systemImage: "plus")
        }
    }
}

/// Cancel/Save toolbar with a discard confirmation that protects unsaved edits.
struct EditToolbar: ToolbarContent {
    let hasChanges: Bool
    var canSave = true
    @Binding var confirmDiscard: Bool
    let onDiscard: () -> Void
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasChanges { confirmDiscard = true } else { onDiscard() }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive, action: onDiscard)
            } message: {
                Text("Your edits and any newly added files will be lost.")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: onSave)
                .disabled(!canSave)
        }
    }
}
