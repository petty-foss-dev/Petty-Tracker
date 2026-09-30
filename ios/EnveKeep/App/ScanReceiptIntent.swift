import AppIntents

struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Receipt"
    static let description: IntentDescription? = IntentDescription("Opens Enve Keep on Receipts with the document scanner ready.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCapture.shared.requestScan()
        return .result()
    }
}

struct EnveKeepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: [
                "Scan receipt in \(.applicationName)",
                "Scan a receipt with \(.applicationName)",
                "Add a receipt to \(.applicationName)",
            ],
            shortTitle: "Scan Receipt",
            systemImageName: "doc.viewfinder"
        )
    }
}
