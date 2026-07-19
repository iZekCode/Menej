//
//  PortfolioViewModel.swift
//  Menej
//
//  Drives PortfolioView — see PRD §6 F6. Shows unrealized P/L and allocation
//  weights for crypto, stocks (IDX + US), mutual funds, time deposits, gold.
//

import Foundation
import Observation

struct HoldingDisplay: Identifiable {
    let holding: Holding
    let currentValue: Decimal
    let unrealizedPL: Decimal
    let allocationWeight: Double

    var id: UUID { holding.id }
}

@Observable
@MainActor
final class PortfolioViewModel {
    private let pricingService: PricingServiceProtocol

    var holdingDisplays: [HoldingDisplay] = []

    // See ImportViewModel.swift for why the default is built in the body.
    init(pricingService: PricingServiceProtocol? = nil) {
        self.pricingService = pricingService ?? PricingService()
    }

    func refresh(holdings: [Holding]) async {
        var displays: [HoldingDisplay] = []
        var totalValue: Decimal = 0

        for holding in holdings {
            let quote = (try? await pricingService.fetchQuote(symbol: holding.symbol, instrument: holding.instrument)) ?? 0
            let currentValue = quote * holding.quantity
            let costBasis = holding.avgCost * holding.quantity
            displays.append(HoldingDisplay(holding: holding, currentValue: currentValue, unrealizedPL: currentValue - costBasis, allocationWeight: 0))
            totalValue += currentValue
        }

        holdingDisplays = displays.map { display in
            let weight = totalValue > 0 ? NSDecimalNumber(decimal: display.currentValue / totalValue).doubleValue : 0
            return HoldingDisplay(holding: display.holding, currentValue: display.currentValue, unrealizedPL: display.unrealizedPL, allocationWeight: weight)
        }
    }
}
