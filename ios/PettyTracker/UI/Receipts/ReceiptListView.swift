import SwiftUI

extension ReceiptSort {
    var label: LocalizedStringKey {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .highestTotal: "Highest total"
        case .lowestTotal: "Lowest total"
        case .merchant: "Merchant"
        case .location: "Store location"
        case .route: "Trip route"
        }
    }
}

extension ReceiptGrouping {
    var label: LocalizedStringKey {
        switch self {
        case .month: "Month"
        case .category: "Category"
        case .merchant: "Merchant"
        case .none: "None"
        }
    }
}

extension ReceiptGroup {
    func displayTitle(_ grouping: ReceiptGrouping) -> String {
        if !title.isEmpty { return title }
        return grouping == .category ? String(localized: "No category") : String(localized: "Other")
    }
}

struct ReceiptOrganizePickers: View {
    @Binding var sort: ReceiptSort
    @Binding var grouping: ReceiptGrouping

    var body: some View {
        Picker(selection: $sort) {
            ForEach(ReceiptSort.allCases, id: \.self) { Text($0.label).tag($0) }
        } label: {
            Label("Sort by", systemImage: "arrow.up.arrow.down")
        }
        .pickerStyle(.menu)
        Picker(selection: $grouping) {
            ForEach(ReceiptGrouping.allCases, id: \.self) { Text($0.label).tag($0) }
        } label: {
            Label("Group by", systemImage: "square.stack")
        }
        .pickerStyle(.menu)
    }
}

struct ReceiptListView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(QuickCapture.self) private var quickCapture
    @State private var query = ""
    @State private var sort = ReceiptSort.newest
    @State private var grouping = ReceiptGrouping.month
    @State private var category: String?
    @State private var tag: String?
    @State private var needsReviewOnly = false
    @State private var exported: OpenedAttachment?
    @State private var captureSource: CaptureSource?
    @State private var editor: ReceiptEditorRequest?
    @State private var showCaptureChoices = false
    @State private var pendingDelete: Receipt?
    @State private var errorMessage: String?

    var body: some View {
        let receipts = store.data.receipts
        let pending = ReceiptReview.pending(receipts, pages: store.receiptPages)
        let filter = ReceiptFilter(query: query, facets: [category.map(ReceiptFacet.category), tag.map(ReceiptFacet.tag)].compactMap { $0 })
        let filtered = receipts.filter { filter.includes($0) && (!needsReviewOnly || pending[$0.id] != nil) }
        let groups = ReceiptOrganizer.groups(filtered, sort: sort, grouping: grouping)

        List {
            if let item = quickCapture.sharedItems.first {
                Button {
                    openShared(item)
                } label: {
                    let count = quickCapture.sharedItems.count
                    Label(count == 1 ? "1 shared file to review" : "\(count) shared files to review", systemImage: "tray.and.arrow.down.fill")
                }
                .accessibilityHint("Opens the next shared file as a new receipt")
            }
            if !receipts.isEmpty && query.isEmpty && !hasFilters {
                NavigationLink(value: Route.receiptBrowse) {
                    Label("Browse by category, route, merchant and more", systemImage: "square.grid.2x2")
                }
            }
            if hasFilters {
                activeFilters
            } else if !pending.isEmpty {
                Button {
                    needsReviewOnly = true
                } label: {
                    Label {
                        Text(pending.count == 1 ? "1 receipt needs review" : "\(pending.count) receipts need review")
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.trackerSoon)
                    }
                }
                .accessibilityHint("Shows only receipts that need review")
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.receipts) { receipt in
                        NavigationLink(value: Route.receipt(receipt.id)) {
                            ReceiptRow(receipt: receipt, needsReview: pending[receipt.id] != nil)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash") { pendingDelete = receipt }
                                .tint(Color.trackerPast)
                            if pending[receipt.id] != nil {
                                Button("Reviewed", systemImage: "checkmark") { markReviewed(receipt) }
                                    .tint(.accentColor)
                            }
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
            if receipts.isEmpty && quickCapture.sharedItems.isEmpty {
                ContentUnavailableView {
                    Label("No receipts yet", systemImage: Receipt.symbol)
                } description: {
                    Text("Scan paper receipts or import photos. Merchant, date, items and totals are read on this iPhone for you to check and edit.")
                } actions: {
                    AddPagesMenu(source: $captureSource) {
                        Text("Add receipt")
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.trackerOnAccent)
                    Button("Enter manually") { editor = ReceiptEditorRequest() }
                }
            } else if needsReviewOnly && pending.isEmpty {
                ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("No receipts need review."))
            } else if filtered.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different search or filter."))
            }
        }
        .navigationTitle("Receipts")
        .searchable(text: $query, prompt: "Search receipts and scanned text")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !receipts.isEmpty { organizeMenu(receipts, pendingCount: pending.count, filtered: groups.flatMap(\.receipts)) }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if DocumentScanner.isSupported {
                        Button("Scan receipt", systemImage: "doc.viewfinder") { captureSource = .scanner }
                    }
                    Button("Photo Library", systemImage: "photo.on.rectangle") { captureSource = .photos }
                    Button("Choose Files", systemImage: "folder") { captureSource = .files }
                    Button("Enter manually", systemImage: "square.and.pencil") { editor = ReceiptEditorRequest() }
                } label: {
                    Label("Add receipt", systemImage: "plus")
                }
            }
        }
        .receiptCapture($captureSource, errorMessage: $errorMessage) { capture in
            editor = ReceiptEditorRequest(capture: capture)
        }
        .confirmationDialog("Add receipt", isPresented: $showCaptureChoices, titleVisibility: .visible) {
            Button("Photo Library") { captureSource = .photos }
            Button("Choose Files") { captureSource = .files }
            Button("Enter manually") { editor = ReceiptEditorRequest() }
        } message: {
            Text("Scanning with the camera isn't available on this device.")
        }
        .sheet(item: $editor, onDismiss: openQuickCapture) { request in
            ReceiptEditView(request: request) { id in
                // Saving one shared file moves straight on to the next.
                if request.sharedItem == nil || quickCapture.nextAutomaticItem == nil {
                    router.receiptsPath.append(.receipt(id))
                }
            }
        }
        .onAppear(perform: openQuickCapture)
        .onChange(of: quickCapture.scanRequestedAt) { openQuickCapture() }
        .onChange(of: quickCapture.sharedItems) { openQuickCapture() }
        .attachmentPresenter($exported)
        .confirmationDialog(
            "Delete \(pendingDelete?.merchant ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { receipt in
            Button("Delete", role: .destructive) { delete(receipt) }
        } message: { _ in
            Text("The receipt and its scans will be removed from this device.")
        }
        .errorAlert($errorMessage)
    }

    private func openQuickCapture() {
        guard router.tab == .receipts, router.receiptsPath.isEmpty, editor == nil, captureSource == nil, !showCaptureChoices,
              !router.isPresentingModal
        else { return }
        if quickCapture.consumeScanRequest() {
            if DocumentScanner.isSupported { captureSource = .scanner } else { showCaptureChoices = true }
        } else if let item = quickCapture.nextAutomaticItem {
            openShared(item)
        }
    }

    private func openShared(_ item: SharedInbox.Item) {
        editor = ReceiptEditorRequest(capture: .files([item.file]), sharedItem: item)
    }

    private var hasFilters: Bool { category != nil || tag != nil || needsReviewOnly }

    private var activeFilters: some View {
        let reviewLabel = needsReviewOnly ? String(localized: "Needs review") : nil
        return HStack {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text([reviewLabel, category, tag.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · "))
                .lineLimit(1)
            Spacer()
            Button("Clear") {
                category = nil
                tag = nil
                needsReviewOnly = false
            }
            .buttonStyle(.borderless)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Filtered by \([reviewLabel, category, tag].compactMap { $0 }.joined(separator: ", "))"))
    }

    private func organizeMenu(_ receipts: [Receipt], pendingCount: Int, filtered: [Receipt]) -> some View {
        let categories = ReceiptOrganizer.categories(receipts)
        let tags = ReceiptOrganizer.tags(receipts)
        return Menu {
            Toggle(isOn: $needsReviewOnly) {
                Label("Needs review (\(pendingCount))", systemImage: "exclamationmark.circle")
            }
            Section("Export CSV") {
                Button("All receipts (\(receipts.count))", systemImage: "tablecells") {
                    exportCSV(ReceiptOrganizer.groups(receipts, sort: sort, grouping: .none).flatMap(\.receipts))
                }
                if filtered.count != receipts.count {
                    Button("Shown receipts (\(filtered.count))", systemImage: "line.3.horizontal.decrease") {
                        exportCSV(filtered)
                    }
                    .disabled(filtered.isEmpty)
                }
            }
            Button("Browse and filter", systemImage: "square.grid.2x2") { router.receiptsPath.append(.receiptBrowse) }
            ReceiptOrganizePickers(sort: $sort, grouping: $grouping)
            if !categories.isEmpty {
                Picker(selection: $category) {
                    Text("All categories").tag(String?.none)
                    ForEach(categories, id: \.self) { Text($0).tag(Optional($0)) }
                } label: {
                    Label("Category", systemImage: "folder")
                }
                .pickerStyle(.menu)
            }
            if !tags.isEmpty {
                Picker(selection: $tag) {
                    Text("All tags").tag(String?.none)
                    ForEach(tags, id: \.self) { Text($0).tag(Optional($0)) }
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label(
                "Sort, filter and export",
                systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private func exportCSV(_ receipts: [Receipt]) {
        do {
            exported = OpenedAttachment(url: try ReceiptCSV.write(receipts, today: store.today), share: true)
        } catch {
            errorMessage = String(localized: "The CSV file could not be created. \(error.localizedDescription)")
        }
    }

    private func markReviewed(_ receipt: Receipt) {
        do {
            try store.markReviewed(receipt.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ receipt: Receipt) {
        do {
            try store.deleteReceipt(receipt.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GroupHeader: View {
    let title: String
    let totals: [(currency: String, amount: Decimal)]

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(totals.map { Money.format($0.amount, currency: $0.currency) }.joined(separator: " + "))
                .monospacedDigit()
        }
    }
}

struct ReceiptRow: View {
    let receipt: Receipt
    var needsReview = false
    @Environment(TrackerStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            if let page = store.attachments(.receipt, receipt.id).first {
                AttachmentThumbnail(attachment: page, size: 44)
            } else {
                Image(systemName: Receipt.symbol)
                    .foregroundStyle(Color.trackerOnPrimaryContainer)
                    .frame(width: 44, height: 44)
                    .background(Color.trackerPrimaryContainer, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(receipt.merchant).font(.body.weight(.medium))
                    if needsReview {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.trackerSoon)
                            .accessibilityLabel("Needs review")
                    }
                }
                let subtitle = [
                    receipt.purchaseDate.map(Formats.date) ?? String(localized: "No date"),
                    receipt.category.isEmpty ? nil : receipt.category,
                ].compactMap { $0 }.joined(separator: " · ")
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if let route = receipt.routeLabel {
                    Label(route, systemImage: ReceiptFacetKind.route.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !receipt.tags.isEmpty {
                    Text(receipt.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let total = receipt.total {
                Text(Money.format(total, currency: receipt.currency))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
