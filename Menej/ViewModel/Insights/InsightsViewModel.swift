//
//  InsightsViewModel.swift
//  Menej
//
//  Drives the analytics dashboard (InsightsView) — see PRD §6 F8. Insights are
//  withheld (nil / empty), never shown wrong or as an empty placeholder, until
//  the data supports them.
//
//  The spend statistics are pure and stateless — computed fresh from the live
//  `@Query` arrays on every call (see NetWorthViewModel.swift for why caching
//  via `.onAppear` goes stale). This ViewModel's jobs are:
//    1. the SwiftData-coupled projection Transaction → [AnalyticsEntry]
//       (dedup, transfer exclusion), shared by every module and mapped down to
//       [SpendEntry] for the existing runway/anomaly logic in InsightService;
//    2. the ONE piece of real state here — the async, cached AI Highlights
//       generation, which must not re-run on every body evaluation.
//

import Foundation
import Observation

@Observable
@MainActor
final class InsightsViewModel {
    private let insightService: InsightServiceProtocol
    private let analyticsService: SpendingAnalyticsServiceProtocol
    private let narrativeService: InsightNarrativeServiceProtocol
    private let factsBuilder = HighlightFactsBuilder()

    /// Rendered highlight cards (template first, then AI-phrased). Kept in
    /// state because generation is async; everything else recomputes inline.
    var highlights: [InsightHighlightCard] = []
    private var highlightsSignature: Int?
    private var highlightsTask: Task<Void, Never>?

    // See ImportViewModel.swift for why the defaults are built in the body.
    init(
        insightService: InsightServiceProtocol? = nil,
        analyticsService: SpendingAnalyticsServiceProtocol? = nil,
        narrativeService: InsightNarrativeServiceProtocol? = nil
    ) {
        self.insightService = insightService ?? InsightService()
        self.analyticsService = analyticsService ?? SpendingAnalyticsService()
        self.narrativeService = narrativeService ?? InsightNarrativeService()
    }

    // MARK: - Analytics (pure, recomputed inline)

    struct Analytics {
        let period: AnalyticsPeriod
        let expenseTotal: Decimal
        let breakdown: [CategorySpend]
        let timeSeries: [SpendBucket]
        let comparison: PeriodComparison
        let cashflow: Cashflow
        let topMerchants: [MerchantSpend]
        let largestExpenses: [AnalyticsEntry]
        let runwayMonths: Double?
        let anomalies: [CategoryAnomaly]
        let hasEnoughDataForAnomalies: Bool
        var hasSpending: Bool { expenseTotal > 0 }
    }

    func analytics(
        transactions: [Transaction],
        liquidAssets: Decimal,
        period: AnalyticsPeriod,
        now: Date = .now
    ) -> Analytics {
        let entries = Self.analyticsEntries(from: transactions)
        let spendEntries = Self.spendEntries(from: entries)

        let runwayMonths: Double?
        if let avg = insightService.averageMonthlySpend(entries: spendEntries, asOf: now) {
            runwayMonths = insightService.runwayMonths(liquidAssets: liquidAssets, averageMonthlySpend: avg)
        } else {
            runwayMonths = nil
        }

        return Analytics(
            period: period,
            expenseTotal: analyticsService.expenseTotal(entries: entries, period: period, asOf: now),
            breakdown: analyticsService.categoryBreakdown(entries: entries, period: period, asOf: now),
            timeSeries: analyticsService.timeSeries(entries: entries, period: period, asOf: now),
            comparison: analyticsService.comparison(entries: entries, period: period, asOf: now),
            cashflow: analyticsService.cashflow(entries: entries, period: period, asOf: now),
            topMerchants: analyticsService.topMerchants(entries: entries, period: period, asOf: now, limit: 5),
            largestExpenses: analyticsService.largestExpenses(entries: entries, period: period, asOf: now, limit: 5),
            runwayMonths: runwayMonths,
            anomalies: insightService.anomalies(entries: spendEntries, asOf: now),
            hasEnoughDataForAnomalies: Self.distinctCompleteMonthCount(in: spendEntries, now: now) >= 2
        )
    }

    struct MonthSummary {
        let total: Decimal
        let top: [CategorySpend]
    }

    /// Compact this-month spend for the Ledger summary strip — reuses the same
    /// projection (dedup + transfer exclusion) as the dashboard so the two
    /// screens never disagree.
    func monthSummary(transactions: [Transaction], now: Date = .now) -> MonthSummary {
        let entries = Self.analyticsEntries(from: transactions)
        return MonthSummary(
            total: analyticsService.expenseTotal(entries: entries, period: .month, asOf: now),
            top: Array(analyticsService.categoryBreakdown(entries: entries, period: .month, asOf: now).prefix(3))
        )
    }

    /// Expenses for one category in the period, most recent first — for the
    /// drill-down view.
    func expenses(in category: Category, transactions: [Transaction], period: AnalyticsPeriod, now: Date = .now) -> [AnalyticsEntry] {
        let entries = Self.analyticsEntries(from: transactions)
        let scoped: [AnalyticsEntry]
        if let range = period.dateRange(reference: now) {
            scoped = entries.filter { range.contains($0.date) }
        } else {
            scoped = entries
        }
        return scoped
            .filter { $0.isExpense && $0.category == category }
            .sorted { $0.date > $1.date }
    }

    // MARK: - AI Highlights (async, cached by facts signature)

    /// Regenerates highlights only when the underlying facts change. Renders
    /// deterministic template cards synchronously, then replaces them with
    /// AI-phrased headlines once the on-device model responds (if available).
    func refreshHighlights(analytics: Analytics) {
        let facts = factsBuilder.build(Self.highlightContext(from: analytics))
        let signature = Self.signature(of: facts)
        guard signature != highlightsSignature else { return }
        highlightsSignature = signature

        highlightsTask?.cancel()
        guard !facts.isEmpty else {
            highlights = []
            return
        }

        // Template cards immediately so the section never flashes empty.
        highlights = facts.map { InsightHighlightCard(id: $0.id, headline: $0.headlineFallback, detail: $0.detail, systemImage: $0.systemImage) }

        highlightsTask = Task { [weak self] in
            guard let self else { return }
            let cards = await self.narrativeService.generateHighlights(from: facts)
            if Task.isCancelled { return }
            // Only overwrite if the facts are still current (period may have
            // changed while the model was thinking).
            if signature == self.highlightsSignature {
                self.highlights = cards
            }
        }
    }

    private static func highlightContext(from a: Analytics) -> HighlightContext {
        HighlightContext(
            period: a.period,
            expenseTotal: a.expenseTotal,
            comparison: a.comparison,
            categoryBreakdown: a.breakdown,
            anomalies: a.anomalies,
            runwayMonths: a.runwayMonths,
            cashflow: a.cashflow,
            largestExpense: a.largestExpenses.first,
            topMerchant: a.topMerchants.first
        )
    }

    private static func signature(of facts: [HighlightFact]) -> Int {
        var hasher = Hasher()
        for fact in facts {
            hasher.combine(fact.kind.rawValue)
            hasher.combine(fact.detail)
        }
        return hasher.finalize()
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
            guard !transaction.isTransfer else { continue }
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

    /// Burn-spend subset for the runway/anomaly engine (InsightService's
    /// contract — debit, consumption categories only).
    private static func spendEntries(from entries: [AnalyticsEntry]) -> [SpendEntry] {
        entries
            .filter(\.isExpense)
            .map { SpendEntry(date: $0.date, amount: $0.amount, category: $0.category) }
    }

    private static func distinctCompleteMonthCount(in entries: [SpendEntry], now: Date) -> Int {
        let calendar = Calendar.current
        let currentMonth = calendar.dateComponents([.year, .month], from: now)
        let months = Set(entries.map { calendar.dateComponents([.year, .month], from: $0.date) })
        return months.filter { $0 != currentMonth }.count
    }
}
