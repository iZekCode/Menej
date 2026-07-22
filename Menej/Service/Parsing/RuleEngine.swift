//
//  RuleEngine.swift
//  Menej
//
//  Applies issuer rules to extract raw transaction row blocks from statement
//  text — see PRD §6 F1 pipeline.
//
//  Real-world statement layouts are too idiosyncratic for one generic
//  column-index scheme (the naive `columnMap` in IssuerRule): GoPay is a
//  clean multi-line list parseable straight from the text layer. myBCA and
//  Grab both need Vision OCR instead — myBCA because PDFKit's plain text
//  dump scrambles row/column order on busy dates (position-aware OCR
//  bounding boxes fix this; the text layer alone cannot), and Grab because
//  its PDF export loses all digit characters on text-layer extraction
//  (font subsetting, no ToUnicode mapping). See OCRRowExtractor.swift for
//  both. This dispatches to per-issuer extraction logic, calibrated against
//  the real corpus in `Menej/Financial Statement/`.
//

import Foundation

/// One transaction's raw text block, in source order, before interpretation.
struct RawTransactionRow {
    let rawLines: [String]
    let sourceLineNumber: Int
    /// Statement period year, when the issuer's dates omit it (e.g. myBCA's
    /// "DD/MM" with the year only printed once in the "PERIODE :" header).
    var periodYear: Int? = nil
}

protocol RuleEngineProtocol {
    /// `fileURL` is the original statement file — needed for issuers (myBCA,
    /// Grab) whose extraction can't rely on the plain text layer at all and
    /// has to re-process the file itself via OCR.
    func extractRows(fromText text: String, fileURL: URL, rule: IssuerRule) throws -> [RawTransactionRow]

    /// Opening/closing balance printed on the statement itself, when the
    /// issuer's format has one (e.g. myBCA's "SALDO AWAL"/"SALDO AKHIR"
    /// footer) — used for reconciliation. `(nil, nil)` when not applicable.
    func statementBalances(fromText text: String, fileURL: URL, rule: IssuerRule) -> (opening: Decimal?, closing: Decimal?)
}

extension RuleEngineProtocol {
    func statementBalances(fromText text: String, fileURL: URL, rule: IssuerRule) -> (opening: Decimal?, closing: Decimal?) {
        (nil, nil)
    }
}

struct RuleEngine: RuleEngineProtocol {
    func extractRows(fromText text: String, fileURL: URL, rule: IssuerRule) throws -> [RawTransactionRow] {
        switch rule.issuer {
        case Issuer.gopay.rawValue:
            return Self.extractGoPayRows(lines: text.components(separatedBy: .newlines))
        case Issuer.bcaMyBCA.rawValue:
            return OCRRowExtractor.extractBCARows(fileURL: fileURL)
        case Issuer.grab.rawValue:
            return OCRRowExtractor.extractGrabRows(fileURL: fileURL)
        default:
            return []
        }
    }

    // MARK: - GoPay

    // Each record: "DD/MM/YYYY" \n "HH:mm" \n 1+ description/reference lines
    // \n 0-2 standalone "GoPay Saldo"/"GoPay Coins" label lines \n a terminal
    // line carrying either an "Rp" amount (real money movement) or a bare
    // number after "GoPay Coins" (cashback points only, not real money).
    private static let goPayDateLine = try! NSRegularExpression(pattern: #"^\d{2}/\d{2}/\d{4}$"#)
    private static let goPayTimeLine = try! NSRegularExpression(pattern: #"^\d{2}:\d{2}$"#)
    // The payment-method label prefixing the amount isn't always "GoPay
    // Saldo"/"GoPay Coins" — confirmed real statements also show e.g.
    // "BCA VA -Rp1.001.000" for bank-transfer top-ups. Match any prefix,
    // anchored on the amount at the end of the line instead.
    static let goPayAmountLine = try! NSRegularExpression(
        pattern: #"(?:^|\s)(-)?Rp([\d.]+)$"#
    )
    static let goPayCoinsOnlyLine = try! NSRegularExpression(pattern: #"^GoPay Coins\s+[\d.]+$"#)

    /// PDFKit emits each page's header as a continuation of the previous
    /// page's last line, glued straight onto that transaction's amount:
    ///
    ///     GoPay Saldo -Rp46.065E-statement Halaman 4 dari 6 Periode transaksi …
    ///
    /// `goPayAmountLine` is end-anchored, so the glued line matched nothing,
    /// the record never terminated, and it was dropped — one lost transaction
    /// per page boundary in every statement of the corpus (12 across the five
    /// real months, Rp383.030 of spending, including two `Google Play`
    /// charges). Cutting the header off restores the amount line.
    private static let goPayPageHeader = try! NSRegularExpression(pattern: #"E-statement\s+Halaman"#)

    private static func stripPageHeaders(_ lines: [String]) -> [String] {
        lines.map { line in
            guard let match = goPayPageHeader.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range, in: line) else { return line }
            return String(line[..<range.lowerBound])
        }
    }

    private static func extractGoPayRows(lines rawLines: [String]) -> [RawTransactionRow] {
        let lines = stripPageHeaders(rawLines)
        var rows: [RawTransactionRow] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard matches(goPayDateLine, line), index + 1 < lines.count else {
                index += 1
                continue
            }

            let startLine = index
            let timeLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
            guard matches(goPayTimeLine, timeLine) else {
                index += 1
                continue
            }

            var recordLines = [line, timeLine]
            var cursor = index + 2
            var coinsOnly = false

            while cursor < lines.count {
                let next = lines[cursor].trimmingCharacters(in: .whitespaces)
                cursor += 1
                if next.isEmpty { continue }
                if matches(goPayDateLine, next) {
                    // A new record started before we found a terminal line —
                    // bail rather than merging two records together.
                    cursor -= 1
                    break
                }
                recordLines.append(next)
                if matches(goPayAmountLine, next) {
                    break
                }
                if matches(goPayCoinsOnlyLine, next) {
                    coinsOnly = true
                    break
                }
            }

            // Cashback/loyalty-point-only records ("Cashback X … GoPay
            // Coins 29") aren't money movement — skip them here rather than
            // emitting them as raw rows, so ConfidenceScorer doesn't count
            // deliberately-skipped rows as parse failures (they dragged real
            // statements down to 0.59 "confidence" on a perfect parse).
            //
            // An *unterminated* record is the opposite case: a real
            // transaction whose amount line couldn't be read. It's emitted so
            // it lands in `rawRowCount`, fails normalization, and shows up as
            // lost confidence. Dropping it here shrank ConfidenceScorer's
            // numerator and denominator alike, which is how the page-break
            // bug above hid 12 transactions behind a perfect 1.0 score.
            if !coinsOnly {
                rows.append(RawTransactionRow(rawLines: recordLines, sourceLineNumber: startLine))
            }
            index = cursor
        }

        return rows
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}

extension RuleEngine {
    func statementBalances(fromText text: String, fileURL: URL, rule: IssuerRule) -> (opening: Decimal?, closing: Decimal?) {
        guard rule.issuer == Issuer.bcaMyBCA.rawValue else { return (nil, nil) }
        return OCRRowExtractor.extractBCABalances(fileURL: fileURL)
    }
}
