import SwiftUI

struct ReceiptEditorRequest: Identifiable {
    let id = UUID()
    var receiptId: Int64?
    var capture: ReceiptCapture?
    var sharedItem: SharedInbox.Item?
}

struct ReceiptEditView: View {
    let request: ReceiptEditorRequest
    let onSaved: (Int64) -> Void
    @Environment(KeepStore.self) private var store

    var body: some View {
        ReceiptEditForm(
            original: request.receiptId.flatMap(store.receipt),
            pages: request.receiptId.map { store.attachments(.receipt, $0) } ?? [],
            defaultCurrency: store.settings.defaultCurrency,
            capture: request.capture,
            sharedItem: request.sharedItem,
            onSaved: onSaved
        )
    }
}

struct ReceiptItemDraft: Identifiable, Equatable {
    var id = UUID()
    var description = ""
    var quantity = ""
    var amount = ""

    init() {}

    init(_ item: ReceiptItem) {
        description = item.description
        quantity = item.quantity.map(Money.formatForInput) ?? ""
        amount = item.amount.map(Money.formatForInput) ?? ""
    }

    var isBlank: Bool { [description, quantity, amount].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    var quantityIsValid: Bool { ReceiptForm.isValidQuantity(quantity) }
    var amountIsValid: Bool { ReceiptForm.isValidAmount(amount) }
}

struct ReceiptFieldDraft: Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var value = ""

    init() {}

    init(_ field: ReceiptField) {
        name = field.name
        value = field.value
    }

    var isBlank: Bool { [name, value].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var isValid: Bool { isBlank || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Editable receipt fields; amounts stay as typed text until saved.
struct ReceiptForm: Equatable {
    var merchant = ""
    var purchaseDate: Day?
    var purchaseTime: ClockTime?
    var currency: String
    var category = ""
    var tags = ""
    var items: [ReceiptItemDraft] = []
    var subtotal = ""
    var tax = ""
    var tip = ""
    var total = ""
    var notes = ""
    var recognizedText: [String: String] = [:]
    var pageConfidence: [String: Double] = [:]
    var pageDigests: [String: String] = [:]
    var storeAddress = ""
    var storePhone = ""
    var transactionId = ""
    var paymentMethod = ""
    var cardLastFour = ""
    var origin = ""
    var destination = ""
    var fuelGrade = ""
    var fuelVolume = ""
    var fuelUnit: FuelUnit?
    var fuelUnitPrice = ""
    var pumpNumber = ""
    var odometer = ""
    var customFields: [ReceiptFieldDraft] = []

    init(_ receipt: Receipt?, defaultCurrency: String) {
        currency = receipt?.currency ?? defaultCurrency
        guard let receipt else { return }
        merchant = receipt.merchant
        purchaseDate = receipt.purchaseDate
        purchaseTime = receipt.purchaseTime
        category = receipt.category
        tags = receipt.tags.joined(separator: ", ")
        items = receipt.items.map(ReceiptItemDraft.init)
        subtotal = receipt.subtotal.map(Money.formatForInput) ?? ""
        tax = receipt.tax.map(Money.formatForInput) ?? ""
        tip = receipt.tip.map(Money.formatForInput) ?? ""
        total = receipt.total.map(Money.formatForInput) ?? ""
        notes = receipt.notes
        recognizedText = receipt.recognizedText
        pageConfidence = receipt.pageConfidence
        pageDigests = receipt.pageDigests
        storeAddress = receipt.storeAddress
        storePhone = receipt.storePhone
        transactionId = receipt.transactionId
        paymentMethod = receipt.paymentMethod
        cardLastFour = receipt.cardLastFour
        origin = receipt.origin
        destination = receipt.destination
        fuelGrade = receipt.fuelGrade
        fuelVolume = receipt.fuelVolume.map(Money.formatForInput) ?? ""
        fuelUnit = receipt.fuelUnit
        fuelUnitPrice = receipt.fuelUnitPrice.map(Money.formatForInput) ?? ""
        pumpNumber = receipt.pumpNumber
        odometer = receipt.odometer
        customFields = receipt.customFields.map(ReceiptFieldDraft.init)
    }

    static func isValidAmount(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || Money.parseSigned(text) != nil
    }

    static func amount(_ text: String) -> Decimal? { Money.parseSigned(text) }

    /// Copies recognized values into fields that are still empty; never overwrites what is there.
    mutating func fillBlanks(from parsed: ParsedReceipt) {
        let noAmounts = items.isEmpty && [subtotal, tax, tip, total].allSatisfy(\.isEmpty)
        if merchant.trimmingCharacters(in: .whitespaces).isEmpty, let value = parsed.merchant { merchant = value }
        if purchaseDate == nil { purchaseDate = parsed.purchaseDate }
        if noAmounts, let value = parsed.currency { currency = value }
        if items.isEmpty { items = parsed.items.map(ReceiptItemDraft.init) }
        for (field, value) in [(\ReceiptForm.subtotal, parsed.subtotal), (\.tax, parsed.tax), (\.tip, parsed.tip), (\.total, parsed.total)] {
            if self[keyPath: field].isEmpty, let value { self[keyPath: field] = Money.formatForInput(value) }
        }
        if purchaseTime == nil { purchaseTime = parsed.purchaseTime }
        let texts: [(WritableKeyPath<ReceiptForm, String>, String?)] = [
            (\.storeAddress, parsed.storeAddress), (\.storePhone, parsed.storePhone), (\.transactionId, parsed.transactionId),
            (\.paymentMethod, parsed.paymentMethod), (\.cardLastFour, parsed.cardLastFour), (\.fuelGrade, parsed.fuelGrade),
            (\.pumpNumber, parsed.pumpNumber), (\.odometer, parsed.odometer),
        ]
        for (field, value) in texts where self[keyPath: field].trimmingCharacters(in: .whitespaces).isEmpty {
            if let value { self[keyPath: field] = value }
        }
        if fuelVolume.isEmpty, let value = parsed.fuelVolume {
            fuelVolume = Money.formatForInput(value)
            fuelUnit = parsed.fuelUnit
        }
        if fuelUnitPrice.isEmpty, let value = parsed.fuelUnitPrice { fuelUnitPrice = Money.formatForInput(value) }
        if category.trimmingCharacters(in: .whitespaces).isEmpty, parsed.isFuel { category = Receipt.fuelCategory }
    }

    var isFuel: Bool {
        category.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(Receipt.fuelCategory) == .orderedSame
            || ![fuelGrade, fuelVolume, fuelUnitPrice, pumpNumber, odometer].allSatisfy(\.isEmpty)
    }

    static func isValidQuantity(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || Money.parse(text) != nil
    }

    var itemsSum: Decimal? {
        let amounts = items.compactMap { Self.amount($0.amount) }
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    /// Subtotal (or the items when there is none) plus tax and tip.
    var computedTotal: Decimal? {
        guard let base = Self.amount(subtotal) ?? itemsSum else { return nil }
        return base + (Self.amount(tax) ?? 0) + (Self.amount(tip) ?? 0)
    }

    var isValid: Bool {
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty
            && [subtotal, tax, tip, total].allSatisfy(Self.isValidAmount)
            && items.allSatisfy { $0.quantityIsValid && $0.amountIsValid }
            && Money.isValidCurrency(currency)
            && Receipt.isValidCardLastFour(cardLastFour.trimmingCharacters(in: .whitespaces))
            && [fuelVolume, fuelUnitPrice].allSatisfy(Self.isValidQuantity)
            && customFields.allSatisfy(\.isValid)
    }

    func receipt(updating original: Receipt?, today: Day) -> Receipt {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var receipt = original ?? Receipt(merchant: "", currency: currency, addedOn: today)
        receipt.merchant = trimmed(merchant)
        receipt.purchaseDate = purchaseDate
        receipt.currency = currency
        receipt.category = trimmed(category)
        receipt.tags = ReceiptOrganizer.tags(from: tags)
        receipt.items = items.filter { !$0.isBlank }.map {
            ReceiptItem(description: trimmed($0.description), quantity: Money.parse($0.quantity), amount: Self.amount($0.amount))
        }
        receipt.subtotal = Self.amount(subtotal)
        receipt.tax = Self.amount(tax)
        receipt.tip = Self.amount(tip)
        receipt.total = Self.amount(total)
        receipt.notes = trimmed(notes)
        receipt.recognizedText = recognizedText
        receipt.pageConfidence = pageConfidence
        receipt.pageDigests = pageDigests
        receipt.purchaseTime = purchaseTime
        receipt.storeAddress = trimmed(storeAddress)
        receipt.storePhone = trimmed(storePhone)
        receipt.transactionId = trimmed(transactionId)
        receipt.paymentMethod = trimmed(paymentMethod)
        receipt.cardLastFour = trimmed(cardLastFour)
        receipt.origin = trimmed(origin)
        receipt.destination = trimmed(destination)
        receipt.fuelGrade = trimmed(fuelGrade)
        receipt.fuelVolume = Money.parse(fuelVolume)
        receipt.fuelUnit = receipt.fuelVolume == nil ? nil : fuelUnit
        receipt.fuelUnitPrice = Money.parse(fuelUnitPrice)
        receipt.pumpNumber = trimmed(pumpNumber)
        receipt.odometer = trimmed(odometer)
        receipt.customFields = customFields.filter { !$0.isBlank }.map {
            ReceiptField(name: trimmed($0.name), value: trimmed($0.value))
        }
        return receipt
    }
}

private struct ReceiptEditForm: View {
    static let suggestedCategories: [String] = [
        String(localized: "Groceries"), String(localized: "Dining"), String(localized: "Travel"),
        Receipt.fuelCategory, String(localized: "Shopping"), String(localized: "Household"),
        String(localized: "Health"), String(localized: "Utilities"), String(localized: "Entertainment"),
        String(localized: "Business"),
    ]

    let original: Receipt?
    let sharedItem: SharedInbox.Item?
    let onSaved: (Int64) -> Void
    private let initial: ReceiptForm
    @State private var form: ReceiptForm
    @State private var pages: AttachmentDraft
    @State private var pendingCapture: ReceiptCapture?
    @State private var captureSource: CaptureSource?
    @State private var importing = 0
    @State private var recognizing = 0
    @State private var work: [Task<Void, Never>] = []
    @State private var noTextFound = false
    @State private var showErrors = false
    @State private var confirmDiscard = false
    @State private var confirmCancelShared = false
    @State private var errorMessage: String?
    @Environment(KeepStore.self) private var store
    @Environment(QuickCapture.self) private var quickCapture
    @Environment(\.dismiss) private var dismiss

    init(
        original: Receipt?,
        pages: [Attachment],
        defaultCurrency: String,
        capture: ReceiptCapture?,
        sharedItem: SharedInbox.Item?,
        onSaved: @escaping (Int64) -> Void
    ) {
        self.original = original
        self.sharedItem = sharedItem
        self.onSaved = onSaved
        initial = ReceiptForm(original, defaultCurrency: defaultCurrency)
        _form = State(initialValue: initial)
        _pages = State(initialValue: AttachmentDraft(existing: pages))
        _pendingCapture = State(initialValue: capture)
    }

    private var busy: Bool { importing > 0 || recognizing > 0 }
    private var hasChanges: Bool { form != initial || pages.hasChanges || busy }

    private var pageText: String {
        pages.visible.compactMap { form.recognizedText[$0.fileName] }.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                pagesSection
                reviewSection
                detailsSection
                ReceiptStoreSection(form: $form, showErrors: showErrors)
                ReceiptTripSection(form: $form, places: places)
                ReceiptFuelSection(form: $form, showErrors: showErrors)
                itemsSection
                totalsSection
                ReceiptCustomFieldsSection(
                    fields: $form.customFields,
                    names: ReceiptOrganizer.suggestions(store.data.receipts.flatMap(\.customFields).map(\.name)),
                    showErrors: showErrors
                )
                Section("Notes") {
                    NotesField(text: $form.notes)
                }
                recognizedTextSection
            }
            .navigationTitle(original == nil ? "New receipt" : "Edit receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let sharedItem {
                    sharedToolbar(sharedItem)
                } else {
                    EditToolbar(hasChanges: hasChanges, canSave: !busy, confirmDiscard: $confirmDiscard, onDiscard: discard, onSave: save)
                }
            }
            .interactiveDismissDisabled(hasChanges || sharedItem != nil)
            .receiptCapture($captureSource, errorMessage: $errorMessage) { capture in
                addPages(capture, fillBlanks: false)
            }
            .errorAlert($errorMessage)
            .onAppear {
                guard let capture = pendingCapture else { return }
                pendingCapture = nil
                addPages(capture, fillBlanks: true)
            }
        }
    }

    /// Canceling never deletes a shared file without asking; it can wait in the list for later.
    @ToolbarContentBuilder
    private func sharedToolbar(_ item: SharedInbox.Item) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { confirmCancelShared = true }
                .confirmationDialog("Keep this shared file?", isPresented: $confirmCancelShared, titleVisibility: .visible) {
                    Button("Review later") {
                        quickCapture.postpone(item)
                        discard()
                    }
                    Button("Delete shared file", role: .destructive) {
                        discard()
                        quickCapture.finish(item)
                    }
                } message: {
                    Text("Review later keeps it under Receipts. Deleting removes it from petty: Tracker.")
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save).disabled(busy)
        }
    }

    private var pagesSection: some View {
        Section {
            if !pages.visible.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(pages.visible.enumerated()), id: \.element.fileName) { index, page in
                            ReceiptPageThumbnail(page: page, width: 72, height: 100)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        pages.remove(page, store: store.attachmentStore)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.keepPast)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.borderless)
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel(String(localized: "Remove page \(index + 1)"))
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel(String(localized: "Page \(index + 1)"))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
            }
            if busy {
                HStack {
                    ProgressView()
                    Text(importing > 0 ? "Adding pages…" : "Reading text on this iPhone…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if noTextFound {
                Text("No text was found on the scan. Enter the details yourself.")
                    .foregroundStyle(Color.keepSoon)
            }
            AddPagesMenu(source: $captureSource) {
                Label(pages.visible.isEmpty ? "Add scan or photo" : "Add pages", systemImage: "doc.viewfinder")
            }
            if !pageText.isEmpty && !busy {
                Button("Fill empty fields from scan", systemImage: "text.viewfinder") {
                    form.fillBlanks(from: parsed(pageText))
                }
            }
        } header: {
            Text("Scans")
        } footer: {
            if !pages.visible.isEmpty {
                Text("Text is recognized on this iPhone and can contain mistakes, especially in handwriting. Check each field before saving.")
            }
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        let draft = form.receipt(updating: original, today: store.today)
        let flags = ReceiptReview.unresolved(
            ReceiptReview.flags(for: draft, pages: pages.visible.map(\.fileName), among: store.data.receipts),
            in: draft
        )
        if !busy && !flags.isEmpty {
            Section {
                ForEach(flags) { ReviewFlagRow(flag: $0, currency: form.currency) }
            } header: {
                Text("Check before saving")
            } footer: {
                Text("Nothing is removed automatically. Saved receipts with open checks appear under Needs review.")
            }
        }
    }

    private var detailsSection: some View {
        Section("Receipt") {
            TextField("Merchant", text: $form.merchant)
                .textInputAutocapitalization(.words)
            if showErrors && form.merchant.trimmingCharacters(in: .whitespaces).isEmpty {
                FieldError(text: String(localized: "Required"))
            }
            OptionalDateRow(title: String(localized: "Purchase date"), selection: $form.purchaseDate)
            OptionalTimeRow(title: String(localized: "Time"), selection: $form.purchaseTime)
            NavigationLink {
                CurrencyPicker(selection: $form.currency)
            } label: {
                LabeledContent("Currency") {
                    Text(form.currency).monospaced()
                }
            }
            HStack {
                TextField("Category", text: $form.category)
                    .textInputAutocapitalization(.words)
                Menu {
                    ForEach(categorySuggestions, id: \.self) { category in
                        Button(category) { form.category = category }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Choose category")
            }
            TextField("Tags, separated by commas", text: $form.tags)
                .textInputAutocapitalization(.never)
        }
    }

    private var categorySuggestions: [String] {
        let used = ReceiptOrganizer.categories(store.data.receipts)
        return used + Self.suggestedCategories.filter { suggestion in
            !used.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        }
    }

    private var places: [String] {
        ReceiptOrganizer.suggestions(store.data.receipts.flatMap { [$0.origin, $0.destination] })
    }

    private var itemsSection: some View {
        Section {
            ForEach($form.items) { $item in
                ItemEditorRow(item: $item, showErrors: showErrors)
            }
            .onDelete { form.items.remove(atOffsets: $0) }
            Button("Add item", systemImage: "plus.circle") {
                form.items.append(ReceiptItemDraft())
            }
        } header: {
            Text("Items")
        } footer: {
            if let sum = form.itemsSum {
                Text("Items add up to \(Money.format(sum, currency: form.currency)). Enter discounts as negative amounts.")
            } else {
                Text("Enter discounts as negative amounts.")
            }
        }
    }

    private var totalsSection: some View {
        Section {
            AmountField(title: "Subtotal", text: $form.subtotal, showErrors: showErrors)
            AmountField(title: "Tax", text: $form.tax, showErrors: showErrors)
            AmountField(title: "Tip", text: $form.tip, showErrors: showErrors)
            AmountField(title: "Total", text: $form.total, showErrors: showErrors)
            if form.total.trimmingCharacters(in: .whitespaces).isEmpty, let computed = form.computedTotal {
                Button("Use \(Money.format(computed, currency: form.currency)) as total") {
                    form.total = Money.formatForInput(computed)
                }
            }
        } header: {
            Text("Totals")
        } footer: {
            if let warning = totalsWarning {
                Text(warning).foregroundStyle(Color.keepSoon)
            }
        }
    }

    private var totalsWarning: String? {
        let format = { Money.format($0, currency: form.currency) }
        if let subtotal = ReceiptForm.amount(form.subtotal), let sum = form.itemsSum, subtotal != sum {
            return String(localized: "Items add up to \(format(sum)), but the subtotal is \(format(subtotal)).")
        }
        if let total = ReceiptForm.amount(form.total), let computed = form.computedTotal, computed != total {
            return String(localized: "Subtotal, tax and tip add up to \(format(computed)), not \(format(total)). Tax may already be included in the total.")
        }
        return nil
    }

    @ViewBuilder
    private var recognizedTextSection: some View {
        let texts = pages.visible.enumerated().compactMap { index, page in
            form.recognizedText[page.fileName].map { (page: index + 1, text: $0) }
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
                Text("The original text is kept with the receipt and is not changed by your edits.")
            }
        }
    }

    private func parsed(_ text: String) -> ParsedReceipt {
        ReceiptParser.parse(text, today: store.today, defaultCurrency: store.settings.defaultCurrency)
    }

    private func addPages(_ capture: ReceiptCapture, fillBlanks: Bool) {
        let attachmentStore = store.attachmentStore
        importing += 1
        work.append(Task {
            let (added, failed, reasons) = await capture.importPages(into: attachmentStore)
            importing -= 1
            guard !Task.isCancelled else {
                attachmentStore.delete(added.map(\.fileName))
                return
            }
            pages.added += added
            if failed > 0 {
                errorMessage = ([String(localized: "\(Formats.count(failed, "page", "pages")) could not be added.")] + reasons)
                    .joined(separator: " ")
            }
            recognizing += 1
            defer { recognizing -= 1 }
            for page in added {
                form.pageDigests[page.fileName] = try? await attachmentStore.digest(of: page.fileName)
                let recognized = try? await TextRecognizer.recognizeText(inImageAt: attachmentStore.url(for: page.fileName))
                form.recognizedText[page.fileName] = (recognized?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                form.pageConfidence[page.fileName] = recognized?.confidence
            }
            let recognized = added.compactMap { form.recognizedText[$0.fileName] }.joined(separator: "\n")
            noTextFound = !added.isEmpty && recognized.isEmpty
            if fillBlanks { form.fillBlanks(from: parsed(recognized)) }
        })
    }

    private func discard() {
        work.forEach { $0.cancel() }
        pages.discard(store: store.attachmentStore)
        dismiss()
    }

    private func save() {
        showErrors = true
        guard !busy, form.isValid else { return }
        let receipt = form.receipt(updating: original, today: store.today)
        do {
            let id = try store.saveReceipt(receipt, added: pages.added, removed: pages.removed)
            if let sharedItem { quickCapture.finish(sharedItem) }
            dismiss()
            onSaved(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ItemEditorRow: View {
    @Binding var item: ReceiptItemDraft
    let showErrors: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Description", text: $item.description)
            HStack {
                TextField("Qty", text: $item.quantity)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 70)
                    .foregroundStyle(showErrors && !item.quantityIsValid ? Color.keepPast : .primary)
                    .accessibilityLabel("Quantity")
                Spacer()
                TextField("Amount", text: $item.amount)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(showErrors && !item.amountIsValid ? Color.keepPast : .primary)
            }
            .font(.subheadline)
            if showErrors && !(item.quantityIsValid && item.amountIsValid) {
                FieldError(text: String(localized: "Enter numbers such as 2 or -1.50"))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AmountField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let showErrors: Bool

    var body: some View {
        LabeledContent(title) {
            TextField("Amount", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(showErrors && !ReceiptForm.isValidAmount(text) ? Color.keepPast : .primary)
        }
    }
}
