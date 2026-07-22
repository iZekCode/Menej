//
//  GoPayCorpusReconciliationTests.swift
//  MenejTests
//
//  GoPay's printed "Total pemasukan"/"Total pengeluaran" are NOT a valid
//  reconciliation target on their own: they count only the Rupiah portion of
//  a part-coins payment, while the transaction row shows the full price. The
//  gap is exactly that month's "Total Coins dipakai" (Feb 22, Mar 416, Apr
//  22.419, Mei 609). The ledger wants the full price, so these expectations
//  are the row sums, with the printed figure noted alongside.
//
//  June is the exception and it is the statement's own inconsistency, not the
//  parser's: GoPay prints Total pengeluaran Rp3.937.156 while the rows it
//  lists sum to Rp1.937.554. Every date row in the PDF is captured (records +
//  coins-only == date lines, in all five months) and June's largest outflow
//  is Rp349.000 — there is no Rp2.000.000 spend anywhere in the document.
//  BCA confirms the matching Rp2.000.000 as a top-up, which GoPay does list
//  as income.
//
//  These numbers are what the parser has always produced; nothing here is a
//  regression baseline. GoPay's text-layer path had no known defect when
//  these tests were written — they exist to keep it that way.
//

import Foundation
import Testing
@testable import Menej

struct GoPayCorpusReconciliationTests {
    private struct Expectation: Sendable {
        let filename: String
        let creditCount: Int
        let creditTotal: Decimal
        let debitCount: Int
        let debitTotal: Decimal

        var transactionCount: Int { creditCount + debitCount }
    }

    private static let corpus: [Expectation] = [
        // printed pengeluaran 1.381.267 + 22 coins
        Expectation(filename: "GoPay_Feb_26", creditCount: 0, creditTotal: 0, debitCount: 14, debitTotal: 1_381_289),
        // printed pengeluaran 1.681.024 + 416 coins
        Expectation(filename: "GoPay_Mar_26", creditCount: 1, creditTotal: 2_000_000, debitCount: 50, debitTotal: 1_681_440),
        // printed pengeluaran 4.314.891 + 22.419 coins
        Expectation(filename: "GoPay_Apr_26", creditCount: 3, creditTotal: 4_705_000, debitCount: 53, debitTotal: 4_337_310),
        // printed pengeluaran 821.715 + 609 coins
        Expectation(filename: "GoPay_Mei_26", creditCount: 0, creditTotal: 0, debitCount: 34, debitTotal: 822_324),
        // printed pengeluaran 3.937.156 — see the file note; rows sum to this
        Expectation(filename: "GoPay_Jun_26", creditCount: 2, creditTotal: 2_003_000, debitCount: 46, debitTotal: 1_937_554),
    ]

    private static func parse(_ filename: String) throws -> ParsedStatement {
        try CorpusFixtures.statement(filename, folder: "GoPay", rule: "gopay")
    }

    @Test(arguments: corpus)
    func statementParsesEveryRow(_ expected: Expectation) throws {
        let statement = try Self.parse(expected.filename)

        let credits = statement.transactions.filter { $0.direction == .credit }
        let debits = statement.transactions.filter { $0.direction == .debit }

        #expect(statement.transactions.count == expected.transactionCount, "\(expected.filename): transaction count")
        #expect(credits.count == expected.creditCount, "\(expected.filename): credit count")
        #expect(debits.count == expected.debitCount, "\(expected.filename): debit count")
        #expect(credits.reduce(Decimal(0)) { $0 + $1.amount } == expected.creditTotal, "\(expected.filename): credit total")
        #expect(debits.reduce(Decimal(0)) { $0 + $1.amount } == expected.debitTotal, "\(expected.filename): debit total")

        // GoPay has no closing balance, so `unaccountedAmount` is structurally
        // 0 and proves nothing — asserting on it here would be theatre.
        // Confidence is the only in-app signal this issuer has, which is why
        // the row counts above are the real check.
        #expect(statement.confidence == 1.0, "\(expected.filename): confidence")
    }

    /// A record's amount sits on its last line, so a transaction rendered at
    /// a page boundary is the shape most likely to lose it. `PDFTextExtractor`
    /// joins pages with an explicit newline, which is what keeps the amount on
    /// its own line — drop that separator and PDFKit runs the next page's
    /// header straight onto it ("…-Rp46.065E-statement Halaman 4 dari 6"),
    /// which `goPayAmountLine` can't match because it is end-anchored.
    ///
    /// These three April transactions are each the last on their page, so they
    /// fail first if that join ever regresses.
    @Test func transactionsAtPageBoundariesKeepTheirAmount() throws {
        let statement = try Self.parse("GoPay_Apr_26")

        func amount(matching needle: String) -> [Decimal] {
            statement.transactions.filter { $0.rawDescription.contains(needle) }.map(\.amount)
        }

        #expect(amount(matching: "Google Play") == [46_065])
        #expect(amount(matching: "Muhamad Aldi") == [2_500])
        #expect(amount(matching: "0420260421233709VYI6") == [47_000])
    }

    /// Coins-only cashback rows are deliberately not transactions, and must
    /// stay out of `rawRowCount` too — counting them as parse failures dragged
    /// a perfect parse down to 0.59 before.
    @Test func cashbackRowsAreExcludedWithoutCostingConfidence() throws {
        let statement = try Self.parse("GoPay_Apr_26")

        #expect(!statement.transactions.contains { $0.rawDescription.hasPrefix("Cashback") })
        #expect(statement.confidence == 1.0)
    }
}
