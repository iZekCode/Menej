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

    var displayName: String {
        switch self {
        case .bankAccount: return "Bank Account"
        case .eWallet: return "E-Wallet"
        case .cash: return "Cash"
        case .crypto: return "Crypto"
        case .stock: return "Stock"
        case .mutualFund: return "Mutual Fund"
        case .timeDeposit: return "Time Deposit"
        case .gold: return "Gold"
        case .electronics: return "Electronics"
        case .vehicle: return "Vehicle"
        case .watch: return "Watch"
        case .jewelry: return "Jewelry"
        }
    }

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
