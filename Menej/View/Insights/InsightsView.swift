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

        NavigationStack {
            List {
                if let runwayMonths = summary.runwayMonths {
                    Section("Runway") {
                        Text("At your current burn rate, your liquid assets last \(Int(runwayMonths)) months.")
                    }
                }

                if summary.hasEnoughDataForAnomalies {
                    Section("Anomalies") {
                        if summary.anomalies.isEmpty {
                            Text("Nothing unusual this month.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(summary.anomalies.enumerated()), id: \.offset) { _, anomaly in
                                Label(
                                    "\(anomaly.category.displayName) is \(anomaly.ratio, specifier: "%.1f")x your average this month.",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(AppColor.loss)
                            }
                        }
                    }
                }

                if summary.runwayMonths == nil && !summary.hasEnoughDataForAnomalies {
                    EmptyStateView(
                        systemImage: "sparkles",
                        title: "Not enough data yet",
                        message: "Import a month of statements to see your first insights."
                    )
                }

                #if DEBUG
                Section("Debug") {
                    Text("""
                    transactions: \(transactions.count)
                    accounts: \(accounts.count), liquidAssets: \(liquidAssets)
                    runwayMonths: \(summary.runwayMonths.map { String($0) } ?? "nil")
                    hasEnoughDataForAnomalies: \(summary.hasEnoughDataForAnomalies)
                    anomalies: \(summary.anomalies.count)
                    debit,non-transfer txns: \(transactions.filter { $0.direction == .debit && !$0.isTransfer }.count)
                    """)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                }
                #endif
            }
            .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
