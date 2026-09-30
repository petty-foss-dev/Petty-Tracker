import Foundation

enum Renewals {
    /// The `n`th renewal counted from `anchor`; month and year steps clamp to the last valid day.
    static func occurrence(anchor: Day, count: Int, unit: CycleUnit, n: Int) -> Day {
        let steps = count * n
        return switch unit {
        case .days: anchor.adding(days: steps)
        case .weeks: anchor.adding(days: steps * 7)
        case .months: anchor.adding(months: steps)
        case .years: anchor.adding(months: steps * 12)
        }
    }

    /// First scheduled renewal strictly after `after`.
    static func nextAfter(anchor: Day, count: Int, unit: CycleUnit, after: Day) -> Day {
        if anchor > after { return anchor }
        let elapsed = switch unit {
        case .days: anchor.days(until: after)
        case .weeks: anchor.days(until: after) / 7
        case .months: anchor.months(until: after)
        case .years: anchor.months(until: after) / 12
        }
        var n = max(0, elapsed / count - 1)
        var date = occurrence(anchor: anchor, count: count, unit: unit, n: n)
        while date <= after {
            n += 1
            date = occurrence(anchor: anchor, count: count, unit: unit, n: n)
        }
        return date
    }

    /// Marks the current renewal as paid. A long-overdue schedule catches up to today rather than
    /// stepping one period at a time.
    static func advance(_ subscription: Subscription, today: Day) -> Subscription {
        let from = max(subscription.nextRenewal, today.adding(days: -1))
        var renewed = subscription
        renewed.nextRenewal = nextAfter(
            anchor: subscription.anchorDate, count: subscription.cycleCount, unit: subscription.cycleUnit, after: from
        )
        return renewed
    }

    static func reactivate(_ subscription: Subscription, today: Day) -> Subscription {
        var active = subscription
        active.canceledOn = nil
        if subscription.nextRenewal < today {
            active.nextRenewal = nextAfter(
                anchor: subscription.anchorDate, count: subscription.cycleCount, unit: subscription.cycleUnit,
                after: today.adding(days: -1)
            )
        }
        return active
    }

    static func monthlyCost(price: Decimal, count: Int, unit: CycleUnit) -> Decimal {
        let periods = Decimal(count)
        return switch unit {
        case .days: price * Decimal(string: "30.436875")! / periods
        case .weeks: price * Decimal(string: "4.348125")! / periods
        case .months: price / periods
        case .years: price / (12 * periods)
        }
    }

    /// Estimated monthly spend of active subscriptions, per currency.
    static func monthlyTotals(_ subscriptions: [Subscription]) -> [(currency: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for subscription in subscriptions where subscription.isActive {
            guard let price = subscription.price else { continue }
            totals[subscription.currency, default: 0] +=
                monthlyCost(price: price, count: subscription.cycleCount, unit: subscription.cycleUnit)
        }
        return totals.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
