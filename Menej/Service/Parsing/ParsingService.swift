//
//  ParsingService.swift
//  Menej
//
//  Orchestrates the pipeline described in PRD §6 F1:
//  File arrives → Issuer detection → text extraction → rule engine →
//  normalize → confidence scoring → user review screen.
//
//  Framework-free by design (no SwiftUI/SwiftData imports) so the corpus can
//  be run against it from a command-line harness — see Appendix C notes.
//

import Foundation

struct ParsedTransaction {
    let date: Date
    let amount: Decimal
    let direction: Direction
    let rawDescription: String
    let merchant: String?
    let confidence: Double

    /// `amount` is an unsigned magnitude; this applies `direction` for display.
    var signedAmount: Decimal {
        direction == .debit ? -amount : amount
    }
}

struct ParsedStatement {
    let issuer: Issuer
    let transactions: [ParsedTransaction]
    let confidence: Double
    let unaccountedAmount: Decimal
    /// The account's balance as printed on the statement itself (e.g.
    /// myBCA's "SALDO AKHIR"), when the issuer's format has one. `nil` for
    /// issuers with no running-balance concept (GoPay, Grab) — callers must
    /// not guess a balance for those.
    let closingBalance: Decimal?
}

enum ParsingError: Error {
    case noRulesAvailable
}

protocol ParsingServiceProtocol {
    func parse(fileURL: URL, availableRules: [IssuerRule]) throws -> ParsedStatement
}

final class ParsingService: ParsingServiceProtocol {
    private let textExtractor: PDFTextExtracting
    private let issuerDetector: IssuerDetecting
    private let ruleEngine: RuleEngineProtocol
    private let normalizer: TransactionNormalizing
    private let confidenceScorer: ConfidenceScoring

    // Defaults are constructed in the body rather than as parameter
    // defaults — see ImportViewModel.swift for why.
    init(
        textExtractor: PDFTextExtracting? = nil,
        issuerDetector: IssuerDetecting? = nil,
        ruleEngine: RuleEngineProtocol? = nil,
        normalizer: TransactionNormalizing? = nil,
        confidenceScorer: ConfidenceScoring? = nil
    ) {
        self.textExtractor = textExtractor ?? PDFTextExtractor()
        self.issuerDetector = issuerDetector ?? IssuerDetector()
        self.ruleEngine = ruleEngine ?? RuleEngine()
        self.normalizer = normalizer ?? TransactionNormalizer()
        self.confidenceScorer = confidenceScorer ?? ConfidenceScorer()
    }

    func parse(fileURL: URL, availableRules: [IssuerRule]) throws -> ParsedStatement {
        guard !availableRules.isEmpty else { throw ParsingError.noRulesAvailable }

        let text = try textExtractor.extractText(from: fileURL)
        let issuer = try issuerDetector.detectIssuer(fromText: text, using: availableRules)
        guard let rule = availableRules.first(where: { $0.issuer == issuer.rawValue }) else {
            throw ParsingError.noRulesAvailable
        }

        let rawRows = try ruleEngine.extractRows(fromText: text, fileURL: fileURL, rule: rule)
        let transactions = normalizer.normalize(rows: rawRows, rule: rule)
        let confidence = confidenceScorer.score(transactions: transactions, rawRowCount: rawRows.count)
        let balances = ruleEngine.statementBalances(fromText: text, fileURL: fileURL, rule: rule)
        let unaccounted = confidenceScorer.unaccountedAmount(
            transactions: transactions,
            printedClosingBalance: balances.closing,
            openingBalance: balances.opening ?? 0
        )

        return ParsedStatement(
            issuer: issuer,
            transactions: transactions,
            confidence: confidence,
            unaccountedAmount: unaccounted,
            closingBalance: balances.closing
        )
    }
}
