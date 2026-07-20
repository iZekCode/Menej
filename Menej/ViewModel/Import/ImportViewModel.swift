//
//  ImportViewModel.swift
//  Menej
//
//  Drives ImportFlowView / ReviewStatementView — see PRD §6 F2.
//  Backlog batching: per-file progress, resumable after mid-batch failure.
//

import Foundation
import Observation
import SwiftData
import CryptoKit

enum ImportFileStatus {
    case pending
    case parsing
    case needsReview(ParsedStatement)
    case failed(Error)
    case imported
}

enum ImportPersistenceError: Error {
    case unreadableFile
}

@Observable
@MainActor
final class ImportViewModel {
    private let parsingService: ParsingServiceProtocol
    private let remoteConfigService: RemoteConfigServiceProtocol
    private let categorizationService: CategorizationServiceProtocol
    private let snapshotService: SnapshotServiceProtocol

    var fileStatuses: [URL: ImportFileStatus] = [:]

    // Defaults are constructed in the body, not as parameter defaults: a
    // default argument expression is evaluated in the caller's isolation
    // context, not the initializer's, which trips MainActor-isolation
    // checking for MainActor-isolated default types under this project's
    // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor setting.
    init(
        parsingService: ParsingServiceProtocol? = nil,
        remoteConfigService: RemoteConfigServiceProtocol? = nil,
        categorizationService: CategorizationServiceProtocol? = nil,
        snapshotService: SnapshotServiceProtocol? = nil
    ) {
        self.parsingService = parsingService ?? ParsingService()
        self.remoteConfigService = remoteConfigService ?? RemoteConfigService()
        self.categorizationService = categorizationService ?? CategorizationService()
        self.snapshotService = snapshotService ?? SnapshotService()
    }

    func importFiles(_ urls: [URL]) {
        let rules = remoteConfigService.loadBundledRules()
        for url in urls {
            fileStatuses[url] = .parsing
            do {
                let parsed = try parsingService.parse(fileURL: url, availableRules: rules)
                fileStatuses[url] = .needsReview(parsed)
            } catch {
                fileStatuses[url] = .failed(error)
            }
        }
    }

    /// Persists a confirmed statement as SwiftData records — the only point
    /// where parsed data enters the ledger, per PRD §6 F1 ("users always
    /// confirm before data enters the ledger").
    ///
    /// Idempotent on (issuer, file hash) — see PRD §6 F2: uploading the same
    /// file twice never duplicates data.
    ///
    /// Throws instead of only recording `.failed` in `fileStatuses`, so a
    /// caller that actually needs to know whether the save succeeded (e.g.
    /// SeedDataService counting real imports) isn't stuck trusting a status
    /// dictionary it has to poll.
    @discardableResult
    func confirmImport(url: URL, statement: ParsedStatement, modelContext: ModelContext) throws -> Int {
        do {
            let hash = try Self.fileHash(for: url)

            let issuerValue = statement.issuer.rawValue
            let existingStatements = try modelContext.fetch(
                FetchDescriptor<Statement>(predicate: #Predicate { $0.fileHash == hash })
            )
            guard !existingStatements.contains(where: { $0.issuer.rawValue == issuerValue }) else {
                fileStatuses[url] = .imported
                return 0
            }

            let account = try Self.findOrCreateAccount(for: statement.issuer, in: modelContext)

            let dates = statement.transactions.map(\.date)
            let periodStart = dates.min() ?? .now
            let periodEnd = dates.max() ?? .now

            let statementRecord = Statement(
                issuer: statement.issuer,
                fileHash: hash,
                periodStart: periodStart,
                periodEnd: periodEnd,
                confidence: statement.confidence,
                unaccountedAmount: statement.unaccountedAmount
            )
            modelContext.insert(statementRecord)

            // Only issuers with a printed running balance (myBCA's "SALDO
            // AKHIR") can update the account balance — GoPay/Grab have no
            // such figure, so their accounts are left untouched rather than
            // guessed at. Only apply it if this statement is the most
            // recent one seen for the account, so importing an older
            // statement out of order doesn't regress a newer balance.
            if let closingBalance = statement.closingBalance,
               account.lastSyncedAt == nil || periodEnd > account.lastSyncedAt! {
                account.balance = closingBalance
                account.lastSyncedAt = periodEnd
            }

            for parsedTransaction in statement.transactions {
                // Auto-categorization (PRD §6 F3): known merchants get a
                // category immediately; unrecognized ones stay `.other`
                // until the user corrects one.
                let (merchant, category) = categorizationService.categorize(
                    rawDescription: parsedTransaction.rawDescription,
                    issuer: statement.issuer
                )
                let transaction = Transaction(
                    accountId: account.id,
                    date: parsedTransaction.date,
                    amount: parsedTransaction.amount,
                    direction: parsedTransaction.direction,
                    rawDescription: parsedTransaction.rawDescription,
                    merchant: merchant,
                    categoryId: category,
                    sourceStatementId: statementRecord.id,
                    confidence: parsedTransaction.confidence
                )
                modelContext.insert(transaction)
            }

            // Monthly net worth snapshot (PRD §6 F5) — frozen once created
            // for a given month, so backfilling historical statements out
            // of order (e.g. all of one issuer's months, then another
            // issuer's) never overwrites an already-committed month. Safe
            // here because only myBCA ever changes an account's balance;
            // GoPay/Grab accounts stay at 0 regardless of processing order.
            try Self.upsertSnapshotIfNeeded(periodEnd: periodEnd, modelContext: modelContext, snapshotService: snapshotService)

            try modelContext.save()
            fileStatuses[url] = .imported
            return statement.transactions.count
        } catch {
            fileStatuses[url] = .failed(error)
            throw error
        }
    }

    private static func fileHash(for url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw ImportPersistenceError.unreadableFile }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func upsertSnapshotIfNeeded(
        periodEnd: Date,
        modelContext: ModelContext,
        snapshotService: SnapshotServiceProtocol
    ) throws {
        let existingSnapshots = try modelContext.fetch(FetchDescriptor<NetWorthSnapshot>())
        guard !snapshotService.hasSnapshot(forMonthOf: periodEnd, in: existingSnapshots) else { return }

        let allAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        let totalAssets = allAccounts.reduce(Decimal(0)) { $0 + $1.balance }
        let snapshot = snapshotService.makeSnapshot(date: periodEnd, totalAssets: totalAssets, totalLiabilities: 0)
        modelContext.insert(snapshot)
    }

    private static func findOrCreateAccount(for issuer: Issuer, in modelContext: ModelContext) throws -> Account {
        // SwiftData's #Predicate doesn't support capturing enum values
        // (confirmed at runtime: "Captured/constant values of type 'Issuer'
        // are not supported") — fetch all and filter in Swift instead.
        let allAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        if let account = allAccounts.first(where: { $0.issuer == issuer }) { return account }

        let type: AssetType = issuer == .bcaMyBCA ? .bankAccount : .eWallet
        let account = Account(issuer: issuer, type: type)
        modelContext.insert(account)
        return account
    }
}
