//
//  TransferServiceTests.swift
//  MenejTests
//

import Foundation
import Testing
@testable import Menej

struct TransferServiceTests {
    private let service = TransferService()

    private let bca = Account(issuer: .bcaMyBCA, type: .bankAccount)
    private let gopay = Account(issuer: .gopay, type: .eWallet)
    private let grab = Account(issuer: .grab, type: .eWallet)

    private func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: day))!
    }

    private func transaction(
        account: Account,
        day: Int,
        amount: Decimal,
        direction: Direction,
        rawDescription: String = "test",
        merchant: String? = nil,
        category: Category? = nil,
        dedupGroupId: UUID? = nil
    ) -> Transaction {
        Transaction(
            accountId: account.id,
            date: date(day),
            amount: amount,
            direction: direction,
            rawDescription: rawDescription,
            merchant: merchant,
            categoryId: category,
            dedupGroupId: dedupGroupId
        )
    }

    @Test func matchedPairBecomesAConfirmedTransferWithTheFee() {
        let groupId = UUID()
        let out = transaction(account: bca, day: 12, amount: 2_001_000, direction: .debit, dedupGroupId: groupId)
        let inbound = transaction(account: gopay, day: 12, amount: 2_000_000, direction: .credit, dedupGroupId: groupId)

        let transfers = service.derive(transactions: [out, inbound], accounts: [bca, gopay])
        #expect(transfers.count == 1)
        #expect(transfers[0].fromAccountId == bca.id)
        #expect(transfers[0].toAccountId == gopay.id)
        #expect(transfers[0].amount == 2_000_000)
        #expect(transfers[0].fee == 1_000)
        #expect(transfers[0].isInferred == false)
    }

    @Test func sameDirectionDedupGroupIsNotATransfer() {
        // The same expense recorded by two sources — not money moving.
        let groupId = UUID()
        let a = transaction(account: bca, day: 12, amount: 47_000, direction: .debit, dedupGroupId: groupId)
        let b = transaction(account: gopay, day: 12, amount: 47_000, direction: .debit, dedupGroupId: groupId)

        #expect(service.derive(transactions: [a, b], accounts: [bca, gopay]).isEmpty)
    }

    @Test func oneSidedTopUpIsInferredFromTheDescription() {
        let out = transaction(
            account: bca,
            day: 12,
            amount: 2_001_000,
            direction: .debit,
            rawDescription: "TRSF E-BANKING DB GOPAY TOP UP",
            merchant: "GoPay Top Up",
            category: .transfer
        )

        let transfers = service.derive(transactions: [out], accounts: [bca, gopay])
        #expect(transfers.count == 1)
        #expect(transfers[0].fromAccountId == bca.id)
        #expect(transfers[0].toAccountId == gopay.id)
        #expect(transfers[0].isInferred)
        #expect(transfers[0].fee == nil)
    }

    @Test func ovoTopUpIsCountedAsATransferToGrab() {
        // BCA's Vision OCR misreads the letter O as the digit 0 — real
        // corpus example. Menej has no OVO account, and for this user an
        // OVO top-up funds their Grab wallet.
        let out = transaction(
            account: bca,
            day: 12,
            amount: 200_000,
            direction: .debit,
            rawDescription: "TRSF E-BANKING DB 70001/0VO TOPUP 0895xxxxxxx",
            merchant: "0VO TOPUP",
            category: .transfer
        )

        let transfers = service.derive(transactions: [out], accounts: [bca, gopay, grab])
        #expect(transfers.count == 1)
        #expect(transfers[0].fromAccountId == bca.id)
        #expect(transfers[0].toAccountId == grab.id)
        #expect(transfers[0].isInferred)
    }

    @Test func externalTransferIsDropped() {
        let out = transaction(
            account: bca,
            day: 12,
            amount: 500_000,
            direction: .debit,
            rawDescription: "BI-FAST TRANSFER KE 022 0T01/19",
            category: .transfer
        )

        #expect(service.derive(transactions: [out], accounts: [bca, gopay]).isEmpty)
    }

    @Test func transferNamingTheAccountsOwnIssuerIsDropped() {
        // A GoPay row saying "GoPay" names itself, not a counterparty.
        let out = transaction(
            account: gopay,
            day: 12,
            amount: 100_000,
            direction: .debit,
            rawDescription: "Ditransfer ke GoPay",
            category: .transfer
        )

        #expect(service.derive(transactions: [out], accounts: [bca, gopay]).isEmpty)
    }

    @Test func incomingOneSidedTopUpPointsAtTheReceivingAccount() {
        let inbound = transaction(
            account: gopay,
            day: 12,
            amount: 2_000_000,
            direction: .credit,
            rawDescription: "Top Up BCA VA 1234567",
            category: .transfer
        )

        let transfers = service.derive(transactions: [inbound], accounts: [bca, gopay])
        #expect(transfers.count == 1)
        #expect(transfers[0].fromAccountId == bca.id)
        #expect(transfers[0].toAccountId == gopay.id)
    }

    @Test func transfersAreSortedNewestFirst() {
        let old = transaction(account: bca, day: 2, amount: 100_000, direction: .debit, merchant: "GoPay Top Up", category: .transfer)
        let recent = transaction(account: bca, day: 20, amount: 200_000, direction: .debit, merchant: "GoPay Top Up", category: .transfer)

        let transfers = service.derive(transactions: [old, recent], accounts: [bca, gopay])
        #expect(transfers.map(\.amount) == [200_000, 100_000])
    }
}
