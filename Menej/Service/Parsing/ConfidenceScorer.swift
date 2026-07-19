//
//  ConfidenceScorer.swift
//  Menej
//
//  Confidence scoring + reconciliation gap — see PRD §6 F1.
//  Low scores (unparsed rows, totals that don't reconcile) trigger the review
//  screen. If the parsed closing balance doesn't match the balance printed on
//  the statement, the gap is surfaced as `unaccountedAmount` — never hidden.
//

import Foundation

protocol ConfidenceScoring {
    func score(transactions: [ParsedTransaction], rawRowCount: Int) -> Double
    func unaccountedAmount(transactions: [ParsedTransaction], printedClosingBalance: Decimal?, openingBalance: Decimal) -> Decimal
}

struct ConfidenceScorer: ConfidenceScoring {
    func score(transactions: [ParsedTransaction], rawRowCount: Int) -> Double {
        guard rawRowCount > 0 else { return 0 }
        return Double(transactions.count) / Double(rawRowCount)
    }

    func unaccountedAmount(transactions: [ParsedTransaction], printedClosingBalance: Decimal?, openingBalance: Decimal) -> Decimal {
        guard let printedClosingBalance else { return 0 }
        let computedClosingBalance = transactions.reduce(openingBalance) { balance, transaction in
            switch transaction.direction {
            case .credit: return balance + transaction.amount
            case .debit: return balance - transaction.amount
            }
        }
        return printedClosingBalance - computedClosingBalance
    }
}
