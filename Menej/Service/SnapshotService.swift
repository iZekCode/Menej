//
//  SnapshotService.swift
//  Menej
//
//  Monthly snapshots — see PRD §6 F5. Net worth is frozen at each month's end
//  so the historical chart stays honest and doesn't retroactively shift when
//  today's asset prices move.
//

import Foundation

protocol SnapshotServiceProtocol {
    func shouldCreateSnapshot(lastSnapshotDate: Date?, now: Date) -> Bool
    func makeSnapshot(date: Date, totalAssets: Decimal, totalLiabilities: Decimal) -> NetWorthSnapshot
}

struct SnapshotService: SnapshotServiceProtocol {
    func shouldCreateSnapshot(lastSnapshotDate: Date?, now: Date) -> Bool {
        guard let lastSnapshotDate else { return true }
        let calendar = Calendar.current
        return !calendar.isDate(lastSnapshotDate, equalTo: now, toGranularity: .month)
    }

    func makeSnapshot(date: Date, totalAssets: Decimal, totalLiabilities: Decimal) -> NetWorthSnapshot {
        NetWorthSnapshot(
            date: date,
            totalAssets: totalAssets,
            totalLiabilities: totalLiabilities,
            netWorth: totalAssets - totalLiabilities
        )
    }
}
