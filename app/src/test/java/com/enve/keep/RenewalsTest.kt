package com.enve.keep

import com.enve.keep.data.CycleUnit
import com.enve.keep.data.Subscription
import com.enve.keep.domain.Renewals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigDecimal
import java.time.LocalDate

class RenewalsTest {
    private fun date(value: String) = LocalDate.parse(value)

    @Test
    fun monthEndAnchorDoesNotDrift() {
        val anchor = date("2025-01-31")
        assertEquals(date("2025-02-28"), Renewals.nextAfter(anchor, 1, CycleUnit.MONTHS, anchor))
        assertEquals(date("2025-03-31"), Renewals.nextAfter(anchor, 1, CycleUnit.MONTHS, date("2025-02-28")))
        assertEquals(date("2025-04-30"), Renewals.nextAfter(anchor, 1, CycleUnit.MONTHS, date("2025-03-31")))
    }

    @Test
    fun leapDayYearlyAnchor() {
        val anchor = date("2024-02-29")
        assertEquals(date("2025-02-28"), Renewals.nextAfter(anchor, 1, CycleUnit.YEARS, anchor))
        assertEquals(date("2028-02-29"), Renewals.nextAfter(anchor, 1, CycleUnit.YEARS, date("2027-02-28")))
    }

    @Test
    fun anchorInFutureIsNextRenewal() {
        assertEquals(date("2030-01-01"), Renewals.nextAfter(date("2030-01-01"), 1, CycleUnit.MONTHS, date("2025-06-01")))
    }

    @Test
    fun multiWeekCycle() {
        val anchor = date("2025-01-01")
        assertEquals(date("2025-01-29"), Renewals.nextAfter(anchor, 2, CycleUnit.WEEKS, date("2025-01-20")))
    }

    @Test
    fun quarterlyFromMonthEnd() {
        val anchor = date("2024-11-30")
        assertEquals(date("2025-02-28"), Renewals.nextAfter(anchor, 3, CycleUnit.MONTHS, anchor))
        assertEquals(date("2025-05-30"), Renewals.nextAfter(anchor, 3, CycleUnit.MONTHS, date("2025-02-28")))
    }

    private fun monthly(next: String, anchor: String = next) = Subscription(
        name = "Test",
        currency = "USD",
        nextRenewal = date(next),
        anchorDate = date(anchor),
    )

    @Test
    fun advanceOnRenewalDayMovesOnePeriod() {
        val advanced = Renewals.advance(monthly("2025-05-15"), today = date("2025-05-15"))
        assertEquals(date("2025-06-15"), advanced.nextRenewal)
    }

    @Test
    fun advanceEarlyMovesOnePeriod() {
        val advanced = Renewals.advance(monthly("2025-05-15"), today = date("2025-05-01"))
        assertEquals(date("2025-06-15"), advanced.nextRenewal)
    }

    @Test
    fun advanceLongOverdueCatchesUpToToday() {
        val advanced = Renewals.advance(monthly("2025-01-15"), today = date("2025-04-20"))
        assertEquals(date("2025-05-15"), advanced.nextRenewal)
    }

    @Test
    fun advanceKeepsMonthEndAnchor() {
        val advanced = Renewals.advance(monthly("2025-02-28", anchor = "2025-01-31"), today = date("2025-02-28"))
        assertEquals(date("2025-03-31"), advanced.nextRenewal)
    }

    @Test
    fun monthlyCostNormalisesCycles() {
        assertEquals(0, BigDecimal("10").compareTo(Renewals.monthlyCost(BigDecimal("120"), 1, CycleUnit.YEARS)))
        assertEquals(0, BigDecimal("5").compareTo(Renewals.monthlyCost(BigDecimal("15"), 3, CycleUnit.MONTHS)))
    }
}
