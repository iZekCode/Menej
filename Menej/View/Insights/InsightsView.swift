//
//  InsightsView.swift
//  Menej
//
//  See PRD §6 F8. Insights are withheld until data supports them — a wrong
//  insight in week one does more damage than no insight at all.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        // Computed once per body evaluation (not cached via `.onAppear`,
        // which would go stale — see InsightsViewModel.swift) and reused
        // below rather than recomputed per section.
        let liquidAssets = accounts.reduce(Decimal(0)) { $0 + $1.balance }
        let summary = viewModel.summarize(transactions: transactions, liquidAssets: liquidAssets)
        let hasAnyInsight = summary.runwayMonths != nil || summary.hasEnoughDataForAnomalies

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    if let runwayMonths = summary.runwayMonths {
                        RunwayCard(months: runwayMonths, liquidAssets: liquidAssets)
                    }

                    if summary.hasEnoughDataForAnomalies {
                        AnomaliesCard(anomalies: summary.anomalies)
                    }

                    if !hasAnyInsight {
                        EmptyStateView(
                            systemImage: "sparkles",
                            title: "Not enough data yet",
                            message: "Import a month of statements to see your first insights."
                        )
                        .padding(.top, AppSpacing.margin)
                    }

                    #if DEBUG
                    debugCard(summary: summary, liquidAssets: liquidAssets)
                    #endif
                }
                .padding(AppSpacing.margin)
            }
            .navigationTitle("Insights")
        }
    }

    #if DEBUG
    private func debugCard(summary: InsightsViewModel.SpendSummary, liquidAssets: Decimal) -> some View {
        SectionCard(title: "Debug") {
            Text("""
            transactions: \(transactions.count)
            accounts: \(accounts.count), liquidAssets: \(liquidAssets)
            runwayMonths: \(summary.runwayMonths.map { String(format: "%.2f", $0) } ?? "nil")
            hasEnoughDataForAnomalies: \(summary.hasEnoughDataForAnomalies)
            anomalies: \(summary.anomalies.count)
            debit,non-transfer txns: \(transactions.filter { $0.direction == .debit && !$0.isTransfer }.count)
            """)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    #endif
}

private struct RunwayCard: View {
    let months: Double
    let liquidAssets: Decimal

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
        let years = Double(rounded) / 12
        return "\(rounded) months (~\(String(format: "%.1f", years)) years)"
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
                        AnomalyRow(anomaly: anomaly)
                    }
                }
            }
        }
    }
}

private struct AnomalyRow: View {
    let anomaly: CategoryAnomaly

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.grid + 4) {
            Image(systemName: anomaly.category.systemImage)
                .foregroundStyle(AppColor.accent)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(anomaly.category.displayName) in \(monthName) was \(ratioText) your average")
                    .font(.subheadline.weight(.medium))
                Text("\(amount(anomaly.currentAmount)) vs \(amount(anomaly.averageAmount)) typical")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numericStyle()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratioText: String {
        "\(String(format: "%.1f", anomaly.ratio))×"
    }

    private var monthName: String {
        anomaly.month.formatted(.dateTime.month(.wide))
    }

    private func amount(_ value: Decimal) -> String {
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
