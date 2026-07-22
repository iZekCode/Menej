//
//  BCACorpusReconciliationTests.swift
//  MenejTests
//
//  Reconciles the myBCA parser against every real statement's own printed
//  footer — the "MUTASI CR"/"MUTASI DB" block, which carries both a count
//  and a total the bank computed itself. This is the check that was missing
//  when a 271,000 credit went missing from a real April import: whatever
//  dropped it did so inside `extractBCARecords`, which shrank
//  ConfidenceScorer's numerator and denominator alike, so the loss still
//  reported 1.0 confidence and nothing in the app disagreed with it.
//
//  Counts matter as much as totals here. April's page 3 holds six identical
//  271,000 credits in a row — a parser can lose one and still look close on
//  any check that only compares sums against a rounded expectation.
//
//  NOTE: like ParsingServiceTests, this file is not yet part of an Xcode
//  target. See CorpusFixtures.swift for how the corpus is located.
//

import Foundation
import Testing
@testable import Menej

struct BCACorpusReconciliationTests {
    /// One statement's printed footer, transcribed from the PDF itself.
    private struct Footer: Sendable {
        let filename: String
        let creditCount: Int
        let creditTotal: Decimal
        let debitCount: Int
        let debitTotal: Decimal

        var transactionCount: Int { creditCount + debitCount }
    }

    private static let corpus: [Footer] = [
        Footer(filename: "MyBCA_Feb_26", creditCount: 4, creditTotal: 14_257_661.66, debitCount: 15, debitTotal: 5_343_822.53),
        Footer(filename: "MyBCA_Mar_26", creditCount: 4, creditTotal: 13_316_424.52, debitCount: 13, debitTotal: 6_933_398.50),
        Footer(filename: "MyBCA_Apr_26", creditCount: 15, creditTotal: 18_893_537.14, debitCount: 24, debitTotal: 33_673_600.83),
        Footer(filename: "MyBCA_May_26", creditCount: 9, creditTotal: 20_713_353.33, debitCount: 19, debitTotal: 14_717_654.27),
        Footer(filename: "MyBCA_Jun_26", creditCount: 6, creditTotal: 13_117_909.22, debitCount: 22, debitTotal: 21_734_147.44),
    ]

    private static func parse(_ filename: String) throws -> ParsedStatement {
        try CorpusFixtures.statement(filename, folder: "MyBCA", rule: "bca_mybca")
    }

    @Test(arguments: corpus)
    func statementReconcilesAgainstItsPrintedFooter(_ footer: Footer) throws {
        let statement = try Self.parse(footer.filename)

        let credits = statement.transactions.filter { $0.direction == .credit }
        let debits = statement.transactions.filter { $0.direction == .debit }

        #expect(statement.transactions.count == footer.transactionCount, "\(footer.filename): transaction count")
        #expect(credits.count == footer.creditCount, "\(footer.filename): credit count")
        #expect(debits.count == footer.debitCount, "\(footer.filename): debit count")
        #expect(credits.reduce(Decimal(0)) { $0 + $1.amount } == footer.creditTotal, "\(footer.filename): credit total")
        #expect(debits.reduce(Decimal(0)) { $0 + $1.amount } == footer.debitTotal, "\(footer.filename): debit total")

        // The footer's own SALDO AWAL → SALDO AKHIR roll-forward. Zero here
        // is the single strongest signal that nothing was dropped: any lost
        // record shows up as exactly its own amount.
        #expect(statement.unaccountedAmount == 0, "\(footer.filename): unaccounted")
        #expect(statement.confidence == 1.0, "\(footer.filename): confidence")
    }

    /// The specific regression. April's page 3 renders six 271,000 credits
    /// back to back with a single balance checkpoint, and one of them (note
    /// "apart", counterparty JENNIFER EDDRICK W) was missing from a real
    /// import. The densest block in the corpus is the one most likely to lose
    /// a row, whatever the mechanism, so it is worth pinning by name rather
    /// than trusting the totals alone — eight of these nine are identical in
    /// amount and date, which is exactly the shape a sum-only check misses.
    @Test func aprilKeepsEveryOneOfTheIdenticalCredits() throws {
        let statement = try Self.parse("MyBCA_Apr_26")

        let reimbursements = statement.transactions.filter { $0.direction == .credit && $0.amount == 271_000 }
        #expect(reimbursements.count == 9)

        let merchants = Set(statement.transactions.compactMap(\.merchant))
        #expect(merchants.contains("JENNIFER EDDRICK W"))
    }

    /// A record whose amount can't be read must survive as an unusable row
    /// rather than vanishing: dropping it moves ConfidenceScorer's numerator
    /// and denominator together and reports the loss as a perfect parse.
    @Test func unreadableAmountLowersConfidenceInsteadOfDisappearing() throws {
        let rows = [
            RawTransactionRow(rawLines: ["01/04", "TRSF E-BANKING DB", "50,000.00", "DB"], sourceLineNumber: 0, periodYear: 2026),
            RawTransactionRow(rawLines: ["02/04", "TRSF E-BANKING DB", "", ""], sourceLineNumber: 0, periodYear: 2026),
        ]
        let parsed = try TransactionNormalizer().normalize(rows: rows, rule: CorpusFixtures.rule(named: "bca_mybca"))

        #expect(parsed.count == 1)
        #expect(ConfidenceScorer().score(transactions: parsed, rawRowCount: rows.count) == 0.5)
    }
}

/// "SWITCHING" is BCA's interbank-network boilerplate, and its meaning flips
/// with direction: outbound it's the user moving their own money, inbound
/// it's someone else's money arriving. It used to map to `.transfer` in both
/// directions, and because `.transfer` is one of the categories a credit is
/// allowed to keep, the credit-coercion guard in `categorize` couldn't repair
/// it — so an incoming reimbursement was treated as an own-account transfer
/// and excluded from Insights' income by `isTransferLike`.
struct SwitchingDirectionTests {
    @Test func incomingSwitchingIsIncomeNotTransfer() {
        let service = CategorizationService(userDefaults: UserDefaults(suiteName: #function)!)
        let (_, category) = service.categorize(
            rawDescription: "SWITCHING CR DR 016 JEPRIANTO IJEPRIANTO",
            issuer: .bcaMyBCA,
            direction: .credit
        )
        #expect(category == .income)
    }

    @Test func outgoingSwitchingStaysATransfer() {
        let service = CategorizationService(userDefaults: UserDefaults(suiteName: #function)!)
        let (_, category) = service.categorize(
            rawDescription: "SWITCHING DB DR 016 SOMEONE",
            issuer: .bcaMyBCA,
            direction: .debit
        )
        #expect(category == .transfer)
    }

    /// The narrowness of the fix matters: a credit landing in a *wallet*
    /// really is an own-account transfer, and coercing it to income would
    /// double-count it against net worth.
    @Test func walletTopUpCreditStaysATransfer() {
        let service = CategorizationService(userDefaults: UserDefaults(suiteName: #function)!)
        let (_, category) = service.categorize(
            rawDescription: "TRSF E-BANKING DB 1004/FTFVA/WS95031 70001/GOPAY TOPUP",
            issuer: .bcaMyBCA,
            direction: .credit
        )
        #expect(category == .transfer)
    }
}
