//
//  CategoryDetailView.swift
//  Menej
//
//  Drill-down for one spending category in the selected period — see PRD §6 F8.
//  Pushed from the "By Category" breakdown. Shows the category's total, its
//  spend over time, and the individual transactions behind it.
//

import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let category: Category
    let period: AnalyticsPeriod
    let reference: Date

    @Query private var transactions: [Transaction]
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        let expenses = viewModel.expenses(in: category, transactions: transactions, period: period, reference: reference)
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        let buckets = Self.buckets(for: expenses, unit: period.bucketComponent)

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.margin) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(category.displayName) · \(scopeLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    AmountText(amount: total)
                        .font(AppTypography.netWorthHeadline)
                }

                if buckets.count > 1 {
                    SectionCard(title: "Over Time") {
                        SpendingBarChart(buckets: buckets, unit: period.bucketComponent)
                    }
                }

                if expenses.isEmpty {
                    EmptyStateView(
                        systemImage: category.systemImage,
                        title: "No \(category.displayName.lowercased()) spending",
                        message: "Nothing in this category for the selected period."
                    )
                } else {
                    SectionCard(title: "Transactions") {
                        VStack(spacing: AppSpacing.grid) {
                            ForEach(Array(expenses.enumerated()), id: \.offset) { index, expense in
                                if index > 0 { Divider() }
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(expense.merchant?.isEmpty == false ? expense.merchant! : category.displayName)
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
            .padding(AppSpacing.margin)
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The selected month's name in month mode, else the aggregate window label.
    private var scopeLabel: String {
        guard period == .singleMonth else { return period.longLabel.lowercased() }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: reference)
    }

    /// Buckets this category's expenses at the period's granularity, matching
    /// the dashboard's spending-over-time chart.
    private static func buckets(for expenses: [AnalyticsEntry], unit: Calendar.Component) -> [SpendBucket] {
        let calendar = Calendar.current
        func bucketStart(_ date: Date) -> Date {
            unit == .month
                ? (calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date))
                : calendar.startOfDay(for: date)
        }
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            totals[bucketStart(expense.date), default: 0] += expense.amount
        }
        return totals.keys.sorted().map { SpendBucket(start: $0, total: totals[$0] ?? 0, byCategory: [:]) }
    }
}
