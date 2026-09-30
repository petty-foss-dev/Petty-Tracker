import SwiftUI

enum ProductFilter: CaseIterable {
    case all, covered, ending, expired

    var label: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .covered: "Covered"
        case .ending: "Ending soon"
        case .expired: "Expired"
        }
    }

    func includes(_ status: DeadlineStatus) -> Bool {
        switch self {
        case .all: true
        case .covered: status == .ok || status.isUpcoming
        case .ending: status.isUpcoming
        case .expired: status == .past
        }
    }
}

struct ProductListView: View {
    @Environment(KeepStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var filter = ProductFilter.all
    @State private var editor: Editor?

    var body: some View {
        let today = store.today
        let lead = store.settings.warrantyLeadDays
        let items = store.data.products
            .filter { $0.matches(query) }
            .map { (product: $0, status: deadlineStatus($0.warrantyExpires, today: today, leadDays: lead)) }
            .filter { filter.includes($0.status) }
            .sorted {
                ($0.status.sortRank, deadlineSortKey($0.product.warrantyExpires, $0.status))
                    < ($1.status.sortRank, deadlineSortKey($1.product.warrantyExpires, $1.status))
            }

        List {
            if !store.data.products.isEmpty {
                FilterPicker(selection: $filter, options: ProductFilter.allCases, label: \.label)
                ForEach(items, id: \.product.id) { item in
                    NavigationLink(value: Route.product(item.product.id)) {
                        ProductRow(product: item.product, status: item.status, today: today)
                    }
                }
            }
        }
        .keepListStyle()
        .overlay {
            if store.data.products.isEmpty {
                ContentUnavailableView {
                    Label("No products yet", systemImage: RecordKind.warranty.symbol)
                } description: {
                    Text("Add purchases to keep receipts, serial numbers and warranty dates together for when you need to make a claim.")
                } actions: {
                    Button("Add product") { editor = .product(nil) }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color.keepOnAccent)
                }
            } else if items.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different search or filter."))
            }
        }
        .navigationTitle("Warranties")
        .searchable(text: $query, prompt: "Search products")
        .toolbar {
            Button("Add product", systemImage: "plus") { editor = .product(nil) }
        }
        .editorSheet($editor) { router.warrantiesPath.append($0) }
    }
}

struct ProductRow: View {
    let product: Product
    let status: DeadlineStatus
    let today: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(product.name).font(.body.weight(.medium))
            let subtitle = [product.brand, product.model].filter { !$0.isEmpty }.joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if let expires = product.warrantyExpires {
                Text(Formats.deadline(.warranty, days: today.days(until: expires)))
                    .font(.subheadline)
                    .foregroundStyle(status == .ok ? Color.secondary : status.tint)
            } else {
                Text("No warranty date").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A segmented filter shown as the first list row.
struct FilterPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: KeyPath<Option, LocalizedStringKey>

    var body: some View {
        Picker("Filter", selection: $selection) {
            ForEach(options, id: \.self) { Text($0[keyPath: label]).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}
