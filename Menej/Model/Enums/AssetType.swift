//
//  AssetType.swift
//  Menej
//
//  Net worth components per PRD §6 F5/F6.
//

import Foundation

enum AssetType: String, Codable, CaseIterable, Identifiable {
    // Liquid
    case bankAccount
    case eWallet
    case cash

    // Portfolio (F6)
    case crypto
    case stock
    case mutualFund
    case timeDeposit
    case gold

    // Physical (F6) — depreciation curve runs both directions (watches, gold appreciate)
    case electronics
    case vehicle
    case watch
    case jewelry

    var id: String { rawValue }

    var isPhysical: Bool {
        switch self {
        case .electronics, .vehicle, .watch, .jewelry: return true
        default: return false
        }
    }

    var isPortfolio: Bool {
        switch self {
        case .crypto, .stock, .mutualFund, .timeDeposit, .gold: return true
        default: return false
        }
    }
}
