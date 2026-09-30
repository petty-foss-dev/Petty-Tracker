import SwiftUI

struct SubscriptionEditView: View {
    let subscriptionId: Int64?
    let onSaved: (Int64) -> Void
    @Environment(KeepStore.self) private var store

    var body: some View {
        SubscriptionEditForm(
            original: subscriptionId.flatMap(store.subscription),
            defaultCurrency: store.settings.defaultCurrency,
            onSaved: onSaved
        )
    }
}

private struct SubscriptionForm: Equatable {
    var name = ""
    var price = ""
    var currency: String
    var cycleCount = "1"
    var cycleUnit = CycleUnit.months
    var nextRenewal: Day?
    var notes = ""

    init(_ subscription: Subscription?, defaultCurrency: String) {
        currency = subscription?.currency ?? defaultCurrency
        guard let subscription else { return }
        name = subscription.name
        price = subscription.price.map(Money.formatForInput) ?? ""
        currency = subscription.currency
        cycleCount = String(subscription.cycleCount)
        cycleUnit = subscription.cycleUnit
        nextRenewal = subscription.nextRenewal
        notes = subscription.notes
    }

    var parsedPrice: Decimal? { Money.parse(price) }
    var priceIsValid: Bool { price.trimmingCharacters(in: .whitespaces).isEmpty || parsedPrice != nil }
    var parsedCycle: Int? { Int(cycleCount).flatMap { (1...999).contains($0) ? $0 : nil } }
}

private struct SubscriptionEditForm: View {
    let original: Subscription?
    let onSaved: (Int64) -> Void
    private let initial: SubscriptionForm
    @State private var form: SubscriptionForm
    @State private var showErrors = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?
    @Environment(KeepStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(original: Subscription?, defaultCurrency: String, onSaved: @escaping (Int64) -> Void) {
        self.original = original
        self.onSaved = onSaved
        initial = SubscriptionForm(original, defaultCurrency: defaultCurrency)
        _form = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Service name", text: $form.name)
                        .textInputAutocapitalization(.words)
                    if showErrors && form.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        FieldError(text: String(localized: "Required"))
                    }
                    AmountRow(price: $form.price, currency: $form.currency, isInvalid: showErrors && !form.priceIsValid)
                }
                Section {
                    HStack {
                        Text("Every")
                        TextField("1", text: $form.cycleCount)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                            .accessibilityLabel("Billing cycle length")
                        Picker("Period", selection: $form.cycleUnit) {
                            ForEach(CycleUnit.allCases, id: \.self) { unit in
                                Text(Formats.unit(unit, count: form.parsedCycle ?? 1)).tag(unit)
                            }
                        }
                        .labelsHidden()
                    }
                    if showErrors && form.parsedCycle == nil {
                        FieldError(text: String(localized: "Enter 1–999"))
                    }
                    OptionalDateRow(
                        title: String(localized: "Next renewal"),
                        selection: $form.nextRenewal,
                        clearable: false,
                        isInvalid: showErrors && form.nextRenewal == nil
                    )
                } header: {
                    Text("Billing cycle")
                } footer: {
                    Text("Future renewals follow this date, keeping month-end dates at month end.")
                }
                Section("Notes") {
                    NotesField(text: $form.notes)
                }
            }
            .navigationTitle(original == nil ? "New subscription" : "Edit subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditToolbar(hasChanges: form != initial, confirmDiscard: $confirmDiscard, onDiscard: { dismiss() }, onSave: save)
            }
            .interactiveDismissDisabled(form != initial)
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        showErrors = true
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, form.priceIsValid, Money.isValidCurrency(form.currency),
              let cycle = form.parsedCycle, let nextRenewal = form.nextRenewal
        else { return }
        // Keep the original anchor unless the schedule itself changed, so month-end billing survives edits.
        let keepAnchor = original.map {
            $0.nextRenewal == nextRenewal && $0.cycleCount == cycle && $0.cycleUnit == form.cycleUnit
        } ?? false
        var subscription = original ?? Subscription(name: name, currency: form.currency, nextRenewal: nextRenewal, anchorDate: nextRenewal)
        subscription.name = name
        subscription.price = form.parsedPrice
        subscription.currency = form.currency
        subscription.cycleCount = cycle
        subscription.cycleUnit = form.cycleUnit
        subscription.nextRenewal = nextRenewal
        if !keepAnchor { subscription.anchorDate = nextRenewal }
        subscription.notes = form.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let id = try store.saveSubscription(subscription)
            dismiss()
            onSaved(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
