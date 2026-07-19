//
//  LedgerViewModel.swift
//  Menej
//
//  Drives TransactionListView / TransactionDetailView — see PRD §6 F3/F4.
//

import Foundation
import Observation

@Observable
@MainActor
final class LedgerViewModel {
    private let categorizationService: CategorizationServiceProtocol
    private let dedupService: DedupServiceProtocol

    var pendingDedupCandidates: [DedupCandidate] = []

    // See ImportViewModel.swift for why the defaults are built in the body.
    init(
        categorizationService: CategorizationServiceProtocol? = nil,
        dedupService: DedupServiceProtocol? = nil
    ) {
        self.categorizationService = categorizationService ?? CategorizationService()
        self.dedupService = dedupService ?? DedupService()
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

    /// Dismisses a candidate for this session only — it isn't persisted as
    /// "not a duplicate," so it can resurface on a future review pass. A
    /// known v1 simplification rather than adding a schema field for it.
    func rejectMatch(_ candidate: DedupCandidate) {
        pendingDedupCandidates.removeAll {
            $0.transactionId == candidate.transactionId && $0.matchedTransactionId == candidate.matchedTransactionId
        }
    }
}
