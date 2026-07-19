//
//  SnapshotChartView.swift
//  Menej
//

import SwiftUI
import Charts

struct SnapshotChartView: View {
    let snapshots: [NetWorthSnapshot]

    var body: some View {
        Chart(snapshots) { snapshot in
            LineMark(
                x: .value("Month", snapshot.date, unit: .month),
                y: .value("Net Worth", NSDecimalNumber(decimal: snapshot.netWorth).doubleValue)
            )
            .foregroundStyle(AppColor.accent)
            .interpolationMethod(.monotone)
        }
        .frame(height: 160)
        .accessibilityLabel("Net worth trend over the last \(snapshots.count) months")
    }
}

#Preview {
    SnapshotChartView(snapshots: [])
        .padding()
}
