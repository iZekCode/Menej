//
//  Holding.swift
//  Menej
//
//  Investment holdings (PRD §6 F6) — crypto, stocks, mutual funds, time deposits, gold.
//

import Foundation
import SwiftData

@Model
final class Holding {
    @Attribute(.unique) var id: UUID
    var instrument: AssetType
    var symbol: String
    var quantity: Decimal
    var avgCost: Decimal
    var currency: String

    init(
        id: UUID = UUID(),
        instrument: AssetType,
        symbol: String,
        quantity: Decimal,
        avgCost: Decimal,
        currency: String = "IDR"
    ) {
        self.id = id
        self.instrument = instrument
        self.symbol = symbol
        self.quantity = quantity
        self.avgCost = avgCost
        self.currency = currency
    }
}
