//
//  SnapshotChartView.swift
//  Menej
//
//  The monthly net worth line — see PRD §6 F5. Snapshots are frozen once
//  written, so this is history, not a live recomputation.
//

import SwiftUI
import Charts

struct SnapshotChartView: View {
    let snapshots: [NetWorthSnapshot]
    /// Masks the value labels along with the rest of the screen. The line
    /// itself stays: its shape is a trend, not a figure, and an empty frame
    /// would read as missing data rather than hidden data.
    var isHidden: Bool = false

    var body: some View {
        Chart(snapshots) { snapshot in
            AreaMark(
                x: .value("Month", snapshot.date, unit: .month),
                y: .value("Net Worth", value(of: snapshot))
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [AppColor.accent.opacity(0.28), AppColor.accent.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Month", snapshot.date, unit: .month),
                y: .value("Net Worth", value(of: snapshot))
            )
            .foregroundStyle(AppColor.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)

            // The newest month gets a dot and its figure, so the current
            // value is readable without measuring it against the axis.
            if snapshot.id == latest?.id {
                PointMark(
                    x: .value("Month", snapshot.date, unit: .month),
                    y: .value("Net Worth", value(of: snapshot))
                )
                .foregroundStyle(AppColor.accent)
                .symbolSize(60)
                .annotation(position: .top, spacing: 4) {
                    if !isHidden {
                        Text(AmountText.compactString(snapshot.netWorth))
                            .font(.caption.weight(.semibold))
                            .numericStyle()
                            .foregroundStyle(AppColor.accent)
                    }
                }
            }
        }
        // Net worth rarely sits near zero, and a forced zero baseline
        // flattens the line into a straight edge — hiding exactly the
        // month-to-month movement this chart exists to show.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if !isHidden, let amount = value.as(Double.self) {
                        Text(AmountText.compactString(Decimal(amount)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Net worth trend over the last \(snapshots.count) months")
    }

    private var latest: NetWorthSnapshot? {
        snapshots.max { $0.date < $1.date }
    }

    private func value(of snapshot: NetWorthSnapshot) -> Double {
        NSDecimalNumber(decimal: snapshot.netWorth).doubleValue
    }
}

#Preview {
    SnapshotChartView(snapshots: [])
        .padding()
}
