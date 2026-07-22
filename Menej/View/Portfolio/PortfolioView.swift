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
    @State private var editingHolding: Holding?
    /// Bumped on every save so the price refresh re-runs after an edit —
    /// `holdings.count` alone can't see one, which would leave the row
    /// showing a value still computed from the old quantity.
    @State private var editRevision = 0
    @State private var displayCurrency: PortfolioCurrency = .usd

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
        // Matches InsightsView's inter-block gap — List's default section
        // spacing is noticeably wider than the AppSpacing.margin rhythm
        // every other screen uses between blocks.
        .listSectionSpacing(AppSpacing.margin)
        .navigationTitle("Portfolio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Holding", systemImage: "plus") {
                    isAddingHolding = true
                }
            }
        }
        .sheet(isPresented: $isAddingHolding) {
            HoldingFormView(mode: .add) { editRevision += 1 }
        }
        .sheet(item: $editingHolding) { holding in
            HoldingFormView(mode: .edit(holding)) { editRevision += 1 }
        }
        .refreshable {
            await viewModel.refresh(holdings: holdings)
        }
        // Re-runs the refresh when a holding is added, deleted, or edited —
        // not just on first appearance.
        .task(id: refreshKey) {
            await viewModel.refresh(holdings: holdings)
        }
    }

    private var refreshKey: String { "\(holdings.count)-\(editRevision)" }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AppSpacing.grid) {
                    Text("Total Value")
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
                // Symbol dropped here — the picker right after it already
                // names the currency, so "Rp"/"$" would just repeat it.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    AmountText(
                        amount: viewModel.totalValue * displayRate,
                        currencyCode: effectiveCurrency.rawValue,
                        showsSymbol: false,
                        isHidden: appState.areAmountsHidden
                    )
                    .font(.title.bold())
                    currencyPicker
                }
                // The other currency's equivalent, so switching to USD
                // doesn't lose the IDR figure everything else on the app
                // is denominated in.
                if effectiveCurrency == .usd, !appState.areAmountsHidden {
                    Text("≈ \(AmountText.string(amount: viewModel.totalValue))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
//                if let lastRefreshedAt = viewModel.lastRefreshedAt {
//                    Text("Prices as of \(lastRefreshedAt, style: .time)")
//                        .font(.caption)
//                        .foregroundStyle(.secondary)
//                }
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

    /// Renders as "USD ⌄", styled to sit quietly next to the headline number
    /// rather than read as a tinted link — a plain `Picker(.menu)` takes the
    /// system accent color, which would compete with the amount for
    /// attention. The trigger label shows `effectiveCurrency`, not the raw
    /// selection: on first launch, before an IDR→USD rate has loaded, that
    /// falls back to IDR so the screen is never captioned "USD" over a
    /// figure that's actually still IDR. The checkmark below shows the
    /// user's real selection either way. Quantities and percentages
    /// (allocation weight, unrealized P/L%) are unaffected by any of this:
    /// they're unit counts and ratios, not currency.
    private var currencyPicker: some View {
        Menu {
            ForEach(PortfolioCurrency.allCases) { currency in
                Button {
                    displayCurrency = currency
                } label: {
                    if currency == displayCurrency {
                        Label(currency.rawValue, systemImage: "checkmark")
                    } else {
                        Text(currency.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(effectiveCurrency.rawValue)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
        }
        // Menu colors its trigger from `.tint`, not the label's own
        // foregroundStyle — without this it renders in the app's lilac
        // accent regardless of the .secondary set above.
        .tint(.secondary)
        .disabled(viewModel.idrToUSDRate == nil)
    }

    /// `displayCurrency` is the user's selection; this is what's actually
    /// safe to render right now. Falls back to IDR while USD is selected
    /// but no rate has loaded yet — the only state where the two diverge.
    private var effectiveCurrency: PortfolioCurrency {
        displayCurrency == .usd && viewModel.idrToUSDRate == nil ? .idr : displayCurrency
    }

    private var displayRate: Decimal {
        effectiveCurrency == .usd ? (viewModel.idrToUSDRate ?? 1) : 1
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
                // A plain Button keeps the row's own layout (a NavigationLink
                // would push, and Add is a sheet — mixing the two for the same
                // form would be inconsistent), so the chevron is drawn here to
                // keep the row visibly tappable.
                Button {
                    editingHolding = slice.display.holding
                } label: {
                    HStack(spacing: AppSpacing.grid) {
                        HoldingRow(
                            display: slice.display,
                            currencyCode: effectiveCurrency.rawValue,
                            rate: displayRate,
                            isHidden: appState.areAmountsHidden
                        )
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit holding")
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
/// the right — see PRD §6 F6.
private struct HoldingRow: View {
    let display: HoldingDisplay
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
                currency: display.holding.currency
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
/// to a plain monogram — while loading, on a failed/missing quote, or for
/// instruments with no logo source (gold, mutual funds) — same pattern as
/// InventoryView's ItemThumbnail falling back to a system icon. Deliberately
/// neutral, not tinted to the holding's donut-slice color — that color
/// identifies a slice's *position in the ranking*, not the instrument
/// itself, so carrying it onto the logo would be a false association.
private struct HoldingLogo: View {
    let symbol: String
    let instrument: AssetType
    let currency: String

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
    }

    private var monogram: some View {
        Text(symbol.prefix(1))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
                .foregroundStyle(plColor)
        }
    }

    /// A flat position (rounds to exactly 0) is neither a gain nor a loss —
    /// green would read as "up" for something that hasn't moved.
    private var plColor: Color {
        amount == 0 ? .secondary : (amount < 0 ? AppColor.loss : AppColor.gain)
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

/// Adding and editing share one form: the fields, per-instrument prompts and
/// validation are identical, and only what Save does differs.
private struct HoldingFormView: View {
    enum Mode {
        case add
        case edit(Holding)

        var holding: Holding? {
            if case .edit(let holding) = self { return holding }
            return nil
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    private let onSave: () -> Void

    @State private var instrument: AssetType
    @State private var symbol: String
    @State private var quantity: Decimal?
    @State private var avgCost: Decimal?
    @State private var currency: String

    init(mode: Mode, onSave: @escaping () -> Void = {}) {
        self.mode = mode
        self.onSave = onSave
        let holding = mode.holding
        _instrument = State(initialValue: holding?.instrument ?? .stock)
        _symbol = State(initialValue: holding?.symbol ?? "")
        _quantity = State(initialValue: holding?.quantity)
        _avgCost = State(initialValue: holding?.avgCost)
        _currency = State(initialValue: holding?.currency ?? "IDR")
    }

    private static let portfolioInstruments: [AssetType] = [.crypto, .stock, .brokerageCash]

    /// The instruments the app can price today, plus whatever this holding
    /// already is. A holding whose type isn't in that list (gold, a mutual
    /// fund) would otherwise open on a blank Picker, which reads as a cleared
    /// field even though an untouched save writes the original value back.
    private var instrumentOptions: [AssetType] {
        guard let current = mode.holding?.instrument,
              !Self.portfolioInstruments.contains(current) else {
            return Self.portfolioInstruments
        }
        return Self.portfolioInstruments + [current]
    }

    private var isEditing: Bool { mode.holding != nil }

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
                        ForEach(instrumentOptions) { type in
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
            .navigationTitle(isEditing ? "Edit Holding" : "Add Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
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
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            modelContext.insert(Holding(
                instrument: instrument,
                symbol: trimmedSymbol,
                quantity: quantity ?? 0,
                avgCost: avgCost ?? 0,
                currency: currency
            ))
        case .edit(let holding):
            apply(to: holding, symbol: trimmedSymbol)
        }
        onSave()
        dismiss()
    }

    /// `lastValueIDR` is a whole-position IDR figure that net worth and the
    /// monthly snapshots read synchronously and offline (`offlineValueIDR`),
    /// so an edit can't just leave it sitting there:
    ///
    /// - **quantity changed** — the per-unit price behind it is still good, so
    ///   rescale instead of discarding a fresh quote. Clearing it here would
    ///   drop a foreign-currency holding's contribution to zero until the next
    ///   refresh, since `offlineValueIDR` has no honest fallback for those.
    /// - **symbol / instrument / currency changed** — this is a different
    ///   instrument now and the cached value describes the old one. Clearing
    ///   returns it to the same "not yet priced" state a new holding starts in.
    /// - **avgCost changed** — cost basis feeds unrealized P/L only, never
    ///   value, so the cache stays valid.
    private func apply(to holding: Holding, symbol trimmedSymbol: String) {
        let newQuantity = quantity ?? 0
        let isDifferentInstrument = holding.symbol != trimmedSymbol
            || holding.instrument != instrument
            || holding.currency != currency

        if isDifferentInstrument {
            holding.lastValueIDR = nil
            holding.lastQuotedAt = nil
        } else if let lastValueIDR = holding.lastValueIDR, holding.quantity != newQuantity {
            // A zero old quantity has no per-unit price to scale from.
            holding.lastValueIDR = holding.quantity > 0
                ? lastValueIDR / holding.quantity * newQuantity
                : nil
        }

        holding.instrument = instrument
        holding.symbol = trimmedSymbol
        holding.quantity = newQuantity
        holding.avgCost = avgCost ?? 0
        holding.currency = currency
    }
}

#Preview {
    NavigationStack {
        PortfolioView()
    }
    .environment(AppState())
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
