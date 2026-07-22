//
//  LogoService.swift
//  Menej
//
//  Ticker logos for Portfolio holdings — keyless, symbol-only (PRD §8: no
//  user data leaves the device, same as PricingService).
//
//  Two static CDNs, verified against the real corpus of symbols this app
//  actually prices:
//  - Crypto: the `cryptocurrency-icons` set via jsDelivr, keyed by lowercase
//    symbol. Covers Indodax's major pairs (BTC, ETH, SOL, DOGE, USDT, …).
//  - Stocks: Parqet's public logo endpoint, keyed by the *same* symbol
//    PricingService already sends to Yahoo (bare US ticker, ".JK"-suffixed
//    IDX ticker) — confirmed the ".JK" form is what Parqet indexes too
//    (e.g. bare "BBRI" 404s, "BBRI.JK" doesn't).
//
//  Coverage isn't universal — an obscure or newly-listed symbol can still
//  404. This only builds the URL; HoldingLogo (PortfolioView) is what
//  handles a failed load by falling back to a plain monogram, same as
//  InventoryView's ItemPhoto falls back to a system icon when there's
//  no photo.
//
//  Gold/mutual funds/time deposits have no ticker to look up a logo for.
//

import Foundation

enum LogoService {
    static func logoURL(symbol: String, instrument: AssetType, currency: String) -> URL? {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        switch instrument {
        case .crypto:
            return URL(string: "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color/\(trimmed.lowercased()).png")
        case .stock:
            let query = PricingService.stockQuerySymbol(symbol: trimmed, currency: currency)
            return URL(string: "https://assets.parqet.com/logos/symbol/\(query)?format=png")
        case .mutualFund, .timeDeposit, .gold, .brokerageCash,
             .bankAccount, .eWallet, .cash, .electronics, .vehicle, .watch, .jewelry:
            return nil
        }
    }
}
