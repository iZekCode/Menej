//
//  PortfolioView.swift
//  Menej
//
//  See PRD §6 F6. Shows unrealized P/L and allocation weights.
//

import SwiftUI
import SwiftData

struct PortfolioView: View {
    @Query private var holdings: [Holding]
    @State private var viewModel = PortfolioViewModel()

    var body: some View {
        NavigationStack {
            List {
                if holdings.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "No holdings yet",
                        message: "Add crypto, stocks, mutual funds, time deposits, or gold to track your portfolio."
                    )
                } else {
                    ForEach(viewModel.holdingDisplays) { display in
                        HoldingRow(display: display)
                    }
                }
            }
            .navigationTitle("Portfolio")
            .task {
                await viewModel.refresh(holdings: holdings)
            }
        }
    }
}

private struct HoldingRow: View {
    let display: HoldingDisplay

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(display.holding.symbol)
                Text("\(display.allocationWeight * 100, specifier: "%.1f")% of portfolio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                AmountText(amount: display.currentValue)
                AmountText(amount: display.unrealizedPL, showSign: true)
                    .font(.caption)
            }
        }
    }
}

#Preview {
    PortfolioView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
