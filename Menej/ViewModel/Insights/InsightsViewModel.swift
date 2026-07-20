//
//  InsightsViewModel.swift
//  Menej
//
//  Drives InsightsView — see PRD §6 F8. Insights are withheld (nil / empty),
//  never shown wrong or as an empty placeholder, until data supports them.
//
//  Deliberately stateless — see NetWorthViewModel.swift for why: computing
//  once via `.onAppear` into cached `@Observable` properties goes stale the
//  moment the underlying transactions change. `summarize` takes the live
//  `@Query` results and recomputes fresh every call, so InsightsView can
//  call it from a plain computed property and let SwiftUI's own
//  reactivity handle refreshing.
//

import Foundation
import Observation

@Observable
@MainActor
final class InsightsViewModel {
    private let insightService: InsightServiceProtocol

    struct SpendSummary {
        let runwayMonths: Double?
        let anomalies: [CategoryAnomaly]
        /// PRD §6 F8 — anomaly detection requires at least 2 months of
        /// data; the View hides that section entirely (not an empty
        /// placeholder) when this is false.
        let hasEnoughDataForAnomalies: Bool
    }

    // See ImportViewModel.swift for why the default is built in the body.
    init(insightService: InsightServiceProtocol? = nil) {
        self.insightService = insightService ?? InsightService()
    }

    func summarize(transactions: [Transaction], liquidAssets: Decimal) -> SpendSummary {
        let spend = Self.realSpendTransactions(from: transactions)
        let months = Self.distinctMonths(in: spend)

        let averageMonthlySpend: Decimal = months.isEmpty ? 0 :
            months.reduce(Decimal(0)) { $0 + Self.total(for: spend, inMonth: $1) } / Decimal(months.count)
        let runwayMonths = insightService.runwayMonths(liquidAssets: liquidAssets, averageMonthlySpend: averageMonthlySpend)

        guard months.count >= 2, let currentMonth = months.last else {
            return SpendSummary(runwayMonths: runwayMonths, anomalies: [], hasEnoughDataForAnomalies: false)
        }
        let historicalMonths = months.dropLast()

        let currentByCategory = Self.categoryTotals(for: spend, inMonth: currentMonth)
        var historicalByCategory: [Category: Decimal] = [:]
        for category in Category.allCases {
            let totals = historicalMonths.map { Self.categoryTotals(for: spend, inMonth: $0)[category] ?? 0 }
            let sum = totals.reduce(Decimal(0), +)
            guard sum > 0 else { continue }
            historicalByCategory[category] = sum / Decimal(totals.count)
        }

        let anomalies = insightService.anomalies(currentMonthByCategory: currentByCategory, historicalAverageByCategory: historicalByCategory)
        return SpendSummary(runwayMonths: runwayMonths, anomalies: anomalies, hasEnoughDataForAnomalies: true)
    }

    /// Real spend only: excludes transfers between the user's own accounts
    /// (see PRD §6 F4) and, for a confirmed duplicate-expense pair (same
    /// event recorded by two sources, e.g. a Grab ride paid via GoPay),
    /// counts it once via `dedupGroupId` rather than twice.
    private static func realSpendTransactions(from transactions: [Transaction]) -> [Transaction] {
        var seenGroups = Set<UUID>()
        return transactions.filter { transaction in
            guard transaction.direction == .debit, !transaction.isTransfer else { return false }
            if let groupId = transaction.dedupGroupId {
                guard !seenGroups.contains(groupId) else { return false }
                seenGroups.insert(groupId)
            }
            return true
        }
    }

    private static func monthKey(for date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month], from: date)
    }

    private static func distinctMonths(in transactions: [Transaction]) -> [DateComponents] {
        Set(transactions.map { monthKey(for: $0.date) }).sorted {
            guard let y1 = $0.year, let m1 = $0.month, let y2 = $1.year, let m2 = $1.month else { return false }
            return (y1, m1) < (y2, m2)
        }
    }

    private static func total(for transactions: [Transaction], inMonth month: DateComponents) -> Decimal {
        transactions
            .filter { monthKey(for: $0.date) == month }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private static func categoryTotals(for transactions: [Transaction], inMonth month: DateComponents) -> [Category: Decimal] {
        let inMonth = transactions.filter { monthKey(for: $0.date) == month }
        return Dictionary(grouping: inMonth, by: { $0.categoryId ?? .other })
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
    }
}
