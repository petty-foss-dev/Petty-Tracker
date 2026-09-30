import SwiftUI

extension ClockTime {
    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)!
    }

    func date(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}

extension FuelUnit {
    var symbol: String {
        switch self {
        case .gallons: String(localized: "gal", comment: "Abbreviation for US gallons")
        case .liters: String(localized: "L", comment: "Abbreviation for liters")
        }
    }
}

struct OptionalTimeRow: View {
    let title: String
    @Binding var selection: ClockTime?

    var body: some View {
        if let time = selection {
            HStack {
                DatePicker(
                    title,
                    selection: Binding(get: { time.date() }, set: { selection = ClockTime(date: $0) }),
                    displayedComponents: .hourAndMinute
                )
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Clear \(title)"))
            }
        } else {
            Button {
                selection = ClockTime(date: .now)
            } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text("Add time").foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityLabel(String(localized: "Choose \(title)"))
        }
    }
}

struct ReceiptStoreSection: View {
    @Binding var form: ReceiptForm
    let showErrors: Bool

    var body: some View {
        Section("Store and payment") {
            TextField("Store address", text: $form.storeAddress, axis: .vertical)
                .lineLimit(1...4)
            TextField("Store phone", text: $form.storePhone)
                .keyboardType(.phonePad)
            TextField("Receipt or transaction number", text: $form.transactionId)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Payment method, such as Visa or Cash", text: $form.paymentMethod)
                .textInputAutocapitalization(.words)
            LabeledContent("Card last 4 digits") {
                TextField("1234", text: $form.cardLastFour)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(showErrors && !cardIsValid ? Color.keepPast : .primary)
            }
            if showErrors && !cardIsValid {
                FieldError(text: String(localized: "Enter exactly 4 digits, or leave it blank."))
            }
        }
    }

    private var cardIsValid: Bool { Receipt.isValidCardLastFour(form.cardLastFour.trimmingCharacters(in: .whitespaces)) }
}

struct ReceiptTripSection: View {
    @Binding var form: ReceiptForm
    /// Places already used on other receipts, most used first.
    let places: [String]

    var body: some View {
        Section {
            placeField("From", text: $form.origin)
            placeField("To", text: $form.destination)
            if !form.origin.isEmpty || !form.destination.isEmpty {
                Button("Swap From and To", systemImage: "arrow.up.arrow.down") {
                    (form.origin, form.destination) = (form.destination, form.origin)
                }
            }
        } header: {
            Text("Trip")
        } footer: {
            Text("Where the trip started and ended, for finding receipts by route. Use the same spelling each time.")
        }
    }

    private func placeField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            TextField(title, text: text)
                .textInputAutocapitalization(.words)
            if !places.isEmpty {
                Menu {
                    ForEach(places.prefix(20), id: \.self) { place in
                        Button(place) { text.wrappedValue = place }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel(String(localized: "Choose a place you used before"))
            }
        }
    }
}

struct ReceiptFuelSection: View {
    @Binding var form: ReceiptForm
    let showErrors: Bool
    @State private var expanded = false

    var body: some View {
        Section {
            if form.isFuel || expanded {
                TextField("Grade, such as Regular or Diesel", text: $form.fuelGrade)
                    .textInputAutocapitalization(.words)
                HStack {
                    TextField("Volume", text: $form.fuelVolume)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(showErrors && !ReceiptForm.isValidQuantity(form.fuelVolume) ? Color.keepPast : .primary)
                    Picker("Unit", selection: $form.fuelUnit) {
                        Text("Unit").tag(FuelUnit?.none)
                        ForEach(FuelUnit.allCases, id: \.self) { Text($0.symbol).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                LabeledContent("Price per \(form.fuelUnit?.symbol ?? String(localized: "unit"))") {
                    TextField("3.459", text: $form.fuelUnitPrice)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(showErrors && !ReceiptForm.isValidQuantity(form.fuelUnitPrice) ? Color.keepPast : .primary)
                }
                TextField("Pump number", text: $form.pumpNumber)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Odometer", text: $form.odometer)
                    .keyboardType(.numbersAndPunctuation)
                if showErrors && ![form.fuelVolume, form.fuelUnitPrice].allSatisfy(ReceiptForm.isValidQuantity) {
                    FieldError(text: String(localized: "Enter numbers such as 10.543"))
                }
            } else {
                Button("Add fuel details", systemImage: "fuelpump") { expanded = true }
            }
        } header: {
            Text("Fuel")
        }
    }
}

struct ReceiptCustomFieldsSection: View {
    @Binding var fields: [ReceiptFieldDraft]
    /// Names already used on other receipts, most used first.
    let names: [String]
    let showErrors: Bool

    var body: some View {
        Section {
            ForEach($fields) { $field in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Name", text: $field.name)
                            .font(.subheadline.weight(.medium))
                            .textInputAutocapitalization(.words)
                        if !names.isEmpty {
                            Menu {
                                ForEach(names.prefix(20), id: \.self) { name in
                                    Button(name) { field.name = name }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                            .accessibilityLabel(String(localized: "Choose a field name you used before"))
                        }
                    }
                    TextField("Value", text: $field.value, axis: .vertical)
                        .lineLimit(1...4)
                    if showErrors && !field.isValid {
                        FieldError(text: String(localized: "Name required"))
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { fields.remove(atOffsets: $0) }
            Button("Add field", systemImage: "plus.circle") {
                fields.append(ReceiptFieldDraft())
            }
        } header: {
            Text("Custom fields")
        } footer: {
            Text("Add your own details, such as Vehicle, Project or Trip purpose. Names and values can be searched and browsed.")
        }
    }
}
