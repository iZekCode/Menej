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

/// Spend at one counterparty. The dashboard has never needed this — it thinks
/// in categories — but "how much have I spent at Dapoer Cowek" is the most
/// natural question to ask the app in words, so FinanceQueryService does.
struct MerchantSpend: Identifiable {
    /// Display casing, as it appears on the transactions.
    let merchant: String
    let total: Decimal
    /// How many transactions make up `total` — "9 visits" is often the more
    /// interesting half of the answer.
    let count: Int
    var id: String { merchant }
}

protocol SpendingAnalyticsServiceProtocol {
    // Fixed dashboard periods.
    func expenseTotal(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Decimal
    func categoryBreakdown(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [CategorySpend]
    func timeSeries(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [SpendBucket]
    func comparison(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> PeriodComparison
    func largestExpenses(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date, limit: Int) -> [AnalyticsEntry]
    func cashflow(entries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Cashflow

    // Arbitrary windows. `nil` means all time, matching `AnalyticsPeriod.all`.
    // The period-based methods above are wrappers over these — a question
    // asked in words ("March through May") has no AnalyticsPeriod case to
    // resolve to.
    func expenseTotal(entries: [AnalyticsEntry], in range: Range<Date>?) -> Decimal
    func categoryBreakdown(entries: [AnalyticsEntry], in range: Range<Date>?) -> [CategorySpend]
    func largestExpenses(entries: [AnalyticsEntry], in range: Range<Date>?, limit: Int) -> [AnalyticsEntry]
    func cashflow(entries: [AnalyticsEntry], in range: Range<Date>?) -> Cashflow
    func merchantBreakdown(entries: [AnalyticsEntry], in range: Range<Date>?, limit: Int) -> [MerchantSpend]

    /// Distinct merchant names containing `query`, case- and
    /// diacritic-insensitively. Callers resolve a user-supplied (or
    /// model-supplied) name through this *before* totalling anything: an empty
    /// result means the merchant isn't in the data, which has to be reported
    /// as such rather than answered with a zero.
    func merchantMatches(entries: [AnalyticsEntry], query: String) -> [String]
}

struct SpendingAnalyticsService: SpendingAnalyticsServiceProtocol {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Windowing

    /// Entries falling inside a window. `nil` returns everything.
    private func entries(_ entries: [AnalyticsEntry], in range: Range<Date>?) -> [AnalyticsEntry] {
        guard let range else { return entries }
        return entries.filter { range.contains($0.date) }
    }

    /// Entries falling inside the period's window. `.all` (nil range) returns
    /// everything.
    private func entriesInPeriod(_ allEntries: [AnalyticsEntry], _ period: AnalyticsPeriod, _ asOf: Date) -> [AnalyticsEntry] {
        entries(allEntries, in: period.dateRange(reference: asOf, calendar: calendar))
    }

    private func entriesInPreviousPeriod(_ allEntries: [AnalyticsEntry], _ period: AnalyticsPeriod, _ asOf: Date) -> [AnalyticsEntry] {
        guard let range = period.previousDateRange(reference: asOf, calendar: calendar) else { return [] }
        return allEntries.filter { range.contains($0.date) }
    }

    // MARK: - Period wrappers
    //
    // Each resolves its period to a window and delegates to the range-based
    // implementation below, so the dashboard and the chat can never drift into
    // computing the same figure two different ways.

    func expenseTotal(entries allEntries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Decimal {
        expenseTotal(entries: allEntries, in: period.dateRange(reference: asOf, calendar: calendar))
    }

    func cashflow(entries allEntries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> Cashflow {
        cashflow(entries: allEntries, in: period.dateRange(reference: asOf, calendar: calendar))
    }

    func categoryBreakdown(entries allEntries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date) -> [CategorySpend] {
        categoryBreakdown(entries: allEntries, in: period.dateRange(reference: asOf, calendar: calendar))
    }

    func largestExpenses(entries allEntries: [AnalyticsEntry], period: AnalyticsPeriod, asOf: Date, limit: Int) -> [AnalyticsEntry] {
        largestExpenses(entries: allEntries, in: period.dateRange(reference: asOf, calendar: calendar), limit: limit)
    }

    // MARK: - Totals

    func expenseTotal(entries allEntries: [AnalyticsEntry], in range: Range<Date>?) -> Decimal {
        entries(allEntries, in: range)
            .filter(\.isExpense)
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    func cashflow(entries allEntries: [AnalyticsEntry], in range: Range<Date>?) -> Cashflow {
        let scoped = entries(allEntries, in: range)
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

    func categoryBreakdown(entries allEntries: [AnalyticsEntry], in range: Range<Date>?) -> [CategorySpend] {
        let expenses = entries(allEntries, in: range).filter(\.isExpense)
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

    func largestExpenses(entries allEntries: [AnalyticsEntry], in range: Range<Date>?, limit: Int) -> [AnalyticsEntry] {
        entries(allEntries, in: range)
            .filter(\.isExpense)
            .sorted { $0.amount > $1.amount }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Merchants

    func merchantBreakdown(entries allEntries: [AnalyticsEntry], in range: Range<Date>?, limit: Int) -> [MerchantSpend] {
        let expenses = entries(allEntries, in: range).filter(\.isExpense)

        // Grouped on a folded key but displayed with the casing that actually
        // appears: merchant strings arrive from CategorizationService's
        // dictionary and from the on-device enhancement pass, which don't
        // agree on capitalization, so "Indomaret" and "INDOMARET" are one
        // counterparty and must not become two rows.
        var totals: [String: (display: String, total: Decimal, count: Int)] = [:]
        for entry in expenses {
            let display = entry.merchant?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = display.isEmpty ? Self.unknownMerchant : display
            let key = Self.foldedKey(name)
            let existing = totals[key]
            totals[key] = (
                display: existing?.display ?? name,
                total: (existing?.total ?? 0) + entry.amount,
                count: (existing?.count ?? 0) + 1
            )
        }

        return totals.values
            .map { MerchantSpend(merchant: $0.display, total: $0.total, count: $0.count) }
            .sorted { $0.total > $1.total }
            .prefix(limit)
            .map { $0 }
    }

    func merchantMatches(entries allEntries: [AnalyticsEntry], query: String) -> [String] {
        let needle = Self.foldedKey(query)
        guard !needle.isEmpty else { return [] }

        var seen = Set<String>()
        var matches: [String] = []
        for entry in allEntries {
            guard let merchant = entry.merchant?.trimmingCharacters(in: .whitespaces), !merchant.isEmpty else { continue }
            let key = Self.foldedKey(merchant)
            guard key.contains(needle), !seen.contains(key) else { continue }
            seen.insert(key)
            matches.append(merchant)
        }
        // Exact matches first: "Indomaret" shouldn't rank below
        // "Indomaret Alam Sutera" just because of iteration order.
        return matches.sorted { lhs, rhs in
            let lhsExact = Self.foldedKey(lhs) == needle
            let rhsExact = Self.foldedKey(rhs) == needle
            if lhsExact != rhsExact { return lhsExact }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    static let unknownMerchant = "Unknown"

    /// Case- and diacritic-insensitive comparison key. Not a display value.
    private static func foldedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
