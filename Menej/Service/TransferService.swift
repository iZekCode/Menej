//
//  TransferService.swift
//  Menej
//
//  Inter-account transfer history, derived from transactions the ledger
//  already holds — no new @Model, nothing extra persisted.
//
//  Transfers between the user's own accounts are already detected
//  (DedupService pairs a debit in one account with a credit in another),
//  flagged (LedgerViewModel.confirmMatch sets `isTransfer` plus a shared
//  `dedupGroupId`) and correctly kept out of spend — but never shown. A
//  confirmed BCA→GoPay top-up just vanished from Insights and sat in the
//  ledger as two unrelated rows. This turns that same data into a readable
//  "MyBCA → GoPay" history.
//
//  Two passes, own accounts only:
//   1. Matched pairs — two legs, opposite directions, different accounts.
//      Exact: the user confirmed them.
//   2. One-sided inference — a `.transfer` transaction with no counterpart
//      (the other side's statement was never imported), whose destination is
//      read out of the description ("GOPAY TOP UP", "BCA VA"). Marked
//      `isInferred` so a guess never reads as fact.
//
//  Anything whose counterparty isn't one of the user's own accounts —
//  BI-FAST to a person, "Ditransfer ke <name>", Stockbit RDN — is dropped:
//  that's money leaving the user's accounts, not moving between them.
//

import Foundation

struct DerivedTransfer: Identifiable {
    /// The dedup group when the pair was matched, otherwise the lone
    /// transaction's id — stable across re-derivations either way.
    let id: String
    let date: Date
    let amount: Decimal
    let fromAccountId: UUID?
    let toAccountId: UUID?
    /// Debit minus credit, when the source was charged more than the
    /// destination received (BCA's interbank transfer fee).
    let fee: Decimal?
    /// True when only one leg exists and the other end was read from the
    /// description rather than matched against a real transaction.
    let isInferred: Bool
    let transactionIds: [UUID]
}

protocol TransferServiceProtocol {
    func derive(transactions: [Transaction], accounts: [Account]) -> [DerivedTransfer]
}

struct TransferService: TransferServiceProtocol {
    /// Description markers that name one of the user's own accounts as the
    /// other end of a transfer. Same vocabulary the categorizer already
    /// keys on (MerchantDictionary.json's "gopay top up"/"gopay transf",
    /// GoPay's "BCA VA" top-up rows) — checked longest-first so "bca va"
    /// wins over a bare "bca".
    private static let counterpartyMarkers: [(marker: String, issuer: Issuer)] = [
        ("gopay top up", .gopay),
        ("gopay topup", .gopay),
        ("gopay transf", .gopay),
        ("top up gopay", .gopay),
        ("bca va", .bcaMyBCA),
        ("gopay", .gopay),
        ("grabpay", .grab),
        ("grab", .grab),
        // OVO isn't a Menej account (PRD defers it to v1.1), and this
        // user's Grab wallet is funded through it — an OVO top-up in a
        // myBCA statement is their MyBCA→Grab transfer. "0vo" covers BCA's
        // Vision OCR misreading the letter O as the digit 0 (same failure
        // mode as the "00000.00" card filler in TransactionNormalizer).
        ("0vo", .grab),
        ("ovo", .grab),
        ("mybca", .bcaMyBCA),
        ("bca", .bcaMyBCA),
    ]

    func derive(transactions: [Transaction], accounts: [Account]) -> [DerivedTransfer] {
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var transfers = matchedTransfers(transactions: transactions)
        transfers += inferredTransfers(transactions: transactions, accounts: accounts, accountsById: accountsById)
        return transfers.sorted { $0.date > $1.date }
    }

    // MARK: - Matched pairs

    private func matchedTransfers(transactions: [Transaction]) -> [DerivedTransfer] {
        let groups = Dictionary(grouping: transactions.filter { $0.dedupGroupId != nil }) { $0.dedupGroupId! }

        return groups.compactMap { groupId, legs -> DerivedTransfer? in
            guard legs.count == 2 else { return nil }
            guard let debit = legs.first(where: { $0.direction == .debit }),
                  let credit = legs.first(where: { $0.direction == .credit }) else { return nil }
            // Same-direction groups are the same expense recorded twice, not
            // a transfer — `first(where:)` above already excluded them.
            guard debit.accountId != credit.accountId else { return nil }

            let fee = debit.amount - credit.amount
            return DerivedTransfer(
                id: groupId.uuidString,
                // The later of the two legs: a top-up can land the next day.
                date: max(debit.date, credit.date),
                amount: credit.amount,
                fromAccountId: debit.accountId,
                toAccountId: credit.accountId,
                fee: fee > 0 ? fee : nil,
                isInferred: false,
                transactionIds: [debit.id, credit.id]
            )
        }
    }

    // MARK: - One-sided inference

    private func inferredTransfers(
        transactions: [Transaction],
        accounts: [Account],
        accountsById: [UUID: Account]
    ) -> [DerivedTransfer] {
        transactions.compactMap { transaction -> DerivedTransfer? in
            guard transaction.dedupGroupId == nil, transaction.categoryId == .transfer else { return nil }
            guard let issuer = Self.counterpartyIssuer(for: transaction) else { return nil }
            guard let counterparty = accounts.first(where: { $0.issuer == issuer }) else { return nil }
            // A GoPay statement row that merely mentions "GoPay" names its
            // own account, not a counterparty.
            guard counterparty.id != transaction.accountId else { return nil }
            guard accountsById[transaction.accountId] != nil else { return nil }

            let isOutgoing = transaction.direction == .debit
            return DerivedTransfer(
                id: transaction.id.uuidString,
                date: transaction.date,
                amount: transaction.amount,
                fromAccountId: isOutgoing ? transaction.accountId : counterparty.id,
                toAccountId: isOutgoing ? counterparty.id : transaction.accountId,
                fee: nil,
                isInferred: true,
                transactionIds: [transaction.id]
            )
        }
    }

    private static func counterpartyIssuer(for transaction: Transaction) -> Issuer? {
        let haystack = [transaction.merchant, transaction.rawDescription]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return counterpartyMarkers.first { haystack.contains($0.marker) }?.issuer
    }
}
