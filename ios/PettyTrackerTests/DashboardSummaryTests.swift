import Testing
@testable import PettyTracker

struct DashboardSummaryTests {
    private let today = day("2026-10-01")

    @Test func groupsUpcomingDatesByHowSoonTheyFall() {
        var data = TrackerData()
        data.settings.documentLeadDays = 60
        data.documents = [
            Document(id: 1, title: "Licence", expiresOn: day("2026-11-20")),
            Document(id: 2, title: "Insurance", expiresOn: day("2026-10-15")),
            Document(id: 3, title: "Permit", expiresOn: day("2026-10-08")),
            Document(id: 4, title: "Registration", expiresOn: day("2026-09-20")),
            Document(id: 5, title: "Passport", expiresOn: day("2030-01-01")),
        ]

        let summary = DashboardSummary(data, today: today)

        #expect(summary.pastDue.map(\.deadline.title) == ["Registration"])
        #expect(summary.upcoming.map(\.band) == [.week, .month, .later])
        #expect(summary.upcoming.map { $0.entries.map(\.deadline.title) } == [["Permit"], ["Insurance"], ["Licence"]])
        #expect(summary.upcomingCount == 3)
    }

    @Test func listPhrasesSwitchToDatesBeyondAMonth() {
        #expect(Formats.deadline(.document, date: day("2026-10-15"), today: today) == "Expires in 14 days")
        #expect(Formats.deadline(.warranty, date: day("2025-06-20"), today: today).hasPrefix("Warranty ended Jun 20"))
    }
}
