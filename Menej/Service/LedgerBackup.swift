//
//  LedgerBackup.swift
//  Menej
//
//  The on-disk backup format. Everything the app knows, as plain Codable
//  values — see BackupService for the SwiftData mapping.
//
//  Foundation only, no SwiftData: this file is the format's definition and
//  stays typecheckable under the CLT swiftc harness, which is where the
//  round-trip tests run. A backup that silently drops a field is worse than
//  no backup, so the format is worth verifying independently of the app.
//
//  Every enum is carried as its `rawValue` string rather than as the enum
//  type. Two reasons: it keeps this file clear of the SwiftData-importing
//  models that declare some of them, and a backup written by a future version
//  with a case this build doesn't know decodes as an unrecognized string
//  instead of failing the entire restore.
//
//  Dates are ISO 8601 and Decimals are encoded by Foundation's own Codable
//  conformance, so the file stays readable and inspectable — which matters,
//  because it's the user's only copy of anything outside the app container.
//

import Foundation

struct LedgerBackup: Codable {
    /// Bumped when the shape changes incompatibly. `BackupService` refuses a
    /// file it doesn't recognize rather than restoring it partially.
    static let currentVersion = 1

    var version: Int = LedgerBackup.currentVersion
    var exportedAt: Date

    var accounts: [AccountBackup] = []
    var transactions: [TransactionBackup] = []
    var statements: [StatementBackup] = []
    var assets: [AssetBackup] = []
    var holdings: [HoldingBackup] = []
    var liabilities: [LiabilityBackup] = []
    var subscriptions: [SubscriptionBackup] = []
    var snapshots: [SnapshotBackup] = []

    /// What a restore is about to replace, for the confirmation copy.
    var itemCount: Int {
        accounts.count + transactions.count + statements.count + assets.count
            + holdings.count + liabilities.count + subscriptions.count + snapshots.count
    }
}

struct AccountBackup: Codable {
    var id: UUID
    var issuer: String
    var type: String
    var currency: String
    var balance: Decimal
    var lastSyncedAt: Date?
    var isBalanceManual: Bool
    var nickname: String?
}

struct TransactionBackup: Codable {
    var id: UUID
    var accountId: UUID
    var date: Date
    var amount: Decimal
    var direction: String
    var rawDescription: String
    var merchant: String?
    var categoryId: String?
    var isTransfer: Bool
    var dedupGroupId: UUID?
    var sourceStatementId: UUID?
    var confidence: Double
    /// Carried so a restore doesn't quietly re-open every manual correction
    /// to being overwritten by the categorizer.
    var isEdited: Bool
}

struct StatementBackup: Codable {
    var id: UUID
    var issuer: String
    /// SHA256 of the source PDF. Preserved because it's what makes re-import
    /// idempotent — and what links a statement to a stored file on disk.
    var fileHash: String
    var periodStart: Date
    var periodEnd: Date
    var parsedAt: Date
    var confidence: Double
    var unaccountedAmount: Decimal
}

struct AssetBackup: Codable {
    var id: UUID
    var type: String
    var name: String
    var acquiredAt: Date
    var acquisitionCost: Decimal
    var currentValue: Decimal
    var depreciationCurve: String?
    var warrantyExpiresAt: Date?
    /// Base64 in JSON. Included because photos are user data a backup has no
    /// business dropping; they're downsampled to ~1200px on the way in
    /// (InventoryItemFormView.downsampled), so this stays tolerable.
    var photoData: Data?
}

struct HoldingBackup: Codable {
    var id: UUID
    var instrument: String
    var symbol: String
    var quantity: Decimal
    var avgCost: Decimal
    var currency: String
    var manualPrice: Decimal?
    var lastValueIDR: Decimal?
    var lastQuotedAt: Date?
}

struct LiabilityBackup: Codable {
    var id: UUID
    var type: String
    var principal: Decimal
    var outstanding: Decimal
    var interestRate: Double
    var dueDate: Date?
}

struct SubscriptionBackup: Codable {
    var id: UUID
    var merchant: String
    var amount: Decimal
    var cadence: String
    var lastChargedAt: Date
    var isActive: Bool
}

struct SnapshotBackup: Codable {
    var id: UUID
    var date: Date
    var totalAssets: Decimal
    var totalLiabilities: Decimal
    var netWorth: Decimal
}

// MARK: - Coding

extension LedgerBackup {
    /// ISO 8601 dates and sorted keys so a backup file is diffable and
    /// readable — the user may well open it, and it's their only copy.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
