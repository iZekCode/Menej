//
//  PortfolioViewModel.swift
//  Menej
//
//  Drives PortfolioView — see PRD §6 F6. Shows unrealized P/L and allocation
//  weights for crypto, stocks (IDX + US), mutual funds, time deposits, gold,
//  and brokerage cash (e.g. an RDN balance).
//
//  A successful refresh persists each holding's IDR value onto the model
//  (`lastValueIDR`/`lastQuotedAt`) so net worth and monthly snapshots can
//  value the portfolio synchronously and offline. Quote failures are
//  per-holding, not all-or-nothing: a dead symbol falls back to its last
//  persisted value and is flagged stale rather than sinking the refresh.
//

import Foundation
import Observation

struct HoldingDisplay: Identifiable {
    let holding: Holding
    /// Whole-position value in IDR.
    let currentValue: Decimal
    /// nil when the value is a stale/offline fallback — showing a P/L
    /// computed against a live cost basis but a dead quote would be wrong.
    let unrealizedPL: Decimal?
    /// `unrealizedPL` as a fraction of cost basis (0.05 = +5%). Shares
    /// `unrealizedPL`'s nil-when-stale rule; also nil when cost basis is 0
    /// (nothing to take a percentage of).
    let unrealizedPLPercent: Double?
    let allocationWeight: Double
    let isStale: Bool

    var id: UUID { holding.id }
}

@Observable
@MainActor
final class PortfolioViewModel {
    private let pricingService: PricingServiceProtocol

    var holdingDisplays: [HoldingDisplay] = []
    var isRefreshing = false
    var lastRefreshedAt: Date?
    /// Symbols whose quote failed on the last refresh (shown as a banner,
    /// their rows fall back to last persisted values).
    var failedSymbols: [String] = []
    /// For PortfolioView's IDR/USD display toggle. nil until the first
    /// successful fetch; a failed refresh keeps the last known rate rather
    /// than clearing it, same "last known beats nothing" rule as a stale
    /// holding quote — the toggle only offers USD once this is non-nil, so
    /// a figure is never mislabeled as USD without a real rate behind it.
    var idrToUSDRate: Decimal?

    var totalValue: Decimal {
        holdingDisplays.reduce(Decimal(0)) { $0 + $1.currentValue }
    }

    // See ImportViewModel.swift for why the default is built in the body.
    init(pricingService: PricingServiceProtocol? = nil) {
        self.pricingService = pricingService ?? PricingService()
    }

    func refresh(holdings: [Holding]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var displays: [HoldingDisplay] = []
        var failures: [String] = []

        for holding in holdings {
            do {
                let valueIDR = try await currentValueIDR(holding)
                let costIDR = try await costBasisIDR(holding)
                let pl = valueIDR - costIDR
                holding.lastValueIDR = valueIDR
                holding.lastQuotedAt = .now
                displays.append(HoldingDisplay(
                    holding: holding,
                    currentValue: valueIDR,
                    unrealizedPL: pl,
                    unrealizedPLPercent: costIDR > 0 ? NSDecimalNumber(decimal: pl / costIDR).doubleValue : nil,
                    allocationWeight: 0,
                    isStale: false
                ))
            } catch {
                failures.append(holding.symbol)
                displays.append(HoldingDisplay(
                    holding: holding,
                    currentValue: holding.offlineValueIDR,
                    unrealizedPL: nil,
                    unrealizedPLPercent: nil,
                    allocationWeight: 0,
                    isStale: true
                ))
            }
        }

        let total = displays.reduce(Decimal(0)) { $0 + $1.currentValue }
        holdingDisplays = displays
            .map { display in
                let weight = total > 0
                    ? NSDecimalNumber(decimal: display.currentValue / total).doubleValue
                    : 0
                return HoldingDisplay(
                    holding: display.holding,
                    currentValue: display.currentValue,
                    unrealizedPL: display.unrealizedPL,
                    unrealizedPLPercent: display.unrealizedPLPercent,
                    allocationWeight: weight,
                    isStale: display.isStale
                )
            }
            .sorted { $0.currentValue > $1.currentValue }
        failedSymbols = failures
        lastRefreshedAt = .now

        // Cached 60 min inside PricingService, so refreshing repeatedly
        // costs one real Frankfurter call an hour, not one per refresh.
        if let rate = try? await pricingService.fetchFXRate(from: "IDR", to: "USD") {
            idrToUSDRate = rate
        }
    }

    /// Manual-valuation instruments (mutual funds, time deposits,
    /// brokerage cash) never hit a market feed — their unit price is
    /// `manualPrice ?? avgCost`; a time deposit or an RDN cash balance
    /// entered as quantity 1 × principal simply holds its principal.
    private func currentValueIDR(_ holding: Holding) async throws -> Decimal {
        switch holding.instrument {
        case .mutualFund, .timeDeposit, .brokerageCash:
            let unitPrice = holding.manualPrice ?? holding.avgCost
            let fx = try await pricingService.fetchFXRate(from: holding.currency, to: "IDR")
            return unitPrice * holding.quantity * fx
        default:
            let quote = try await pricingService.fetchQuoteIDR(
                symbol: holding.symbol,
                instrument: holding.instrument,
                currency: holding.currency
            )
            return quote * holding.quantity
        }
    }

    /// Cost basis converted at the *current* FX rate, so a USD position's
    /// P/L reflects only the instrument's move, not a frozen historical
    /// rate the app never knew.
    private func costBasisIDR(_ holding: Holding) async throws -> Decimal {
        let fx = try await pricingService.fetchFXRate(from: holding.currency, to: "IDR")
        return holding.avgCost * holding.quantity * fx
    }
}
