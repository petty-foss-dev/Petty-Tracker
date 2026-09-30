import QuickLook
import SwiftUI

struct ReceiptDetailView: View {
    let receiptId: Int64
    @Environment(KeepStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ReceiptEditorRequest?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var preview: URL?
    @State private var previewPages: [URL] = []
    @State private var sharedPages: SharedPages?
    @State private var newProduct: ProductDraftRequest?
    @State private var linkingProduct = false

    var body: some View {
        if let receipt = store.receipt(receiptId) {
            content(receipt)
        } else {
            ContentUnavailableView("Receipt not found", systemImage: Receipt.symbol)
        }
    }

    private func content(_ receipt: Receipt) -> some View {
        let pages = store.attachments(.receipt, receiptId)
        return List {
            Section {
                ReceiptHeader(receipt: receipt)
            }
            reviewSection(receipt, pages: pages)
            if !pages.isEmpty {
                Section("Scans") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                Button {
                                    open(pages, at: index)
                                } label: {
                                    ReceiptPageThumbnail(page: page, width: 110, height: 150)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Page \(index + 1) of \(pages.count)"))
                                .accessibilityHint("Opens a preview")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            detailSections(receipt)
            Section("Items") {
                if receipt.items.isEmpty {
                    Text("No items").foregroundStyle(.secondary)
                }
                ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                    ItemRow(item: item, currency: receipt.currency)
                        .contextMenu {
                            Button("Create product from item", systemImage: "plus.circle") {
                                newProduct = ProductDraftRequest(product: Product(receipt: receipt, item: item))
                            }
                        }
                }
            }
            productsSection(receipt)
            if receipt.subtotal != nil || receipt.tax != nil || receipt.tip != nil || receipt.total != nil {
                Section("Totals") {
                    amountRow("Subtotal", receipt.subtotal, receipt.currency)
                    amountRow("Tax", receipt.tax, receipt.currency)
                    amountRow("Tip", receipt.tip, receipt.currency)
                    amountRow("Total", receipt.total, receipt.currency)
                }
            }
            if !receipt.customFields.isEmpty {
                Section("Custom fields") {
                    ForEach(Array(receipt.customFields.enumerated()), id: \.offset) { _, field in
                        NavigationLink(value: Route.receipts(ReceiptFilter(facets: [
                            .field(name: field.name, value: field.value.isEmpty ? nil : field.value),
                        ]))) {
                            LabeledContent(field.name, value: field.value)
                        }
                    }
                }
            }
            if !receipt.notes.isEmpty {
                Section("Notes") {
                    Text(receipt.notes).textSelection(.enabled)
                }
            }
            let texts = pages.enumerated().compactMap { index, page in
                receipt.recognizedText[page.fileName].map { (page: index + 1, text: $0) }
            }
            if !texts.isEmpty {
                Section {
                    DisclosureGroup("Recognized text") {
                        ForEach(texts, id: \.page) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                if texts.count > 1 {
                                    Text("Page \(entry.page)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                Text(entry.text.isEmpty ? String(localized: "No text found") : entry.text)
                                    .font(.footnote.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } footer: {
                    Text("Read on this iPhone when the page was added. It may contain mistakes.")
                }
            }
            Section {
                Button("Delete receipt", role: .destructive) { confirmDelete = true }
            }
        }
        .keepListStyle()
        .quickLookPreview($preview, in: previewPages)
        .sheet(item: $sharedPages) { shared in
            ActivityView(items: shared.urls)
                .presentationDetents([.medium, .large])
        }
        .navigationTitle(receipt.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                ShareLink(item: shareText(receipt), subject: Text("Receipt: \(receipt.merchant)")) {
                    Label("Share details", systemImage: "text.alignleft")
                }
                if !pages.isEmpty {
                    Button("Share scans", systemImage: "doc.on.doc") { share(pages) }
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button("Edit") { editor = ReceiptEditorRequest(receiptId: receiptId) }
        }
        .sheet(item: $editor) { request in
            ReceiptEditView(request: request) { _ in }
        }
        .sheet(item: $newProduct) { request in
            ProductEditView(productId: nil, draft: request.product, receiptId: receiptId) { _ in }
        }
        .sheet(isPresented: $linkingProduct) {
            ProductLinkPicker(receiptId: receiptId)
        }
        .confirmationDialog("Delete \(receipt.merchant)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try store.deleteReceipt(receiptId)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text(receipt.productIds.isEmpty
                ? "The receipt and its scans will be removed from this device."
                : "The receipt and its scans will be removed from this device. Linked products are kept.")
        }
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private func reviewSection(_ receipt: Receipt, pages: [Attachment]) -> some View {
        let flags = ReceiptReview.flags(for: receipt, pages: pages.map(\.fileName), among: store.data.receipts)
        let open = ReceiptReview.unresolved(flags, in: receipt)
        if !open.isEmpty {
            Section {
                ForEach(open) { flag in
                    if let other = flag.kind.otherReceiptId {
                        NavigationLink(value: Route.receipt(other)) {
                            ReviewFlagRow(flag: flag, currency: receipt.currency)
                        }
                    } else {
                        ReviewFlagRow(flag: flag, currency: receipt.currency)
                    }
                }
                Button("Edit receipt", systemImage: "pencil") { editor = ReceiptEditorRequest(receiptId: receiptId) }
                Button("Mark as reviewed", systemImage: "checkmark.circle") { perform { try store.markReviewed(receiptId) } }
            } header: {
                Text("Needs review")
            } footer: {
                Text("Fix what's wrong, or mark as reviewed if it's correct as is. Duplicates are never removed automatically.")
            }
        } else if !flags.isEmpty {
            Section {
                HStack {
                    Label("Reviewed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Review again") { perform { try store.setResolvedFlags([], forReceipt: receiptId) } }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder
    private func detailSections(_ receipt: Receipt) -> some View {
        let storeDetails = [receipt.storeAddress, receipt.storePhone, receipt.transactionId, receipt.paymentMethod, receipt.cardLastFour]
        if !storeDetails.allSatisfy(\.isEmpty) {
            Section("Store and payment") {
                if !receipt.storeAddress.isEmpty {
                    NavigationLink(value: Route.receipts(ReceiptFilter(facets: [.location(receipt.storeAddress)]))) {
                        LabeledContent("Address", value: receipt.storeAddress)
                    }
                }
                textRow("Phone", receipt.storePhone)
                textRow("Transaction", receipt.transactionId)
                textRow("Payment", [receipt.paymentMethod, receipt.cardLastFour.isEmpty ? "" : "•••• \(receipt.cardLastFour)"]
                    .filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
        if let route = receipt.routeLabel {
            Section("Trip") {
                NavigationLink(value: Route.receipts(ReceiptFilter(facets: [.route(origin: receipt.origin, destination: receipt.destination)]))) {
                    Label(route, systemImage: ReceiptFacetKind.route.symbol)
                }
            }
        }
        if receipt.hasFuelDetails {
            Section("Fuel") {
                textRow("Grade", receipt.fuelGrade)
                if let volume = receipt.fuelVolume {
                    textRow("Volume", Formats.fuelVolume(volume, unit: receipt.fuelUnit))
                }
                if let price = receipt.fuelUnitPrice {
                    textRow("Price", Formats.fuelUnitPrice(price, currency: receipt.currency, unit: receipt.fuelUnit))
                }
                textRow("Pump", receipt.pumpNumber)
                textRow("Odometer", receipt.odometer)
            }
        }
    }

    @ViewBuilder
    private func textRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func productsSection(_ receipt: Receipt) -> some View {
        Section {
            ForEach(store.products(coveredBy: receipt)) { product in
                NavigationLink(value: Route.product(product.id)) {
                    Label(product.name, systemImage: RecordKind.warranty.symbol)
                }
                .swipeActions {
                    Button("Unlink", systemImage: "link.badge.minus") {
                        perform { try store.linkProduct(product.id, toReceipt: nil) }
                    }
                    .tint(Color.keepSoon)
                }
            }
            if !receipt.items.isEmpty {
                Menu {
                    ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                        Button(itemTitle(item, currency: receipt.currency)) {
                            newProduct = ProductDraftRequest(product: Product(receipt: receipt, item: item))
                        }
                    }
                } label: {
                    Label("Create product from item", systemImage: "plus.circle")
                }
            }
            Button("New product from this receipt", systemImage: "plus.rectangle.on.rectangle") {
                newProduct = ProductDraftRequest(product: Product(receipt: receipt, item: nil))
            }
            Button("Link existing product", systemImage: "link") { linkingProduct = true }
        } header: {
            Text("Products and warranties")
        } footer: {
            Text("Linked products use this receipt as proof of purchase. The scans stay here and aren't copied.")
        }
    }

    private func itemTitle(_ item: ReceiptItem, currency: String) -> String {
        let name = item.description.isEmpty ? String(localized: "Unnamed item") : item.description
        return item.amount.map { "\(name) – \(Money.format($0, currency: currency))" } ?? name
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func amountRow(_ label: LocalizedStringKey, _ amount: Decimal?, _ currency: String) -> some View {
        if let amount {
            LabeledContent(label) {
                Text(Money.format(amount, currency: currency))
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
    }

    private func open(_ pages: [Attachment], at index: Int) {
        do {
            previewPages = try pages.map(store.attachmentStore.shareableURL)
            preview = previewPages[index]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share(_ pages: [Attachment]) {
        do {
            sharedPages = SharedPages(urls: try pages.map(store.attachmentStore.shareableURL))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareText(_ receipt: Receipt) -> String {
        let money = { Money.format($0, currency: receipt.currency) }
        let items = receipt.items.map { item in
            let quantity = item.quantity.map { "\(Money.formatForInput($0)) × " } ?? ""
            let amount = item.amount.map { "  \(money($0))" } ?? ""
            return "\(quantity)\(item.description)\(amount)"
        }
        func line(_ label: String, _ value: String) -> String? { value.isEmpty ? nil : "\(label): \(value)" }
        let details: [String?] = [
            receipt.merchant,
            receipt.purchaseDate.map { String(localized: "Date: \(Formats.date($0))") },
            receipt.purchaseTime.map { String(localized: "Time: \(Formats.time($0))") },
            receipt.category.isEmpty ? nil : String(localized: "Category: \(receipt.category)"),
            line(String(localized: "Address"), receipt.storeAddress),
            line(String(localized: "Phone"), receipt.storePhone),
            line(String(localized: "Transaction"), receipt.transactionId),
            line(String(localized: "Payment"), receipt.paymentMethod),
            receipt.routeLabel.map { String(localized: "Trip: \($0)") },
            line(String(localized: "Fuel grade"), receipt.fuelGrade),
            receipt.fuelVolume.map { String(localized: "Fuel volume: \(Formats.fuelVolume($0, unit: receipt.fuelUnit))") },
            receipt.fuelUnitPrice.map {
                String(localized: "Fuel price: \(Formats.fuelUnitPrice($0, currency: receipt.currency, unit: receipt.fuelUnit))")
            },
            line(String(localized: "Pump"), receipt.pumpNumber),
            line(String(localized: "Odometer"), receipt.odometer),
        ]
        let fields = receipt.customFields.map { line($0.name, $0.value) ?? $0.name }
        let totals: [String?] = [
            receipt.subtotal.map { String(localized: "Subtotal: \(money($0))") },
            receipt.tax.map { String(localized: "Tax: \(money($0))") },
            receipt.tip.map { String(localized: "Tip: \(money($0))") },
            receipt.total.map { String(localized: "Total: \(money($0))") },
            receipt.tags.isEmpty ? nil : String(localized: "Tags: \(receipt.tags.joined(separator: ", "))"),
            receipt.notes.isEmpty ? nil : receipt.notes,
        ]
        return (details.compactMap { $0 } + fields + items + totals.compactMap { $0 })
            .joined(separator: "\n")
    }
}

private struct ProductDraftRequest: Identifiable {
    let id = UUID()
    let product: Product
}

private struct SharedPages: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct ReceiptHeader: View {
    let receipt: Receipt

    private var purchased: String {
        guard let date = receipt.purchaseDate else { return String(localized: "No purchase date") }
        return [Formats.date(date), receipt.purchaseTime.map(Formats.time)].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !receipt.category.isEmpty {
                    StatusBadge(text: receipt.category, status: .ok)
                }
                Spacer()
                Text(purchased)
                    .foregroundStyle(.secondary)
            }
            Text(receipt.total.map { Money.format($0, currency: receipt.currency) } ?? String(localized: "No total"))
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(receipt.total == nil ? .secondary : .primary)
            if !receipt.tags.isEmpty {
                Text(receipt.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ItemRow: View {
    let item: ReceiptItem
    let currency: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.description.isEmpty ? String(localized: "Unnamed item") : item.description)
                    .foregroundStyle(item.description.isEmpty ? .secondary : .primary)
                if let quantity = item.quantity {
                    Text("Quantity \(Money.formatForInput(quantity))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let amount = item.amount {
                Text(Money.format(amount, currency: currency))
                    .monospacedDigit()
                    .foregroundStyle(amount < 0 ? Color.accentColor : .primary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
