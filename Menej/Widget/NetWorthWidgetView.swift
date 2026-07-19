//
//  NetWorthWidgetView.swift
//  Menej
//
//  See PRD §6 F9. Sizes: small (net worth + delta), medium (net worth + 6-month
//  trend). Refreshes on data change, not on a timer. Privacy mode hides
//  amounts while the device is locked (optional, on by default).
//
//  NOTE: this file currently compiles into the main app target only (the
//  project has a single PBXFileSystemSynchronizedRootGroup target). A real
//  widget requires adding a Widget Extension target in Xcode
//  (File > New > Target > Widget Extension) and moving this code — plus a
//  WidgetBundle `@main` entry point — into that target. TODO(M5).
//

import SwiftUI
import WidgetKit

struct NetWorthWidgetEntry: TimelineEntry {
    let date: Date
    let netWorth: Decimal
    let deltaSinceLastMonth: Decimal
    let isPrivacyModeEnabled: Bool
}

struct NetWorthWidgetView: View {
    let entry: NetWorthWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total Assets")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.isPrivacyModeEnabled {
                Text("••••••••")
                    .font(AppTypography.netWorthHeadline)
            } else {
                AmountText(amount: entry.netWorth)
                    .font(.title.bold())
                DeltaBadge(delta: entry.deltaSinceLastMonth)
            }
        }
        .padding()
    }
}

#Preview {
    NetWorthWidgetView(entry: NetWorthWidgetEntry(date: .now, netWorth: 152_000_000, deltaSinceLastMonth: 3_200_000, isPrivacyModeEnabled: false))
}

// The `Widget`/`WidgetBundle` `@main` conformance and the `#Preview(as:)`
// widget-family preview macro are intentionally omitted here: they only
// make sense once this file lives in a real Widget Extension target
// (see the NOTE above and NetWorthTimelineProvider.swift).
