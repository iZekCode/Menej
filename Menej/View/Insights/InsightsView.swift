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

private enum InsightsTab: String, CaseIterable {
    case spending, income
}

struct InsightsView: View {
    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @State private var viewModel = InsightsViewModel()
    @State private var selectedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var tab: InsightsTab = .spending

    private var issuerByAccount: [UUID: Issuer] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.issuer) })
    }

    /// Every transaction in the selected month, newest first — for the
    /// "Last Transactions" preview and its full-list drill-in.
    private var monthTransactions: [Transaction] {
        guard let range = AnalyticsPeriod.singleMonth.dateRange(reference: selectedMonth) else { return transactions }
        return transactions.filter { range.contains($0.date) }.sorted { $0.date > $1.date }
    }

    /// The month's income — credits that aren't transfers between the user's
    /// own accounts — so the user can see where the money came from.
    private var monthIncome: [Transaction] {
        monthTransactions.filter { $0.direction == .credit && !$0.isTransfer }
    }

    /// The month's spending — debits that aren't own-account transfers.
    private var monthSpending: [Transaction] {
        monthTransactions.filter { $0.direction == .debit && !$0.isTransfer }
    }

    private var monthIncomeTotal: Decimal {
        monthIncome.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Income change vs the previous month, for the Income header. nil when
    /// there's no prior-month income to compare against.
    private var incomeDeltaFraction: Double? {
        guard let range = AnalyticsPeriod.singleMonth.previousDateRange(reference: selectedMonth) else { return nil }
        let previous = transactions
            .filter { range.contains($0.date) && $0.direction == .credit && !$0.isTransfer }
            .reduce(Decimal(0)) { $0 + $1.amount }
        guard previous > 0 else { return nil }
        let delta = monthIncomeTotal - previous
        return NSDecimalNumber(decimal: delta).doubleValue / NSDecimalNumber(decimal: previous).doubleValue
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
                        Picker("Type", selection: $tab) {
                            Text("Spending").tag(InsightsTab.spending)
                            Text("Income").tag(InsightsTab.income)
                        }
                        .pickerStyle(.segmented)

                        switch tab {
                        case .spending:
                            spendingSections(analytics)
                        case .income:
                            incomeSections()
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

    @ViewBuilder
    private func spendingSections(_ analytics: InsightsViewModel.Analytics) -> some View {
        if analytics.expenseTotal > 0 {
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
            if !analytics.largestExpenses.isEmpty {
                LargestExpensesSection(expenses: analytics.largestExpenses)
            }
            if !monthSpending.isEmpty {
                TransactionHistorySection(
                    title: "Spending History",
                    transactions: Array(monthSpending.prefix(5)),
                    issuerByAccount: issuerByAccount,
                    month: selectedMonth,
                    kind: .spending
                )
            }
        } else {
            EmptyStateView(
                systemImage: "cart",
                title: "No spending this month",
                message: "Nothing was spent this month."
            )
            .padding(.top, AppSpacing.margin)
        }
    }

    @ViewBuilder
    private func incomeSections() -> some View {
        if monthIncome.isEmpty {
            EmptyStateView(
                systemImage: "banknote",
                title: "No income this month",
                message: "No money came in this month."
            )
            .padding(.top, AppSpacing.margin)
        } else {
            IncomeHeaderView(total: monthIncomeTotal, deltaFraction: incomeDeltaFraction)
            TransactionHistorySection(
                title: "Income History",
                transactions: Array(monthIncome.prefix(5)),
                issuerByAccount: issuerByAccount,
                month: selectedMonth,
                kind: .income
            )
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

// MARK: - Income

private struct IncomeHeaderView: View {
    let total: Decimal
    let deltaFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Received this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AmountText(amount: total, showSign: true)
                .font(AppTypography.netWorthHeadline)
            if let deltaFraction {
                let up = deltaFraction >= 0
                Label(
                    "\(Int((abs(deltaFraction) * 100).rounded()))% vs last month",
                    systemImage: up ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Transaction history (spending / income)

/// A recent-transactions card (last 5) whose header chevron drills into the
/// full filtered month list. Used for both Spending History and Income History.
private struct TransactionHistorySection: View {
    let title: String
    let transactions: [Transaction]
    let issuerByAccount: [UUID: Issuer]
    let month: Date
    let kind: MonthTransactionsView.Kind

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.grid) {
            NavigationLink {
                MonthTransactionsView(month: month, kind: kind)
            } label: {
                HStack {
                    Text(title)
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
//                if let deltaFraction {
//                    Label(
//                        "\(Int((abs(deltaFraction) * 100).rounded()))%",
//                        systemImage: deltaFraction >= 0 ? "arrow.up" : "arrow.down"
//                    )
//                    .labelStyle(.titleAndIcon)
//                    .font(.caption2)
//                    .foregroundStyle(.tertiary)
//                }
            }
            .frame(width: 52, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
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

#Preview {
    InsightsView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
