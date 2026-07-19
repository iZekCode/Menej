//
//  Category.swift
//  Menej
//
//  Categories per PRD §6 F3.
//

import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
    case food
    case transport
    case shopping
    case bills
    case entertainment
    case health
    case education
    case transfer
    case investment
    case income
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Transport"
        case .shopping: return "Shopping"
        case .bills: return "Bills"
        case .entertainment: return "Entertainment"
        case .health: return "Health"
        case .education: return "Education"
        case .transfer: return "Transfer"
        case .investment: return "Investment"
        case .income: return "Income"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .bills: return "doc.text.fill"
        case .entertainment: return "play.tv.fill"
        case .health: return "heart.fill"
        case .education: return "book.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .income: return "banknote.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}
