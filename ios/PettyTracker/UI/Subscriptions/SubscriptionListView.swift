import SwiftUI

enum SubscriptionFilter: CaseIterable {
    case active, canceled, all

    var label: LocalizedStringKey {
        switch self {
        case .active: "Active"
        case .canceled: "Canceled"
        case .all: "All"
        }
    }

    func includes(_ subscription: Subscription) -> Bool {
        switch self {
        case .active: subscription.isActive
        case .canceled: !subscription.isActive
        case .all: true
        }
    }
}

struct SubscriptionListView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var filter = SubscriptionFilter.active
    @State private var editor: Editor?
    @State private var errorMessage: String?

    var body: some View {
        let today = store.today
        let all = store.data.subscriptions
        let items = all
            .filter { $0.matches(query) && filter.includes($0) }
            .sorted { ($0.isActive ? 0 : 1, $0.nextRenewal.epochDay) < ($1.isActive ? 0 : 1, $1.nextRenewal.epochDay) }
        let totals = Renewals.monthlyTotals(all)

        TrackerList {
            if !all.isEmpty {
                FilterPicker(selection: $filter, options: SubscriptionFilter.allCases, label: \.label)
                if !totals.isEmpty && query.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Monthly cost").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(totals, id: \.currency) { total in
                                Text("≈ \(Money.format(total.amount, currency: total.currency))")
                                    .font(.title2.weight(.semibold))
                                    .fontDesign(.serif)
                            }
                            Text(Formats.count(all.filter(\.isActive).count, "active subscription", "active subscriptions"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    ForEach(items) { subscription in
                        NavigationLink(value: Route.subscription(subscription.id)) {
                            SubscriptionRow(subscription: subscription, leadDays: store.settings.subscriptionLeadDays, today: today)
                        }
                        .swipeActions {
                            if subscription.isActive {
                                Button("Mark renewed", systemImage: "checkmark.circle") { markRenewed(subscription.id) }
                                    .tint(Color.trackerAccent)
                            }
                        }
                    }
                }
            }
        }
        .trackerListStyle()
        .overlay {
            if all.isEmpty {
                ContentUnavailableView {
                    Label("No subscriptions yet", systemImage: RecordKind.subscription.symbol)
                } description: {
                    Text("Add the services you pay for to see what renews next and roughly what they cost each month.")
                } actions: {
                    Button("Add subscription") { editor = .subscription(nil) }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color.trackerOnAccent)
                }
            } else if items.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different search or filter."))
            }
        }
        .navigationTitle("Subscriptions")
        .searchable(text: $query, prompt: "Search subscriptions")
        .toolbar {
            Button("Add subscription", systemImage: "plus") { editor = .subscription(nil) }
        }
        .editorSheet($editor) { router.subscriptionsPath.append($0) }
        .errorAlert($errorMessage)
    }

    private func markRenewed(_ id: Int64) {
        do {
            try store.updateSubscription(id) { Renewals.advance($0, today: store.today) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SubscriptionRow: View {
    let subscription: Subscription
    let leadDays: Int
    let today: Day

    var body: some View {
        let status = subscription.isActive
            ? deadlineStatus(subscription.nextRenewal, today: today, leadDays: leadDays)
            : .none
        HStack(spacing: 12) {
            RecordIcon(symbol: RecordKind.subscription.symbol, tint: status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name).font(.body.weight(.semibold)).fontDesign(.serif)
                if let canceled = subscription.canceledOn {
                    Text("Canceled \(Formats.date(canceled))").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(Formats.deadline(.subscription, date: subscription.nextRenewal, today: today))
                        .font(.subheadline)
                        .foregroundStyle(status == .ok ? Color.secondary : status.tint)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let price = subscription.price {
                    Text(Money.format(price, currency: subscription.currency)).font(.body.monospacedDigit())
                }
                Text(Formats.cycle(count: subscription.cycleCount, unit: subscription.cycleUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(subscription.isActive ? 1 : 0.7)
        .accessibilityElement(children: .combine)
    }
}
