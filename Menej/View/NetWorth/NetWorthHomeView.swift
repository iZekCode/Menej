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
    // Liquid balances roll forward from each account's anchor, so the
    // headline depends on transactions too — see LiquidBalanceService.
    @Query private var transactions: [Transaction]
    @Query private var assets: [Asset]
    @Query private var holdings: [Holding]
    @Query private var liabilities: [Liability]
    @Query(sort: \NetWorthSnapshot.date) private var snapshots: [NetWorthSnapshot]

    @Environment(AppState.self) private var appState
    @State private var viewModel = NetWorthViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Assets")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: AppSpacing.grid) {
                            Text(appState.areAmountsHidden ? "••••••" : headlineAmount)
                                .font(AppTypography.netWorthHeadline)
                            Button {
                                appState.areAmountsHidden.toggle()
                            } label: {
                                Image(systemName: appState.areAmountsHidden ? "eye.slash" : "eye")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(appState.areAmountsHidden ? "Show amounts" : "Hide amounts")
                        }
                        if let delta = monthlyDelta, !appState.areAmountsHidden {
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
                // Liquid, Portfolio and Inventory are net-worth components,
                // not top-level tabs — drill in from their breakdown rows.
                NavigationLink {
                    LiquidAccountsView()
                } label: {
                    BreakdownRow(label: "Liquid", systemImage: "banknote", amount: liquidTotal, showsChevron: true, isHidden: appState.areAmountsHidden)
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink {
                    PortfolioView()
                } label: {
                    BreakdownRow(label: "Portfolio", systemImage: "chart.pie", amount: portfolioTotal, showsChevron: true, isHidden: appState.areAmountsHidden)
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink {
                    InventoryView()
                } label: {
                    BreakdownRow(label: "Inventory", systemImage: "shippingbox", amount: physicalTotal, showsChevron: true, isHidden: appState.areAmountsHidden)
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
            accountBalances: accountBalances,
            assets: assets,
            holdings: holdings,
            holdingValues: holdingValues,
            liabilities: liabilities
        ).netWorth
    }

    private var accountBalances: [UUID: Decimal] {
        LiquidBalanceService().balances(accounts: accounts, transactions: transactions)
    }

    /// Holdings valued from their last persisted quote — synchronous and
    /// offline-safe. PortfolioView's refresh keeps these current.
    private var holdingValues: [UUID: Decimal] {
        Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0.offlineValueIDR) })
    }

    private var liquidTotal: Decimal {
        accountBalances.values.reduce(Decimal(0), +)
    }

    private var portfolioTotal: Decimal {
        holdings.reduce(Decimal(0)) { $0 + $1.offlineValueIDR }
    }

    private var physicalTotal: Decimal {
        assets.reduce(Decimal(0)) { $0 + $1.currentValue }
    }

    private var headlineAmount: String {
        // `AmountText.string` formats the magnitude; a negative net worth
        // still has to read as negative here.
        let value = AmountText.string(amount: netWorth)
        return netWorth < 0 ? "-\(value)" : value
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
    var isHidden: Bool = false

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
                .font(.subheadline)
            Spacer()
            if isHidden {
                Text(verbatim: "••••••")
                    .font(.subheadline)
                    .monospacedDigit()
            } else {
                AmountText(amount: amount)
                    .font(.subheadline)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NetWorthHomeView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
