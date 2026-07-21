//
//  SpendingBarChart.swift
//  Menej
//
//  Spending-over-time bars for the analytics dashboard — see PRD §6 F8.
//  Deliberately a SINGLE series (total spend per time bucket): identity of
//  *which* category lives in the donut + breakdown list, not crammed into the
//  time axis (an 8-series stacked time chart reads as noise). One hue keeps
//  the eye on the shape of spend over time; the lilac accent is fine here
//  because there's no second series to distinguish.
//

import SwiftUI
import Charts

struct SpendingBarChart: View {
    let buckets: [SpendBucket]
    /// .day or .month — matches AnalyticsPeriod.bucketComponent so the axis
    /// labels at the right granularity.
    let unit: Calendar.Component

    var body: some View {
        Chart(buckets) { bucket in
            BarMark(
                x: .value("Period", bucket.start, unit: calendarUnit),
                y: .value("Spent", doubleValue(bucket.total))
            )
            .foregroundStyle(AppColor.accent)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(compactIDR(amount))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: axisFormat, centered: false)
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Spending over time")
        .accessibilityChartDescriptor(SpendingBarDescriptor(buckets: buckets, unit: unit))
    }

    private var calendarUnit: Calendar.Component {
        unit == .month ? .month : .day
    }

    private var axisFormat: Date.FormatStyle {
        unit == .month
            ? .dateTime.month(.narrow)
            : .dateTime.day()
    }

    private func doubleValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    /// Compact rupiah for axis ticks: 1.2M / 350K / 0.
    private func compactIDR(_ value: Double) -> String {
        switch abs(value) {
        case 1_000_000...:
            return "\(trim(value / 1_000_000))M"
        case 1_000...:
            return "\(trim(value / 1_000))K"
        default:
            return "\(Int(value))"
        }
    }

    private func trim(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// Minimal audio-chart descriptor so VoiceOver users can read the series.
private struct SpendingBarDescriptor: AXChartDescriptorRepresentable {
    let buckets: [SpendBucket]
    let unit: Calendar.Component

    func makeChartDescriptor() -> AXChartDescriptor {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = unit == .month ? "MMM yyyy" : "d MMM"

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Period",
            categoryOrder: buckets.map { dateFormatter.string(from: $0.start) }
        )
        let values = buckets.map { NSDecimalNumber(decimal: $0.total).doubleValue }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Spent",
            range: 0...(values.max() ?? 0),
            gridlinePositions: []
        ) { "Rp \(Int($0))" }

        let series = AXDataSeriesDescriptor(
            name: "Spending",
            isContinuous: false,
            dataPoints: buckets.map {
                .init(x: dateFormatter.string(from: $0.start), y: NSDecimalNumber(decimal: $0.total).doubleValue)
            }
        )
        return AXChartDescriptor(title: "Spending over time", summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

#Preview {
    let now = Date()
    let cal = Calendar.current
    let buckets = (0..<6).reversed().map { offset in
        SpendBucket(
            start: cal.date(byAdding: .month, value: -offset, to: now)!,
            total: Decimal(2_000_000 + offset * 400_000),
            byCategory: [:]
        )
    }
    return SpendingBarChart(buckets: buckets, unit: .month)
        .padding()
}
