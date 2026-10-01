import SwiftUI

enum DocumentFilter: CaseIterable {
    case all, valid, expiring, expired

    var label: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .valid: "Valid"
        case .expiring: "Expiring soon"
        case .expired: "Expired"
        }
    }

    func includes(_ status: DeadlineStatus) -> Bool {
        switch self {
        case .all: true
        case .valid: status != .past
        case .expiring: status.isUpcoming
        case .expired: status == .past
        }
    }
}

struct DocumentListView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var filter = DocumentFilter.all
    @State private var editor: Editor?

    var body: some View {
        let today = store.today
        let lead = store.settings.documentLeadDays
        let items = store.data.documents
            .filter { $0.matches(query) }
            .map { (document: $0, status: deadlineStatus($0.expiresOn, today: today, leadDays: lead)) }
            .filter { filter.includes($0.status) }
            .sorted {
                ($0.status.sortRank, deadlineSortKey($0.document.expiresOn, $0.status))
                    < ($1.status.sortRank, deadlineSortKey($1.document.expiresOn, $1.status))
            }

        TrackerList {
            if !store.data.documents.isEmpty {
                FilterPicker(selection: $filter, options: DocumentFilter.allCases, label: \.label)
                ForEach(StatusSection.group(items, status: \.status), id: \.section) { group in
                    Section(overline: group.section.title(.document)) {
                        ForEach(group.items, id: \.document.id) { item in
                            NavigationLink(value: Route.document(item.document.id)) {
                                DocumentRow(document: item.document, status: item.status, today: today)
                            }
                        }
                    }
                }
            }
        }
        .trackerListStyle()
        .overlay {
            if store.data.documents.isEmpty {
                ContentUnavailableView {
                    Label("No documents yet", systemImage: RecordKind.document.symbol)
                } description: {
                    Text("Add passports, licences, insurance policies and other documents to be reminded before they expire.")
                } actions: {
                    Button("Add document") { editor = .document(nil) }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color.trackerOnAccent)
                }
            } else if items.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different search or filter."))
            }
        }
        .navigationTitle("Documents")
        .searchable(text: $query, prompt: "Search documents")
        .toolbar {
            Button("Add document", systemImage: "plus") { editor = .document(nil) }
        }
        .editorSheet($editor) { router.documentsPath.append($0) }
    }
}

struct DocumentRow: View {
    let document: Document
    let status: DeadlineStatus
    let today: Day

    var body: some View {
        HStack(spacing: 12) {
            RecordIcon(symbol: RecordKind.document.symbol, tint: status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).font(.body.weight(.semibold)).fontDesign(.serif)
                if !document.issuer.isEmpty {
                    Text(document.issuer).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(document.expiresOn.map { Formats.deadline(.document, date: $0, today: today) } ?? String(localized: "No expiry date"))
                    .font(.subheadline)
                    .foregroundStyle(status == .ok ? Color.secondary : status.tint)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
