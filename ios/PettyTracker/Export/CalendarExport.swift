import Foundation

/// An iCalendar (RFC 5545) file of upcoming warranty ends, document expiries and subscription renewals,
/// for importing into any calendar app. Every event is all-day and carries an alert at the reminder lead time.
enum CalendarExport {
    /// How far ahead subscription renewals are listed; each one is its own event so month-end dates stay exact.
    static let renewalHorizonMonths = 24
    static let maxRenewalsPerSubscription = 60

    struct Event: Equatable {
        let uid: String
        let day: Day
        let summary: String
        let details: [String]
        let alertDaysBefore: Int
    }

    static func events(_ data: TrackerData, today: Day) -> [Event] {
        let settings = data.settings
        var events: [Event] = []
        for product in data.products {
            guard let expires = product.warrantyExpires, expires >= today else { continue }
            events.append(Event(
                uid: "warranty-\(product.id)",
                day: expires,
                summary: String(localized: "Warranty ends: \(product.name)"),
                details: [
                    [product.brand, product.model].filter { !$0.isEmpty }.joined(separator: " "),
                    product.serialNumber.isEmpty ? "" : String(localized: "Serial number: \(product.serialNumber)"),
                    product.productUrl,
                ],
                alertDaysBefore: settings.warrantyLeadDays
            ))
        }
        for document in data.documents {
            guard let expires = document.expiresOn, expires >= today else { continue }
            events.append(Event(
                uid: "document-\(document.id)",
                day: expires,
                summary: String(localized: "Expires: \(document.title)"),
                details: [
                    document.issuer,
                    document.reference.isEmpty ? "" : String(localized: "Number: \(document.reference)"),
                ],
                alertDaysBefore: settings.documentLeadDays
            ))
        }
        let horizon = today.adding(months: renewalHorizonMonths)
        for subscription in data.subscriptions where subscription.isActive {
            let price = subscription.price.map { Money.format($0, currency: subscription.currency) }
            var day = subscription.nextRenewal
            var listed = 0
            while day <= horizon && listed < maxRenewalsPerSubscription {
                if day >= today {
                    events.append(Event(
                        uid: "subscription-\(subscription.id)-\(day.iso)",
                        day: day,
                        summary: price.map { String(localized: "Renews: \(subscription.name) (\($0))") }
                            ?? String(localized: "Renews: \(subscription.name)"),
                        details: [Formats.cycle(count: subscription.cycleCount, unit: subscription.cycleUnit)],
                        alertDaysBefore: settings.subscriptionLeadDays
                    ))
                    listed += 1
                }
                day = Renewals.nextAfter(anchor: subscription.anchorDate, count: subscription.cycleCount,
                                         unit: subscription.cycleUnit, after: day)
            }
        }
        return events.sorted { ($0.day, $0.uid) < ($1.day, $1.uid) }
    }

    static func make(_ data: TrackerData, today: Day, now: Date) -> String {
        let stamp = now.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)Z",
            timeZone: .gmt,
            calendar: Calendar(identifier: .gregorian)
        ))
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Petty FOSS//petty: Tracker//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:\(text("petty: Tracker"))",
        ]
        for event in events(data, today: today) {
            let details = event.details.filter { !$0.isEmpty }.joined(separator: "\n")
            lines += [
                "BEGIN:VEVENT",
                "UID:\(event.uid)@petty-tracker",
                "DTSTAMP:\(stamp)",
                "DTSTART;VALUE=DATE:\(compact(event.day))",
                "DTEND;VALUE=DATE:\(compact(event.day.adding(days: 1)))",
                "SUMMARY:\(text(event.summary))",
            ]
            if !details.isEmpty { lines.append("DESCRIPTION:\(text(details))") }
            lines += [
                "TRANSP:TRANSPARENT",
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                "DESCRIPTION:\(text(event.summary))",
                "TRIGGER:-P\(event.alertDaysBefore)D",
                "END:VALARM",
                "END:VEVENT",
            ]
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func write(_ data: TrackerData, today: Day) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calendar", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Petty Tracker dates \(today.iso).ics")
        try Data(make(data, today: today, now: .now).utf8).write(to: url, options: .atomic)
        return url
    }

    private static func compact(_ day: Day) -> String {
        day.iso.replacingOccurrences(of: "-", with: "")
    }

    /// Escapes TEXT values: backslash, semicolon, comma and newlines.
    static func text(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Splits lines longer than 75 octets, continuing with a leading space, without breaking a character.
    static func fold(_ line: String) -> String {
        var parts: [String] = []
        var current = ""
        var octets = 0
        for character in line {
            let size = String(character).utf8.count
            let limit = parts.isEmpty ? 75 : 74
            if octets + size > limit {
                parts.append(current)
                current = ""
                octets = 0
            }
            current.append(character)
            octets += size
        }
        parts.append(current)
        return parts.joined(separator: "\r\n ")
    }
}
