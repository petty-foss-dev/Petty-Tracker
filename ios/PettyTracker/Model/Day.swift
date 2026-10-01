import Foundation

/// A calendar date with no time or zone, serialized as ISO `yyyy-MM-dd` like `java.time.LocalDate`.
struct Day: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...Day.daysIn(month: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: Day, rhs: Day) -> Bool { lhs.epochDay < rhs.epochDay }

    static func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // Days since 1970-01-01 (Howard Hinnant's civil calendar algorithm).
    var epochDay: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    init(epochDay: Int) {
        let z = epochDay + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(unchecked: yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    func adding(days: Int) -> Day { Day(epochDay: epochDay + days) }

    /// Month arithmetic clamps to the last valid day, as `LocalDate.plusMonths` does.
    func adding(months: Int) -> Day {
        let total = year * 12 + (month - 1) + months
        let y = total >= 0 ? total / 12 : (total - 11) / 12
        let m = total - y * 12 + 1
        return Day(unchecked: y, m, min(day, Day.daysIn(month: m, year: y)))
    }

    func days(until other: Day) -> Int { other.epochDay - epochDay }

    /// Whole months from `self` to `other`, matching `ChronoUnit.MONTHS.between`.
    func months(until other: Day) -> Int {
        let packed1 = (year * 12 + month) * 32 + day
        let packed2 = (other.year * 12 + other.month) * 32 + other.day
        return (packed2 - packed1) / 32
    }

    static func today(calendar: Calendar = .gregorian) -> Day { Day(date: Date(), calendar: calendar) }

    init(date: Date, calendar: Calendar = .gregorian) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(unchecked: c.year!, c.month!, c.day!)
    }

    /// Noon local time keeps the date stable across DST changes when bridged to date pickers.
    func date(calendar: Calendar = .gregorian, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

extension Day: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = Day(iso: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}

extension Calendar {
    /// Gregorian in the device time zone, so `Day` stays ISO even when the user's calendar isn't.
    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
