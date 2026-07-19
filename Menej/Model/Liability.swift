//
//  Liability.swift
//  Menej
//
//  Schema reserved, unused in v1 — see PRD §6 F5. Kept from day one so the
//  net worth calculation and historical snapshots don't need retrofitting later.
//

import Foundation
import SwiftData

@Model
final class Liability {
    @Attribute(.unique) var id: UUID
    var type: String
    var principal: Decimal
    var outstanding: Decimal
    var interestRate: Double
    var dueDate: Date?

    init(
        id: UUID = UUID(),
        type: String,
        principal: Decimal,
        outstanding: Decimal,
        interestRate: Double,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.principal = principal
        self.outstanding = outstanding
        self.interestRate = interestRate
        self.dueDate = dueDate
    }
}
