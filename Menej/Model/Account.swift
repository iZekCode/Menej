//
//  Account.swift
//  Menej
//

import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var issuer: Issuer
    var type: AssetType
    var currency: String
    var balance: Decimal
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        issuer: Issuer,
        type: AssetType,
        currency: String = "IDR",
        balance: Decimal = 0,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.issuer = issuer
        self.type = type
        self.currency = currency
        self.balance = balance
        self.lastSyncedAt = lastSyncedAt
    }
}
