import Foundation
import Testing
@testable import EnveKeep

struct RenewalsTests {
    @Test func monthEndAnchorDoesNotDrift() {
        let anchor = day("2025-01-31")
        #expect(Renewals.nextAfter(anchor: anchor, count: 1, unit: .months, after: anchor) == day("2025-02-28"))
        #expect(Renewals.nextAfter(anchor: anchor, count: 1, unit: .months, after: day("2025-02-28")) == day("2025-03-31"))
        #expect(Renewals.nextAfter(anchor: anchor, count: 1, unit: .months, after: day("2025-03-31")) == day("2025-04-30"))
    }

    @Test func leapDayYearlyAnchor() {
        let anchor = day("2024-02-29")
        #expect(Renewals.nextAfter(anchor: anchor, count: 1, unit: .years, after: anchor) == day("2025-02-28"))
        #expect(Renewals.nextAfter(anchor: anchor, count: 1, unit: .years, after: day("2027-02-28")) == day("2028-02-29"))
    }

    @Test func anchorInFutureIsNextRenewal() {
        #expect(Renewals.nextAfter(anchor: day("2030-01-01"), count: 1, unit: .months, after: day("2025-06-01")) == day("2030-01-01"))
    }

    @Test func multiWeekAndDailyCycles() {
        #expect(Renewals.nextAfter(anchor: day("2025-01-01"), count: 2, unit: .weeks, after: day("2025-01-20")) == day("2025-01-29"))
        #expect(Renewals.nextAfter(anchor: day("2025-01-01"), count: 10, unit: .days, after: day("2025-01-11")) == day("2025-01-21"))
    }

    @Test func quarterlyFromMonthEnd() {
        let anchor = day("2024-11-30")
        #expect(Renewals.nextAfter(anchor: anchor, count: 3, unit: .months, after: anchor) == day("2025-02-28"))
        #expect(Renewals.nextAfter(anchor: anchor, count: 3, unit: .months, after: day("2025-02-28")) == day("2025-05-30"))
    }

    private func monthly(_ next: String, anchor: String? = nil) -> Subscription {
        Subscription(name: "Test", currency: "USD", nextRenewal: day(next), anchorDate: day(anchor ?? next))
    }

    @Test func advanceOnRenewalDayMovesOnePeriod() {
        #expect(Renewals.advance(monthly("2025-05-15"), today: day("2025-05-15")).nextRenewal == day("2025-06-15"))
    }

    @Test func advanceEarlyMovesOnePeriod() {
        #expect(Renewals.advance(monthly("2025-05-15"), today: day("2025-05-01")).nextRenewal == day("2025-06-15"))
    }

    @Test func advanceLongOverdueCatchesUpToToday() {
        #expect(Renewals.advance(monthly("2025-01-15"), today: day("2025-04-20")).nextRenewal == day("2025-05-15"))
    }

    @Test func advanceKeepsMonthEndAnchor() {
        let subscription = monthly("2025-02-28", anchor: "2025-01-31")
        let advanced = Renewals.advance(subscription, today: day("2025-02-28"))
        #expect(advanced.nextRenewal == day("2025-03-31"))
        #expect(advanced.anchorDate == day("2025-01-31"))
    }

    @Test func reactivateSkipsMissedRenewals() {
        var canceled = monthly("2025-01-31")
        canceled.canceledOn = day("2025-01-10")
        let active = Renewals.reactivate(canceled, today: day("2025-04-15"))
        #expect(active.isActive)
        #expect(active.nextRenewal == day("2025-04-30"))

        var future = monthly("2025-06-01")
        future.canceledOn = day("2025-05-01")
        #expect(Renewals.reactivate(future, today: day("2025-05-10")).nextRenewal == day("2025-06-01"))
    }

    @Test func monthlyCostNormalisesCycles() {
        #expect(Renewals.monthlyCost(price: 120, count: 1, unit: .years) == 10)
        #expect(Renewals.monthlyCost(price: 15, count: 3, unit: .months) == 5)
        let totals = Renewals.monthlyTotals([
            Subscription(name: "A", price: 10, currency: "USD", nextRenewal: day("2025-01-01"), anchorDate: day("2025-01-01")),
            Subscription(name: "B", price: 5, currency: "USD", nextRenewal: day("2025-01-01"), anchorDate: day("2025-01-01")),
            Subscription(name: "C", price: 99, currency: "USD", nextRenewal: day("2025-01-01"), anchorDate: day("2025-01-01"),
                         canceledOn: day("2024-12-01")),
        ])
        #expect(totals.count == 1)
        #expect(totals[0].amount == 15)
    }
}

struct DayTests {
    @Test func parsesOnlyStrictISODates() {
        #expect(Day(iso: "2026-09-29")?.iso == "2026-09-29")
        #expect(Day(iso: "2026-02-29") == nil)
        #expect(Day(iso: "2024-02-29") != nil)
        #expect(Day(iso: "2026-9-29") == nil)
        #expect(Day(iso: "2026-09-29T00:00") == nil)
    }

    @Test func epochDayRoundTrips() {
        #expect(day("1970-01-01").epochDay == 0)
        #expect(day("2000-03-01").epochDay == 11_017)
        for epoch in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(Day(epochDay: epoch).epochDay == epoch)
        }
    }

    @Test func monthArithmeticMatchesJavaTime() {
        #expect(day("2025-01-31").adding(months: 1) == day("2025-02-28"))
        #expect(day("2025-03-31").adding(months: -1) == day("2025-02-28"))
        #expect(day("2025-01-15").adding(months: -13) == day("2023-12-15"))
        #expect(day("2025-01-31").months(until: day("2025-02-28")) == 0)
        #expect(day("2025-01-31").months(until: day("2025-03-31")) == 2)
        #expect(day("2025-03-31").months(until: day("2025-01-01")) == -2)
    }
}

struct DeadlineTests {
    @Test func statusUsesLeadWindow() {
        let today = day("2026-09-29")
        #expect(deadlineStatus(nil, today: today, leadDays: 30) == .none)
        #expect(deadlineStatus(day("2026-09-28"), today: today, leadDays: 30) == .past)
        #expect(deadlineStatus(today, today: today, leadDays: 30) == .today)
        #expect(deadlineStatus(day("2026-10-29"), today: today, leadDays: 30) == .soon)
        #expect(deadlineStatus(day("2026-10-30"), today: today, leadDays: 30) == .ok)
    }

    @Test func searchFoldsCaseAndDiacritics() {
        let product = Product(name: "Café Machine", brand: "Brëwco", serialNumber: "SN-42", currency: "EUR")
        #expect(product.matches("cafe brewco"))
        #expect(product.matches("  sn-4 "))
        #expect(!product.matches("cafe toaster"))
    }
}
