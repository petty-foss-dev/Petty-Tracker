import Foundation
import UserNotifications

/// Schedules one-shot local notifications at 9 AM when a date enters its reminder window and when it
/// arrives. Delivered reminders are remembered so rescheduling never repeats them.
@MainActor
final class ReminderScheduler {
    private static let checkHour = 9
    // Covers dates that passed while the app wasn't able to schedule, without alerting about old ones.
    private static let missedGraceDays = 7
    // iOS keeps at most 64 pending requests per app.
    private static let maxPending = 60
    private static let scheduledKey = "reminders.scheduled"
    private static let sentKey = "reminders.sent"

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Forgets delivery history, e.g. after an import replaces every record.
    func reset() {
        defaults.removeObject(forKey: Self.scheduledKey)
        defaults.removeObject(forKey: Self.sentKey)
    }

    func reschedule(_ data: TrackerData, now: Date = .now) async {
        let calendar = Calendar.gregorian
        let today = Day(date: now, calendar: calendar)
        var sent = defaults.dictionary(forKey: Self.sentKey) as? [String: Int] ?? [:]
        let scheduled = defaults.dictionary(forKey: Self.scheduledKey) as? [String: Double] ?? [:]
        for (key, fireTime) in scheduled where fireTime <= now.timeIntervalSince1970 {
            sent[key] = today.epochDay
        }
        sent = sent.filter { $0.value >= today.epochDay - 90 }
        defaults.set(sent, forKey: Self.sentKey)
        defaults.removeObject(forKey: Self.scheduledKey)
        center.removeAllPendingNotificationRequests()

        let status = await authorizationStatus()
        guard data.settings.remindersEnabled, status == .authorized || status == .provisional else { return }

        let nextSlot = Self.fireDate(today, calendar) > now ? today : today.adding(days: 1)
        var pending: [Reminder] = []
        let deadlines = data.products.compactMap(\.deadline)
            + data.subscriptions.compactMap(\.deadline)
            + data.documents.compactMap(\.deadline)
        for deadline in deadlines {
            var dueDay: Day? = deadline.date
            if Self.fireDate(deadline.date, calendar) <= now {
                dueDay = deadline.days(from: today) >= -Self.missedGraceDays ? nextSlot : nil
            }
            if let dueDay {
                pending.append(Reminder(deadline: deadline, stage: .due, fireDay: dueDay))
            }
            let lead = data.settings.leadDays(deadline.kind)
            var soonDay = deadline.date.adding(days: -lead)
            if Self.fireDate(soonDay, calendar) <= now { soonDay = nextSlot }
            if lead > 0, soonDay < deadline.date {
                pending.append(Reminder(deadline: deadline, stage: .soon, fireDay: soonDay))
            }
        }

        let upcoming = pending
            .filter { sent[$0.key] == nil }
            .sorted { $0.fireDay < $1.fireDay }
            .prefix(Self.maxPending)
        var nextScheduled: [String: Double] = [:]
        for reminder in upcoming {
            let fireDate = Self.fireDate(reminder.fireDay, calendar)
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            components.calendar = calendar
            let request = UNNotificationRequest(
                identifier: reminder.key,
                content: reminder.content(),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
                nextScheduled[reminder.key] = fireDate.timeIntervalSince1970
            } catch {
                continue
            }
        }
        defaults.set(nextScheduled, forKey: Self.scheduledKey)
    }

    private static func fireDate(_ day: Day, _ calendar: Calendar) -> Date {
        day.date(calendar: calendar, hour: checkHour)
    }
}

private struct Reminder {
    enum Stage: String { case soon, due }

    let deadline: Deadline
    let stage: Stage
    let fireDay: Day

    var key: String { "\(deadline.kind.rawValue):\(deadline.id):\(deadline.date.iso):\(stage.rawValue)" }

    func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let title = deadline.title
        let arrived = stage == .due
        let isToday = fireDay == deadline.date
        content.title = switch (deadline.kind, arrived) {
        case (.warranty, false): String(localized: "Warranty ending: \(title)")
        case (.warranty, true): isToday ? String(localized: "Warranty ends today: \(title)") : String(localized: "Warranty ended: \(title)")
        case (.subscription, false): String(localized: "Renewal coming up: \(title)")
        case (.subscription, true): String(localized: "Renewal due: \(title)")
        case (.document, false): String(localized: "Document expiring: \(title)")
        case (.document, true): isToday ? String(localized: "Document expires today: \(title)") : String(localized: "Document expired: \(title)")
        }
        content.body = Formats.deadlinePhrase(deadline.kind, date: deadline.date, past: fireDay > deadline.date)
        content.sound = .default
        content.userInfo = ["kind": deadline.kind.rawValue, "id": deadline.id]
        return content
    }
}
