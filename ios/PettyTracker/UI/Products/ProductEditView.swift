import SwiftUI

struct ProductEditView: View {
    let productId: Int64?
    /// Prefilled values and receipt link for a new product.
    var draft: Product?
    var receiptId: Int64?
    let onSaved: (Int64) -> Void
    @Environment(TrackerStore.self) private var store

    var body: some View {
        ProductEditForm(
            original: productId.flatMap(store.product),
            draft: draft,
            attachments: productId.map { store.attachments(.product, $0) } ?? [],
            receiptId: productId.map { store.receiptCovering($0)?.id } ?? receiptId,
            defaultCurrency: store.settings.defaultCurrency,
            onSaved: onSaved
        )
    }
}

private struct ProductForm: Equatable {
    var name = ""
    var brand = ""
    var model = ""
    var serialNumber = ""
    var purchaseDate: Day?
    var retailer = ""
    var price = ""
    var currency: String
    var warrantyExpires: Day?
    var notes = ""
    var receiptId: Int64?

    init(_ product: Product?, receiptId: Int64?, defaultCurrency: String) {
        currency = product?.currency ?? defaultCurrency
        self.receiptId = receiptId
        guard let product else { return }
        name = product.name
        brand = product.brand
        model = product.model
        serialNumber = product.serialNumber
        purchaseDate = product.purchaseDate
        retailer = product.retailer
        price = product.price.map(Money.formatForInput) ?? ""
        warrantyExpires = product.warrantyExpires
        notes = product.notes
    }

    var parsedPrice: Decimal? { Money.parse(price) }
    var priceIsValid: Bool { price.trimmingCharacters(in: .whitespaces).isEmpty || parsedPrice != nil }
}

private struct ProductEditForm: View {
    let original: Product?
    let onSaved: (Int64) -> Void
    private let initial: ProductForm
    @State private var form: ProductForm
    @State private var attachments: AttachmentDraft
    @State private var showErrors = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(
        original: Product?,
        draft: Product?,
        attachments: [Attachment],
        receiptId: Int64?,
        defaultCurrency: String,
        onSaved: @escaping (Int64) -> Void
    ) {
        self.original = original
        self.onSaved = onSaved
        initial = ProductForm(original ?? draft, receiptId: receiptId, defaultCurrency: defaultCurrency)
        _form = State(initialValue: initial)
        _attachments = State(initialValue: AttachmentDraft(existing: attachments))
    }

    private var hasChanges: Bool { form != initial || attachments.hasChanges }

    var body: some View {
        NavigationStack {
            TrackerForm {
                Section(overline: "Details") {
                    FormTextField("Name", text: $form.name, prompt: "Required")
                        .textInputAutocapitalization(.words)
                    if showErrors && form.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        FieldError(text: String(localized: "Required"))
                    }
                    FormTextField("Brand", text: $form.brand)
                    FormTextField("Model", text: $form.model)
                    FormTextField("Serial number", text: $form.serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section(overline: "Purchase") {
                    OptionalDateRow(title: String(localized: "Purchase date"), selection: $form.purchaseDate)
                    FormTextField("Retailer", text: $form.retailer)
                    AmountRow(price: $form.price, currency: $form.currency, isInvalid: showErrors && !form.priceIsValid)
                }
                Section {
                    OptionalDateRow(title: String(localized: "Warranty ends"), selection: $form.warrantyExpires)
                    Menu {
                        ForEach([1, 2, 3, 5], id: \.self) { years in
                            Button(Formats.count(years, "year", "years")) {
                                form.warrantyExpires = (form.purchaseDate ?? store.today).adding(months: years * 12)
                            }
                        }
                    } label: {
                        Label(
                            form.purchaseDate == nil ? "Set length from today" : "Set length from purchase date",
                            systemImage: "calendar.badge.clock"
                        )
                    }
                } header: {
                    Overline("Warranty")
                } footer: {
                    if let start = form.purchaseDate, let end = form.warrantyExpires, end < start {
                        Text("This is before the purchase date").foregroundStyle(Color.trackerSoon)
                    }
                }
                Section {
                    NavigationLink {
                        ReceiptPicker(selection: form.receiptId) { form.receiptId = $0 }
                    } label: {
                        if let receipt = form.receiptId.flatMap(store.receipt) {
                            ReceiptRow(receipt: receipt)
                        } else {
                            Label("Link a saved receipt", systemImage: Receipt.symbol)
                        }
                    }
                } header: {
                    Overline("Receipt")
                } footer: {
                    Text("A receipt can cover several products. Its scans stay with the receipt and aren't copied.")
                }
                Section(overline: "Notes") {
                    NotesField(text: $form.notes)
                }
                AttachmentEditorSection(title: "Files and photos", draft: $attachments)
            }
            .navigationTitle(original == nil ? "New product" : "Edit product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditToolbar(hasChanges: hasChanges, confirmDiscard: $confirmDiscard, onDiscard: discard, onSave: save)
            }
            .interactiveDismissDisabled(hasChanges)
            .errorAlert($errorMessage)
        }
    }

    private func discard() {
        attachments.discard(store: store.attachmentStore)
        dismiss()
    }

    private func save() {
        showErrors = true
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, form.priceIsValid, Money.isValidCurrency(form.currency) else { return }
        var product = original ?? Product(name: name, currency: form.currency)
        product.name = name
        product.brand = form.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        product.model = form.model.trimmingCharacters(in: .whitespacesAndNewlines)
        product.serialNumber = form.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        product.purchaseDate = form.purchaseDate
        product.retailer = form.retailer.trimmingCharacters(in: .whitespacesAndNewlines)
        product.price = form.parsedPrice
        product.currency = form.currency
        product.warrantyExpires = form.warrantyExpires
        product.notes = form.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let id = try store.saveProduct(
                product, added: attachments.added, removed: attachments.removed, receiptId: form.receiptId
            )
            dismiss()
            onSaved(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
