import SwiftUI

struct ProductDetailView: View {
    let productId: Int64
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editor: Editor?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var openedAttachment: OpenedAttachment?
    @State private var pickingReceipt = false
    @State private var confirmPacketWithoutReceipt = false
    @State private var preparingPacket = false

    var body: some View {
        if let product = store.product(productId) {
            content(product)
        } else {
            ContentUnavailableView("Product not found", systemImage: RecordKind.warranty.symbol)
        }
    }

    private func content(_ product: Product) -> some View {
        let today = store.today
        let status = deadlineStatus(product.warrantyExpires, today: today, leadDays: store.settings.warrantyLeadDays)
        return List {
            Section {
                WarrantyHeader(product: product, status: status, today: today)
            }
            if !(product.brand + product.model + product.serialNumber).isEmpty {
                Section("Details") {
                    DetailField("Brand", product.brand)
                    DetailField("Model", product.model)
                    DetailField("Serial number", product.serialNumber, monospaced: true)
                }
            }
            if product.purchaseDate != nil || !product.retailer.isEmpty || product.price != nil {
                Section("Purchase") {
                    DetailField("Purchase date", product.purchaseDate.map(Formats.date) ?? "")
                    DetailField("Retailer", product.retailer)
                    DetailField("Price", product.price.map { Money.format($0, currency: product.currency) } ?? "")
                }
            }
            receiptSection
            if !product.notes.isEmpty {
                Section("Notes") {
                    Text(product.notes).textSelection(.enabled)
                }
            }
            Section("Files and photos") {
                AttachmentGallery(
                    attachments: store.attachments(.product, productId),
                    emptyText: "No files or photos. Edit the product to add them.",
                    opened: $openedAttachment,
                    errorMessage: $errorMessage
                )
            }
            Section {
                Button("Delete product", role: .destructive) { confirmDelete = true }
            }
        }
        .trackerListStyle()
        .attachmentPresenter($openedAttachment)
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                ShareLink(item: shareText(product), subject: Text("Product details: \(product.name)")) {
                    Label("Share details", systemImage: "text.alignleft")
                }
                Button("Claim packet (PDF)", systemImage: "doc.richtext") {
                    if store.receiptCovering(productId) == nil {
                        confirmPacketWithoutReceipt = true
                    } else {
                        makeClaimPacket()
                    }
                }
                .disabled(preparingPacket)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button("Edit") { editor = .product(productId) }
        }
        .editorSheet($editor)
        .sheet(isPresented: $pickingReceipt) {
            NavigationStack {
                ReceiptPicker(selection: store.receiptCovering(productId)?.id) { link($0) }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { pickingReceipt = false }
                        }
                    }
            }
        }
        .confirmationDialog("No receipt is linked", isPresented: $confirmPacketWithoutReceipt, titleVisibility: .visible) {
            Button("Link a receipt") { pickingReceipt = true }
            Button("Create without receipt") { makeClaimPacket() }
        } message: {
            Text("The claim packet will contain only the product summary. Link the purchase receipt to include its scans as proof of purchase.")
        }
        .confirmationDialog("Delete \(product.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try store.deleteProduct(productId)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("The product and its files and photos will be removed from this device. A linked receipt is kept.")
        }
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private var receiptSection: some View {
        Section {
            if let receipt = store.receiptCovering(productId) {
                NavigationLink(value: Route.receipt(receipt.id)) {
                    ReceiptRow(receipt: receipt)
                }
                .swipeActions {
                    Button("Unlink", systemImage: "link.badge.minus") { link(nil) }
                        .tint(Color.trackerSoon)
                }
                .contextMenu {
                    Button("Change receipt", systemImage: "arrow.triangle.swap") { pickingReceipt = true }
                    Button("Unlink", systemImage: "link.badge.minus", role: .destructive) { link(nil) }
                }
            } else {
                Button("Link a receipt", systemImage: "link") { pickingReceipt = true }
            }
        } header: {
            Text("Receipt")
        } footer: {
            if store.receiptCovering(productId) == nil {
                Text("Link the purchase receipt so it's ready as proof of purchase for a claim.")
            }
        }
    }

    private func link(_ receiptId: Int64?) {
        do {
            try store.linkProduct(productId, toReceipt: receiptId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeClaimPacket() {
        guard let product = store.product(productId) else { return }
        let receipt = store.receiptCovering(productId)
        let pages = receipt.map { store.attachments(.receipt, $0.id).filter(\.isImage) } ?? []
        let packet = ClaimPacket(
            product: product,
            receipt: receipt,
            receiptPages: pages.map { store.attachmentStore.url(for: $0.fileName) },
            today: store.today
        )
        preparingPacket = true
        Task {
            defer { preparingPacket = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) { try packet.write() }.value
                openedAttachment = OpenedAttachment(url: url, share: false)
            } catch {
                errorMessage = String(localized: "The claim packet could not be created. \(error.localizedDescription)")
            }
        }
    }

    private func shareText(_ product: Product) -> String {
        [
            product.name,
            product.brand.isEmpty ? nil : String(localized: "Brand: \(product.brand)"),
            product.model.isEmpty ? nil : String(localized: "Model: \(product.model)"),
            product.serialNumber.isEmpty ? nil : String(localized: "Serial number: \(product.serialNumber)"),
            product.purchaseDate.map { String(localized: "Purchase date: \(Formats.date($0))") },
            product.retailer.isEmpty ? nil : String(localized: "Retailer: \(product.retailer)"),
            product.price.map { String(localized: "Price: \(Money.format($0, currency: product.currency))") },
            product.warrantyExpires.map { String(localized: "Warranty ends: \(Formats.date($0))") },
            product.notes.isEmpty ? nil : product.notes,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

private struct WarrantyHeader: View {
    let product: Product
    let status: DeadlineStatus
    let today: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(text: badgeText, status: status)
                Spacer()
                if let expires = product.warrantyExpires {
                    Text(Formats.date(expires)).foregroundStyle(.secondary)
                }
            }
            if let expires = product.warrantyExpires {
                Text(Formats.deadline(.warranty, days: today.days(until: expires)))
                    .font(.title3.weight(.semibold))
                if let remaining {
                    ProgressView(value: remaining)
                        .tint(status.tint)
                        .accessibilityLabel("Warranty period remaining")
                        .accessibilityValue(remaining.formatted(.percent.precision(.fractionLength(0))))
                    Text("\(Int((remaining * 100).rounded()))% of the warranty period left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var badgeText: String {
        switch status {
        case .none: String(localized: "No warranty date")
        case .past: String(localized: "Warranty ended")
        default: String(localized: "Under warranty")
        }
    }

    private var remaining: Double? {
        guard let start = product.purchaseDate, let end = product.warrantyExpires, start < end, status != .past else {
            return nil
        }
        let total = Double(start.days(until: end))
        return min(1, max(0, Double(today.days(until: end)) / total))
    }
}

/// A label/value row that hides itself when the value is empty.
struct DetailField: View {
    let label: LocalizedStringKey
    let value: String
    var monospaced = false

    init(_ label: LocalizedStringKey, _ value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value)
                    .monospaced(monospaced)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
