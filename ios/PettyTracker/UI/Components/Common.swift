import SwiftUI

struct StatusBadge: View {
    let text: String
    let status: DeadlineStatus

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .past: .trackerPast
        case .soon, .today: .trackerSoon
        case .ok: .trackerOnPrimaryContainer
        case .none: .secondary
        }
    }

    private var background: Color {
        switch status {
        case .past: .trackerPastContainer.opacity(0.6)
        case .soon, .today: .trackerSoonContainer.opacity(0.6)
        case .ok: .trackerPrimaryContainer.opacity(0.7)
        case .none: Color.secondary.opacity(0.12)
        }
    }
}

extension DeadlineStatus {
    var tint: Color {
        switch self {
        case .past: .trackerPast
        case .soon, .today: .trackerSoon
        case .ok: .accentColor
        case .none: .secondary
        }
    }
}

/// The rounded symbol tile that leads record rows.
struct RecordIcon: View {
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

/// A dashboard or search row for any record with a date.
struct DeadlineRow: View {
    let deadline: Deadline
    let status: DeadlineStatus
    let today: Day

    var body: some View {
        let phrase = Formats.deadline(deadline.kind, days: deadline.days(from: today))
        HStack(spacing: 12) {
            RecordIcon(symbol: deadline.kind.symbol, tint: status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(phrase)
                    .font(.subheadline)
                    .foregroundStyle(status == .ok ? Color.secondary : status.tint)
            }
            Spacer(minLength: 8)
            Text(Formats.shortDate(deadline.date, today: today))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deadline.kind.label), \(deadline.title), \(phrase), \(Formats.date(deadline.date))")
    }
}

/// A form row that keeps its label visible once the field has a value.
struct FormTextField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey = "Optional"

    init(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey = "Optional") {
        self.label = label
        _text = text
        self.prompt = prompt
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A date row that can be empty; required dates hide the clear button.
struct OptionalDateRow: View {
    let title: String
    @Binding var selection: Day?
    var clearable = true
    var isInvalid = false

    var body: some View {
        if let day = selection {
            HStack {
                DatePicker(
                    title,
                    selection: Binding(get: { day.date() }, set: { selection = Day(date: $0) }),
                    displayedComponents: .date
                )
                if clearable {
                    Button {
                        selection = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Clear \(title)"))
                }
            }
        } else {
            Button {
                selection = Day.today()
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(isInvalid ? Color.trackerPast : .primary)
                    Spacer()
                    Text(isInvalid ? "Required" : "Add date")
                        .foregroundStyle(isInvalid ? Color.trackerPast : .accentColor)
                }
            }
            .accessibilityLabel(String(localized: "Choose \(title)"))
        }
    }
}

struct AmountRow: View {
    @Binding var price: String
    @Binding var currency: String
    var isInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                LabeledContent("Price") {
                    TextField("Price", text: $price, prompt: Text("0.00"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                NavigationLink {
                    CurrencyPicker(selection: $currency)
                } label: {
                    Text(currency)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                .fixedSize()
                .accessibilityLabel(String(localized: "Currency, \(currency)"))
            }
            if isInvalid {
                Text("Enter an amount such as 12.50")
                    .font(.footnote)
                    .foregroundStyle(Color.trackerPast)
            }
        }
    }
}

struct CurrencyPicker: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(filtered, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack {
                    Text(code).monospaced()
                    Text(Money.currencyName(code) ?? "")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if code == selection {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .foregroundStyle(.primary)
            .accessibilityAddTraits(code == selection ? .isSelected : [])
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    private var filtered: [String] {
        let codes = Money.currencies
        guard !query.isEmpty else { return codes }
        return codes.filter { Search.matches(query, $0, Money.currencyName($0) ?? "") }
    }
}

struct NotesField: View {
    @Binding var text: String

    var body: some View {
        TextField("Notes", text: $text, axis: .vertical)
            .lineLimit(3...10)
    }
}

struct FieldError: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.trackerPast)
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK") {}
        } message: { text in
            Text(text)
        }
    }
}

/// List sections in reading order: what needs action, what's fine, what has no date, what's over.
enum StatusSection: CaseIterable {
    case soon, ok, undated, past

    init(_ status: DeadlineStatus) {
        self = switch status {
        case .today, .soon: .soon
        case .ok: .ok
        case .none: .undated
        case .past: .past
        }
    }

    func title(_ kind: RecordKind) -> LocalizedStringKey {
        switch (self, kind) {
        case (.soon, .document): "Expiring soon"
        case (.soon, _): "Ending soon"
        case (.ok, .document): "Valid"
        case (.ok, _): "Covered"
        case (.undated, .document): "No expiry date"
        case (.undated, _): "No warranty date"
        case (.past, .document): "Expired"
        case (.past, _): "Ended"
        }
    }

    /// Splits status-sorted items into non-empty sections, keeping their order.
    static func group<T>(_ items: [T], status: (T) -> DeadlineStatus) -> [(section: StatusSection, items: [T])] {
        let grouped = Dictionary(grouping: items) { StatusSection(status($0)) }
        return allCases.compactMap { section in grouped[section].map { (section, $0) } }
    }
}
