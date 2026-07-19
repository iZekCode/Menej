//
//  PricingService.swift
//  Menej
//
//  Prices refreshed from public sources — see PRD §6 F5/F6. Rates fetched
//  daily from public endpoints that receive no user data.
//
//  TODO(M4): wire real quote/FX endpoints.
//

import Foundation

protocol PricingServiceProtocol {
    func fetchQuote(symbol: String, instrument: AssetType) async throws -> Decimal
    func fetchFXRate(from currencyCode: String, to currencyCode2: String) async throws -> Decimal
}

struct PricingService: PricingServiceProtocol {
    func fetchQuote(symbol: String, instrument: AssetType) async throws -> Decimal {
        0
    }

    func fetchFXRate(from currencyCode: String, to currencyCode2: String) async throws -> Decimal {
        1
    }
}
