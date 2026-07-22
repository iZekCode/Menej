//
//  PortfolioDonutChart.swift
//  Menej
//
//  Portfolio allocation as a donut — see PRD §6 F6. Paired with a directly-
//  labeled legend in PortfolioView (the same relief rule CategoryDonutChart
//  uses): the ring shows proportion at a glance, the legend names every
//  slice, so color is never the only thing distinguishing two holdings.
//

import SwiftUI
import Charts

/// One holding, pre-priced and pre-colored — the shared unit both the ring
/// and PortfolioView's legend rows are built from, so a slice and its label
/// can never fall out of sync.
struct PortfolioSlice: Identifiable {
    let display: HoldingDisplay
    let color: Color
    var id: UUID { display.id }
}

struct PortfolioDonutChart: View {
    let slices: [PortfolioSlice]

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Share", NSDecimalNumber(decimal: slice.display.currentValue).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden) // the legend list is the legend
        .accessibilityLabel("Portfolio allocation")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        slices
            .prefix(5)
            .map { "\($0.display.holding.symbol) \(Int(($0.display.allocationWeight * 100).rounded())) percent" }
            .joined(separator: ", ")
    }
}

#Preview {
    let holding = Holding(instrument: .crypto, symbol: "BTC", quantity: 0.01, avgCost: 900_000_000)
    let display = HoldingDisplay(holding: holding, currentValue: 10_000_000, unrealizedPL: 500_000, unrealizedPLPercent: 0.05, allocationWeight: 1, isStale: false)
    PortfolioDonutChart(slices: [PortfolioSlice(display: display, color: PortfolioPalette.color(at: 0))])
        .frame(height: 180)
        .padding()
}
