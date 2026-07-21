//
//  InsightHighlights.swift
//  Menej
//
//  Turns computed analytics into a small ranked set of "highlight" facts for
//  the Health-app-style summary cards — see PRD §6 F8.
//
//  CRITICAL: every number in a highlight is computed and formatted HERE, in
//  pure deterministic code. The on-device LLM (InsightNarrativeService) only
//  rephrases and reorders these facts into friendlier copy — it is never
//  asked to produce a figure. `detail` is the authoritative fact string;
//  `headlineFallback` is what renders verbatim when Apple Intelligence is
//  unavailable. This is the guardrail against a plausible-but-wrong number,
//  the exact failure mode PRD §6 F8 warns against.
//
//  Pure Foundation so it compiles under the CLT swiftc harness.
//

import Foundation

struct HighlightFact: Identifiable {
    enum Kind: String {
        case spendTrend
        case anomaly
        case topCategory
        case runway
        case savingsRate
        case largestExpense
        case topMerchant
    }

    let kind: Kind
    /// Template headline, shown verbatim when the LLM is unavailable.
    let headlineFallback: String
    /// The authoritative fact, with numbers already formatted — the LLM must
    /// preserve these figures, and the fallback shows this under the headline.
    let detail: String
    let systemImage: String
    /// Higher wins when selecting which few facts to surface.
    let priority: Int

    var id: String { kind.rawValue }
}

/// Everything the builder needs, all pre-computed by SpendingAnalyticsService
/// and InsightService — the builder does no windowing itself.
struct HighlightContext {
    let period: AnalyticsPeriod
    let expenseTotal: Decimal
    let comparison: PeriodComparison
    let categoryBreakdown: [CategorySpend]
    let anomalies: [CategoryAnomaly]
    let runwayMonths: Double?
    let cashflow: Cashflow
    let largestExpense: AnalyticsEntry?
    let topMerchant: MerchantSpend?
}

struct HighlightFactsBuilder {
    /// How many facts to surface as cards.
    var maxFacts: Int = 4

    func build(_ context: HighlightContext) -> [HighlightFact] {
        var facts: [HighlightFact] = []

        // Spend trend vs the previous period.
        if let delta = context.comparison.deltaFraction, let label = context.period.comparisonLabel {
            let pct = Self.percent(abs(delta))
            let up = delta >= 0
            facts.append(HighlightFact(
                kind: .spendTrend,
                headlineFallback: up ? "Spending is up \(pct)" : "Spending is down \(pct)",
                detail: "\(Self.money(context.comparison.currentTotal)) \(label) (\(Self.money(context.comparison.previousTotal)) before).",
                systemImage: up ? "arrow.up.right" : "arrow.down.right",
                // A big swing is the most attention-worthy; a small one isn't.
                priority: abs(delta) >= 0.15 ? 95 : 60
            ))
        }

        // Sharpest anomaly (already noise-floored and ratio-gated upstream).
        if let anomaly = context.anomalies.first {
            facts.append(HighlightFact(
                kind: .anomaly,
                headlineFallback: "\(anomaly.category.displayName) spending stands out",
                detail: "\(anomaly.category.displayName) was \(Self.multiple(anomaly.ratio)) your usual — \(Self.money(anomaly.currentAmount)) vs \(Self.money(anomaly.averageAmount)) typical.",
                systemImage: "exclamationmark.triangle",
                priority: 90
            ))
        }

        // Biggest spending category.
        if let top = context.categoryBreakdown.first {
            facts.append(HighlightFact(
                kind: .topCategory,
                headlineFallback: "\(top.category.displayName) is your biggest category",
                detail: "\(Self.money(top.total)) on \(top.category.displayName.lowercased()) — \(Self.percent(top.share)) of spending \(context.period.longLabel.lowercased()).",
                systemImage: top.category.systemImage,
                priority: 70
            ))
        }

        // Runway.
        if let months = context.runwayMonths, months >= 1 {
            let rounded = Int(months.rounded())
            facts.append(HighlightFact(
                kind: .runway,
                headlineFallback: "About \(rounded) \(rounded == 1 ? "month" : "months") of runway",
                detail: "At this burn rate your liquid assets would last about \(rounded) \(rounded == 1 ? "month" : "months").",
                systemImage: "hourglass",
                priority: 65
            ))
        }

        // Savings rate (only meaningful when there was income this period).
        if let rate = context.cashflow.savingsRate {
            let positive = rate >= 0
            facts.append(HighlightFact(
                kind: .savingsRate,
                headlineFallback: positive ? "You saved \(Self.percent(rate)) of income" : "You spent more than you earned",
                detail: positive
                    ? "\(Self.money(context.cashflow.net)) kept from \(Self.money(context.cashflow.income)) of income."
                    : "Spending exceeded income by \(Self.money(-context.cashflow.net)).",
                systemImage: positive ? "banknote" : "arrow.down.circle",
                priority: positive ? 55 : 85
            ))
        }

        // Largest single expense.
        if let largest = context.largestExpense {
            let name = largest.merchant?.isEmpty == false ? largest.merchant! : largest.category.displayName
            facts.append(HighlightFact(
                kind: .largestExpense,
                headlineFallback: "Largest purchase: \(Self.money(largest.amount))",
                detail: "\(Self.money(largest.amount)) at \(name) was your single biggest expense \(context.period.longLabel.lowercased()).",
                systemImage: "creditcard",
                priority: 45
            ))
        }

        // Top merchant by total.
        if let merchant = context.topMerchant {
            facts.append(HighlightFact(
                kind: .topMerchant,
                headlineFallback: "You spend most at \(merchant.merchant)",
                detail: "\(Self.money(merchant.total)) across \(merchant.transactionCount) \(merchant.transactionCount == 1 ? "visit" : "visits") to \(merchant.merchant).",
                systemImage: "storefront",
                priority: 40
            ))
        }

        return Array(facts.sorted { $0.priority > $1.priority }.prefix(maxFacts))
    }

    // MARK: - Formatting (single source of truth for highlight numbers)

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func money(_ value: Decimal) -> String {
        currencyFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "Rp\(value)"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func multiple(_ ratio: Double) -> String {
        String(format: "%.1f×", ratio)
    }
}
