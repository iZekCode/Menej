//
//  InsightsView.swift
//  Menej
//
//  The spending analytics dashboard — see PRD §6 F8. Charts, categorized
//  totals, time-period breakdowns, cashflow, and largest purchases. Everything
//  obeys the withholding rule: a module renders only when its data supports it.
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
                        if !analytics.largestExpenses.isEmpty {
                            LargestExpensesSection(expenses: analytics.largestExpenses)
                        }
                    }
                }
                .padding(AppSpacing.margin)
            }
            .navigationTitle("Insights")
            .navigationDestination(for: Category.self) { category in
                CategoryDetailView(category: category, period: period)
            }
        }
    }
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

#Preview {
    InsightsView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
