//
//  Subscription.swift
//  Menej
//
//  Detected from recurring transaction patterns — see PRD §6 F7.
//

import Foundation
import SwiftData

enum SubscriptionCadence: String, Codable {
    case monthly
    case annual
}

@Model
final class Subscription {
    @Attribute(.unique) var id: UUID
    var merchant: String
    var amount: Decimal
    var cadence: SubscriptionCadence
    var lastChargedAt: Date
    var isActive: Bool

    init(
        id: UUID = UUID(),
        merchant: String,
        amount: Decimal,
        cadence: SubscriptionCadence,
        lastChargedAt: Date,
        isActive: Bool = true
    ) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.cadence = cadence
        self.lastChargedAt = lastChargedAt
        self.isActive = isActive
    }
}
