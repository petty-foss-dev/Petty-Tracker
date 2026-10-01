import SwiftUI

struct RootView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.reminders) private var reminders
    @Environment(QuickCapture.self) private var quickCapture
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.pureBlackKey) private var pureBlack = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.homePath) {
                DashboardView().routeDestinations()
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.warrantiesPath) {
                ProductListView().routeDestinations()
            }
            .tabItem { Label("Warranties", systemImage: RecordKind.warranty.symbol) }
            .tag(AppTab.warranties)

            NavigationStack(path: $router.subscriptionsPath) {
                SubscriptionListView().routeDestinations()
            }
            .tabItem { Label("Subscriptions", systemImage: RecordKind.subscription.symbol) }
            .tag(AppTab.subscriptions)

            NavigationStack(path: $router.documentsPath) {
                DocumentListView().routeDestinations()
            }
            .tabItem { Label("Documents", systemImage: RecordKind.document.symbol) }
            .tag(AppTab.documents)

            NavigationStack(path: $router.receiptsPath) {
                ReceiptListView().routeDestinations()
            }
            .tabItem { Label("Receipts", systemImage: Receipt.symbol) }
            .tag(AppTab.receipts)
        }
        // Surface colors read the pure-black preference when they resolve, so rebuild the tabs when it changes.
        .id(pureBlack)
        .tint(Color.trackerAccent)
        .preferredColorScheme(store.settings.themeMode.colorScheme)
        .task(id: store.data) {
            await reminders?.reschedule(store.data)
        }
        .task(id: store.receiptPages) {
            await store.backfillPageDigests()
        }
        .onAppear(perform: showQuickCapture)
        .onChange(of: quickCapture.scanRequestedAt) { showQuickCapture() }
        .onChange(of: quickCapture.sharedItems) { showQuickCapture() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.refreshToday()
            showQuickCapture()
            Task { await reminders?.reschedule(store.data) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.refreshToday()
        }
    }

    /// Switches to Receipts for shared files or a shortcut, unless that would close something open.
    private func showQuickCapture() {
        quickCapture.refresh()
        if quickCapture.needsAttention && !router.isPresentingModal { router.showReceipts() }
    }
}

private extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .product(let id): ProductDetailView(productId: id)
            case .subscription(let id): SubscriptionDetailView(subscriptionId: id)
            case .document(let id): DocumentDetailView(documentId: id)
            case .receipt(let id): ReceiptDetailView(receiptId: id)
            case .receiptBrowse: ReceiptBrowseView()
            case .receiptFacets(let kind): ReceiptFacetListView(kind: kind)
            case .receipts(let filter): ReceiptResultsView(filter: filter)
            case .settings: SettingsView()
            }
        }
    }
}
