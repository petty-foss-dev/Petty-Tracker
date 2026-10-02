import Foundation
import Testing
@testable import PettyTracker

struct CalendarExportTests {
    private let today = day("2026-10-01")

    private var data: TrackerData {
        var data = TrackerData()
        data.products = [
            Product(id: 1, name: "Laptop", currency: "USD", warrantyExpires: day("2026-10-12")),
            Product(id: 2, name: "Old blender", currency: "USD", warrantyExpires: day("2026-01-01")),
        ]
        data.documents = [Document(id: 3, title: "Passport", reference: "X1", expiresOn: day("2027-03-08"))]
        data.subscriptions = [
            Subscription(id: 4, name: "Cloud", price: Decimal(string: "9.99"), currency: "USD",
                         nextRenewal: day("2026-10-31"), anchorDate: day("2024-01-31")),
            Subscription(id: 5, name: "Gone", currency: "USD", nextRenewal: day("2026-10-05"),
                         anchorDate: day("2026-10-05"), canceledOn: day("2026-09-01")),
        ]
        return data
    }

    @Test func listsUpcomingDatesWithReminderLeadTimes() {
        let events = CalendarExport.events(data, today: today)

        #expect(!events.contains { $0.uid == "warranty-2" })
        #expect(!events.contains { $0.uid.hasPrefix("subscription-5") })
        #expect(events.first { $0.uid == "warranty-1" }?.alertDaysBefore == 30)
        #expect(events.first { $0.uid == "document-3" }?.alertDaysBefore == 60)
    }

    @Test func monthEndRenewalsStayAtMonthEnd() {
        let renewals = CalendarExport.events(data, today: today).filter { $0.uid.hasPrefix("subscription-4") }.map(\.day)

        #expect(renewals.prefix(4) == [day("2026-10-31"), day("2026-11-30"), day("2026-12-31"), day("2027-01-31")])
        #expect(renewals.count == CalendarExport.renewalHorizonMonths)
    }

    @Test func writesAValidCalendarFile() {
        let ics = CalendarExport.make(data, today: today, now: Date(timeIntervalSince1970: 0))
        let lines = ics.components(separatedBy: "\r\n")

        #expect(lines.first == "BEGIN:VCALENDAR")
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
        #expect(lines.filter { $0 == "BEGIN:VEVENT" }.count == lines.filter { $0 == "END:VEVENT" }.count)
        #expect(lines.contains("DTSTART;VALUE=DATE:20261012"))
        #expect(lines.contains("DTSTAMP:19700101T000000Z"))
        #expect(lines.contains("SUMMARY:Renews: Cloud ($9.99)"))
        #expect(lines.allSatisfy { $0.utf8.count <= 75 })
    }

    @Test func escapesTextAndFoldsLongLines() {
        #expect(CalendarExport.text("a, b; c\\d\ne") == "a\\, b\\; c\\\\d\\ne")
        let folded = CalendarExport.fold("SUMMARY:" + String(repeating: "é", count: 60))
        #expect(folded.components(separatedBy: "\r\n ").allSatisfy { $0.utf8.count <= 75 })
        #expect(folded.replacingOccurrences(of: "\r\n ", with: "") == "SUMMARY:" + String(repeating: "é", count: 60))
    }
}

struct RecordsCSVTests {
    @Test func listsEveryRecordWithItsStatus() {
        var data = TrackerData()
        data.products = [Product(id: 1, name: "=Desk", brand: "Oak, Co", currency: "USD",
                                 warrantyExpires: day("2026-10-12"), productUrl: "https://example.com/desk")]
        data.subscriptions = [Subscription(id: 2, name: "Music", price: Decimal(string: "119.88"), currency: "USD",
                                           cycleUnit: .years, nextRenewal: day("2027-01-01"), anchorDate: day("2027-01-01"))]
        data.documents = [Document(id: 3, title: "Licence", expiresOn: day("2026-09-01"))]

        let rows = RecordsCSV.make(data, today: day("2026-10-01")).components(separatedBy: "\r\n")

        #expect(rows[0].hasPrefix("Type,Name,Due Date,Status"))
        #expect(rows[1] == "Product,'=Desk,2026-10-12,Due soon,\"Oak, Co\",,,,,,USD,,,,,,,https://example.com/desk,")
        #expect(rows[2].hasPrefix("Subscription,Music,2027-01-01,Active,,,,,,119.88,USD,Every year,9.99,"))
        #expect(rows[3].hasPrefix("Document,Licence,2026-09-01,Expired,"))
    }
}
