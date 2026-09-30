import Foundation

enum Formats {
    static func date(_ day: Day) -> String {
        day.date().formatted(date: .abbreviated, time: .omitted)
    }

    static func time(_ time: ClockTime) -> String {
        time.date().formatted(date: .omitted, time: .shortened)
    }

    static func fuelVolume(_ volume: Decimal, unit: FuelUnit?) -> String {
        [Money.formatForInput(volume), unit?.symbol].compactMap { $0 }.joined(separator: " ")
    }

    static func fuelUnitPrice(_ price: Decimal, currency: String, unit: FuelUnit?) -> String {
        let amount = price.formatted(.currency(code: currency).precision(.fractionLength(2...3)))
        return unit.map { "\(amount)/\($0.symbol)" } ?? amount
    }

    static func relativeDays(_ days: Int) -> String {
        switch days {
        case 0: String(localized: "today")
        case 1: String(localized: "tomorrow")
        case -1: String(localized: "yesterday")
        case let d where d > 0: String(localized: "in \(d) days")
        default: String(localized: "\(abs(days)) days ago")
        }
    }

    /// "Renews in 3 days", "Warranty ended yesterday" and similar phrases for list rows.
    static func deadline(_ kind: RecordKind, days: Int) -> String {
        let when = relativeDays(days)
        return switch (kind, days < 0) {
        case (.warranty, false): String(localized: "Warranty ends \(when)")
        case (.warranty, true): String(localized: "Warranty ended \(when)")
        case (.subscription, false): String(localized: "Renews \(when)")
        case (.subscription, true): String(localized: "Renewal was due \(when)")
        case (.document, false): String(localized: "Expires \(when)")
        case (.document, true): String(localized: "Expired \(when)")
        }
    }

    /// Absolute phrasing for notifications, which may be read long after they were scheduled.
    static func deadlinePhrase(_ kind: RecordKind, date day: Day, past: Bool) -> String {
        let when = date(day)
        return switch (kind, past) {
        case (.warranty, false): String(localized: "Warranty ends \(when)")
        case (.warranty, true): String(localized: "Warranty ended \(when)")
        case (.subscription, false): String(localized: "Renews \(when)")
        case (.subscription, true): String(localized: "Renewal was due \(when)")
        case (.document, false): String(localized: "Expires \(when)")
        case (.document, true): String(localized: "Expired \(when)")
        }
    }

    static func cycle(count: Int, unit: CycleUnit) -> String {
        switch (unit, count) {
        case (.days, 1): String(localized: "Every day")
        case (.weeks, 1): String(localized: "Every week")
        case (.months, 1): String(localized: "Every month")
        case (.years, 1): String(localized: "Every year")
        case (.days, _): String(localized: "Every \(count) days")
        case (.weeks, _): String(localized: "Every \(count) weeks")
        case (.months, _): String(localized: "Every \(count) months")
        case (.years, _): String(localized: "Every \(count) years")
        }
    }

    static func unit(_ unit: CycleUnit, count: Int) -> String {
        switch unit {
        case .days: count == 1 ? String(localized: "day") : String(localized: "days")
        case .weeks: count == 1 ? String(localized: "week") : String(localized: "weeks")
        case .months: count == 1 ? String(localized: "month") : String(localized: "months")
        case .years: count == 1 ? String(localized: "year") : String(localized: "years")
        }
    }

    static func count(_ n: Int, _ singular: String.LocalizationValue, _ plural: String.LocalizationValue) -> String {
        "\(n) " + String(localized: n == 1 ? singular : plural)
    }

    static func fileSize(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
