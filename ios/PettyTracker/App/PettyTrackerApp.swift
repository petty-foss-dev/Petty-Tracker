import SwiftUI
import UserNotifications

@main
struct PettyTrackerApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.store)
                .environment(appDelegate.router)
                .environment(QuickCapture.shared)
                .environment(\.reminders, appDelegate.reminders)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = TrackerStore.appDefault()
    let router = Router()
    let reminders = ReminderScheduler()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        store.deleteOrphanedAttachments()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let kind = (info["kind"] as? String).flatMap(RecordKind.init(rawValue:)),
              let id = (info["id"] as? NSNumber)?.int64Value
        else { return }
        await MainActor.run { router.open(kind, id: id) }
    }
}

extension EnvironmentValues {
    @Entry var reminders: ReminderScheduler? = nil
}
