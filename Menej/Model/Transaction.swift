//
//  Transaction.swift
//  Menej
//

import Foundation
import SwiftData

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var accountId: UUID
    var date: Date
    var amount: Decimal
    var direction: Direction
    var rawDescription: String
    var merchant: String?
    var categoryId: Category?
    var isTransfer: Bool
    var dedupGroupId: UUID?
    var sourceStatementId: UUID?
    var confidence: Double
    var isEdited: Bool

    init(
        id: UUID = UUID(),
        accountId: UUID,
        date: Date,
        amount: Decimal,
        direction: Direction,
        rawDescription: String,
        merchant: String? = nil,
        categoryId: Category? = nil,
        isTransfer: Bool = false,
        dedupGroupId: UUID? = nil,
        sourceStatementId: UUID? = nil,
        confidence: Double = 1.0,
        isEdited: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.direction = direction
        self.rawDescription = rawDescription
        self.merchant = merchant
        self.categoryId = categoryId
        self.isTransfer = isTransfer
        self.dedupGroupId = dedupGroupId
        self.sourceStatementId = sourceStatementId
        self.confidence = confidence
        self.isEdited = isEdited
    }

    /// `amount` is an unsigned magnitude; this applies `direction` for display.
    var signedAmount: Decimal {
        direction == .debit ? -amount : amount
    }
}
