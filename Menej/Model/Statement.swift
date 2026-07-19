//
//  Statement.swift
//  Menej
//

import Foundation
import SwiftData

@Model
final class Statement {
    @Attribute(.unique) var id: UUID
    var issuer: Issuer
    var fileHash: String
    var periodStart: Date
    var periodEnd: Date
    var parsedAt: Date
    var confidence: Double
    /// PRD §6 F1 — the reconciliation gap. Shown explicitly, never hidden.
    var unaccountedAmount: Decimal

    init(
        id: UUID = UUID(),
        issuer: Issuer,
        fileHash: String,
        periodStart: Date,
        periodEnd: Date,
        parsedAt: Date = .now,
        confidence: Double,
        unaccountedAmount: Decimal = 0
    ) {
        self.id = id
        self.issuer = issuer
        self.fileHash = fileHash
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.parsedAt = parsedAt
        self.confidence = confidence
        self.unaccountedAmount = unaccountedAmount
    }
}
