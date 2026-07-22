//
//  InsightsViewModel.swift
//  Menej
//
//  Drives the month-by-month analytics dashboard (InsightsView) — see PRD §6
//  F8. Insights are withheld (empty) until the data supports them.
//
//  The ViewModel is stateless: every statistic is computed fresh from the live
//  `@Query` arrays on each call (see NetWorthViewModel.swift for why caching
//  via `.onAppear` goes stale). Its only job is the SwiftData-coupled
//  projection Transaction → [AnalyticsEntry] (dedup, transfer exclusion); all
//  the statistics live in the pure SpendingAnalyticsService.
//

import Foundation
import Observation

@Observable
@MainActor
final class InsightsViewModel {
    private let analyticsService: SpendingAnalyticsServiceProtocol

    // See ImportViewModel.swift for why the default is built in the body.
    init(analyticsService: SpendingAnalyticsServiceProtocol? = nil) {
        self.analyticsService = analyticsService ?? SpendingAnalyticsService()
    }

    // MARK: - Analytics (pure, recomputed inline)

    struct Analytics {
        let expenseTotal: Decimal
        let breakdown: [CategorySpend]
        let timeSeries: [SpendBucket]
        let comparison: PeriodComparison
        let cashflow: Cashflow
        let largestExpenses: [AnalyticsEntry]
        var hasData: Bool { expenseTotal > 0 || cashflow.income > 0 }
    }

    /// Analytics for `period` relative to `reference`. For `.singleMonth` the
    /// reference is the selected month (any day in it); for the aggregate
    /// windows (W/6M/Y/All) it's "now".
    func analytics(transactions: [Transaction], period: AnalyticsPeriod, reference: Date) -> Analytics {
        let entries = Self.analyticsEntries(from: transactions)
        return Analytics(
            expenseTotal: analyticsService.expenseTotal(entries: entries, period: period, asOf: reference),
            breakdown: analyticsService.categoryBreakdown(entries: entries, period: period, asOf: reference),
            timeSeries: analyticsService.timeSeries(entries: entries, period: period, asOf: reference),
            comparison: analyticsService.comparison(entries: entries, period: period, asOf: reference),
            cashflow: analyticsService.cashflow(entries: entries, period: period, asOf: reference),
            largestExpenses: analyticsService.largestExpenses(entries: entries, period: period, asOf: reference, limit: 5)
        )
    }

    /// Expenses for one category in the period, most recent first — for the
    /// drill-down view.
    func expenses(in category: Category, transactions: [Transaction], period: AnalyticsPeriod, reference: Date) -> [AnalyticsEntry] {
        let entries = Self.analyticsEntries(from: transactions)
        let scoped: [AnalyticsEntry]
        if let range = period.dateRange(reference: reference) {
            scoped = entries.filter { range.contains($0.date) }
        } else {
            scoped = entries
        }
        return scoped
            .filter { $0.isExpense && $0.category == category }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Projection

    /// Transaction → AnalyticsEntry: excludes transfers between the user's own
    /// accounts (PRD §6 F4) and counts a confirmed duplicate-expense pair once
    /// via `dedupGroupId`. Keeps both debits and credits so cashflow/income can
    /// be computed; the burn-spend narrowing happens in AnalyticsEntry.isExpense.
    private static func analyticsEntries(from transactions: [Transaction]) -> [AnalyticsEntry] {
        var seenGroups = Set<UUID>()
        var entries: [AnalyticsEntry] = []
        for transaction in transactions {
            guard !transaction.isTransferLike else { continue }
            if let groupId = transaction.dedupGroupId {
                guard !seenGroups.contains(groupId) else { continue }
                seenGroups.insert(groupId)
            }
            entries.append(AnalyticsEntry(
                date: transaction.date,
                amount: transaction.amount,
                direction: transaction.direction,
                category: transaction.categoryId ?? .other,
                merchant: transaction.merchant
            ))
        }
        return entries
    }
}
