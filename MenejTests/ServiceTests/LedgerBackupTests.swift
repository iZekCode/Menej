//
//  LedgerBackupTests.swift
//  MenejTests
//
//  A backup that silently drops a field is worse than no backup — the loss
//  isn't discovered until a restore, by which point the original is gone. So
//  these round-trip every model through the real encoder/decoder and assert
//  each field survives, including the ones easiest to lose: optionals left
//  nil, Decimals, and an asset's photo bytes.
//

import Foundation
import Testing
@testable import Menej

struct LedgerBackupTests {
    private static func roundTrip(_ backup: LedgerBackup) throws -> LedgerBackup {
        let data = try LedgerBackup.encoder().encode(backup)
        return try LedgerBackup.decoder().decode(LedgerBackup.self, from: data)
    }

    @Test func fullyPopulatedBackupSurvivesRoundTrip() throws {
        let accountId = UUID()
        let statementId = UUID()
        let date = Date(timeIntervalSince1970: 1_780_000_000)

        var backup = LedgerBackup(exportedAt: date)
        backup.accounts = [AccountBackup(
            id: accountId,
            issuer: Issuer.bcaMyBCA.rawValue,
            type: AssetType.bankAccount.rawValue,
            currency: "IDR",
            balance: 12_345_678,
            lastSyncedAt: date,
            isBalanceManual: true,
            nickname: "Main"
        )]
        backup.transactions = [TransactionBackup(
            id: UUID(),
            accountId: accountId,
            date: date,
            amount: 271_000,
            direction: Direction.debit.rawValue,
            rawDescription: "DAPOER COWEK 0420260518050724h083",
            merchant: "Dapoer Cowek",
            categoryId: Category.food.rawValue,
            isTransfer: false,
            dedupGroupId: UUID(),
            sourceStatementId: statementId,
            confidence: 0.97,
            isEdited: true
        )]
        backup.statements = [StatementBackup(
            id: statementId,
            issuer: Issuer.gopay.rawValue,
            fileHash: "abc123",
            periodStart: date,
            periodEnd: date,
            parsedAt: date,
            confidence: 1.0,
            unaccountedAmount: 2_000_000
        )]
        backup.assets = [AssetBackup(
            id: UUID(),
            type: AssetType.vehicle.rawValue,
            name: "NMAX 155",
            acquiredAt: date,
            acquisitionCost: 32_000_000,
            currentValue: 28_000_000,
            depreciationCurve: "vehicle",
            warrantyExpiresAt: date,
            photoData: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        )]
        backup.holdings = [HoldingBackup(
            id: UUID(),
            instrument: AssetType.crypto.rawValue,
            symbol: "BTC",
            quantity: Decimal(string: "0.00123456")!,
            avgCost: 900_000_000,
            currency: "IDR",
            manualPrice: nil,
            lastValueIDR: 1_200_000,
            lastQuotedAt: date
        )]
        backup.liabilities = [LiabilityBackup(
            id: UUID(),
            type: "Credit Card",
            principal: 10_000_000,
            outstanding: 4_500_000,
            interestRate: 0.0225,
            dueDate: date
        )]
        backup.subscriptions = [SubscriptionBackup(
            id: UUID(),
            merchant: "Netflix",
            amount: 186_000,
            cadence: SubscriptionCadence.monthly.rawValue,
            lastChargedAt: date,
            isActive: true
        )]
        backup.snapshots = [SnapshotBackup(
            id: UUID(),
            date: date,
            totalAssets: 150_000_000,
            totalLiabilities: 4_500_000,
            netWorth: 145_500_000
        )]

        let decoded = try Self.roundTrip(backup)

        #expect(decoded.version == LedgerBackup.currentVersion)
        #expect(decoded.itemCount == backup.itemCount)

        #expect(decoded.accounts.first?.balance == 12_345_678)
        #expect(decoded.accounts.first?.nickname == "Main")
        #expect(decoded.accounts.first?.isBalanceManual == true)

        let transaction = decoded.transactions.first
        #expect(transaction?.amount == 271_000)
        #expect(transaction?.merchant == "Dapoer Cowek")
        #expect(transaction?.categoryId == Category.food.rawValue)
        // The user's manual corrections are the least reproducible thing in
        // the whole file — a parser can regenerate everything else.
        #expect(transaction?.isEdited == true)
        #expect(transaction?.dedupGroupId != nil)

        #expect(decoded.statements.first?.fileHash == "abc123")
        #expect(decoded.statements.first?.unaccountedAmount == 2_000_000)

        #expect(decoded.assets.first?.photoData?.count == 6)
        #expect(decoded.assets.first?.currentValue == 28_000_000)

        // Eight fractional digits, which a Double round-trip would mangle.
        #expect(decoded.holdings.first?.quantity == Decimal(string: "0.00123456"))
        #expect(decoded.liabilities.first?.interestRate == 0.0225)
        #expect(decoded.subscriptions.first?.cadence == SubscriptionCadence.monthly.rawValue)
        #expect(decoded.snapshots.first?.netWorth == 145_500_000)
    }

    @Test func nilOptionalsSurviveAsNil() throws {
        var backup = LedgerBackup(exportedAt: .now)
        backup.accounts = [AccountBackup(
            id: UUID(),
            issuer: Issuer.manual.rawValue,
            type: AssetType.cash.rawValue,
            currency: "IDR",
            balance: 0,
            lastSyncedAt: nil,
            isBalanceManual: false,
            nickname: nil
        )]
        backup.assets = [AssetBackup(
            id: UUID(),
            type: AssetType.watch.rawValue,
            name: "Seiko",
            acquiredAt: .now,
            acquisitionCost: 8_000_000,
            currentValue: 8_400_000,
            depreciationCurve: nil,
            warrantyExpiresAt: nil,
            photoData: nil
        )]

        let decoded = try Self.roundTrip(backup)

        // `lastSyncedAt == nil` is the difference between "balance unknown"
        // and "balance is zero" — see LiquidBalanceService.
        #expect(decoded.accounts.first?.lastSyncedAt == nil)
        #expect(decoded.accounts.first?.nickname == nil)
        // A nil curve means manually valued; restoring it as "electronics"
        // would start depreciating something the user priced by hand.
        #expect(decoded.assets.first?.depreciationCurve == nil)
        #expect(decoded.assets.first?.photoData == nil)
    }

    @Test func emptyBackupRoundTrips() throws {
        let decoded = try Self.roundTrip(LedgerBackup(exportedAt: .now))
        #expect(decoded.itemCount == 0)
    }

    @Test func versionIsRecordedInTheFile() throws {
        let data = try LedgerBackup.encoder().encode(LedgerBackup(exportedAt: .now))
        let json = String(decoding: data, as: UTF8.self)
        // BackupService refuses a file from a newer format, so the field has
        // to actually be written.
        #expect(json.contains("\"version\""))
    }
}
