//
//  SpendingAnalyticsService.swift
//  Menej
//
//  The pure statistical core behind the analytics dashboard — see PRD §6 F8.
//  Operates on `AnalyticsEntry` values (not SwiftData models) so it compiles
//  under the CLT swiftc harness and is unit-testable without a ModelContainer,
//  the same discipline as InsightService. InsightsViewModel does the
//  SwiftData-coupled projection (dedup, transfer exclusion) into these values.
//
//  "Expense" here means real consumption: a debit in a burn-spend category
//  (Category.isBurnSpend — excludes transfers, investment top-ups, income).
//  "Income" is any credit. Transfers between the user's own accounts are
//  dropped upstream and never reach this service.
//

import Foundation

/// One projected transaction, already deduplicated and transfer-filtered by
/// the caller. `amount` is a positive magnitude; `direction` gives its sign.
struct AnalyticsEntry {
    let date: Date
    let amount: Decimal
    let direction: Direction
    let category: Category
    let merchant: String?

    /// Real outbound spend: money out, in a consumption category.
    var isExpense: Bool { direction == .debit && category.isBurnSpend }
    var isIncome: Bool { direction == .credit }
}

struct CategorySpend: Identifiable {
    let category: Category
    let total: Decimal
    /// Fraction of the period's total expense, 0...1.
    let share: Double
    var id: Category { category }
}

struct SpendBucket: Identifiable {
    /// Start of the bucket (a day or a month, per AnalyticsPeriod.bucketComponent).
    let start: Date
    let total: Decimal
    let byCategory: [Category: Decimal]
    var id: Date { start }
}

struct CategoryDelta: Identifiable {
    let category: Category
    let current: Decimal
    let previous: Decimal
    /// (current - previous) / previous, or nil when previous is 0 (no
    /// baseline — a brand-new category can't be expressed as a percentage).
    let deltaFraction: Double?
    var id: Category { category }
}

struct PeriodComparison {
    let currentTotal: Decimal
    let previousTotal: Decimal
    /// nil when there's no prior period (`.all`) or no prior spend.
    let deltaFraction: Double?
    let categoryDeltas: [CategoryDelta]
}

struct Cashflow {
    let income: Decimal
    let expense: Decimal
    var net: Decimal { income - expense }
    /// (income - expense) / income, or nil when there's no income to save from.
    let savingsRate: Double?
}

protocol SpendingAnalyticsServiceProtocol {
    func expenseTotal(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Decimal
    func categoryBreakdown(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [CategorySpend]
    func timeSeries(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [SpendBucket]
    func comparison(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> PeriodComparison
    func largestExpenses(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date, limit: Int) -> [AnalyticsEntry]
    func cashflow(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Cashflow
}

struct SpendingAnalyticsService: SpendingAnalyticsServiceProtocol {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Windowing

    /// Entries falling inside the period's window. `.all` (nil range) returns
    /// everything.
    private func entriesInPeriod(_ entries: [AnalyticsEntry], _ period: AnalyticsPeriod, _ asOf: Date) -> [AnalyticsEntry] {
        guard let range = period.dateRange(reference: asOf, calendar: calendar) else { return entries }
        return entries.filter { range.contains($0.date) }
    }

    private func entriesInPreviousPeriod(_ entries: [AnalyticsEntry], _ period: AnalyticsPeriod, _ asOf: Date) -> [AnalyticsEntry] {
        guard let range = period.previousDateRange(reference: asOf, calendar: calendar) else { return [] }
        return entries.filter { range.contains($0.date) }
    }

    // MARK: - Totals

    func expenseTotal(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Decimal {
        entriesInPeriod(entries, period, asOf)
            .filter(\.isExpense)
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    func cashflow(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Cashflow {
        let scoped = entriesInPeriod(entries, period, asOf)
        let income = scoped.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        let expense = scoped.filter(\.isExpense).reduce(Decimal(0)) { $0 + $1.amount }
        let savingsRate: Double?
        if income > 0 {
            let net = income - expense
            savingsRate = NSDecimalNumber(decimal: net).doubleValue / NSDecimalNumber(decimal: income).doubleValue
        } else {
            savingsRate = nil
        }
        return Cashflow(income: income, expense: expense, savingsRate: savingsRate)
    }

    // MARK: - Category breakdown

    func categoryBreakdown(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [CategorySpend] {
        let expenses = entriesInPeriod(entries, period, asOf).filter(\.isExpense)
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        guard total > 0 else { return [] }

        let totalDouble = NSDecimalNumber(decimal: total).doubleValue
        return Dictionary(grouping: expenses, by: \.category)
            .map { category, group in
                let categoryTotal = group.reduce(Decimal(0)) { $0 + $1.amount }
                let share = NSDecimalNumber(decimal: categoryTotal).doubleValue / totalDouble
                return CategorySpend(category: category, total: categoryTotal, share: share)
            }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Time series

    func timeSeries(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [SpendBucket] {
        let expenses = entriesInPeriod(entries, period, asOf).filter(\.isExpense)
        let component = period.bucketComponent

        var totals: [Date: Decimal] = [:]
        var byCategory: [Date: [Category: Decimal]] = [:]
        for entry in expenses {
            let key = bucketStart(for: entry.date, component: component)
            totals[key, default: 0] += entry.amount
            byCategory[key, default: [:]][entry.category, default: 0] += entry.amount
        }

        return totals.keys.sorted().map { key in
            SpendBucket(start: key, total: totals[key] ?? 0, byCategory: byCategory[key] ?? [:])
        }
    }

    private func bucketStart(for date: Date, component: Calendar.Component) -> Date {
        switch component {
        case .day:
            return calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        default:
            return calendar.startOfDay(for: date)
        }
    }

    // MARK: - Comparison

    func comparison(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> PeriodComparison {
        let current = entriesInPeriod(entries, period, asOf).filter(\.isExpense)
        let previous = entriesInPreviousPeriod(entries, period, asOf).filter(\.isExpense)

        let currentTotal = current.reduce(Decimal(0)) { $0 + $1.amount }
        let previousTotal = previous.reduce(Decimal(0)) { $0 + $1.amount }

        let currentByCategory = totalsByCategory(current)
        let previousByCategory = totalsByCategory(previous)

        let categoryDeltas: [CategoryDelta] = Category.allCases.compactMap { category in
            let cur = currentByCategory[category] ?? 0
            let prev = previousByCategory[category] ?? 0
            guard cur > 0 || prev > 0 else { return nil }
            return CategoryDelta(category: category, current: cur, previous: prev, deltaFraction: Self.fraction(cur, over: prev))
        }
        .sorted { $0.current > $1.current }

        return PeriodComparison(
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            deltaFraction: Self.fraction(currentTotal, over: previousTotal),
            categoryDeltas: categoryDeltas
        )
    }

    private func totalsByCategory(_ entries: [AnalyticsEntry]) -> [Category: Decimal] {
        entries.reduce(into: [:]) { $0[$1.category, default: 0] += $1.amount }
    }

    /// (current - baseline) / baseline; nil when baseline is 0.
    private static func fraction(_ current: Decimal, over baseline: Decimal) -> Double? {
        guard baseline > 0 else { return nil }
        let delta = current - baseline
        return NSDecimalNumber(decimal: delta).doubleValue / NSDecimalNumber(decimal: baseline).doubleValue
    }

    // MARK: - Largest

    func largestExpenses(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date, limit: Int) -> [AnalyticsEntry] {
        entriesInPeriod(entries, period, asOf)
            .filter(\.isExpense)
            .sorted { $0.amount > $1.amount }
            .prefix(limit)
            .map { $0 }
    }
}
