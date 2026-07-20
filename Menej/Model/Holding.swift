//
//  Holding.swift
//  Menej
//
//  Investment holdings (PRD §6 F6) — crypto, stocks, mutual funds, time deposits, gold.
//

import Foundation
import SwiftData

@Model
final class Holding {
    @Attribute(.unique) var id: UUID
    var instrument: AssetType
    var symbol: String
    /// Units priced by PricingService: coins for crypto, shares for stocks,
    /// grams for gold (the unit Indonesian gold is bought in).
    var quantity: Decimal
    var avgCost: Decimal
    var currency: String
    /// Per-unit price in `currency`, entered by the user — the only price
    /// source for mutual funds and time deposits (no keyless public feed
    /// exists for reksadana NAV); ignored for market-priced instruments.
    var manualPrice: Decimal?
    /// Whole-position value in IDR as of `lastQuotedAt`, persisted so net
    /// worth and monthly snapshots can read holdings synchronously and
    /// offline instead of blocking on a quote fetch.
    var lastValueIDR: Decimal?
    var lastQuotedAt: Date?

    init(
        id: UUID = UUID(),
        instrument: AssetType,
        symbol: String,
        quantity: Decimal,
        avgCost: Decimal,
        currency: String = "IDR",
        manualPrice: Decimal? = nil,
        lastValueIDR: Decimal? = nil,
        lastQuotedAt: Date? = nil
    ) {
        self.id = id
        self.instrument = instrument
        self.symbol = symbol
        self.quantity = quantity
        self.avgCost = avgCost
        self.currency = currency
        self.manualPrice = manualPrice
        self.lastValueIDR = lastValueIDR
        self.lastQuotedAt = lastQuotedAt
    }

    /// Best available IDR value without a network round-trip: the persisted
    /// last quote, else manual/cost valuation for IDR-denominated holdings.
    /// Foreign-currency holdings have no honest offline fallback (cost basis
    /// in USD would be off by the whole FX rate), so they contribute nothing
    /// until first refreshed.
    var offlineValueIDR: Decimal {
        if let lastValueIDR { return lastValueIDR }
        guard currency == "IDR" else { return 0 }
        return (manualPrice ?? avgCost) * quantity
    }
}
