//
//  InsightsView.swift
//  Menej
//
//  See PRD §6 F8. Insights are withheld until data supports them — a wrong
//  insight in week one does more damage than no insight at all.
//

import SwiftUI

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let runwayMonths = viewModel.runwayMonths {
                    Section("Runway") {
                        Text("At your current burn rate, your liquid assets last \(Int(runwayMonths)) months.")
                    }
                }

                if viewModel.hasEnoughDataForAnomalies {
                    Section("Anomalies") {
                        ForEach(Array(viewModel.anomalies.enumerated()), id: \.offset) { _, anomaly in
                            Text("\(anomaly.category.displayName) is \(anomaly.ratio, specifier: "%.1f")x your average this month.")
                        }
                    }
                }

                if viewModel.runwayMonths == nil && !viewModel.hasEnoughDataForAnomalies {
                    EmptyStateView(
                        systemImage: "sparkles",
                        title: "Not enough data yet",
                        message: "Import a month of statements to see your first insights."
                    )
                }
            }
            .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
}
