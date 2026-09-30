import SwiftUI
import UserNotifications

struct DashboardSummary {
    // Ended warranties drop off the dashboard after a month; they stay visible in the Warranties list.
    static let recentWarrantyDays = 30

    struct Entry: Hashable {
        let deadline: Deadline
        let status: DeadlineStatus
    }

    struct Category {
        let count: Int
        let next: Deadline?
    }

    let pastDue: [Entry]
    let upcoming: [Entry]
    let warranties: Category
    let subscriptions: Category
    let documents: Category
    let isEmpty: Bool

    init(_ data: KeepData, today: Day) {
        let deadlines = data.products.compactMap(\.deadline)
            + data.subscriptions.compactMap(\.deadline)
            + data.documents.compactMap(\.deadline)
        let entries = deadlines
            .map { Entry(deadline: $0, status: deadlineStatus($0.date, today: today, leadDays: data.settings.leadDays($0.kind))) }
            .sorted { $0.deadline.date < $1.deadline.date }
        pastDue = entries.filter {
            $0.status == .past
                && ($0.deadline.kind != .warranty || $0.deadline.days(from: today) >= -Self.recentWarrantyDays)
        }.reversed()
        upcoming = entries.filter { $0.status.isUpcoming }

        func category(_ kind: RecordKind, count: Int) -> Category {
            Category(count: count, next: deadlines.filter { $0.kind == kind && $0.date >= today }.min { $0.date < $1.date })
        }
        warranties = category(.warranty, count: data.products.count)
        subscriptions = category(.subscription, count: data.subscriptions.filter(\.isActive).count)
        documents = category(.document, count: data.documents.count)
        isEmpty = data.products.isEmpty && data.subscriptions.isEmpty && data.documents.isEmpty && data.receipts.isEmpty
    }
}

struct DashboardView: View {
    @Environment(KeepStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.reminders) private var reminders
    @State private var query = ""
    @State private var editor: Editor?
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var errorMessage: String?

    var body: some View {
        let summary = DashboardSummary(store.data, today: store.today)
        List {
            if !query.isEmpty {
                SearchResultsSection(query: query)
            } else if summary.isEmpty {
                WelcomeSection(onAdd: { editor = Editor(new: $0) }, onReceipts: { router.tab = .receipts })
            } else {
                if showReminderPrompt {
                    ReminderPromptSection(onAllow: allowReminders, onDismiss: dismissReminderPrompt)
                }
                if !summary.pastDue.isEmpty {
                    Section("Needs attention") {
                        ForEach(summary.pastDue, id: \.self) { entry in deadlineLink(entry) }
                    }
                }
                Section("Coming up") {
                    if summary.upcoming.isEmpty {
                        Text("Nothing due within your reminder windows.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(summary.upcoming, id: \.self) { entry in deadlineLink(entry) }
                }
                OverviewSection(summary: summary)
            }
        }
        .keepListStyle()
        .navigationTitle("Enve Keep")
        .searchable(text: $query, prompt: "Search everything")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                AddRecordMenu { editor = Editor(new: $0) }
            }
        }
        .editorSheet($editor) { router.homePath.append($0) }
        .errorAlert($errorMessage)
        .task { notificationStatus = await reminders?.authorizationStatus() }
    }

    private var showReminderPrompt: Bool {
        store.settings.remindersEnabled && !store.settings.reminderPromptDismissed && notificationStatus == .notDetermined
    }

    @ViewBuilder
    private func deadlineLink(_ entry: DashboardSummary.Entry) -> some View {
        NavigationLink(value: Route(entry.deadline.kind, id: entry.deadline.id)) {
            DeadlineRow(deadline: entry.deadline, status: entry.status, today: store.today)
        }
        .swipeActions {
            if entry.deadline.kind == .subscription {
                Button("Mark renewed", systemImage: "checkmark.circle") { markRenewed(entry.deadline.id) }
                    .tint(.accentColor)
            }
        }
    }

    private func markRenewed(_ id: Int64) {
        do {
            try store.updateSubscription(id) { Renewals.advance($0, today: store.today) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func allowReminders() {
        Task {
            _ = await reminders?.requestAuthorization()
            notificationStatus = await reminders?.authorizationStatus()
            dismissReminderPrompt()
            await reminders?.reschedule(store.data)
        }
    }

    private func dismissReminderPrompt() {
        do {
            try store.updateSettings { $0.reminderPromptDismissed = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WelcomeSection: View {
    let onAdd: (RecordKind) -> Void
    let onReceipts: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Keep it all in one place")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Track warranties, subscriptions and document expiry dates. Everything stays on this iPhone.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        Section("What do you want to keep?") {
            addButton(.warranty, title: "Product and warranty", hint: "Receipt, serial number and warranty")
            addButton(.subscription, title: "Subscription", hint: "Price, billing cycle and next renewal")
            addButton(.document, title: "Document", hint: "Passport, licence, insurance or ID")
            addButton(symbol: Receipt.symbol, title: "Receipt", hint: "Scan and organize receipts and expenses", action: onReceipts)
        }
    }

    private func addButton(_ kind: RecordKind, title: LocalizedStringKey, hint: LocalizedStringKey) -> some View {
        addButton(symbol: kind.symbol, title: title, hint: hint) { onAdd(kind) }
    }

    private func addButton(symbol: String, title: LocalizedStringKey, hint: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 36, height: 36)
                    .background(Color.keepPrimaryContainer, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.keepOnPrimaryContainer)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(hint).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderPromptSection: View {
    let onAllow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Get reminded in time", systemImage: "bell.badge")
                    .font(.headline)
                Text("Allow notifications so Enve Keep can tell you before warranties end, subscriptions renew and documents expire.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Allow notifications", action: onAllow)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color.keepOnAccent)
                    Button("Not now", action: onDismiss)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.keepPrimaryContainer.opacity(0.5))
    }
}

private struct OverviewSection: View {
    let summary: DashboardSummary
    @Environment(KeepStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Section("Overview") {
            row(.warranty, tab: .warranties, category: summary.warranties,
                count: Formats.count(summary.warranties.count, "product", "products"))
            row(.subscription, tab: .subscriptions, category: summary.subscriptions,
                count: Formats.count(summary.subscriptions.count, "active subscription", "active subscriptions"))
            row(.document, tab: .documents, category: summary.documents,
                count: Formats.count(summary.documents.count, "document", "documents"))
            let latest = store.data.receipts.max { ($0.sortDate, $0.id) < ($1.sortDate, $1.id) }
            row(symbol: Receipt.symbol, tab: .receipts,
                count: Formats.count(store.data.receipts.count, "receipt", "receipts"),
                detail: latest.map { String(localized: "Latest: \($0.merchant)") })
            let totals = Renewals.monthlyTotals(store.data.subscriptions)
            if !totals.isEmpty {
                LabeledContent("Monthly cost") {
                    VStack(alignment: .trailing) {
                        ForEach(totals, id: \.currency) { total in
                            Text("≈ \(Money.format(total.amount, currency: total.currency))")
                        }
                    }
                }
            }
        }
    }

    private func row(_ kind: RecordKind, tab: AppTab, category: DashboardSummary.Category, count: String) -> some View {
        row(symbol: kind.symbol, tab: tab, count: count, detail: category.next.map { next in
            String(localized: "Next: \(next.title), \(Formats.relativeDays(next.days(from: store.today)))")
        })
    }

    private func row(symbol: String, tab: AppTab, count: String, detail: String?) -> some View {
        Button {
            router.tab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count).foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
