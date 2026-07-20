//
//  LedgerViewModel.swift
//  Menej
//
//  Drives TransactionListView / TransactionDetailView — see PRD §6 F3/F4.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class LedgerViewModel {
    private let categorizationService: CategorizationServiceProtocol
    private let dedupService: DedupServiceProtocol
    private let aiEnhancementService: AIEnhancementServiceProtocol

    var pendingDedupCandidates: [DedupCandidate] = []

    /// Progress during a bulk AI enhancement pass — (completed, total).
    /// `nil` when no pass is running.
    var enhancementProgress: (completed: Int, total: Int)?
    var enhancementError: String?
    private var enhancementTask: Task<Void, Never>?

    // See ImportViewModel.swift for why the defaults are built in the body.
    init(
        categorizationService: CategorizationServiceProtocol? = nil,
        dedupService: DedupServiceProtocol? = nil,
        aiEnhancementService: AIEnhancementServiceProtocol? = nil
    ) {
        self.categorizationService = categorizationService ?? CategorizationService()
        self.dedupService = dedupService ?? DedupService()
        self.aiEnhancementService = aiEnhancementService ?? AIEnhancementService()
    }

    /// Applies a category correction to this transaction and, when it has a
    /// known merchant, retroactively to every other transaction sharing
    /// that merchant — see PRD §6 F3. `allTransactions` comes from the
    /// driving View's own `@Query`, same as `refreshDedupCandidates`.
    func correctCategory(for transaction: Transaction, to category: Category, allTransactions: [Transaction]) {
        transaction.categoryId = category
        transaction.isEdited = true

        guard let merchant = transaction.merchant else { return }
        categorizationService.recordCorrection(merchant: merchant, category: category)
        for other in allTransactions where other.id != transaction.id && other.merchant == merchant {
            other.categoryId = category
        }
    }

    /// `transactions` comes from the driving View's own `@Query` — simple
    /// list screens query directly per Appendix C notes, so this ViewModel
    /// doesn't hold its own copy or manage a ModelContext.
    func refreshDedupCandidates(transactions: [Transaction]) {
        pendingDedupCandidates = dedupService.findCandidates(in: transactions)
    }

    /// Links two transactions as the same real-world event. Opposite
    /// directions (a debit in one account, a credit in another) means a
    /// transfer between the user's own accounts — not spend, net worth
    /// unchanged. Same direction means the same expense was recorded by
    /// two sources (e.g. a Grab ride paid via GoPay) — still linked via
    /// `dedupGroupId` so future spend totals can count the group once, but
    /// not marked as a transfer since it's a real expense.
    func confirmMatch(_ candidate: DedupCandidate, in transactions: [Transaction]) {
        guard let a = transactions.first(where: { $0.id == candidate.transactionId }),
              let b = transactions.first(where: { $0.id == candidate.matchedTransactionId }) else { return }

        let groupId = UUID()
        a.dedupGroupId = groupId
        b.dedupGroupId = groupId
        if a.direction != b.direction {
            a.isTransfer = true
            b.isTransfer = true
        }

        pendingDedupCandidates.removeAll {
            $0.transactionId == candidate.transactionId && $0.matchedTransactionId == candidate.matchedTransactionId
        }
    }

    /// Permanently marks a candidate as not a match — `DedupService`
    /// excludes it from future scans, so it won't resurface next time the
    /// review screen reopens.
    func rejectMatch(_ candidate: DedupCandidate) {
        dedupService.markRejected(candidate)
        pendingDedupCandidates.removeAll {
            $0.transactionId == candidate.transactionId && $0.matchedTransactionId == candidate.matchedTransactionId
        }
    }

    /// Bulk policy over every pending candidate: transfers (opposite
    /// directions) above `transferAmountThreshold` are confirmed, at or
    /// below it are rejected (too small to be worth linking); duplicate
    /// expenses (same direction) are always rejected. This resolves every
    /// pending candidate one way or the other — nothing is left over.
    func bulkResolvePendingCandidates(in transactions: [Transaction], transferAmountThreshold: Decimal) {
        for candidate in pendingDedupCandidates {
            guard let a = transactions.first(where: { $0.id == candidate.transactionId }),
                  let b = transactions.first(where: { $0.id == candidate.matchedTransactionId }) else { continue }

            if a.direction != b.direction && max(a.amount, b.amount) > transferAmountThreshold {
                confirmMatch(candidate, in: transactions)
            } else {
                rejectMatch(candidate)
            }
        }
    }

    /// Re-derives `merchant`/`categoryId` for every given transaction using
    /// the on-device model — a user-requested, opt-in upgrade over the
    /// rule-based categorizer applied at import time (see
    /// AIEnhancementService.swift for why this stays on-device only).
    /// Runs sequentially, one call per transaction, with progress reported
    /// via `enhancementProgress`; call `cancelEnhancement()` to stop early
    /// (whatever's already been enhanced up to that point is kept).
    func startEnhancement(transactions: [Transaction], modelContext: ModelContext) {
        guard enhancementTask == nil else { return }
        enhancementError = nil

        guard aiEnhancementService.isAvailable else {
            enhancementError = aiEnhancementService.unavailabilityReason ?? "Apple Intelligence is unavailable."
            return
        }

        // The issuer hint tells the model which statement format the raw
        // description is in (GoPay ID junk vs. BCA jargon vs. Grab routes).
        let accounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let issuerByAccount = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.issuer) })

        enhancementProgress = (0, transactions.count)
        enhancementTask = Task { [weak self] in
            guard let self else { return }
            for (index, transaction) in transactions.enumerated() {
                if Task.isCancelled { break }
                if let (merchant, category) = try? await self.aiEnhancementService.enhance(
                    rawDescription: transaction.rawDescription,
                    amount: transaction.amount,
                    direction: transaction.direction,
                    issuer: issuerByAccount[transaction.accountId]
                ) {
                    transaction.merchant = merchant
                    transaction.categoryId = category
                }
                self.enhancementProgress = (index + 1, transactions.count)
            }
            try? modelContext.save()
            self.enhancementProgress = nil
            self.enhancementTask = nil
        }
    }

    func cancelEnhancement() {
        enhancementTask?.cancel()
        enhancementTask = nil
        enhancementProgress = nil
    }
}
