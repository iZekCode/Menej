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
//  call it from a plain computed property and let SwiftUI's own reactivity
//  handle refreshing.
//
//  This ViewModel's only real job is the SwiftData-coupled projection from
//  `Transaction` into the pure `SpendEntry` values InsightService consumes;
//  all the statistics (month bucketing, partial-month handling, averaging,
//  anomaly detection) live in InsightService so they're testable without a
//  ModelContainer.
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
        /// PRD §6 F8 — anomaly detection requires at least 2 complete months
        /// of data; the View hides that section entirely (not an empty
        /// placeholder) when this is false.
        let hasEnoughDataForAnomalies: Bool
    }

    // See ImportViewModel.swift for why the default is built in the body.
    init(insightService: InsightServiceProtocol? = nil) {
        self.insightService = insightService ?? InsightService()
    }

    func summarize(transactions: [Transaction], liquidAssets: Decimal, now: Date = .now) -> SpendSummary {
        let entries = Self.spendEntries(from: transactions)

        let runwayMonths: Double?
        if let averageMonthlySpend = insightService.averageMonthlySpend(entries: entries, asOf: now) {
            runwayMonths = insightService.runwayMonths(liquidAssets: liquidAssets, averageMonthlySpend: averageMonthlySpend)
        } else {
            runwayMonths = nil
        }

        let anomalies = insightService.anomalies(entries: entries, asOf: now)
        let completeMonths = Self.distinctCompleteMonthCount(in: entries, now: now)

        return SpendSummary(
            runwayMonths: runwayMonths,
            anomalies: anomalies,
            hasEnoughDataForAnomalies: completeMonths >= 2
        )
    }

    /// Projects transactions into the burn-spend entries InsightService
    /// consumes. Excludes:
    ///  - credits and transfers between the user's own accounts (PRD §6 F4);
    ///  - the second half of a confirmed duplicate-expense pair (same event
    ///    from two sources, e.g. a Grab ride paid via GoPay), counted once
    ///    via `dedupGroupId`;
    ///  - non-consumption categories (transfers, investment top-ups, income)
    ///    — see Category.isBurnSpend.
    private static func spendEntries(from transactions: [Transaction]) -> [SpendEntry] {
        var seenGroups = Set<UUID>()
        var entries: [SpendEntry] = []
        for transaction in transactions {
            guard transaction.direction == .debit, !transaction.isTransfer else { continue }
            let category = transaction.categoryId ?? .other
            guard category.isBurnSpend else { continue }
            if let groupId = transaction.dedupGroupId {
                guard !seenGroups.contains(groupId) else { continue }
                seenGroups.insert(groupId)
            }
            entries.append(SpendEntry(date: transaction.date, amount: transaction.amount, category: category))
        }
        return entries
    }

    private static func distinctCompleteMonthCount(in entries: [SpendEntry], now: Date) -> Int {
        let calendar = Calendar.current
        let currentMonth = calendar.dateComponents([.year, .month], from: now)
        let months = Set(entries.map { calendar.dateComponents([.year, .month], from: $0.date) })
        return months.filter { $0 != currentMonth }.count
    }
}
