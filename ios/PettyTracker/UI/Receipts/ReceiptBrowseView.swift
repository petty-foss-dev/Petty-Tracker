import SwiftUI

extension ReceiptFacetKind {
    var label: String {
        switch self {
        case .category: String(localized: "Categories")
        case .merchant: String(localized: "Merchants")
        case .route: String(localized: "Routes")
        case .location: String(localized: "Store locations")
        case .tag: String(localized: "Tags")
        case .field: String(localized: "Custom fields")
        }
    }

    var symbol: String {
        switch self {
        case .category: "folder"
        case .merchant: "storefront"
        case .route: "point.topleft.down.to.point.bottomright.curvepath"
        case .location: "mappin.and.ellipse"
        case .tag: "tag"
        case .field: "list.bullet.rectangle"
        }
    }
}

/// Sections to drill into, with how many receipts each holds.
struct ReceiptBrowseView: View {
    @Environment(TrackerStore.self) private var store

    var body: some View {
        let receipts = store.data.receipts
        let categories = ReceiptOrganizer.facets(.category, in: receipts)
        TrackerList {
            Section {
                NavigationLink(value: Route.receipts(ReceiptFilter())) {
                    FacetSummaryRow(
                        title: String(localized: "All receipts"),
                        symbol: Receipt.symbol,
                        count: receipts.count,
                        totals: ReceiptOrganizer.totals(receipts)
                    )
                }
            }
            if !categories.isEmpty {
                Section(ReceiptFacetKind.category.label) {
                    ForEach(categories) { summary in
                        NavigationLink(value: Route.receipts(ReceiptFilter(facets: [summary.facet]))) {
                            FacetSummaryRow(summary: summary)
                        }
                    }
                }
            }
            Section(overline: "Browse by") {
                ForEach([ReceiptFacetKind.route, .merchant, .location, .tag, .field], id: \.self) { kind in
                    let count = ReceiptFacetListView.valueCount(kind, in: receipts)
                    if count > 0 {
                        NavigationLink(value: Route.receiptFacets(kind)) {
                            LabeledContent {
                                Text(count, format: .number)
                            } label: {
                                Label(kind.label, systemImage: kind.symbol)
                            }
                        }
                    }
                }
            }
        }
        .trackerListStyle()
        .navigationTitle("Browse receipts")
    }
}

/// Every value of one kind, such as each route, most used first. Tapping one shows its receipts, or hands
/// it to `onSelect` when refining an existing list.
struct ReceiptFacetListView: View {
    let kind: ReceiptFacetKind
    var receipts: [Receipt]?
    var onSelect: ((ReceiptFacet) -> Void)?
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static func valueCount(_ kind: ReceiptFacetKind, in receipts: [Receipt]) -> Int {
        let summaries = ReceiptOrganizer.facets(kind, in: receipts)
        return kind == .field ? summaries.filter(\.isFieldName).count : summaries.count
    }

    var body: some View {
        let all = ReceiptOrganizer.facets(kind, in: receipts ?? store.data.receipts)
        let summaries = all.filter { Search.matches(query, $0.facet.title) }
        TrackerList {
            if kind == .field {
                // A field name stays visible while any of its values match the search.
                let names = all.filter { name in
                    name.isFieldName && (summaries.contains { $0.facet == name.facet } || summaries.contains { $0.isValue(of: name.facet) })
                }
                ForEach(names) { name in
                    Section(name.facet.title) {
                        row(name, title: String(localized: "Any value"))
                        ForEach(summaries.filter { $0.isValue(of: name.facet) }) { row($0, title: $0.fieldValue) }
                    }
                }
            } else {
                ForEach(summaries) { row($0, title: $0.facet.title) }
            }
        }
        .trackerListStyle()
        .overlay {
            if summaries.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: kind.symbol, description: Text(emptyDescription))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search \(kind.label.lowercased())"))
    }

    @ViewBuilder
    private func row(_ summary: ReceiptFacetSummary, title: String) -> some View {
        if let onSelect {
            Button {
                onSelect(summary.facet)
                dismiss()
            } label: {
                FacetSummaryRow(summary: summary, title: title)
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink(value: Route.receipts(ReceiptFilter(facets: [summary.facet]))) {
                FacetSummaryRow(summary: summary, title: title)
            }
        }
    }

    private var emptyTitle: String {
        kind == .route ? String(localized: "No routes yet") : String(localized: "Nothing to show")
    }

    private var emptyDescription: String {
        switch kind {
        case .route: String(localized: "Add where a trip started and ended when editing a receipt.")
        case .field: String(localized: "Add custom fields when editing a receipt.")
        default: String(localized: "None of these receipts have this detail.")
        }
    }
}

private extension ReceiptFacetSummary {
    var isFieldName: Bool {
        if case .field(_, nil) = facet { true } else { false }
    }

    var fieldValue: String {
        if case .field(_, let value?) = facet { value } else { facet.title }
    }

    func isValue(of nameFacet: ReceiptFacet) -> Bool {
        guard case .field(let name, _?) = facet, case .field(let other, nil) = nameFacet else { return false }
        return Search.key(name) == Search.key(other)
    }
}

struct FacetSummaryRow: View {
    let title: String
    var symbol: String?
    let count: Int
    let totals: [(currency: String, amount: Decimal)]

    init(title: String, symbol: String? = nil, count: Int, totals: [(currency: String, amount: Decimal)]) {
        self.title = title
        self.symbol = symbol
        self.count = count
        self.totals = totals
    }

    init(summary: ReceiptFacetSummary, title: String? = nil) {
        self.init(title: title ?? summary.facet.title, count: summary.count, totals: summary.totals)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(Color.trackerAccent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(Formats.count(count, "receipt", "receipts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            TotalsText(totals: totals)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Per-currency sums, one line each, since amounts in different currencies can't be added.
struct TotalsText: View {
    let totals: [(currency: String, amount: Decimal)]

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(totals, id: \.currency) { total in
                Text(Money.format(total.amount, currency: total.currency))
            }
        }
        .monospacedDigit()
    }
}

/// The receipts matching a filter, which can be narrowed further, sorted and exported.
struct ReceiptResultsView: View {
    @Environment(TrackerStore.self) private var store
    @State private var filter: ReceiptFilter
    @State private var sort = ReceiptSort.newest
    @State private var grouping = ReceiptGrouping.none
    @State private var editingFilter = false
    @State private var exported: OpenedAttachment?
    @State private var errorMessage: String?

    init(filter: ReceiptFilter) {
        _filter = State(initialValue: filter)
    }

    var body: some View {
        let matches = store.data.receipts.filter(filter.includes)
        let groups = ReceiptOrganizer.groups(matches, sort: sort, grouping: grouping)
        let pending = ReceiptReview.pending(store.data.receipts, pages: store.receiptPages)
        TrackerList {
            Section {
                LabeledContent {
                    TotalsText(totals: ReceiptOrganizer.totals(matches))
                } label: {
                    Text(Formats.count(matches.count, "receipt", "receipts")).font(.headline)
                }
                ForEach(filter.facets, id: \.self) { facet in
                    HStack {
                        Label(facet.title, systemImage: facet.kind.symbol)
                        Spacer()
                        Button {
                            filter.facets.removeAll { $0 == facet }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Remove \(facet.title)"))
                    }
                }
                if filter.refinementCount > 0 {
                    Button {
                        editingFilter = true
                    } label: {
                        Label(ReceiptFilterSheet.summary(filter), systemImage: "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.receipts) { receipt in
                        NavigationLink(value: Route.receipt(receipt.id)) {
                            ReceiptRow(receipt: receipt, needsReview: pending[receipt.id] != nil)
                        }
                    }
                } header: {
                    if grouping != .none {
                        GroupHeader(title: group.displayTitle(grouping), totals: group.totals)
                    }
                }
            }
        }
        .trackerListStyle()
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different search or filter."))
            }
        }
        .navigationTitle(filter.facets.first?.title ?? String(localized: "All receipts"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter.query, prompt: "Search these receipts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editingFilter = true
                } label: {
                    Label("Filter", systemImage: filter.refinementCount > 0
                        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                Menu {
                    ReceiptOrganizePickers(sort: $sort, grouping: $grouping)
                    Button("Export \(matches.count) as CSV", systemImage: "tablecells") { exportCSV(groups.flatMap(\.receipts)) }
                        .disabled(matches.isEmpty)
                } label: {
                    Label("Sort and export", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        }
        .sheet(isPresented: $editingFilter) {
            ReceiptFilterSheet(filter: $filter, receipts: store.data.receipts)
        }
        .attachmentPresenter($exported)
        .errorAlert($errorMessage)
    }

    private func exportCSV(_ receipts: [Receipt]) {
        do {
            exported = OpenedAttachment(url: try ReceiptCSV.write(receipts, today: store.today), share: true)
        } catch {
            errorMessage = String(localized: "The CSV file could not be created. \(error.localizedDescription)")
        }
    }
}

/// Edits a copy of the filter and applies it on Done, so half-typed amounts never narrow the list.
struct ReceiptFilterSheet: View {
    @Binding var filter: ReceiptFilter
    let receipts: [Receipt]
    @State private var draft: ReceiptFilter
    @State private var minTotal: String
    @State private var maxTotal: String
    @State private var showErrors = false
    @Environment(\.dismiss) private var dismiss

    init(filter: Binding<ReceiptFilter>, receipts: [Receipt]) {
        _filter = filter
        self.receipts = receipts
        _draft = State(initialValue: filter.wrappedValue)
        _minTotal = State(initialValue: filter.wrappedValue.minTotal.map(Money.formatForInput) ?? "")
        _maxTotal = State(initialValue: filter.wrappedValue.maxTotal.map(Money.formatForInput) ?? "")
    }

    static func summary(_ filter: ReceiptFilter) -> String {
        var parts: [String] = []
        if !filter.origin.isEmpty || !filter.destination.isEmpty {
            parts.append(Receipt.routeLabel(origin: filter.origin, destination: filter.destination))
        }
        switch (filter.fromDate, filter.toDate) {
        case let (from?, to?): parts.append("\(Formats.date(from)) – \(Formats.date(to))")
        case let (from?, nil): parts.append(String(localized: "From \(Formats.date(from))"))
        case let (nil, to?): parts.append(String(localized: "Until \(Formats.date(to))"))
        case (nil, nil): break
        }
        let money = { (amount: Decimal) in filter.currency.map { Money.format(amount, currency: $0) } ?? Money.formatForInput(amount) }
        switch (filter.minTotal, filter.maxTotal) {
        case let (min?, max?): parts.append("\(money(min)) – \(money(max))")
        case let (min?, nil): parts.append(String(localized: "At least \(money(min))"))
        case let (nil, max?): parts.append(String(localized: "At most \(money(max))"))
        case (nil, nil): break
        }
        if let currency = filter.currency, filter.minTotal == nil, filter.maxTotal == nil { parts.append(currency) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let matches = receipts.filter { draft.includes($0) }
        let currencies = Set(receipts.map(\.currency)).sorted()
        NavigationStack {
            TrackerForm {
                Section {
                    ForEach(draft.facets, id: \.self) { facet in
                        Label(facet.title, systemImage: facet.kind.symbol)
                    }
                    .onDelete { draft.facets.remove(atOffsets: $0) }
                    ForEach(ReceiptFacetKind.allCases, id: \.self) { kind in
                        if ReceiptFacetListView.valueCount(kind, in: matches) > 0 {
                            NavigationLink {
                                ReceiptFacetListView(kind: kind, receipts: matches) { draft.facets.append($0) }
                            } label: {
                                Label(kind.label, systemImage: kind.symbol)
                            }
                        }
                    }
                } header: {
                    Overline("Narrow by")
                } footer: {
                    Text("Choices come from the \(Formats.count(matches.count, "receipt", "receipts")) that match so far.")
                }
                Section {
                    TextField("From", text: $draft.origin)
                        .textInputAutocapitalization(.words)
                    TextField("To", text: $draft.destination)
                        .textInputAutocapitalization(.words)
                } header: {
                    Overline("Trip")
                } footer: {
                    Text("Matches part of a place name, so “San Fran” finds San Francisco.")
                }
                Section {
                    OptionalDateRow(title: String(localized: "From"), selection: $draft.fromDate)
                    OptionalDateRow(title: String(localized: "Until"), selection: $draft.toDate)
                } header: {
                    Overline("Date")
                } footer: {
                    Text("Receipts without a purchase date use the day they were added.")
                }
                Section {
                    LabeledContent("At least") {
                        TextField("Any", text: $minTotal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("At most") {
                        TextField("Any", text: $maxTotal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if currencies.count > 1 {
                        Picker("Currency", selection: $draft.currency) {
                            Text("Any").tag(String?.none)
                            ForEach(currencies, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    }
                    if showErrors && !amountsAreValid {
                        FieldError(text: String(localized: "Enter amounts such as 25 or 49.99"))
                    }
                } header: {
                    Overline("Total")
                } footer: {
                    Text("Totals are compared in each receipt's own currency.")
                }
                Section {
                    Button("Clear all filters", role: .destructive) {
                        draft = ReceiptFilter(query: draft.query)
                        minTotal = ""
                        maxTotal = ""
                    }
                }
            }
            .navigationTitle("Filter receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: apply)
                }
            }
        }
    }

    private var amountsAreValid: Bool {
        [minTotal, maxTotal].allSatisfy(ReceiptForm.isValidQuantity)
    }

    private func apply() {
        showErrors = true
        guard amountsAreValid else { return }
        var applied = draft
        applied.origin = draft.origin.trimmingCharacters(in: .whitespaces)
        applied.destination = draft.destination.trimmingCharacters(in: .whitespaces)
        applied.minTotal = Money.parse(minTotal)
        applied.maxTotal = Money.parse(maxTotal)
        if let from = applied.fromDate, let to = applied.toDate, from > to {
            (applied.fromDate, applied.toDate) = (to, from)
        }
        if let min = applied.minTotal, let max = applied.maxTotal, min > max {
            (applied.minTotal, applied.maxTotal) = (max, min)
        }
        filter = applied
        dismiss()
    }
}
