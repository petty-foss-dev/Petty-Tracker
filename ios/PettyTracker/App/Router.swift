import SwiftUI

enum AppTab: Hashable {
    case home, warranties, subscriptions, documents, receipts
}

enum Route: Hashable {
    case product(Int64)
    case subscription(Int64)
    case document(Int64)
    case receipt(Int64)
    case receiptBrowse
    case receiptFacets(ReceiptFacetKind)
    case receipts(ReceiptFilter)
    case settings

    init(_ kind: RecordKind, id: Int64) {
        self = switch kind {
        case .warranty: .product(id)
        case .subscription: .subscription(id)
        case .document: .document(id)
        }
    }
}

@MainActor
@Observable
final class Router {
    var tab = AppTab.home
    var homePath: [Route] = []
    var warrantiesPath: [Route] = []
    var subscriptionsPath: [Route] = []
    var documentsPath: [Route] = []
    var receiptsPath: [Route] = []

    /// Something covers the tabs, such as an editor sheet, a picker or an alert.
    var isPresentingModal: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }

    func showReceipts() {
        tab = .receipts
        receiptsPath = []
    }

    /// Opens a record from outside the app, such as a tapped reminder.
    func open(_ kind: RecordKind, id: Int64) {
        let route = Route(kind, id: id)
        switch kind {
        case .warranty:
            tab = .warranties
            warrantiesPath = [route]
        case .subscription:
            tab = .subscriptions
            subscriptionsPath = [route]
        case .document:
            tab = .documents
            documentsPath = [route]
        }
    }
}
