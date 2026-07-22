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
    /// Uninvested IDR sitting in a brokerage cash account (e.g. a Stockbit
    /// RDN balance) — money that's left the bank but isn't in a specific
    /// stock yet. Distinct from `.cash` (physical wallet cash, PRD §6
    /// "Assets": a separate, still-unbuilt liquid asset class) — the two
    /// are different real-world things and would be confusing to conflate.
    /// Manual valuation only, same as `.timeDeposit`.
    case brokerageCash

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
        case .brokerageCash: return "Cash (RDN)"
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
        case .crypto, .stock, .mutualFund, .timeDeposit, .gold, .brokerageCash: return true
        default: return false
        }
    }
}
