import SwiftUI

/// Chooses the receipt that proves a product's purchase, or none.
struct ReceiptPicker: View {
    let selection: Int64?
    let onSelect: (Int64?) -> Void
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let receipts = ReceiptOrganizer.groups(store.data.receipts.filter { $0.matches(query) }, sort: .newest, grouping: .none)
            .flatMap(\.receipts)
        List {
            if query.isEmpty {
                Button {
                    choose(nil)
                } label: {
                    HStack {
                        Text("No receipt")
                        Spacer()
                        if selection == nil { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
            }
            ForEach(receipts) { receipt in
                Button {
                    choose(receipt.id)
                } label: {
                    HStack {
                        ReceiptRow(receipt: receipt)
                        if selection == receipt.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityAddTraits(selection == receipt.id ? .isSelected : [])
            }
        }
        .overlay {
            if store.data.receipts.isEmpty {
                ContentUnavailableView(
                    "No receipts yet",
                    systemImage: Receipt.symbol,
                    description: Text("Add receipts in the Receipts tab, then link them here.")
                )
            } else if receipts.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search receipts")
    }

    private func choose(_ id: Int64?) {
        onSelect(id)
        dismiss()
    }
}

/// Links an existing product to a receipt; a product linked elsewhere moves to this receipt.
struct ProductLinkPicker: View {
    let receiptId: Int64
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var errorMessage: String?

    var body: some View {
        let products = store.data.products
            .filter { $0.matches(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        NavigationStack {
            List(products) { product in
                let current = store.receiptCovering(product.id)
                Button {
                    link(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                            if let current, current.id != receiptId {
                                Text("Linked to \(current.merchant)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if current?.id == receiptId { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
                .disabled(current?.id == receiptId)
            }
            .overlay {
                if store.data.products.isEmpty {
                    ContentUnavailableView("No products yet", systemImage: RecordKind.warranty.symbol)
                } else if products.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Link product")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search products")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func link(_ product: Product) {
        do {
            try store.linkProduct(product.id, toReceipt: receiptId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
