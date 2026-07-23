//
//  BackupService.swift
//  Menej
//
//  Export the whole ledger to a file, and restore it back. The format lives in
//  LedgerBackup.swift; this is only the SwiftData mapping.
//
//  Why this exists: everything the app knows lives in one on-device SQLite
//  store, so deleting the app destroys all of it. For GoPay and Grab that's
//  unrecoverable — neither issuer prints a balance, so the anchors the user
//  typed exist nowhere else.
//
//  Restore is REPLACE-ALL, not merge. Merging would need identity rules this
//  app doesn't have for assets, liabilities or holdings, and would silently
//  duplicate them on every restore. Callers must confirm before calling it.
//
//  The exported file is unencrypted, readable JSON containing account
//  nicknames and every transaction. That doesn't break the app's privacy
//  promise — the promise is that the *app* transmits nothing, and this is
//  user-initiated — but the UI has to say plainly what the file contains.
//

import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This backup was made by a newer version of Menej (format \(version)). Update the app and try again."
        }
    }
}

@MainActor
protocol BackupServiceProtocol {
    func export(modelContext: ModelContext) throws -> Data
    func restore(from data: Data, modelContext: ModelContext) throws -> LedgerBackup
}

@MainActor
struct BackupService: BackupServiceProtocol {
    // MARK: - Export

    func export(modelContext: ModelContext) throws -> Data {
        var backup = LedgerBackup(exportedAt: .now)

        backup.accounts = fetch(Account.self, modelContext).map {
            AccountBackup(
                id: $0.id,
                issuer: $0.issuer.rawValue,
                type: $0.type.rawValue,
                currency: $0.currency,
                balance: $0.balance,
                lastSyncedAt: $0.lastSyncedAt,
                isBalanceManual: $0.isBalanceManual,
                nickname: $0.nickname
            )
        }
        backup.transactions = fetch(Transaction.self, modelContext).map {
            TransactionBackup(
                id: $0.id,
                accountId: $0.accountId,
                date: $0.date,
                amount: $0.amount,
                direction: $0.direction.rawValue,
                rawDescription: $0.rawDescription,
                merchant: $0.merchant,
                categoryId: $0.categoryId?.rawValue,
                isTransfer: $0.isTransfer,
                dedupGroupId: $0.dedupGroupId,
                sourceStatementId: $0.sourceStatementId,
                confidence: $0.confidence,
                isEdited: $0.isEdited
            )
        }
        backup.statements = fetch(Statement.self, modelContext).map {
            StatementBackup(
                id: $0.id,
                issuer: $0.issuer.rawValue,
                fileHash: $0.fileHash,
                periodStart: $0.periodStart,
                periodEnd: $0.periodEnd,
                parsedAt: $0.parsedAt,
                confidence: $0.confidence,
                unaccountedAmount: $0.unaccountedAmount
            )
        }
        backup.assets = fetch(Asset.self, modelContext).map {
            AssetBackup(
                id: $0.id,
                type: $0.type.rawValue,
                name: $0.name,
                acquiredAt: $0.acquiredAt,
                acquisitionCost: $0.acquisitionCost,
                currentValue: $0.currentValue,
                depreciationCurve: $0.depreciationCurve,
                warrantyExpiresAt: $0.warrantyExpiresAt,
                photoData: $0.photoData
            )
        }
        backup.holdings = fetch(Holding.self, modelContext).map {
            HoldingBackup(
                id: $0.id,
                instrument: $0.instrument.rawValue,
                symbol: $0.symbol,
                quantity: $0.quantity,
                avgCost: $0.avgCost,
                currency: $0.currency,
                manualPrice: $0.manualPrice,
                lastValueIDR: $0.lastValueIDR,
                lastQuotedAt: $0.lastQuotedAt
            )
        }
        backup.liabilities = fetch(Liability.self, modelContext).map {
            LiabilityBackup(
                id: $0.id,
                type: $0.type,
                principal: $0.principal,
                outstanding: $0.outstanding,
                interestRate: $0.interestRate,
                dueDate: $0.dueDate
            )
        }
        backup.subscriptions = fetch(Subscription.self, modelContext).map {
            SubscriptionBackup(
                id: $0.id,
                merchant: $0.merchant,
                amount: $0.amount,
                cadence: $0.cadence.rawValue,
                lastChargedAt: $0.lastChargedAt,
                isActive: $0.isActive
            )
        }
        backup.snapshots = fetch(NetWorthSnapshot.self, modelContext).map {
            SnapshotBackup(
                id: $0.id,
                date: $0.date,
                totalAssets: $0.totalAssets,
                totalLiabilities: $0.totalLiabilities,
                netWorth: $0.netWorth
            )
        }

        return try LedgerBackup.encoder().encode(backup)
    }

    // MARK: - Restore

    /// Wipes every model type and rebuilds from the file. Returns what was
    /// restored so the caller can report it.
    ///
    /// Unrecognized enum strings fall back to a safe default rather than
    /// aborting: a backup that fails wholesale because of one unknown category
    /// is worse than one that restores with a transaction marked `.other`.
    @discardableResult
    func restore(from data: Data, modelContext: ModelContext) throws -> LedgerBackup {
        let backup = try LedgerBackup.decoder().decode(LedgerBackup.self, from: data)
        guard backup.version <= LedgerBackup.currentVersion else {
            throw BackupError.unsupportedVersion(backup.version)
        }

        for type in PersistenceService.modelTypes {
            try? modelContext.delete(model: type)
        }

        for item in backup.accounts {
            modelContext.insert(Account(
                id: item.id,
                issuer: Issuer(rawValue: item.issuer) ?? .manual,
                type: AssetType(rawValue: item.type) ?? .bankAccount,
                currency: item.currency,
                balance: item.balance,
                lastSyncedAt: item.lastSyncedAt,
                isBalanceManual: item.isBalanceManual,
                nickname: item.nickname
            ))
        }
        for item in backup.transactions {
            modelContext.insert(Transaction(
                id: item.id,
                accountId: item.accountId,
                date: item.date,
                amount: item.amount,
                direction: Direction(rawValue: item.direction) ?? .debit,
                rawDescription: item.rawDescription,
                merchant: item.merchant,
                categoryId: item.categoryId.flatMap { Category(rawValue: $0) },
                isTransfer: item.isTransfer,
                dedupGroupId: item.dedupGroupId,
                sourceStatementId: item.sourceStatementId,
                confidence: item.confidence,
                isEdited: item.isEdited
            ))
        }
        for item in backup.statements {
            modelContext.insert(Statement(
                id: item.id,
                issuer: Issuer(rawValue: item.issuer) ?? .manual,
                fileHash: item.fileHash,
                periodStart: item.periodStart,
                periodEnd: item.periodEnd,
                parsedAt: item.parsedAt,
                confidence: item.confidence,
                unaccountedAmount: item.unaccountedAmount
            ))
        }
        for item in backup.assets {
            modelContext.insert(Asset(
                id: item.id,
                type: AssetType(rawValue: item.type) ?? .electronics,
                name: item.name,
                acquiredAt: item.acquiredAt,
                acquisitionCost: item.acquisitionCost,
                currentValue: item.currentValue,
                depreciationCurve: item.depreciationCurve,
                warrantyExpiresAt: item.warrantyExpiresAt,
                photoData: item.photoData
            ))
        }
        for item in backup.holdings {
            modelContext.insert(Holding(
                id: item.id,
                instrument: AssetType(rawValue: item.instrument) ?? .stock,
                symbol: item.symbol,
                quantity: item.quantity,
                avgCost: item.avgCost,
                currency: item.currency,
                manualPrice: item.manualPrice,
                lastValueIDR: item.lastValueIDR,
                lastQuotedAt: item.lastQuotedAt
            ))
        }
        for item in backup.liabilities {
            modelContext.insert(Liability(
                id: item.id,
                type: item.type,
                principal: item.principal,
                outstanding: item.outstanding,
                interestRate: item.interestRate,
                dueDate: item.dueDate
            ))
        }
        for item in backup.subscriptions {
            modelContext.insert(Subscription(
                id: item.id,
                merchant: item.merchant,
                amount: item.amount,
                cadence: SubscriptionCadence(rawValue: item.cadence) ?? .monthly,
                lastChargedAt: item.lastChargedAt,
                isActive: item.isActive
            ))
        }
        for item in backup.snapshots {
            modelContext.insert(NetWorthSnapshot(
                id: item.id,
                date: item.date,
                totalAssets: item.totalAssets,
                totalLiabilities: item.totalLiabilities,
                netWorth: item.netWorth
            ))
        }

        try modelContext.save()
        return backup
    }

    // MARK: - Helpers

    private func fetch<T: PersistentModel>(_ type: T.Type, _ modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }

    /// "Menej-Backup-2026-07-23.json"
    static func suggestedFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Menej-Backup-\(formatter.string(from: date)).json"
    }
}
