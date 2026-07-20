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
                    } else {
                        breakdownCard

                        if snapshots.count >= 2 {
                            SectionCard(title: "6-Month Trend") {
                                SnapshotChartView(snapshots: snapshots)
                            }
                        }
                    }
                }
                .padding(AppSpacing.margin)
            }
            .navigationTitle("Menej")
            // Curve-managed physical asset values drift with time, not with
            // data changes — recompute on appear so the headline (and the
            // stored currentValue that snapshots read) stays current.
            .onAppear {
                for asset in assets {
                    asset.applyCurveIfNeeded()
                }
            }
        }
    }

    private var breakdownCard: some View {
        SectionCard(title: "Breakdown") {
            VStack(spacing: AppSpacing.grid) {
                BreakdownRow(label: "Liquid", systemImage: "banknote", amount: liquidTotal)
                Divider()
                BreakdownRow(label: "Portfolio", systemImage: "chart.pie", amount: portfolioTotal)
                Divider()
                NavigationLink {
                    PhysicalAssetsView()
                } label: {
                    BreakdownRow(
                        label: "Physical Assets",
                        systemImage: "briefcase",
                        amount: physicalTotal,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Computed fresh on every body evaluation rather than cached via
    // `.onAppear` — see NetWorthViewModel.swift for why that broke.
    private var netWorth: Decimal {
        viewModel.netWorth(
            accounts: accounts,
            assets: assets,
            holdings: holdings,
            holdingValues: holdingValues,
            liabilities: liabilities
        ).netWorth
    }

    /// Holdings valued from their last persisted quote — synchronous and
    /// offline-safe. PortfolioView's refresh keeps these current.
    private var holdingValues: [UUID: Decimal] {
        Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0.offlineValueIDR) })
    }

    private var liquidTotal: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var portfolioTotal: Decimal {
        holdings.reduce(Decimal(0)) { $0 + $1.offlineValueIDR }
    }

    private var physicalTotal: Decimal {
        assets.reduce(Decimal(0)) { $0 + $1.currentValue }
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

private struct BreakdownRow: View {
    let label: String
    let systemImage: String
    let amount: Decimal
    var showsChevron: Bool = false

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
            Spacer()
            AmountText(amount: amount)
                .font(.subheadline)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NetWorthHomeView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
