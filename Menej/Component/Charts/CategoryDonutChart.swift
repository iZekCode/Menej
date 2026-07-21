//
//  CategoryDonutChart.swift
//  Menej
//
//  Category share as a donut — see PRD §6 F8. Always rendered next to the
//  directly-labeled breakdown list (CategoryBreakdownRow), which is the
//  relief that lets the colorblind-safe-but-lower-contrast light hues carry
//  identity: the ring shows proportion at a glance, the list names every slice.
//  Center shows the period's total so the donut doubles as the headline.
//

import SwiftUI
import Charts

struct CategoryDonutChart: View {
    let breakdown: [CategorySpend]
    let total: Decimal

    var body: some View {
        Chart(breakdown) { slice in
            SectorMark(
                angle: .value("Share", NSDecimalNumber(decimal: slice.total).doubleValue),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(slice.category.chartTint)
        }
        .chartLegend(.hidden) // the breakdown list is the legend
        .frame(height: 180)
        .overlay {
            VStack(spacing: 2) {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(compactIDR(total))
                    .font(.headline)
                    .numericStyle()
            }
        }
        .accessibilityLabel("Spending by category")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        breakdown
            .prefix(5)
            .map { "\($0.category.displayName) \(Int(($0.share * 100).rounded())) percent" }
            .joined(separator: ", ")
    }

    private func compactIDR(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        switch abs(double) {
        case 1_000_000...:
            return "Rp \(trim(double / 1_000_000))M"
        case 1_000...:
            return "Rp \(trim(double / 1_000))K"
        default:
            return "Rp \(Int(double))"
        }
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

#Preview {
    CategoryDonutChart(
        breakdown: [
            CategorySpend(category: .food, total: 3_000_000, share: 0.5),
            CategorySpend(category: .transport, total: 1_800_000, share: 0.3),
            CategorySpend(category: .shopping, total: 1_200_000, share: 0.2),
        ],
        total: 6_000_000
    )
    .padding()
}
