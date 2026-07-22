//
//  NetWorthServiceTests.swift
//  MenejTests
//

import Testing
@testable import Menej

struct NetWorthServiceTests {
    @Test func netWorthIsAssetsMinusLiabilities() {
        let service = NetWorthService()
        let netWorth = service.netWorth(totalAssets: 100, totalLiabilities: 30)
        #expect(netWorth == 70)
    }

    @Test func totalAssetsSumsAccountsAssetsAndHoldings() {
        let service = NetWorthService()
        let account = Account(issuer: .bcaMyBCA, type: .bankAccount, balance: 1_000_000)
        let asset = Asset(type: .watch, name: "Test Watch", acquiredAt: .now, acquisitionCost: 500_000, currentValue: 600_000)
        let total = service.totalAssets(accounts: [account], accountBalances: [:], assets: [asset], holdings: [], holdingValues: [:])
        #expect(total == 1_600_000)
    }
}
