//
//  LiquidBalanceServiceTests.swift
//  MenejTests
//
//  NOTE: not yet part of any Xcode target — see ParsingServiceTests.swift.
//

import Foundation
import Testing
@testable import Menej

struct LiquidBalanceServiceTests {
    private let service = LiquidBalanceService()

    private func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: day))!
    }

    private func transaction(
        account: Account,
        day: Int,
        amount: Decimal,
        direction: Direction,
        dedupGroupId: UUID? = nil
    ) -> Transaction {
        Transaction(
            accountId: account.id,
            date: date(day),
            amount: amount,
            direction: direction,
            rawDescription: "test",
            dedupGroupId: dedupGroupId
        )
    }

    @Test func anchoredAccountWithNoLaterTransactionsKeepsItsBalance() {
        let bca = Account(issuer: .bcaMyBCA, type: .bankAccount, balance: 5_000_000, lastSyncedAt: date(30))
        let before = transaction(account: bca, day: 12, amount: 100_000, direction: .debit)

        #expect(service.balances(accounts: [bca], transactions: [before])[bca.id] == 5_000_000)
    }

    @Test func balanceRollsForwardFromTheAnchorDate() {
        let gopay = Account(issuer: .gopay, type: .eWallet, balance: 500_000, lastSyncedAt: date(10), isBalanceManual: true)
        let topUp = transaction(account: gopay, day: 12, amount: 2_000_000, direction: .credit)
        let spend = transaction(account: gopay, day: 14, amount: 47_000, direction: .debit)
        let beforeAnchor = transaction(account: gopay, day: 5, amount: 900_000, direction: .debit)

        let balances = service.balances(accounts: [gopay], transactions: [topUp, spend, beforeAnchor])
        #expect(balances[gopay.id] == 2_453_000)
    }

    @Test func unanchoredAccountDoesNotRollForward() {
        let grab = Account(issuer: .grab, type: .eWallet)
        let spend = transaction(account: grab, day: 14, amount: 47_000, direction: .debit)

        #expect(service.balances(accounts: [grab], transactions: [spend])[grab.id] == 0)
    }

    @Test func sameDirectionDedupPairIsCountedOnceOnTheFundingAccount() {
        // A Grab ride paid with GoPay: a debit in both statements.
        let gopay = Account(issuer: .gopay, type: .eWallet, balance: 500_000, lastSyncedAt: date(10), isBalanceManual: true)
        let grab = Account(issuer: .grab, type: .eWallet, balance: 200_000, lastSyncedAt: date(10), isBalanceManual: true)
        let groupId = UUID()
        let gopayLeg = transaction(account: gopay, day: 12, amount: 47_000, direction: .debit, dedupGroupId: groupId)
        let grabLeg = transaction(account: grab, day: 12, amount: 47_000, direction: .debit, dedupGroupId: groupId)

        let balances = service.balances(accounts: [gopay, grab], transactions: [gopayLeg, grabLeg])
        // Exactly one of the two accounts absorbs the ride, never both.
        #expect(balances[gopay.id]! + balances[grab.id]! == 653_000)
    }

    @Test func oppositeDirectionDedupPairMovesBothAccounts() {
        let bca = Account(issuer: .bcaMyBCA, type: .bankAccount, balance: 5_000_000, lastSyncedAt: date(1))
        let gopay = Account(issuer: .gopay, type: .eWallet, balance: 0, lastSyncedAt: date(1), isBalanceManual: true)
        let groupId = UUID()
        let out = transaction(account: bca, day: 12, amount: 2_001_000, direction: .debit, dedupGroupId: groupId)
        let inbound = transaction(account: gopay, day: 12, amount: 2_000_000, direction: .credit, dedupGroupId: groupId)

        let balances = service.balances(accounts: [bca, gopay], transactions: [out, inbound])
        #expect(balances[bca.id] == 2_999_000)
        #expect(balances[gopay.id] == 2_000_000)
    }

    @Test func totalSumsEveryAccount() {
        let bca = Account(issuer: .bcaMyBCA, type: .bankAccount, balance: 5_000_000, lastSyncedAt: date(30))
        let gopay = Account(issuer: .gopay, type: .eWallet, balance: 500_000, lastSyncedAt: date(30), isBalanceManual: true)

        #expect(service.total(accounts: [bca, gopay], transactions: []) == 5_500_000)
    }
}
