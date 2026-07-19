//
//  NetWorthService.swift
//  Menej
//
//  See PRD §6 F5. v1 label is "Total Assets" until liabilities ship in v1.1 —
//  totalLiabilities is summed regardless so the schema doesn't need a
//  retrofit later.
//

import Foundation

protocol NetWorthServiceProtocol {
    func totalAssets(accounts: [Account], assets: [Asset], holdings: [Holding], holdingValues: [UUID: Decimal]) -> Decimal
    func totalLiabilities(_ liabilities: [Liability]) -> Decimal
    func netWorth(totalAssets: Decimal, totalLiabilities: Decimal) -> Decimal
}

struct NetWorthService: NetWorthServiceProtocol {
    func totalAssets(accounts: [Account], assets: [Asset], holdings: [Holding], holdingValues: [UUID: Decimal]) -> Decimal {
        let accountsTotal = accounts.reduce(Decimal(0)) { $0 + $1.balance }
        let physicalTotal = assets.reduce(Decimal(0)) { $0 + $1.currentValue }
        let holdingsTotal = holdings.reduce(Decimal(0)) { $0 + (holdingValues[$1.id] ?? 0) }
        return accountsTotal + physicalTotal + holdingsTotal
    }

    func totalLiabilities(_ liabilities: [Liability]) -> Decimal {
        liabilities.reduce(Decimal(0)) { $0 + $1.outstanding }
    }

    func netWorth(totalAssets: Decimal, totalLiabilities: Decimal) -> Decimal {
        totalAssets - totalLiabilities
    }
}
