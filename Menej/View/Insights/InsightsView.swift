//
//  InsightsView.swift
//  Menej
//
//  The spending analytics dashboard — see PRD §6 F8. Charts, categorized
//  totals, time-period breakdowns, cashflow, and Health-app-style AI
//  Highlights, over the existing runway + anomaly insights. Everything obeys
//  the withholding rule: a module renders only when its data supports it.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @State private var viewModel = InsightsViewModel()
    @State private var period: AnalyticsPeriod = .month

    var body: some View {
        // Computed once per body evaluation (not cached via `.onAppear`, which
        // would go stale — see InsightsViewModel.swift), reused across sections.
        let liquidAssets = accounts.reduce(Decimal(0)) { $0 + $1.balance }
        let analytics = viewModel.analytics(transactions: transactions, liquidAssets: liquidAssets, period: period)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    Picker("Period", selection: $period) {
                        ForEach(AnalyticsPeriod.allCases) { period in
                            Text(period.shortLabel).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !analytics.hasSpending && analytics.runwayMonths == nil {
                        EmptyStateView(
                            systemImage: "sparkles",
                            title: "Not enough data yet",
                            message: "Import a month of statements to see your spending analytics."
                        )
                        .padding(.top, AppSpacing.margin)
                    } else {
                        HeaderView(period: period, total: analytics.expenseTotal, comparison: analytics.comparison)

                        if !viewModel.highlights.isEmpty {
                            HighlightsSection(cards: viewModel.highlights)
                        }
                        if !analytics.timeSeries.isEmpty {
                            SectionCard(title: "Spending Over Time") {
                                SpendingBarChart(buckets: analytics.timeSeries, unit: period.bucketComponent)
                            }
                        }
                        if !analytics.breakdown.isEmpty {
                            CategoryBreakdownSection(
                                breakdown: analytics.breakdown,
                                total: analytics.expenseTotal,
                                comparison: analytics.comparison,
                                period: period
                            )
                        }
                        if analytics.cashflow.income > 0 || analytics.cashflow.expense > 0 {
                            CashflowSection(cashflow: analytics.cashflow)
                        }
                        if !analytics.topMerchants.isEmpty {
                            TopMerchantsSection(merchants: analytics.topMerchants)
                        }
                        if !analytics.largestExpenses.isEmpty {
                            LargestExpensesSection(expenses: analytics.largestExpenses)
                        }
                        if let runwayMonths = analytics.runwayMonths {
                            RunwayCard(months: runwayMonths)
                        }
                        if analytics.hasEnoughDataForAnomalies {
                            AnomaliesCard(anomalies: analytics.anomalies)
                        }
                    }

                    #if DEBUG
                    debugCard(analytics: analytics, liquidAssets: liquidAssets)
                    #endif
                }
                .padding(AppSpacing.margin)
            }
            .navigationTitle("Insights")
            .navigationDestination(for: Category.self) { category in
                CategoryDetailView(category: category, period: period)
            }
        }
        // Regenerates AI Highlights only when the period or data changes;
        // refreshHighlights itself no-ops when the underlying facts are equal.
        .task(id: "\(period.rawValue)-\(transactions.count)") {
            let analytics = viewModel.analytics(transactions: transactions, liquidAssets: liquidAssets, period: period)
            viewModel.refreshHighlights(analytics: analytics)
        }
    }

    #if DEBUG
    private func debugCard(analytics: InsightsViewModel.Analytics, liquidAssets: Decimal) -> some View {
        SectionCard(title: "Debug") {
            Text("""
            transactions: \(transactions.count), liquidAssets: \(liquidAssets)
            period: \(period.rawValue), expenseTotal: \(analytics.expenseTotal)
            categories: \(analytics.breakdown.count), buckets: \(analytics.timeSeries.count)
            runway: \(analytics.runwayMonths.map { String(format: "%.2f", $0) } ?? "nil")
            anomalies: \(analytics.anomalies.count) (enough data: \(analytics.hasEnoughDataForAnomalies))
            highlights: \(viewModel.highlights.count)
            """)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif
}

// MARK: - Header

private struct HeaderView: View {
    let period: AnalyticsPeriod
    let total: Decimal
    let comparison: PeriodComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spent \(period.longLabel.lowercased())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AmountText(amount: total)
                .font(AppTypography.netWorthHeadline)
            if let delta = comparison.deltaFraction, let label = period.comparisonLabel {
                let up = delta >= 0
                Label(
                    "\(Int((abs(delta) * 100).rounded()))% \(label)",
                    systemImage: up ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Highlights

private struct HighlightsSection: View {
    let cards: [InsightHighlightCard]

    var body: some View {
        SectionCard(title: "Highlights") {
            VStack(spacing: AppSpacing.grid) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: AppSpacing.grid + 4) {
                        Image(systemName: card.systemImage)
                            .foregroundStyle(AppColor.accent)
                            .frame(width: 24)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.headline)
                                .font(.subheadline.weight(.semibold))
                            Text(card.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Category breakdown

private struct CategoryBreakdownSection: View {
    let breakdown: [CategorySpend]
    let total: Decimal
    let comparison: PeriodComparison
    let period: AnalyticsPeriod

    var body: some View {
        SectionCard(title: "By Category") {
            VStack(spacing: AppSpacing.margin) {
                CategoryDonutChart(breakdown: breakdown, total: total)
                VStack(spacing: AppSpacing.grid) {
                    ForEach(breakdown) { slice in
                        NavigationLink(value: slice.category) {
                            CategoryBreakdownRow(slice: slice, deltaFraction: deltaFraction(for: slice.category))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func deltaFraction(for category: Category) -> Double? {
        comparison.categoryDeltas.first { $0.category == category }?.deltaFraction
    }
}

private struct CategoryBreakdownRow: View {
    let slice: CategorySpend
    let deltaFraction: Double?

    var body: some View {
        HStack(spacing: AppSpacing.grid + 2) {
            Image(systemName: slice.category.systemImage)
                .font(.caption)
                .foregroundStyle(slice.category.chartTint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(slice.category.displayName)
                        .font(.subheadline)
                    Spacer()
                    AmountText(amount: slice.total)
                        .font(.subheadline)
                }
                ProgressView(value: min(slice.share, 1))
                    .tint(slice.category.chartTint)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int((slice.share * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let deltaFraction {
                    Label(
                        "\(Int((abs(deltaFraction) * 100).rounded()))%",
                        systemImage: deltaFraction >= 0 ? "arrow.up" : "arrow.down"
                    )
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 52, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Cashflow

private struct CashflowSection: View {
    let cashflow: Cashflow

    var body: some View {
        SectionCard(title: "Cashflow") {
            VStack(alignment: .leading, spacing: AppSpacing.grid) {
                CashflowChart(cashflow: cashflow)
                Divider()
                HStack {
                    Text(savingsLabel)
                        .font(.subheadline)
                    Spacer()
                    if let rate = cashflow.savingsRate {
                        Text("\(Int((rate * 100).rounded()))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(rate >= 0 ? AppColor.gain : AppColor.loss)
                    }
                }
            }
        }
    }

    private var savingsLabel: String {
        guard let rate = cashflow.savingsRate else { return "Net cashflow" }
        return rate >= 0 ? "Saved this period" : "Overspent this period"
    }
}

// MARK: - Top merchants

private struct TopMerchantsSection: View {
    let merchants: [MerchantSpend]

    var body: some View {
        SectionCard(title: "Top Merchants") {
            VStack(spacing: AppSpacing.grid) {
                ForEach(Array(merchants.enumerated()), id: \.element.id) { index, merchant in
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(merchant.merchant)
                                .font(.subheadline)
                            Text("\(merchant.transactionCount) \(merchant.transactionCount == 1 ? "transaction" : "transactions")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountText(amount: merchant.total)
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - Largest expenses

private struct LargestExpensesSection: View {
    let expenses: [AnalyticsEntry]

    var body: some View {
        SectionCard(title: "Largest Purchases") {
            VStack(spacing: AppSpacing.grid) {
                ForEach(Array(expenses.enumerated()), id: \.offset) { index, expense in
                    if index > 0 { Divider() }
                    HStack {
                        Image(systemName: expense.category.systemImage)
                            .font(.caption)
                            .foregroundStyle(expense.category.chartTint)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.merchant?.isEmpty == false ? expense.merchant! : expense.category.displayName)
                                .font(.subheadline)
                            Text(expense.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountText(amount: expense.amount)
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - Runway & anomalies (retained from the prior Insights screen)

private struct RunwayCard: View {
    let months: Double

    var body: some View {
        SectionCard(title: "Runway") {
            VStack(alignment: .leading, spacing: AppSpacing.grid) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                Text("At your current burn rate, your liquid assets would last this long.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headline: String {
        let rounded = Int(months.rounded())
        guard rounded >= 1 else { return "Under a month of runway" }
        let monthWord = rounded == 1 ? "month" : "months"
        guard rounded >= 24 else { return "\(rounded) \(monthWord)" }
        return "\(rounded) months (~\(String(format: "%.1f", Double(rounded) / 12)) years)"
    }
}

private struct AnomaliesCard: View {
    let anomalies: [CategoryAnomaly]

    var body: some View {
        SectionCard(title: "Unusual Spending") {
            if anomalies.isEmpty {
                Text("Nothing unusual — every category was in line with your recent months.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: AppSpacing.grid) {
                    ForEach(Array(anomalies.enumerated()), id: \.offset) { index, anomaly in
                        if index > 0 { Divider() }
                        HStack(alignment: .top, spacing: AppSpacing.grid + 4) {
                            Image(systemName: anomaly.category.systemImage)
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 24)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(anomaly.category.displayName) in \(anomaly.month.formatted(.dateTime.month(.wide))) was \(String(format: "%.1f", anomaly.ratio))× your average")
                                    .font(.subheadline.weight(.medium))
                                Text("\(idr(anomaly.currentAmount)) vs \(idr(anomaly.averageAmount)) typical")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .numericStyle()
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func idr(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
