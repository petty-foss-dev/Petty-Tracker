package com.isaaclamb.pettytracker.domain

import com.isaaclamb.pettytracker.data.CycleUnit
import com.isaaclamb.pettytracker.data.Subscription
import java.math.BigDecimal
import java.math.MathContext
import java.time.LocalDate
import java.time.temporal.ChronoUnit

object Renewals {
    /** The [n]th renewal counted from [anchor]; month and year steps clamp to the last valid day. */
    fun occurrence(anchor: LocalDate, count: Int, unit: CycleUnit, n: Long): LocalDate {
        val steps = count.toLong() * n
        return when (unit) {
            CycleUnit.DAYS -> anchor.plusDays(steps)
            CycleUnit.WEEKS -> anchor.plusWeeks(steps)
            CycleUnit.MONTHS -> anchor.plusMonths(steps)
            CycleUnit.YEARS -> anchor.plusYears(steps)
        }
    }

    /** First scheduled renewal strictly after [after]. */
    fun nextAfter(anchor: LocalDate, count: Int, unit: CycleUnit, after: LocalDate): LocalDate {
        if (anchor.isAfter(after)) return anchor
        val chrono = when (unit) {
            CycleUnit.DAYS -> ChronoUnit.DAYS
            CycleUnit.WEEKS -> ChronoUnit.WEEKS
            CycleUnit.MONTHS -> ChronoUnit.MONTHS
            CycleUnit.YEARS -> ChronoUnit.YEARS
        }
        var n = maxOf(0L, chrono.between(anchor, after) / count - 1)
        var date = occurrence(anchor, count, unit, n)
        while (!date.isAfter(after)) {
            n++
            date = occurrence(anchor, count, unit, n)
        }
        return date
    }

    /**
     * Marks the current renewal as paid. A long-overdue schedule catches up to today rather than
     * stepping one period at a time.
     */
    fun advance(subscription: Subscription, today: LocalDate): Subscription {
        val from = maxOf(subscription.nextRenewal, today.minusDays(1))
        val next = nextAfter(subscription.anchorDate, subscription.cycleCount, subscription.cycleUnit, from)
        return subscription.copy(nextRenewal = next)
    }

    fun monthlyCost(price: BigDecimal, count: Int, unit: CycleUnit): BigDecimal {
        val periodsPerMonth = when (unit) {
            CycleUnit.DAYS -> BigDecimal("30.436875")
            CycleUnit.WEEKS -> BigDecimal("4.348125")
            CycleUnit.MONTHS -> BigDecimal.ONE
            CycleUnit.YEARS -> BigDecimal.ONE.divide(BigDecimal(12), MathContext.DECIMAL64)
        }
        return price.multiply(periodsPerMonth).divide(BigDecimal(count), MathContext.DECIMAL64)
    }
}
