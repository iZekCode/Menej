//
//  InsightService.swift
//  Menej
//
//  See PRD §6 F8. Insights must be withheld until the data supports them —
//  a wrong insight in week one does more damage than no insight at all.
//  All computation is rules-based and statistical, on-device. No LLM in v1.
//
//  This is the pure statistical core: it operates on `SpendEntry` values
//  (date + amount + category), not SwiftData models, so it stays
//  typecheckable with the CLT-only swiftc harness and unit-testable without
//  a ModelContainer. InsightsViewModel does the SwiftData-coupled projection
//  (dedup, transfer filtering) from `Transaction` into `[SpendEntry]`.
//
//  Two deliberate anti-"wrong insight" rules run through everything here:
//    1. The current calendar month is partial and is excluded from every
//       average and comparison — a mid-month total is not a monthly total.
//       Runway falls back to prorating a sole partial month only once enough
//       of it has elapsed, otherwise it withholds.
//    2. Anomalies compare the latest *complete* month against earlier
//       complete months, gated by an absolute rupiah floor so a tiny
//       category doubling doesn't raise an alarm.
//

import Foundation

/// One unit of real consumption, already filtered by the caller (debit,
/// non-transfer, deduplicated, burn-spend category).
struct SpendEntry {
    let date: Date
    /// Positive magnitude in IDR.
    let amount: Decimal
    let category: Category
}

struct CategoryAnomaly {
    let category: Category
    /// First day of the (complete) month the anomaly was found in — the view
    /// names it ("Transport in June…") rather than saying "this month",
    /// which would be dishonest when the latest complete month isn't the
    /// current calendar month.
    let month: Date
    let currentAmount: Decimal
    let averageAmount: Decimal
    let ratio: Double
}

protocol InsightServiceProtocol {
    /// Runway in months. Requires only liquid assets and average spend.
    func runwayMonths(liquidAssets: Decimal, averageMonthlySpend: Decimal) -> Double?

    /// Average monthly *burn* over complete months, or nil to withhold.
    /// Works with a single month of data (PRD §6 F8) by prorating a
    /// sufficiently-elapsed sole partial month; withholds when the only data
    /// is a barely-started month, since projecting from a few days overstates.
    func averageMonthlySpend(entries: [SpendEntry], asOf: Date) -> Decimal?

    /// Spending anomalies for the latest complete month vs earlier complete
    /// months. Empty until there are at least 2 complete months; the caller
    /// hides the module entirely (not an empty placeholder) until then.
    func anomalies(entries: [SpendEntry], asOf: Date) -> [CategoryAnomaly]
}

struct InsightService: InsightServiceProtocol {
    /// Anomaly flagged when current spend reaches this multiple of the average.
    let anomalyRatioThreshold: Double = 2.0
    /// Below this, a category's spike isn't worth surfacing however large the
    /// ratio — a Rp 5k average tripling to Rp 15k is noise, not an insight.
    let minimumAnomalyAmount: Decimal = 100_000
    /// A sole partial month is only projected once at least this fraction of
    /// it has elapsed; earlier than that, runway is withheld.
    let minimumElapsedFractionForProration: Double = 0.5

    private static let calendar = Calendar.current

    // MARK: - Runway

    func runwayMonths(liquidAssets: Decimal, averageMonthlySpend: Decimal) -> Double? {
        guard averageMonthlySpend > 0 else { return nil }
        let liquid = NSDecimalNumber(decimal: liquidAssets).doubleValue
        let spend = NSDecimalNumber(decimal: averageMonthlySpend).doubleValue
        return liquid / spend
    }

    func averageMonthlySpend(entries: [SpendEntry], asOf: Date) -> Decimal? {
        let totals = Self.monthlyTotals(entries)
        guard !totals.isEmpty else { return nil }

        let currentKey = Self.monthKey(for: asOf)
        let completeMonthTotals = totals.filter { $0.key != currentKey }.map(\.value)
        if !completeMonthTotals.isEmpty {
            let sum = completeMonthTotals.reduce(Decimal(0), +)
            return sum / Decimal(completeMonthTotals.count)
        }

        // Only the current, partial month has data — project it to a full
        // month if enough has elapsed to be meaningful, else withhold.
        guard let partialTotal = totals[currentKey] else { return nil }
        let fraction = Self.elapsedFractionOfMonth(asOf: asOf)
        guard fraction >= minimumElapsedFractionForProration else { return nil }
        return partialTotal / Decimal(fraction)
    }

    // MARK: - Anomalies

    func anomalies(entries: [SpendEntry], asOf: Date) -> [CategoryAnomaly] {
        let currentKey = Self.monthKey(for: asOf)
        let buckets = Self.monthlyCategoryTotals(entries).filter { $0.key != currentKey }
        let orderedKeys = buckets.keys.sorted(by: Self.monthKeyIsBefore)
        guard orderedKeys.count >= 2, let latestKey = orderedKeys.last else { return [] }

        let latest = buckets[latestKey] ?? [:]
        let historicalKeys = orderedKeys.dropLast()

        var result: [CategoryAnomaly] = []
        for category in Category.allCases where category.isBurnSpend && category != .other {
            let current = latest[category] ?? 0
            guard current >= minimumAnomalyAmount else { continue }

            // Average over every historical complete month, counting months
            // where the category was absent as zero. A brand-new category
            // (historical average 0) is deliberately not flagged — a first
            // appearance isn't an anomaly against your own history.
            let historicalSum = historicalKeys.reduce(Decimal(0)) { $0 + (buckets[$1]?[category] ?? 0) }
            let average = historicalSum / Decimal(historicalKeys.count)
            guard average > 0 else { continue }

            let ratio = NSDecimalNumber(decimal: current).doubleValue / NSDecimalNumber(decimal: average).doubleValue
            guard ratio >= anomalyRatioThreshold else { continue }

            result.append(CategoryAnomaly(
                category: category,
                month: Self.startOfMonth(latestKey) ?? asOf,
                currentAmount: current,
                averageAmount: average,
                ratio: ratio
            ))
        }
        return result.sorted { $0.ratio > $1.ratio }
    }

    // MARK: - Month math

    private static func monthKey(for date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month], from: date)
    }

    private static func startOfMonth(_ key: DateComponents) -> Date? {
        calendar.date(from: DateComponents(year: key.year, month: key.month, day: 1))
    }

    private static func monthKeyIsBefore(_ lhs: DateComponents, _ rhs: DateComponents) -> Bool {
        (lhs.year ?? 0, lhs.month ?? 0) < (rhs.year ?? 0, rhs.month ?? 0)
    }

    private static func monthlyTotals(_ entries: [SpendEntry]) -> [DateComponents: Decimal] {
        var totals: [DateComponents: Decimal] = [:]
        for entry in entries {
            totals[monthKey(for: entry.date), default: 0] += entry.amount
        }
        return totals
    }

    private static func monthlyCategoryTotals(_ entries: [SpendEntry]) -> [DateComponents: [Category: Decimal]] {
        var buckets: [DateComponents: [Category: Decimal]] = [:]
        for entry in entries {
            buckets[monthKey(for: entry.date), default: [:]][entry.category, default: 0] += entry.amount
        }
        return buckets
    }

    /// Fraction of the calendar month containing `asOf` that has elapsed,
    /// in (0, 1]. Used to project a sole partial month to a full-month figure.
    private static func elapsedFractionOfMonth(asOf: Date) -> Double {
        guard let interval = calendar.dateInterval(of: .month, for: asOf) else { return 1 }
        let elapsed = asOf.timeIntervalSince(interval.start)
        let span = interval.end.timeIntervalSince(interval.start)
        guard span > 0 else { return 1 }
        return max(0, min(1, elapsed / span))
    }
}
