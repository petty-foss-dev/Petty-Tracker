import Foundation
import Observation

/// Receipt captures started outside the app: files from the share extension and the Scan Receipt shortcut.
@MainActor
@Observable
final class QuickCapture {
    static let shared = QuickCapture(inbox: SharedInbox.appGroupInbox(), defaults: .standard)

    private static let scanRequestKey = "quickCapture.scanRequestedAt"
    private static let scanRequestLifetime: TimeInterval = 10 * 60

    private(set) var sharedItems: [SharedInbox.Item] = []
    private(set) var scanRequestedAt: Date?
    private var postponed: Set<String> = []
    @ObservationIgnored private let inbox: SharedInbox?
    @ObservationIgnored private let defaults: UserDefaults

    init(inbox: SharedInbox?, defaults: UserDefaults) {
        self.inbox = inbox
        self.defaults = defaults
        scanRequestedAt = defaults.object(forKey: Self.scanRequestKey) as? Date
        inbox?.removeAbandonedBatches(olderThan: .now.addingTimeInterval(-24 * 60 * 60))
        refresh()
    }

    /// The next shared file to open without being asked; files put off for later wait until the next launch.
    var nextAutomaticItem: SharedInbox.Item? {
        sharedItems.first { !postponed.contains($0.id) }
    }

    var scanRequested: Bool {
        scanRequestedAt.map { $0.timeIntervalSinceNow > -Self.scanRequestLifetime } ?? false
    }

    var needsAttention: Bool { scanRequested || nextAutomaticItem != nil }

    func refresh() {
        let items = inbox?.items() ?? []
        if items != sharedItems { sharedItems = items }
    }

    func requestScan() {
        scanRequestedAt = .now
        defaults.set(scanRequestedAt, forKey: Self.scanRequestKey)
    }

    /// Clears a pending scan request, returning whether there was one.
    func consumeScanRequest() -> Bool {
        let requested = scanRequested
        scanRequestedAt = nil
        defaults.removeObject(forKey: Self.scanRequestKey)
        return requested
    }

    func postpone(_ item: SharedInbox.Item) {
        postponed.insert(item.id)
    }

    /// Deletes the shared copy once the receipt is saved or the user discards it.
    func finish(_ item: SharedInbox.Item) {
        inbox?.remove(item)
        postponed.remove(item.id)
        refresh()
    }
}
