//
//  LogoServiceTests.swift
//  MenejTests
//

import Testing
@testable import Menej

struct LogoServiceTests {
    @Test func cryptoUsesTheLowercasedSymbol() {
        let url = LogoService.logoURL(symbol: "BTC", instrument: .crypto, currency: "IDR")
        #expect(url?.absoluteString == "https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color/btc.png")
    }

    @Test func idrStockGetsTheJKSuffix() {
        // Same disambiguation PricingService already applies when quoting —
        // Parqet indexes IDX logos under the same suffixed symbol Yahoo does.
        let url = LogoService.logoURL(symbol: "BBCA", instrument: .stock, currency: "IDR")
        #expect(url?.absoluteString == "https://assets.parqet.com/logos/symbol/BBCA.JK?format=png")
    }

    @Test func usStockStaysBare() {
        let url = LogoService.logoURL(symbol: "AAPL", instrument: .stock, currency: "USD")
        #expect(url?.absoluteString == "https://assets.parqet.com/logos/symbol/AAPL?format=png")
    }

    @Test func instrumentsWithNoLogoSourceReturnNil() {
        #expect(LogoService.logoURL(symbol: "ANTAM", instrument: .gold, currency: "IDR") == nil)
        #expect(LogoService.logoURL(symbol: "SR012", instrument: .timeDeposit, currency: "IDR") == nil)
        #expect(LogoService.logoURL(symbol: "RDPT", instrument: .mutualFund, currency: "IDR") == nil)
        #expect(LogoService.logoURL(symbol: "Stockbit RDN", instrument: .brokerageCash, currency: "IDR") == nil)
    }

    @Test func blankSymbolReturnsNil() {
        #expect(LogoService.logoURL(symbol: "  ", instrument: .crypto, currency: "IDR") == nil)
    }
}
