//
//  PortfolioView.swift
//  Menej
//
//  See PRD §6 F6. Manual holding entry (quantity + cost basis), prices
//  refreshed from public sources, unrealized P/L and allocation weights.
//

import SwiftUI
import SwiftData

/// Portfolio's IDR/USD display toggle. Purely a presentation choice —
/// `Holding`/`HoldingDisplay` always store IDR, this only decides what
/// PortfolioView multiplies by and labels amounts with.
private enum PortfolioCurrency: String, CaseIterable, Identifiable {
    case idr = "IDR"
    case usd = "USD"
    var id: String { rawValue }
}

struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var holdings: [Holding]
    @State private var viewModel = PortfolioViewModel()
    @State private var isAddingHolding = false
    @State private var displayCurrency: PortfolioCurrency = .idr

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack
    // from the Breakdown card.
    var body: some View {
        List {
            if holdings.isEmpty {
                EmptyStateView(
                    systemImage: "chart.pie",
                    title: "No holdings yet",
                    message: "Add crypto or stocks to track your portfolio."
                )
            } else {
                summarySection
                allocationSection
                holdingsSection
            }
        }
        .navigationTitle("Portfolio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Holding", systemImage: "plus") {
                    isAddingHolding = true
                }
            }
        }
        .sheet(isPresented: $isAddingHolding) {
            AddHoldingView()
        }
        .refreshable {
            await viewModel.refresh(holdings: holdings)
        }
        // `id: holdings.count` re-runs the refresh when a holding is
        // added or deleted, not just on first appearance.
        .task(id: holdings.count) {
            await viewModel.refresh(holdings: holdings)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Total Value")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    currencyPicker
                }
                HStack(spacing: AppSpacing.grid) {
                    AmountText(
                        amount: viewModel.totalValue * displayRate,
                        currencyCode: displayCurrency.rawValue,
                        isHidden: appState.areAmountsHidden
                    )
                    .font(.title2.weight(.semibold))
                    Button {
                        appState.areAmountsHidden.toggle()
                    } label: {
                        Image(systemName: appState.areAmountsHidden ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.areAmountsHidden ? "Show amounts" : "Hide amounts")
                }
                if let lastRefreshedAt = viewModel.lastRefreshedAt {
                    Text("Prices as of \(lastRefreshedAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if !viewModel.failedSymbols.isEmpty {
                Label(
                    "No quote for \(viewModel.failedSymbols.joined(separator: ", ")) — showing last known values.",
                    systemImage: "wifi.exclamationmark"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Disabled until an IDR→USD rate has actually loaded — never lets the
    /// screen switch to a "USD" label backed by no real rate. Quantities and
    /// percentages (allocation weight, unrealized P/L%) are unaffected by
    /// this: they're unit counts and ratios, not currency.
    private var currencyPicker: some View {
        Picker("Currency", selection: $displayCurrency) {
            ForEach(PortfolioCurrency.allCases) { currency in
                Text(currency.rawValue).tag(currency)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 120)
        .disabled(viewModel.idrToUSDRate == nil)
    }

    private var displayRate: Decimal {
        displayCurrency == .usd ? (viewModel.idrToUSDRate ?? 1) : 1
    }

    /// Largest holding first, colored by rank — see PortfolioPalette. The
    /// donut, the legend below it, and each holding row's logo ring all
    /// read from this same array so a slice's color never drifts from its
    /// label.
    private var slices: [PortfolioSlice] {
        viewModel.holdingDisplays.enumerated().map { index, display in
            PortfolioSlice(display: display, color: PortfolioPalette.color(at: index))
        }
    }

    @ViewBuilder
    private var allocationSection: some View {
        if slices.count > 1 {
            Section {
                HStack(alignment: .center, spacing: AppSpacing.margin) {
                    PortfolioDonutChart(slices: slices)
                        .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: AppSpacing.grid) {
                        ForEach(slices) { slice in
                            PortfolioLegendRow(slice: slice)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var holdingsSection: some View {
        Section {
            ForEach(slices) { slice in
                HoldingRow(
                    display: slice.display,
                    color: slice.color,
                    currencyCode: displayCurrency.rawValue,
                    rate: displayRate,
                    isHidden: appState.areAmountsHidden
                )
            }
            .onDelete(perform: deleteHoldings)
        }
    }

    private func deleteHoldings(at offsets: IndexSet) {
        let deleted = offsets.map { viewModel.holdingDisplays[$0] }
        for display in deleted {
            modelContext.delete(display.holding)
        }
        // Drop the rows now rather than waiting for the async refresh —
        // a HoldingRow rendering a deleted @Model faults.
        let deletedIds = Set(deleted.map(\.id))
        viewModel.holdingDisplays.removeAll { deletedIds.contains($0.id) }
    }
}

/// Logo + symbol + unrealized P/L on the left, current value + quantity on
/// the right — see PRD §6 F6. `color` matches this holding's donut slice so
/// the row, the ring, and the legend read as one system even before the
/// logo image (if any) loads.
private struct HoldingRow: View {
    let display: HoldingDisplay
    let color: Color
    /// "IDR" or "USD" — see PortfolioCurrency. `rate` is the multiplier
    /// PortfolioView has already resolved for that code (1 for IDR).
    var currencyCode: String = "IDR"
    var rate: Decimal = 1
    var isHidden: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            HoldingLogo(
                symbol: display.holding.symbol,
                instrument: display.holding.instrument,
                currency: display.holding.currency,
                color: color
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(display.holding.symbol)
                    .font(.subheadline.weight(.semibold))
                if let unrealizedPL = display.unrealizedPL, let unrealizedPLPercent = display.unrealizedPLPercent {
                    UnrealizedPLLabel(
                        amount: unrealizedPL * rate,
                        percent: unrealizedPLPercent,
                        currencyCode: currencyCode,
                        isHidden: isHidden
                    )
                } else if display.isStale {
                    Text("last known")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: display.currentValue * rate, currencyCode: currencyCode, isHidden: isHidden)
                    .font(.subheadline)
                if !isHidden {
                    // Unit count, not currency — never scaled by `rate`.
                    Text(quantityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quantityText: String {
        "\(display.holding.quantity.formatted(.number.precision(.fractionLength(0...8)))) \(display.holding.symbol)"
    }
}

/// Circular ticker logo, fetched from LogoService's keyless CDNs. Falls back
/// to a color-ringed monogram — while loading, on a failed/missing quote, or
/// for instruments with no logo source (gold, mutual funds) — same pattern
/// as InventoryView's ItemThumbnail falling back to a system icon.
private struct HoldingLogo: View {
    let symbol: String
    let instrument: AssetType
    let currency: String
    let color: Color

    private var url: URL? {
        LogoService.logoURL(symbol: symbol, instrument: instrument, currency: currency)
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit().padding(6)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: 36, height: 36)
        .background(Color(.secondarySystemBackground))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color.opacity(0.5), lineWidth: 1.5))
    }

    private var monogram: some View {
        Text(symbol.prefix(1))
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

/// A signed IDR delta with its percentage in parentheses — e.g.
/// "+Rp60.58 (+10.10%)" — green/red like every other gain/loss figure.
private struct UnrealizedPLLabel: View {
    let amount: Decimal
    let percent: Double
    var currencyCode: String = "IDR"
    var isHidden: Bool = false

    var body: some View {
        if isHidden {
            Text(verbatim: "••••••")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("\(AmountText.string(amount: amount, currencyCode: currencyCode, showSign: true)) (\(percentText))")
                .font(.caption)
                .numericStyle()
                .foregroundStyle(amount < 0 ? AppColor.loss : AppColor.gain)
        }
    }

    private var percentText: String {
        let sign = percent >= 0 ? "+" : "-"
        return "\(sign)\(abs(percent * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

/// One row of the allocation legend — color dot, symbol, share of the
/// portfolio. Directly labels each donut slice (the relief rule
/// PortfolioDonutChart's header describes) so color is never the only thing
/// telling two holdings apart.
private struct PortfolioLegendRow: View {
    let slice: PortfolioSlice

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            Circle()
                .fill(slice.color)
                .frame(width: 8, height: 8)
            Text(slice.display.holding.symbol)
                .font(.subheadline)
            Spacer()
            Text(weightText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var weightText: String {
        "\((slice.display.allocationWeight * 100).formatted(.number.precision(.fractionLength(2))))%"
    }
}

private struct AddHoldingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var instrument: AssetType = .stock
    @State private var symbol = ""
    @State private var quantity: Decimal?
    @State private var avgCost: Decimal?
    @State private var currency = "IDR"

    private static let portfolioInstruments: [AssetType] = [.crypto, .stock, .brokerageCash]

    private var canSave: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty
            && (quantity ?? 0) > 0
            && (avgCost ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Instrument", selection: $instrument) {
                        ForEach(Self.portfolioInstruments) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField(symbolPrompt, text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Quantity", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Average cost per unit", value: $avgCost, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        Text("IDR").tag("IDR")
                        Text("USD").tag("USD")
                    }
                } footer: {
                    Text(costFooter)
                }
            }
            .navigationTitle("Add Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var symbolPrompt: String {
        switch instrument {
        case .crypto: return "Symbol (BTC, ETH…)"
        case .brokerageCash: return "Label (e.g. Stockbit RDN)"
        default: return "Ticker (BBCA, AAPL…)"
        }
    }

    private var costFooter: String {
        switch instrument {
        case .stock:
            return "IDR tickers are looked up on IDX, USD tickers on US exchanges."
        case .brokerageCash:
            return "Enter 1 as quantity and your balance as the cost — this has no market price, so it's valued exactly as entered."
        default:
            return "Cost basis is used for unrealized P/L."
        }
    }

    private func save() {
        let holding = Holding(
            instrument: instrument,
            symbol: symbol.trimmingCharacters(in: .whitespaces),
            quantity: quantity ?? 0,
            avgCost: avgCost ?? 0,
            currency: currency
        )
        modelContext.insert(holding)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environment(AppState())
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
