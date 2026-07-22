//
//  LiquidBalanceService.swift
//  Menej
//
//  Current balance of a liquid account (PRD §6 F5, "Liquid" breakdown row).
//
//  Only myBCA statements print a running balance ("SALDO AKHIR") — GoPay and
//  Grab don't, so their accounts sat at 0 forever and silently understated
//  net worth. One rule covers all three issuers:
//
//      current balance = anchor + Σ signed amounts of that account's
//                        transactions dated strictly after the anchor date
//
//  where the anchor is (`Account.balance` @ `Account.lastSyncedAt`). For
//  myBCA the anchor is the statement's closing balance and nothing is dated
//  after it, so its displayed balance is unchanged. For GoPay/Grab the user
//  sets the anchor once and every later imported transaction rolls it
//  forward.
//
//  An account with no anchor (`lastSyncedAt == nil`) contributes its stored
//  balance as-is and gets no roll-forward: "unknown" is honest, a large
//  negative number extrapolated from an imaginary zero is not.
//

import Foundation

protocol LiquidBalanceServiceProtocol {
    func balances(accounts: [Account], transactions: [Transaction]) -> [UUID: Decimal]
    func total(accounts: [Account], transactions: [Transaction]) -> Decimal
}

struct LiquidBalanceService: LiquidBalanceServiceProtocol {
    func balances(accounts: [Account], transactions: [Transaction]) -> [UUID: Decimal] {
        let countedIds = countedTransactionIds(accounts: accounts, transactions: transactions)

        var result: [UUID: Decimal] = [:]
        for account in accounts {
            guard let anchorDate = account.lastSyncedAt else {
                result[account.id] = account.balance
                continue
            }
            let movement = transactions
                .filter { $0.accountId == account.id && $0.date > anchorDate && countedIds.contains($0.id) }
                .reduce(Decimal(0)) { $0 + $1.signedAmount }
            result[account.id] = account.balance + movement
        }
        return result
    }

    func total(accounts: [Account], transactions: [Transaction]) -> Decimal {
        balances(accounts: accounts, transactions: transactions).values.reduce(0, +)
    }

    /// The transactions that may move a balance, with one class excluded:
    /// the *non-funding* leg of a same-direction dedup group. Paying for a
    /// Grab ride with GoPay produces a debit in both statements (this is
    /// exactly the shape DedupService exists to catch) — counting both would
    /// subtract the ride twice. The funding leg is the one that really left
    /// an account, picked deterministically: an anchored account first (an
    /// unanchored one has no balance to move anyway), then a bank over an
    /// e-wallet, then the lowest account id.
    ///
    /// Opposite-direction groups are transfers between the user's own
    /// accounts and both legs are kept — −X here and +X there is correct.
    private func countedTransactionIds(accounts: [Account], transactions: [Transaction]) -> Set<UUID> {
        var counted = Set(transactions.map(\.id))
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        let groups = Dictionary(grouping: transactions.filter { $0.dedupGroupId != nil }) { $0.dedupGroupId! }
        for (_, legs) in groups {
            guard legs.count > 1 else { continue }
            let directions = Set(legs.map(\.direction))
            guard directions.count == 1 else { continue }

            let funding = legs.min { isBetterFundingLeg($0, than: $1, accountsById: accountsById) }
            for leg in legs where leg.id != funding?.id {
                counted.remove(leg.id)
            }
        }
        return counted
    }

    /// Strict ordering over the legs of a same-direction group: anchored
    /// before unanchored, bank before e-wallet, then lowest account id — so
    /// `min(by:)` returns the funding leg and the choice never flips between
    /// launches.
    private func isBetterFundingLeg(
        _ a: Transaction,
        than b: Transaction,
        accountsById: [UUID: Account]
    ) -> Bool {
        let accountA = accountsById[a.accountId]
        let accountB = accountsById[b.accountId]

        let anchoredA = accountA?.hasBalanceAnchor ?? false
        let anchoredB = accountB?.hasBalanceAnchor ?? false
        if anchoredA != anchoredB { return anchoredA }

        let bankA = accountA?.type == .bankAccount
        let bankB = accountB?.type == .bankAccount
        if bankA != bankB { return bankA }

        return a.accountId.uuidString < b.accountId.uuidString
    }
}
