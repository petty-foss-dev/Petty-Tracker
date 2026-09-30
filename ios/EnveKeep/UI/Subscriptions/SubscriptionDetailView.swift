import SwiftUI

struct SubscriptionDetailView: View {
    let subscriptionId: Int64
    @Environment(KeepStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editor: Editor?
    @State private var confirmCancel = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        if let subscription = store.subscription(subscriptionId) {
            content(subscription)
        } else {
            ContentUnavailableView("Subscription not found", systemImage: RecordKind.subscription.symbol)
        }
    }

    private func content(_ subscription: Subscription) -> some View {
        let today = store.today
        let status = subscription.isActive
            ? deadlineStatus(subscription.nextRenewal, today: today, leadDays: store.settings.subscriptionLeadDays)
            : .none
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusBadge(
                            text: subscription.isActive ? String(localized: "Active") : String(localized: "Canceled"),
                            status: status
                        )
                        Spacer()
                    }
                    if let price = subscription.price {
                        Text(Money.format(price, currency: subscription.currency))
                            .font(.largeTitle.weight(.semibold))
                    }
                    Text(Formats.cycle(count: subscription.cycleCount, unit: subscription.cycleUnit))
                        .foregroundStyle(.secondary)
                    if let price = subscription.price, subscription.cycleUnit != .months || subscription.cycleCount != 1 {
                        let monthly = Renewals.monthlyCost(price: price, count: subscription.cycleCount, unit: subscription.cycleUnit)
                        Text("≈ \(Money.format(monthly, currency: subscription.currency)) per month")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if let canceled = subscription.canceledOn {
                    LabeledContent("Canceled", value: Formats.date(canceled))
                    Button("Reactivate", systemImage: "arrow.uturn.backward") {
                        update { Renewals.reactivate($0, today: store.today) }
                    }
                } else {
                    LabeledContent("Next renewal") {
                        VStack(alignment: .trailing) {
                            Text(Formats.date(subscription.nextRenewal))
                            Text(Formats.relativeDays(today.days(until: subscription.nextRenewal)))
                                .font(.footnote)
                                .foregroundStyle(status == .ok ? Color.secondary : status.tint)
                        }
                    }
                    Button("Mark renewed", systemImage: "checkmark.circle") {
                        update { Renewals.advance($0, today: store.today) }
                    }
                    .accessibilityLabel(String(localized: "Mark \(subscription.name) renewed"))
                    Button("Mark canceled", systemImage: "xmark.circle") { confirmCancel = true }
                }
            } header: {
                Text("Renewal")
            } footer: {
                if subscription.isActive && status == .past {
                    Text("The renewal date has passed. Mark it renewed to move to the next billing date.")
                }
            }

            if !subscription.notes.isEmpty {
                Section("Notes") {
                    Text(subscription.notes).textSelection(.enabled)
                }
            }
            Section {
                Button("Delete subscription", role: .destructive) { confirmDelete = true }
            }
        }
        .keepListStyle()
        .navigationTitle(subscription.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editor = .subscription(subscriptionId) }
        }
        .editorSheet($editor)
        .confirmationDialog("Mark as canceled?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Mark canceled", role: .destructive) {
                update { subscription in
                    var canceled = subscription
                    canceled.canceledOn = store.today
                    return canceled
                }
            }
        } message: {
            Text("Enve Keep stops reminding you about renewals. This does not cancel anything with the provider.")
        }
        .confirmationDialog("Delete \(subscription.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try store.deleteSubscription(subscriptionId)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("The subscription will be removed from this device.")
        }
        .errorAlert($errorMessage)
    }

    private func update(_ transform: (Subscription) -> Subscription) {
        do {
            try store.updateSubscription(subscriptionId, transform)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
