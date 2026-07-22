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

    /// Icon shown when an asset has no image of its own. Inventory's grid
    /// leans on this: a wall of identical `shippingbox` glyphs (what the old
    /// list used) tells you nothing, whereas one glyph per category still
    /// distinguishes a laptop from a motorbike at a glance.
    var systemImage: String {
        switch self {
        case .bankAccount: return "banknote"
        case .eWallet: return "wallet.bifold"
        case .cash: return "dollarsign.circle"
        case .crypto: return "bitcoinsign.circle"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .mutualFund: return "chart.pie"
        case .timeDeposit: return "lock.circle"
        case .gold: return "circle.hexagongrid.fill"
        case .brokerageCash: return "building.columns"
        case .electronics: return "laptopcomputer"
        case .vehicle: return "car.fill"
        case .watch: return "watch.analog"
        case .jewelry: return "diamond"
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
