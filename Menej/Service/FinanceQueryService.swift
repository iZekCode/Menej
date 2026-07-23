//
//  FinanceQueryService.swift
//  Menej
//
//  The answering half of Ask (PRD §6 F8). The on-device model routes a
//  question into a `FinanceQuery`; this executes it and returns the numbers.
//  The model never computes anything — see FinanceChatService.swift for why
//  that division is the whole design.
//
//  Value types only, no SwiftData and no FoundationModels imports — same
//  discipline as InsightService and SpendingAnalyticsService, so this
//  typechecks under the CLT swiftc harness and is unit-testable without a
//  ModelContainer. FinanceChatViewModel does the projection from @Model types.
//

import Foundation

// MARK: - Query

enum FinanceIntent: String, CaseIterable {
    case spendTotal
    case categoryBreakdown
    case merchantSpend
    case largestExpenses
    case comparison
    case cashflow
    case netWorth
    case accountBalance
    case runway
    case anomalies
    case assetValue
    /// The honest exit. A question this app can't compute an answer to — an
    /// opinion, a forecast, something about data that was never imported —
    /// resolves here and is declined. It must stay reachable: approximating
    /// instead is exactly the failure InsightService is built to avoid.
    case unsupported
}

/// A resolved time window. `nil` range means all time (`AnalyticsPeriod.all`).
/// `label` is the phrase to state back to the user ("last month", "March to
/// May 2026") so an answer always says which window it's for — a total with an
/// unstated period is not an answer.
struct DateWindow {
    let range: Range<Date>?
    let label: String

    static let allTime = DateWindow(range: nil, label: "all time")
}

struct FinanceQuery {
    let intent: FinanceIntent
    var category: Category?
    /// As the user said it. Resolved against real data via
    /// `SpendingAnalyticsService.merchantMatches` before anything is totalled.
    var merchant: String?
    /// For `.accountBalance` and `.assetValue` — the account or item named.
    var subject: String?
    var window: DateWindow = .allTime
    var limit: Int = 5
}

// MARK: - Inputs

/// Everything outside the transaction ledger that a question might be about,
/// flattened to values by the view model. Deliberately not the @Model types.
struct FinanceContext {
    struct NamedAmount {
        let name: String
        let amount: Decimal
    }

    var accounts: [NamedAmount] = []
    var assets: [NamedAmount] = []
    var liquidTotal: Decimal = 0
    var portfolioTotal: Decimal = 0
    var inventoryTotal: Decimal = 0
    var liabilitiesTotal: Decimal = 0
    var netWorth: Decimal = 0
}

// MARK: - Answer

enum FinanceAnswer {
    case spendTotal(amount: Decimal, category: Category?, window: DateWindow)
    case categoryBreakdown(breakdown: [CategorySpend], total: Decimal, window: DateWindow)
    case merchantSpend(merchant: String, amount: Decimal, count: Int, window: DateWindow)
    /// The named merchant isn't in the data. Carries near-misses when there
    /// are any, so the answer can suggest rather than just refuse.
    case merchantNotFound(query: String, suggestions: [String])
    /// The name matched several counterparties — asking is the only honest
    /// move, since picking one silently would answer a different question.
    case merchantAmbiguous(query: String, matches: [String])
    case largestExpenses(entries: [AnalyticsEntry], window: DateWindow)
    case comparison(PeriodComparison, window: DateWindow)
    case cashflow(Cashflow, window: DateWindow)
    case netWorth(total: Decimal, liquid: Decimal, portfolio: Decimal, inventory: Decimal, liabilities: Decimal)
    case accountBalance(name: String, amount: Decimal)
    case assetValue(name: String, amount: Decimal)
    case runway(months: Double, averageMonthlySpend: Decimal)
    case anomalies([CategoryAnomaly])
    /// Nothing to report, with the reason. Distinct from `.unsupported`: the
    /// question was understood, the data just doesn't support an answer yet.
    case noData(reason: String)
    case unsupported
}

// MARK: - Service

protocol FinanceQueryServiceProtocol {
    func answer(query: FinanceQuery, entries: [AnalyticsEntry], context: FinanceContext, asOf: Date) -> FinanceAnswer
}

struct FinanceQueryService: FinanceQueryServiceProtocol {
    private let analyticsService: SpendingAnalyticsServiceProtocol
    private let insightService: InsightServiceProtocol

    // See ImportViewModel.swift for why defaults are built in the body.
    init(
        analyticsService: SpendingAnalyticsServiceProtocol? = nil,
        insightService: InsightServiceProtocol? = nil
    ) {
        self.analyticsService = analyticsService ?? SpendingAnalyticsService()
        self.insightService = insightService ?? InsightService()
    }

    func answer(query: FinanceQuery, entries: [AnalyticsEntry], context: FinanceContext, asOf: Date) -> FinanceAnswer {
        switch query.intent {
        case .spendTotal:
            return spendTotal(query, entries)
        case .categoryBreakdown:
            return categoryBreakdown(query, entries)
        case .merchantSpend:
            return merchantSpend(query, entries)
        case .largestExpenses:
            return largestExpenses(query, entries)
        case .comparison:
            return comparison(query, entries)
        case .cashflow:
            return .cashflow(analyticsService.cashflow(entries: entries, in: query.window.range), window: query.window)
        case .netWorth:
            return .netWorth(
                total: context.netWorth,
                liquid: context.liquidTotal,
                portfolio: context.portfolioTotal,
                inventory: context.inventoryTotal,
                liabilities: context.liabilitiesTotal
            )
        case .accountBalance:
            guard let match = named(query.subject, in: context.accounts) else {
                return .noData(reason: "I couldn't find an account by that name.")
            }
            return .accountBalance(name: match.name, amount: match.amount)
        case .assetValue:
            guard let match = named(query.subject, in: context.assets) else {
                return .noData(reason: "I couldn't find an item by that name in your inventory.")
            }
            return .assetValue(name: match.name, amount: match.amount)
        case .runway:
            return runway(entries, liquid: context.liquidTotal, asOf: asOf)
        case .anomalies:
            let anomalies = insightService.anomalies(entries: spendEntries(from: entries), asOf: asOf)
            return anomalies.isEmpty
                ? .noData(reason: "Nothing looks unusual — that needs at least two complete months to judge.")
                : .anomalies(anomalies)
        case .unsupported:
            return .unsupported
        }
    }

    // MARK: - Intents

    private func spendTotal(_ query: FinanceQuery, _ entries: [AnalyticsEntry]) -> FinanceAnswer {
        // A category filter narrows the entries themselves rather than being
        // applied to the total afterwards, so the window arithmetic stays in
        // one place.
        let scoped = query.category.map { category in
            entries.filter { $0.category == category }
        } ?? entries
        let amount = analyticsService.expenseTotal(entries: scoped, in: query.window.range)
        return .spendTotal(amount: amount, category: query.category, window: query.window)
    }

    private func categoryBreakdown(_ query: FinanceQuery, _ entries: [AnalyticsEntry]) -> FinanceAnswer {
        let breakdown = analyticsService.categoryBreakdown(entries: entries, in: query.window.range)
        guard !breakdown.isEmpty else {
            return .noData(reason: "There's no spending recorded for \(query.window.label).")
        }
        let total = breakdown.reduce(Decimal(0)) { $0 + $1.total }
        return .categoryBreakdown(breakdown: breakdown, total: total, window: query.window)
    }

    /// Resolves the name against real data *first*. The model can produce a
    /// plausible-looking merchant that was never in a statement, and totalling
    /// straight from its string would answer with a confident Rp 0.
    private func merchantSpend(_ query: FinanceQuery, _ entries: [AnalyticsEntry]) -> FinanceAnswer {
        let requested = (query.merchant ?? "").trimmingCharacters(in: .whitespaces)
        guard !requested.isEmpty else {
            return .noData(reason: "I didn't catch which merchant you meant.")
        }

        let matches = analyticsService.merchantMatches(entries: entries, query: requested)
        guard let match = matches.first else {
            return .merchantNotFound(query: requested, suggestions: [])
        }
        // Several distinct counterparties contain the same substring, and none
        // is an exact match — "Indomaret Alam Sutera" vs "Indomaret BSD".
        if matches.count > 1, match.compare(requested, options: .caseInsensitive) != .orderedSame {
            return .merchantAmbiguous(query: requested, matches: Array(matches.prefix(5)))
        }

        let scoped = entries.filter { entry in
            entry.merchant?.compare(match, options: .caseInsensitive) == .orderedSame
        }
        let breakdown = analyticsService.merchantBreakdown(entries: scoped, in: query.window.range, limit: 1)
        guard let spend = breakdown.first else {
            return .noData(reason: "No spending at \(match) during \(query.window.label).")
        }
        return .merchantSpend(merchant: spend.merchant, amount: spend.total, count: spend.count, window: query.window)
    }

    private func largestExpenses(_ query: FinanceQuery, _ entries: [AnalyticsEntry]) -> FinanceAnswer {
        let largest = analyticsService.largestExpenses(entries: entries, in: query.window.range, limit: query.limit)
        guard !largest.isEmpty else {
            return .noData(reason: "There's no spending recorded for \(query.window.label).")
        }
        return .largestExpenses(entries: largest, window: query.window)
    }

    /// Uses the period-based comparison, which knows how to derive the
    /// preceding equal-length window. A free-form range has no defined "period
    /// before it", so this intent is month-over-month only.
    private func comparison(_ query: FinanceQuery, _ entries: [AnalyticsEntry]) -> FinanceAnswer {
        let comparison = analyticsService.comparison(entries: entries, period: .month, asOf: Date())
        guard comparison.currentTotal > 0 || comparison.previousTotal > 0 else {
            return .noData(reason: "There isn't enough spending recorded to compare two months yet.")
        }
        return .comparison(comparison, window: DateWindow(range: nil, label: "this month vs last month"))
    }

    private func runway(_ entries: [AnalyticsEntry], liquid: Decimal, asOf: Date) -> FinanceAnswer {
        guard let average = insightService.averageMonthlySpend(entries: spendEntries(from: entries), asOf: asOf),
              let months = insightService.runwayMonths(liquidAssets: liquid, averageMonthlySpend: average) else {
            // InsightService withholds on purpose (no complete month yet, a
            // sole partial month too early to prorate, no burn at all).
            return .noData(reason: "I need at least one complete month of spending before I can work out a runway.")
        }
        return .runway(months: months, averageMonthlySpend: average)
    }

    // MARK: - Helpers

    /// AnalyticsEntry → SpendEntry, for the two InsightService calls. Both
    /// types are already deduplicated and transfer-filtered by the projection
    /// upstream; this only narrows to real burn, which is what
    /// `AnalyticsEntry.isExpense` means.
    private func spendEntries(from entries: [AnalyticsEntry]) -> [SpendEntry] {
        entries
            .filter(\.isExpense)
            .map { SpendEntry(date: $0.date, amount: $0.amount, category: $0.category) }
    }

    /// Case-insensitive substring match over named amounts, preferring an
    /// exact name. Same "resolve before answering" rule as merchants.
    private func named(_ subject: String?, in candidates: [FinanceContext.NamedAmount]) -> FinanceContext.NamedAmount? {
        let requested = (subject ?? "").trimmingCharacters(in: .whitespaces)
        guard !requested.isEmpty else { return nil }

        if let exact = candidates.first(where: { $0.name.compare(requested, options: .caseInsensitive) == .orderedSame }) {
            return exact
        }
        return candidates.first {
            $0.name.range(of: requested, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
