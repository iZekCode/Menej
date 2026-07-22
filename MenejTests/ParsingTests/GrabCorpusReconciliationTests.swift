//
//  GrabCorpusReconciliationTests.swift
//  MenejTests
//
//  Grab prints its own summary in the statement header — "Jumlah Pemesanan: 28
//  | Jumlah: IDR 1087730.00" — which is an authoritative count *and* total, so
//  unlike GoPay this reconciles directly with no adjustment.
//
//  Grab's extractor already assigns each record's fields from a Y band around
//  its date anchor, which is the approach the myBCA extractor was rewritten to
//  use after a credit went missing from an April statement. It is measurably
//  the more robust of the two: exact on all five months from render scale 1.5
//  upward (it ships at 3.0).
//

import Foundation
import Testing
@testable import Menej

struct GrabCorpusReconciliationTests {
    /// Transcribed from each statement's own printed header.
    private struct PrintedSummary: Sendable {
        let filename: String
        let orderCount: Int
        let total: Decimal
    }

    private static let corpus: [PrintedSummary] = [
        PrintedSummary(filename: "Grab_Feb_26", orderCount: 4, total: 199_200),
        PrintedSummary(filename: "Grab_Mar_26", orderCount: 15, total: 717_160),
        PrintedSummary(filename: "Grab_Apr_26", orderCount: 28, total: 1_087_730),
        PrintedSummary(filename: "Grab_May_26", orderCount: 44, total: 1_638_693),
        PrintedSummary(filename: "Grab_Jun_26", orderCount: 35, total: 1_202_669),
    ]

    private static func parse(_ filename: String) throws -> ParsedStatement {
        try CorpusFixtures.statement(filename, folder: "Grab", rule: "grab")
    }

    @Test(arguments: corpus)
    func statementMatchesItsPrintedSummary(_ printed: PrintedSummary) throws {
        let statement = try Self.parse(printed.filename)

        #expect(statement.transactions.count == printed.orderCount, "\(printed.filename): order count")
        #expect(
            statement.transactions.reduce(Decimal(0)) { $0 + $1.amount } == printed.total,
            "\(printed.filename): total"
        )

        // Grab's order history is spend from the user's perspective; a credit
        // here would mean the direction logic broke, not that a refund appeared
        // (none exist in the corpus).
        #expect(statement.transactions.allSatisfy { $0.direction == .debit }, "\(printed.filename): all debits")
        #expect(statement.confidence == 1.0, "\(printed.filename): confidence")
    }

    /// A record whose time-of-day OCR clipped at the page edge keeps its date
    /// and amount at reduced confidence rather than being dropped — the ledger
    /// cares which day it was, not the minute. One May order is in this state.
    @Test func clippedTimeKeepsTheOrderAtLowerConfidence() throws {
        let statement = try Self.parse("Grab_May_26")

        let assumedNoon = statement.transactions.filter { $0.confidence < 1.0 }
        #expect(assumedNoon.count == 1)
        #expect(statement.transactions.count == 44)
    }
}
