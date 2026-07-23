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
    case needsReview
    case failed(Error)
    case imported
}

/// One file in the import queue.
///
/// Replaces the old `[URL: ImportFileStatus]` dictionary. A Dictionary's key
/// order is unspecified and can change on any mutation, so the list visibly
/// reshuffled every time a file's status advanced — and there was no order to
/// group or sort by in the first place.
struct ImportFile: Identifiable {
    let id = UUID()
    /// Moves when the file is renamed to its canonical name after parsing.
    var url: URL
    /// The name the file arrived with. Still the best label a file that
    /// failed to parse has — it has no issuer or period to be named after.
    let originalName: String
    var status: ImportFileStatus
    /// Set once parsing succeeds, and kept after import so the row keeps its
    /// title and stays in its month's section.
    var parsed: ParsedStatement?

    /// The month this statement belongs to, taken from its newest
    /// transaction. `confirmImport` derives the stored `Statement.periodEnd`
    /// exactly the same way, so a row can't be filed under a different month
    /// than the record it creates. The end date rather than the start: a
    /// myBCA period can open in late March and still be the April statement.
    var periodEnd: Date? {
        parsed?.transactions.map(\.date).max()
    }

    /// What the row is titled — and, after `ImportViewModel` renames it, what
    /// the file on disk is actually called.
    var displayName: String {
        guard let parsed, let periodEnd else { return originalName }
        return "\(parsed.issuer.displayName) — \(periodEnd.formatted(.dateTime.month(.wide).year()))"
    }
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

    /// The queue, in the order files arrived. ImportFlowView groups it by
    /// month for display; this stays a flat arrival-ordered list.
    var files: [ImportFile] = []

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
            // Draining the shared inbox happens on every appearance of
            // ImportFlowView, so the same URL can arrive twice.
            guard !files.contains(where: { $0.url == url }) else { continue }

            var file = ImportFile(url: url, originalName: url.lastPathComponent, status: .pending)
            do {
                let parsed = try parsingService.parse(fileURL: url, availableRules: rules)
                file.parsed = parsed
                file.status = .needsReview
                if let renamed = Self.renamedToCanonicalName(url, for: parsed) {
                    file.url = renamed
                }
            } catch {
                file.status = .failed(error)
            }
            files.append(file)
        }
    }

    /// Drops a file from the queue and deletes the app's own copy of it.
    ///
    /// Safe to do at any status: the copy is not the user's file (see
    /// ImportFlowView.copyIntoAppStorage) and it has no further use once
    /// imported — the ledger holds the transactions, and `Statement.fileHash`
    /// records which PDF produced them. Removing an already-imported row does
    /// not un-import anything.
    func remove(_ file: ImportFile) {
        files.removeAll { $0.id == file.id }
        guard Self.isInAppStorage(file.url) else { return }
        try? FileManager.default.removeItem(at: file.url)
    }

    private func updateStatus(_ status: ImportFileStatus, for url: URL) {
        guard let index = files.firstIndex(where: { $0.url == url }) else { return }
        files[index].status = status
    }

    /// "MyBCA 2024-04.pdf" instead of "e-statement (3).pdf".
    ///
    /// Only ever touches the app's own copy: `copyIntoAppStorage` copies each
    /// picked file into Documents and leaves the original where the user
    /// keeps it, and `SharedImportInbox` moves shared files there too — the
    /// `isInAppStorage` guard is what makes that a rule rather than an
    /// assumption. Returns nil and leaves the file alone on any failure; a
    /// tidier name isn't worth losing an import over. Dedup is unaffected
    /// either way, since `fileHash` is computed from bytes, not the name.
    private static func renamedToCanonicalName(_ url: URL, for statement: ParsedStatement) -> URL? {
        guard isInAppStorage(url),
              let periodEnd = statement.transactions.map(\.date).max() else { return nil }

        let base = "\(statement.issuer.displayName) \(monthFormatter.string(from: periodEnd))"
        let directory = url.deletingLastPathComponent()

        // PickedImports gives every file its own UUID directory, so nothing
        // can collide there. SharedImports is flat, so two statements from
        // the same issuer and month would want the same name.
        var candidate = directory.appendingPathComponent("\(base).pdf")
        var suffix = 2
        while candidate != url, FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(suffix)).pdf")
            suffix += 1
        }
        // Already correctly named — nothing to do.
        guard candidate != url else { return nil }

        do {
            try FileManager.default.moveItem(at: url, to: candidate)
            return candidate
        } catch {
            return nil
        }
    }

    private static func isInAppStorage(_ url: URL) -> Bool {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        return url.path.hasPrefix(documents.path)
    }

    /// Fixed format, POSIX locale: this names a file, so it must not vary
    /// with the device's region settings.
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

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
    /// Throws instead of only recording `.failed` on the queue entry, so a
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
            updateStatus(.imported, for: url)
            return statement.transactions.count
        } catch {
            updateStatus(.failed(error), for: url)
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
