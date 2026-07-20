//
//  PortfolioView.swift
//  Menej
//
//  See PRD §6 F6. Manual holding entry (quantity + cost basis), prices
//  refreshed from public sources, unrealized P/L and allocation weights.
//

import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var holdings: [Holding]
    @State private var viewModel = PortfolioViewModel()
    @State private var isAddingHolding = false

    var body: some View {
        NavigationStack {
            List {
                if holdings.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "No holdings yet",
                        message: "Add crypto or stocks to track your portfolio."
                    )
                } else {
                    summarySection
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
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AmountText(amount: viewModel.totalValue)
                    .font(.title2.weight(.semibold))
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

    private var holdingsSection: some View {
        Section {
            ForEach(viewModel.holdingDisplays) { display in
                HoldingRow(display: display)
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

private struct HoldingRow: View {
    let display: HoldingDisplay

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.holding.symbol)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: display.currentValue)
                if let unrealizedPL = display.unrealizedPL {
                    AmountText(amount: unrealizedPL, showSign: true)
                        .font(.caption)
                } else if display.isStale {
                    Text("last known")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        let weight = (display.allocationWeight * 100).formatted(.number.precision(.fractionLength(1)))
        return "\(display.holding.instrument.displayName) · \(weight)% of portfolio"
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

    private static let portfolioInstruments: [AssetType] = [.crypto, .stock]

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
        instrument == .crypto ? "Symbol (BTC, ETH…)" : "Ticker (BBCA, AAPL…)"
    }

    private var costFooter: String {
        instrument == .stock
            ? "IDR tickers are looked up on IDX, USD tickers on US exchanges."
            : "Cost basis is used for unrealized P/L."
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
    PortfolioView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
