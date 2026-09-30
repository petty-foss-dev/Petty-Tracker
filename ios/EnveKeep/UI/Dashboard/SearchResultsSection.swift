import SwiftUI

/// Results across every record type for the dashboard search field.
struct SearchResultsSection: View {
    let query: String
    @Environment(KeepStore.self) private var store

    var body: some View {
        let data = store.data
        let products = data.products.filter { $0.matches(query) }
        let subscriptions = data.subscriptions.filter { $0.matches(query) }
        let documents = data.documents.filter { $0.matches(query) }
        let receipts = data.receipts.filter { $0.matches(query) }

        if products.isEmpty && subscriptions.isEmpty && documents.isEmpty && receipts.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        }
        if !products.isEmpty {
            Section("Warranties") {
                ForEach(products) { product in
                    NavigationLink(value: Route.product(product.id)) {
                        ProductRow(
                            product: product,
                            status: deadlineStatus(product.warrantyExpires, today: store.today, leadDays: data.settings.warrantyLeadDays),
                            today: store.today
                        )
                    }
                }
            }
        }
        if !subscriptions.isEmpty {
            Section("Subscriptions") {
                ForEach(subscriptions) { subscription in
                    NavigationLink(value: Route.subscription(subscription.id)) {
                        SubscriptionRow(subscription: subscription, leadDays: data.settings.subscriptionLeadDays, today: store.today)
                    }
                }
            }
        }
        if !documents.isEmpty {
            Section("Documents") {
                ForEach(documents) { document in
                    NavigationLink(value: Route.document(document.id)) {
                        DocumentRow(
                            document: document,
                            status: deadlineStatus(document.expiresOn, today: store.today, leadDays: data.settings.documentLeadDays),
                            today: store.today
                        )
                    }
                }
            }
        }
        if !receipts.isEmpty {
            Section("Receipts") {
                ForEach(receipts) { receipt in
                    NavigationLink(value: Route.receipt(receipt.id)) {
                        ReceiptRow(receipt: receipt)
                    }
                }
            }
        }
    }
}
