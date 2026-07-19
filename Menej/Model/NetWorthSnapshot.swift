//
//  NetWorthSnapshot.swift
//  Menej
//
//  Frozen at each month's end so the historical chart doesn't retroactively
//  shift when today's asset prices move — see PRD §6 F5.
//

import Foundation
import SwiftData

@Model
final class NetWorthSnapshot {
    @Attribute(.unique) var id: UUID
    var date: Date
    var totalAssets: Decimal
    var totalLiabilities: Decimal
    var netWorth: Decimal

    init(
        id: UUID = UUID(),
        date: Date,
        totalAssets: Decimal,
        totalLiabilities: Decimal = 0,
        netWorth: Decimal
    ) {
        self.id = id
        self.date = date
        self.totalAssets = totalAssets
        self.totalLiabilities = totalLiabilities
        self.netWorth = netWorth
    }
}
