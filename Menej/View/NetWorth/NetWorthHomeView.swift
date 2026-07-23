//
//  NetWorthHomeView.swift
//  Menej
//
//  See PRD §6 F5. Assets minus liabilities — the headline said "Total Assets"
//  for as long as nothing could create a `Liability`; LiabilitiesView closed
//  that gap, so this is a real net worth figure now.
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

    /// The chart card is labelled "6-Month Trend", so it gets six months —
    /// it used to plot every snapshot ever written under that title.
    private static let trendMonths = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    headline

                    if snapshots.isEmpty && accounts.isEmpty {
                        EmptyStateView(
                            systemImage: "tray",
                            title: "No statements yet",
                            message: "Share a PDF statement from Mail, Files, or WhatsApp to get started."
                        )
                    } else {
                        breakdownCard
                        runwayCard

                        if trendSnapshots.count >= 2 {
                            SectionCard(title: "6-Month Trend") {
                                SnapshotChartView(snapshots: trendSnapshots, isHidden: appState.areAmountsHidden)
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

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AppSpacing.grid) {
                Text("Net Worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    appState.areAmountsHidden.toggle()
                } label: {
                    Image(systemName: appState.areAmountsHidden ? "eye.slash" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.areAmountsHidden ? "Show amounts" : "Hide amounts")
            }
            Text(appState.areAmountsHidden ? "••••••" : headlineAmount)
                .font(AppTypography.netWorthHeadline)
            if let delta = monthlyDelta, !appState.areAmountsHidden {
                DeltaBadge(delta: delta)
            }
        }
    }

    // MARK: - Breakdown

    private var breakdownCard: some View {
        SectionCard(title: "Breakdown") {
            VStack(spacing: AppSpacing.grid) {
                // The ring shows proportion; the rows below name every slice
                // (the relief rule the other two donuts follow). Below two
                // non-zero components there's no proportion worth drawing.
                if slices.count >= 2 {
                    NetWorthDonutChart(
                        slices: slices,
                        total: totalAssets,
                        isHidden: appState.areAmountsHidden
                    )
                    .padding(.bottom, AppSpacing.grid)
                }

                // Liquid, Portfolio and Inventory are net-worth components,
                // not top-level tabs — drill in from their breakdown rows.
                // Every component keeps its row even at zero, so an empty
                // Inventory is still reachable to add the first item.
                NavigationLink {
                    LiquidAccountsView()
                } label: {
                    BreakdownRow(component: .liquid, amount: liquidTotal, isHidden: appState.areAmountsHidden)
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink {
                    PortfolioView()
                } label: {
                    BreakdownRow(component: .portfolio, amount: portfolioTotal, isHidden: appState.areAmountsHidden)
                }
                .buttonStyle(.plain)
                Divider()
                NavigationLink {
                    InventoryView()
                } label: {
                    BreakdownRow(component: .inventory, amount: physicalTotal, isHidden: appState.areAmountsHidden)
                }
                .buttonStyle(.plain)

                // Liabilities are subtracted, not allocated: they're set off
                // below a heavier rule and rendered negative, and they're
                // deliberately not a donut slice — the ring is what the
                // assets are made of.
                Divider()
                    .padding(.vertical, 2)
                NavigationLink {
                    LiabilitiesView()
                } label: {
                    LiabilitiesRow(amount: totalLiabilities, isHidden: appState.areAmountsHidden)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Only components that actually hold something. A zero slice would be an
    /// invisible wedge with a legend row pointing at it.
    private var slices: [NetWorthSlice] {
        [
            NetWorthSlice(component: .liquid, amount: liquidTotal),
            NetWorthSlice(component: .portfolio, amount: portfolioTotal),
            NetWorthSlice(component: .inventory, amount: physicalTotal),
        ]
        .filter { $0.amount > 0 }
    }

    // MARK: - Runway

    /// Absent, not zero, when InsightService withholds — see
    /// NetWorthViewModel.runway.
    @ViewBuilder
    private var runwayCard: some View {
        if let runway = viewModel.runway(liquidAssets: liquidTotal, transactions: transactions) {
            SectionCard(title: "Runway") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.runwayText(months: runway.months))
                        .font(.title3.weight(.semibold))
                    Text("Your liquid assets at \(AmountText.string(amount: runway.averageMonthlySpend)) a month, your average spend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Past a couple of years the exact month count is false precision — it's
    /// derived from an average of a handful of months, and "37 months" claims
    /// an accuracy the input doesn't have.
    private static func runwayText(months: Double) -> String {
        switch months {
        case ..<1:
            return "Under a month"
        case ..<24:
            let rounded = Int(months.rounded())
            return rounded == 1 ? "1 month" : "\(rounded) months"
        default:
            return "Over \(Int(months / 12)) years"
        }
    }

    // MARK: - Derived data

    // Computed fresh on every body evaluation rather than cached via
    // `.onAppear` — see NetWorthViewModel.swift for why that broke.
    private var totals: (totalAssets: Decimal, totalLiabilities: Decimal, netWorth: Decimal) {
        viewModel.netWorth(
            accounts: accounts,
            accountBalances: accountBalances,
            assets: assets,
            holdings: holdings,
            holdingValues: holdingValues,
            liabilities: liabilities
        )
    }

    private var totalAssets: Decimal { totals.totalAssets }
    private var totalLiabilities: Decimal { totals.totalLiabilities }
    private var netWorth: Decimal { totals.netWorth }

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

    private var trendSnapshots: [NetWorthSnapshot] {
        Array(snapshots.suffix(Self.trendMonths))
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
    let component: NetWorthComponent
    let amount: Decimal
    var isHidden: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            // Doubles as the donut's legend swatch, which is why the dot and
            // the icon both appear — the dot ties the row to a wedge, the
            // icon says what the row is.
            Circle()
                .fill(component.tint)
                .frame(width: 8, height: 8)
            Label(component.displayName, systemImage: component.systemImage)
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
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Deliberately not a `BreakdownRow`: it has no donut slice to swatch, and its
/// amount is subtracted, so it's shown in the loss color with a sign rather
/// than as one more figure in a column of assets.
private struct LiabilitiesRow: View {
    let amount: Decimal
    var isHidden: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            // Keeps the label aligned with the rows above, which start with
            // an 8pt swatch.
            Color.clear
                .frame(width: 8, height: 8)
            Label("Liabilities", systemImage: "creditcard")
                .font(.subheadline)
            Spacer()
            if isHidden {
                Text(verbatim: "••••••")
                    .font(.subheadline)
                    .monospacedDigit()
            } else if amount > 0 {
                Text("-\(AmountText.string(amount: amount))")
                    .font(.subheadline)
                    .numericStyle()
                    .foregroundStyle(AppColor.loss)
            } else {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NetWorthHomeView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
