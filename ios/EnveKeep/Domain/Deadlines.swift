import Foundation

enum RecordKind: String, CaseIterable, Sendable {
    case warranty, subscription, document
}

enum DeadlineStatus: Sendable {
    case none, ok, soon, today, past

    var sortRank: Int {
        switch self {
        case .today: 0
        case .soon: 1
        case .ok: 2
        case .none: 3
        case .past: 4
        }
    }

    var isUpcoming: Bool { self == .soon || self == .today }
}

struct Deadline: Hashable, Sendable {
    let kind: RecordKind
    let id: Int64
    let title: String
    let date: Day

    func days(from today: Day) -> Int { today.days(until: date) }
}

func deadlineStatus(_ date: Day?, today: Day, leadDays: Int) -> DeadlineStatus {
    guard let date else { return .none }
    let days = today.days(until: date)
    if days < 0 { return .past }
    if days == 0 { return .today }
    return days <= leadDays ? .soon : .ok
}

/// Upcoming dates sort soonest first; past dates sort most recent first.
func deadlineSortKey(_ date: Day?, _ status: DeadlineStatus) -> Int {
    guard let date else { return .max }
    return status == .past ? -date.epochDay : date.epochDay
}

extension Settings {
    func leadDays(_ kind: RecordKind) -> Int {
        switch kind {
        case .warranty: warrantyLeadDays
        case .subscription: subscriptionLeadDays
        case .document: documentLeadDays
        }
    }
}

extension Product {
    var deadline: Deadline? { warrantyExpires.map { Deadline(kind: .warranty, id: id, title: name, date: $0) } }
}

extension Subscription {
    var deadline: Deadline? { isActive ? Deadline(kind: .subscription, id: id, title: name, date: nextRenewal) : nil }
}

extension Document {
    var deadline: Deadline? { expiresOn.map { Deadline(kind: .document, id: id, title: title, date: $0) } }
}

extension Product {
    func matches(_ query: String) -> Bool {
        Search.matches(query, name, brand, model, serialNumber, retailer, notes)
    }
}

extension Subscription {
    func matches(_ query: String) -> Bool { Search.matches(query, name, notes) }
}

extension Document {
    func matches(_ query: String) -> Bool { Search.matches(query, title, issuer, reference, notes) }
}

enum Search {
    /// Every whitespace-separated term must appear somewhere, ignoring case and diacritics.
    static func matches(_ query: String, _ fields: String...) -> Bool {
        let terms = fold(query).split(whereSeparator: \.isWhitespace)
        if terms.isEmpty { return true }
        let haystack = fields.map(fold).joined(separator: " ")
        return terms.allSatisfy { haystack.contains($0) }
    }

    /// Folded and single-spaced, so "San  Francisco" and "san francisco" count as the same value.
    static func key(_ text: String) -> String {
        fold(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
