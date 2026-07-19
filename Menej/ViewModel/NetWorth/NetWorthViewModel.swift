//
//  NetWorthViewModel.swift
//  Menej
//
//  Shapes net worth data for NetWorthHomeView — see PRD §6 F5.
//  Arithmetic itself lives in NetWorthService; this only shapes for display.
//
//  Deliberately stateless (a pure function of its inputs, not cached
//  properties refreshed imperatively): NetWorthHomeView used to call
//  `refresh(...)` from `.onAppear` into stored `@Observable` properties,
//  which only fires once per tab activation — if the underlying accounts
//  changed afterward (e.g. a statement finished importing asynchronously),
//  the displayed total stayed stale. Recomputing fresh on every call means
//  the View can call this directly from a computed property, which SwiftUI
//  re-evaluates automatically whenever the `@Query`-tracked inputs change.
//

import Foundation
import Observation

@Observable
@MainActor
final class NetWorthViewModel {
    private let netWorthService: NetWorthServiceProtocol

    // See ImportViewModel.swift for why the default is built in the body.
    init(netWorthService: NetWorthServiceProtocol? = nil) {
        self.netWorthService = netWorthService ?? NetWorthService()
    }

    func netWorth(
        accounts: [Account],
        assets: [Asset],
        holdings: [Holding],
        holdingValues: [UUID: Decimal],
        liabilities: [Liability]
    ) -> (totalAssets: Decimal, totalLiabilities: Decimal, netWorth: Decimal) {
        let totalAssets = netWorthService.totalAssets(accounts: accounts, assets: assets, holdings: holdings, holdingValues: holdingValues)
        let totalLiabilities = netWorthService.totalLiabilities(liabilities)
        let netWorth = netWorthService.netWorth(totalAssets: totalAssets, totalLiabilities: totalLiabilities)
        return (totalAssets, totalLiabilities, netWorth)
    }
}
