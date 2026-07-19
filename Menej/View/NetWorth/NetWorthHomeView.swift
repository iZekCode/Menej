//
//  NetWorthHomeView.swift
//  Menej
//
//  See PRD §6 F5. Labeled "Total Assets" — honest until liabilities ship in v1.1.
//

import SwiftUI
import SwiftData

struct NetWorthHomeView: View {
    @Query private var accounts: [Account]
    @Query private var assets: [Asset]
    @Query private var holdings: [Holding]
    @Query private var liabilities: [Liability]
    @Query(sort: \NetWorthSnapshot.date) private var snapshots: [NetWorthSnapshot]

    @State private var viewModel = NetWorthViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Assets")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(headlineAmount)
                            .font(AppTypography.netWorthHeadline)
                        if let delta = monthlyDelta {
                            DeltaBadge(delta: delta)
                        }
                    }

                    if snapshots.isEmpty && accounts.isEmpty {
                        EmptyStateView(
                            systemImage: "tray",
                            title: "No statements yet",
                            message: "Share a PDF statement from Mail, Files, or WhatsApp to get started."
                        )
                    } else if snapshots.count >= 2 {
                        SectionCard(title: "6-Month Trend") {
                            SnapshotChartView(snapshots: snapshots)
                        }
                    }
                }
                .padding(AppSpacing.margin)
            }
            .navigationTitle("Menej")
        }
    }

    // Computed fresh on every body evaluation rather than cached via
    // `.onAppear` — see NetWorthViewModel.swift for why that broke.
    private var netWorth: Decimal {
        viewModel.netWorth(accounts: accounts, assets: assets, holdings: holdings, holdingValues: [:], liabilities: liabilities).netWorth
    }

    private var headlineAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp"
        return formatter.string(from: NSDecimalNumber(decimal: netWorth)) ?? "\(netWorth)"
    }

    private var monthlyDelta: Decimal? {
        guard snapshots.count >= 2 else { return nil }
        return snapshots[snapshots.count - 1].netWorth - snapshots[snapshots.count - 2].netWorth
    }
}

#Preview {
    NetWorthHomeView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
