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
    @State private var selectedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private var issuerByAccount: [UUID: Issuer] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.issuer) })
    }

    /// Every transaction in the selected month, newest first — for the
    /// "Last Transactions" preview and its full-list drill-in.
    private var monthTransactions: [Transaction] {
        guard let range = AnalyticsPeriod.singleMonth.dateRange(reference: selectedMonth) else { return transactions }
        return transactions.filter { range.contains($0.date) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        // Computed once per body evaluation (not cached via `.onAppear`, which
        // would go stale — see InsightsViewModel.swift), reused across sections.
        let analytics = viewModel.analytics(transactions: transactions, period: .singleMonth, reference: selectedMonth)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    MonthStepper(month: $selectedMonth)

                    if !analytics.hasData {
                        EmptyStateView(
                            systemImage: "calendar",
                            title: "Nothing this month",
                            message: "No transactions for this month. Step to another month or import a statement."
                        )
                        .padding(.top, AppSpacing.margin)
                    } else {
                        HeaderView(period: .singleMonth, total: analytics.expenseTotal, comparison: analytics.comparison)

                        if !analytics.timeSeries.isEmpty {
                            SectionCard(title: "Spending Over Time") {
                                SpendingBarChart(buckets: analytics.timeSeries, unit: .day)
                            }
                        }
                        if !analytics.breakdown.isEmpty {
                            CategoryBreakdownSection(
                                breakdown: analytics.breakdown,
                                total: analytics.expenseTotal,
                                comparison: analytics.comparison
                            )
                        }
                        if analytics.cashflow.income > 0 || analytics.cashflow.expense > 0 {
                            CashflowSection(cashflow: analytics.cashflow)
                        }
                        if !analytics.largestExpenses.isEmpty {
                            LargestExpensesSection(expenses: analytics.largestExpenses)
                        }
                        if !monthTransactions.isEmpty {
                            LastTransactionsSection(
                                transactions: Array(monthTransactions.prefix(5)),
                                issuerByAccount: issuerByAccount,
                                month: selectedMonth
                            )
                        }
                    }
                }
                .padding(AppSpacing.margin)
            }
            .navigationTitle("Insights")
            .navigationDestination(for: Category.self) { category in
                CategoryDetailView(category: category, period: .singleMonth, reference: selectedMonth)
            }
        }
    }
}

// MARK: - Month stepper

private struct MonthStepper: View {
    @Binding var month: Date

    private let calendar = Calendar.current

    /// Can't step into the future — disable the right arrow once at the
    /// current calendar month.
    private var isAtCurrentMonth: Bool {
        calendar.isDate(month, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        HStack {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()
            Text(monthLabel)
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isAtCurrentMonth)
            .opacity(isAtCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(AppColor.accent)
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    private func step(by months: Int) {
        guard let stepped = calendar.date(byAdding: .month, value: months, to: month),
              let start = calendar.dateInterval(of: .month, for: stepped)?.start else { return }
        withAnimation(.snappy) { month = start }
    }
}

// MARK: - Header

private struct HeaderView: View {
    let period: AnalyticsPeriod
    let total: Decimal
    let comparison: PeriodComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(period.spentLabel)
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

// MARK: - Last transactions

private struct LastTransactionsSection: View {
    let transactions: [Transaction]
    let issuerByAccount: [UUID: Issuer]
    let month: Date

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.grid) {
            // Header doubles as the drill-in to the full month list.
            NavigationLink {
                MonthTransactionsView(month: month)
            } label: {
                HStack {
                    Text("Last Transactions")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                if index > 0 { Divider() }
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction, issuer: issuerByAccount[transaction.accountId])
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.margin)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius))
    }
}

// MARK: - Category breakdown

private struct CategoryBreakdownSection: View {
    let breakdown: [CategorySpend]
    let total: Decimal
    let comparison: PeriodComparison

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
