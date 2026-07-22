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
    /// file twice never duplicates data. Re-importing a known file REPLACES
    /// that statement's transactions with the freshly parsed ones rather
    /// than silently no-oping — after a parser upgrade, re-importing the
    /// same PDF is the only way better rows can ever reach the ledger.
    /// User edits (corrected category/merchant) and dedup links are carried
    /// over onto the matching re-parsed transaction (same date, amount,
    /// direction) so a replace never destroys manual work.
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
            var carriedEdits: [String: [CarriedEdits]] = [:]
            for previous in existingStatements where previous.issuer.rawValue == issuerValue {
                try Self.collectEditsAndDelete(statement: previous, into: &carriedEdits, modelContext: modelContext)
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
            // guessed at. Only apply it if this statement is at least as
            // recent as the newest one seen for the account, so importing an
            // older statement out of order doesn't regress a newer balance
            // (>= not >: re-importing the newest statement after a parser
            // upgrade must be able to refresh the balance too).
            if let closingBalance = statement.closingBalance,
               account.lastSyncedAt == nil || periodEnd >= account.lastSyncedAt! {
                account.balance = closingBalance
                account.lastSyncedAt = periodEnd
                // A printed closing balance is better evidence than anything
                // the user typed, and it re-anchors the roll-forward here.
                account.isBalanceManual = false
            }

            for parsedTransaction in statement.transactions {
                // Auto-categorization (PRD §6 F3): known merchants get a
                // category immediately; unrecognized ones stay `.other`
                // until the user corrects one. A merchant extracted by the
                // parser itself (e.g. Grab's restaurant/destination title,
                // taken from the statement's own table columns) beats the
                // dictionary's generic label ("Grab"/"GrabFood").
                var (merchant, category) = categorizationService.categorize(
                    rawDescription: parsedTransaction.rawDescription,
                    issuer: statement.issuer,
                    direction: parsedTransaction.direction
                )
                merchant = parsedTransaction.merchant ?? merchant

                let key = Self.carryoverKey(
                    date: parsedTransaction.date,
                    amount: parsedTransaction.amount,
                    direction: parsedTransaction.direction
                )
                var carried: CarriedEdits?
                if var edits = carriedEdits[key], !edits.isEmpty {
                    carried = edits.removeFirst()
                    carriedEdits[key] = edits
                }
                if let carried, carried.isEdited {
                    merchant = carried.merchant
                    category = carried.categoryId ?? category
                }

                let transaction = Transaction(
                    accountId: account.id,
                    date: parsedTransaction.date,
                    amount: parsedTransaction.amount,
                    direction: parsedTransaction.direction,
                    rawDescription: parsedTransaction.rawDescription,
                    merchant: merchant,
                    categoryId: category,
                    isTransfer: carried?.isTransfer ?? false,
                    dedupGroupId: carried?.dedupGroupId,
                    sourceStatementId: statementRecord.id,
                    confidence: parsedTransaction.confidence,
                    isEdited: carried?.isEdited ?? false
                )
                modelContext.insert(transaction)
            }

            // Monthly net worth snapshot (PRD §6 F5) — frozen once created
            // for a given month, so backfilling historical statements out
            // of order (e.g. all of one issuer's months, then another
            // issuer's) never overwrites an already-committed month. A month
            // is written once, from whatever was known at the time — later
            // balance anchors move the live headline, not sealed history.
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

    /// The user's manual work on a transaction, snapshotted as plain values
    /// before the transaction is deleted during a re-import replace.
    private struct CarriedEdits {
        let merchant: String?
        let categoryId: Category?
        let isEdited: Bool
        let isTransfer: Bool
        let dedupGroupId: UUID?
    }

    /// (date, amount, direction) identifies "the same transaction" across a
    /// re-parse of the same file — the raw description may legitimately
    /// change between parser versions, so it can't be part of the key.
    /// Same-key collisions (e.g. several identical same-day transfers) are
    /// kept as an array and consumed in order.
    private static func carryoverKey(date: Date, amount: Decimal, direction: Direction) -> String {
        "\(date.timeIntervalSince1970)|\(amount)|\(direction.rawValue)"
    }

    private static func collectEditsAndDelete(
        statement previous: Statement,
        into carriedEdits: inout [String: [CarriedEdits]],
        modelContext: ModelContext
    ) throws {
        let previousId: UUID? = previous.id
        let oldTransactions = try modelContext.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.sourceStatementId == previousId })
        )
        for old in oldTransactions {
            let key = carryoverKey(date: old.date, amount: old.amount, direction: old.direction)
            carriedEdits[key, default: []].append(CarriedEdits(
                merchant: old.merchant,
                categoryId: old.categoryId,
                isEdited: old.isEdited,
                isTransfer: old.isTransfer,
                dedupGroupId: old.dedupGroupId
            ))
            modelContext.delete(old)
        }
        modelContext.delete(previous)
    }

    private static func upsertSnapshotIfNeeded(
        periodEnd: Date,
        modelContext: ModelContext,
        snapshotService: SnapshotServiceProtocol
    ) throws {
        let existingSnapshots = try modelContext.fetch(FetchDescriptor<NetWorthSnapshot>())
        guard !snapshotService.hasSnapshot(forMonthOf: periodEnd, in: existingSnapshots) else { return }

        // All asset classes, not just account balances (PRD §6 F5) — the
        // same arithmetic NetWorthHomeView shows, so a snapshot never
        // disagrees with the headline the user just saw. Holdings are
        // valued from their last persisted quote (`offlineValueIDR`);
        // snapshot creation must stay synchronous and offline-safe, so it
        // never fetches prices itself.
        let allAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        let allTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
        let allAssets = try modelContext.fetch(FetchDescriptor<Asset>())
        let allHoldings = try modelContext.fetch(FetchDescriptor<Holding>())
        for asset in allAssets {
            asset.applyCurveIfNeeded()
        }
        let holdingValues = Dictionary(uniqueKeysWithValues: allHoldings.map { ($0.id, $0.offlineValueIDR) })
        let accountBalances = LiquidBalanceService().balances(accounts: allAccounts, transactions: allTransactions)
        let totalAssets = NetWorthService().totalAssets(
            accounts: allAccounts,
            accountBalances: accountBalances,
            assets: allAssets,
            holdings: allHoldings,
            holdingValues: holdingValues
        )
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
