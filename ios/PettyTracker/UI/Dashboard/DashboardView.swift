import SwiftUI
import UserNotifications

struct DashboardSummary {
    // Ended warranties drop off the dashboard after a month; they stay visible in the Warranties list.
    static let recentWarrantyDays = 30

    struct Entry: Hashable {
        let deadline: Deadline
        let status: DeadlineStatus
    }

    enum Band: CaseIterable {
        case week, month, later

        init(days: Int) {
            self = days <= 7 ? .week : days <= 30 ? .month : .later
        }

        var title: LocalizedStringKey {
            switch self {
            case .week: "Next 7 days"
            case .month: "Next 30 days"
            case .later: "Later"
            }
        }
    }

    let pastDue: [Entry]
    let upcoming: [(band: Band, entries: [Entry])]
    let upcomingCount: Int
    let isEmpty: Bool

    init(_ data: TrackerData, today: Day) {
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
        let soon = entries.filter { $0.status.isUpcoming }
        let banded = Dictionary(grouping: soon) { Band(days: $0.deadline.days(from: today)) }
        upcoming = Band.allCases.compactMap { band in banded[band].map { (band, $0) } }
        upcomingCount = soon.count
        isEmpty = data.products.isEmpty && data.subscriptions.isEmpty && data.documents.isEmpty && data.receipts.isEmpty
    }
}

struct DashboardView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.reminders) private var reminders
    @Environment(QuickCapture.self) private var quickCapture
    @State private var query = ""
    @State private var editor: Editor?
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var errorMessage: String?

    var body: some View {
        let summary = DashboardSummary(store.data, today: store.today)
        TrackerList {
            if !query.isEmpty {
                SearchResultsSection(query: query)
            } else if summary.isEmpty {
                WelcomeSection(onAdd: { editor = Editor(new: $0) }, onReceipts: quickCapture.requestScan)
            } else {
                SummaryTiles(summary: summary)
                QuickAddSection(onAdd: { editor = Editor(new: $0) }, onScanReceipt: quickCapture.requestScan)
                if showReminderPrompt {
                    ReminderPromptSection(onAllow: allowReminders, onDismiss: dismissReminderPrompt)
                }
                if !summary.pastDue.isEmpty {
                    Section(overline: "Needs attention") {
                        ForEach(summary.pastDue, id: \.self) { entry in deadlineLink(entry) }
                    }
                }
                ForEach(summary.upcoming, id: \.band) { group in
                    Section(overline: group.band.title) {
                        ForEach(group.entries, id: \.self) { entry in deadlineLink(entry) }
                    }
                }
                if summary.pastDue.isEmpty && summary.upcoming.isEmpty {
                    Section {
                        Label("Nothing due within your reminder windows.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                RecentReceiptsSection()
            }
        }
        .trackerListStyle()
        .navigationTitle("petty: Tracker")
        .searchable(text: $query, prompt: "Search everything")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                AddRecordMenu(onSelect: { editor = Editor(new: $0) }, onScanReceipt: quickCapture.requestScan)
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
                    .tint(Color.trackerAccent)
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
                    .foregroundStyle(Color.trackerAccent)
                    .accessibilityHidden(true)
                Text("Keep it all in one place")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Track warranties, subscriptions and document expiry dates. Everything stays on this iPhone.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        Section(overline: "What do you want to keep?") {
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
                    .background(Color.trackerPrimaryContainer, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.trackerOnPrimaryContainer)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(hint).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(Color.trackerAccent)
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
                Text("Allow notifications so petty: Tracker can tell you before warranties end, subscriptions renew and documents expire.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Allow notifications", action: onAllow)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color.trackerOnAccent)
                    Button("Not now", action: onDismiss)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.trackerPrimaryContainer)
    }
}

private struct SummaryTiles: View {
    let summary: DashboardSummary
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let monthly = Renewals.monthlyTotals(store.data.subscriptions)
        Section {
            HStack(spacing: 10) {
                tile(
                    value: "\(summary.pastDue.count)",
                    label: "Overdue",
                    tint: summary.pastDue.isEmpty ? .primary : .trackerPast
                )
                tile(
                    value: "\(summary.upcomingCount)",
                    label: "Due soon",
                    tint: summary.upcomingCount == 0 ? .primary : .trackerSoon
                )
                Button {
                    router.tab = .subscriptions
                } label: {
                    tile(
                        value: monthly.first.map { Money.format($0.amount, currency: $0.currency) } ?? "–",
                        label: monthly.count > 1 ? "Per month, \(monthly[0].currency)" : "Per month",
                        tint: .primary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows subscriptions")
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func tile(value: String, label: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.trackerElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.trackerHairline))
        .accessibilityElement(children: .combine)
    }
}

private struct QuickAddSection: View {
    let onAdd: (RecordKind) -> Void
    let onScanReceipt: () -> Void

    var body: some View {
        Section {
            HStack(spacing: 10) {
                button("Product", symbol: RecordKind.warranty.symbol) { onAdd(.warranty) }
                button("Subscription", symbol: RecordKind.subscription.symbol) { onAdd(.subscription) }
                button("Document", symbol: RecordKind.document.symbol) { onAdd(.document) }
                button("Receipt", symbol: Receipt.symbol, action: onScanReceipt)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func button(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(height: 24)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.trackerOnPrimaryContainer)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.trackerPrimaryContainer, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add \(Text(title))"))
    }
}

private struct RecentReceiptsSection: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let receipts = store.data.receipts
        if !receipts.isEmpty {
            Section {
                ForEach(receipts.sorted { ($0.sortDate, $0.id) > ($1.sortDate, $1.id) }.prefix(3)) { receipt in
                    NavigationLink(value: Route.receipt(receipt.id)) {
                        ReceiptRow(receipt: receipt)
                    }
                }
                Button {
                    router.tab = .receipts
                } label: {
                    HStack {
                        Text("All \(Formats.count(receipts.count, "receipt", "receipts"))")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Overline("Recent receipts")
            }
        }
    }
}
