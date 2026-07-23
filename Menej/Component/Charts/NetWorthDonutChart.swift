//
//  NetWorthDonutChart.swift
//  Menej
//
//  Asset allocation as a donut — see PRD §6 F5. Same construction as
//  PortfolioDonutChart and CategoryDonutChart, and the same relief rule: the
//  ring shows proportion, NetWorthHomeView's breakdown rows below name every
//  slice, so color never carries identity alone. Center shows the total, so
//  the donut doubles as a restatement of the headline.
//

import SwiftUI
import Charts

/// One component of the allocation, pre-totalled. The chart and
/// NetWorthHomeView's rows are built from the same array so a slice and its
/// label can't fall out of sync.
struct NetWorthSlice: Identifiable {
    let component: NetWorthComponent
    let amount: Decimal
    var id: String { component.rawValue }
}

struct NetWorthDonutChart: View {
    let slices: [NetWorthSlice]
    let total: Decimal
    /// Masks the center figure with the rest of the screen. The ring itself
    /// stays — proportions aren't a figure, and a blank circle would just
    /// look broken.
    var isHidden: Bool = false

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Share", NSDecimalNumber(decimal: slice.amount).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(slice.component.tint)
        }
        .chartLegend(.hidden) // the breakdown rows are the legend
        .frame(height: 170)
        .overlay {
            VStack(spacing: 2) {
                Text("Assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(isHidden ? "••••••" : AmountText.compactString(total))
                    .font(.headline)
                    .numericStyle()
            }
        }
        .accessibilityLabel("Asset allocation")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard total > 0 else { return "No assets" }
        return slices.map { slice in
            let share = NSDecimalNumber(decimal: slice.amount / total).doubleValue
            return "\(slice.component.displayName) \(Int((share * 100).rounded())) percent"
        }
        .joined(separator: ", ")
    }
}

#Preview {
    NetWorthDonutChart(
        slices: [
            NetWorthSlice(component: .liquid, amount: 42_000_000),
            NetWorthSlice(component: .portfolio, amount: 18_000_000),
            NetWorthSlice(component: .inventory, amount: 84_000_000),
        ],
        total: 144_000_000
    )
    .padding()
}
