//
//  TransactionNormalizer.swift
//  Menej
//
//  Normalizes raw row blocks into ParsedTransaction — see PRD §6 F1 pipeline.
//  Dispatches per issuer, matching RuleEngine's per-issuer extraction.
//

import Foundation

protocol TransactionNormalizing {
    func normalize(rows: [RawTransactionRow], rule: IssuerRule) -> [ParsedTransaction]
}

struct TransactionNormalizer: TransactionNormalizing {
    func normalize(rows: [RawTransactionRow], rule: IssuerRule) -> [ParsedTransaction] {
        switch rule.issuer {
        case Issuer.gopay.rawValue:
            return rows.compactMap { Self.normalizeGoPayRow($0, rule: rule) }
        case Issuer.bcaMyBCA.rawValue:
            return rows.compactMap { Self.normalizeBCARow($0, rule: rule) }
        case Issuer.grab.rawValue:
            return rows.compactMap { Self.normalizeGrabRow($0, rule: rule) }
        default:
            return []
        }
    }

    // MARK: - GoPay

    private static let goPayDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        return formatter
    }()

    private static func normalizeGoPayRow(_ row: RawTransactionRow, rule: IssuerRule) -> ParsedTransaction? {
        guard row.rawLines.count >= 3 else { return nil }

        let dateString = row.rawLines[0]
        let timeString = row.rawLines[1]
        let terminal = row.rawLines.last!

        // Cashback/loyalty-point-only rows aren't real money movement.
        guard !matches(RuleEngine.goPayCoinsOnlyLine, terminal) else { return nil }

        guard let (isDebit, amountString) = parseGoPayAmountLine(terminal) else { return nil }
        guard let amount = parseAmount(amountString, format: rule.amountFormat) else { return nil }
        guard let date = goPayDateTimeFormatter.date(from: "\(dateString) \(timeString)") else { return nil }

        let descriptionLines = row.rawLines[2..<(row.rawLines.count - 1)]
            .filter { $0 != "GoPay Saldo" && $0 != "GoPay Coins" }
        let rawDescription = descriptionLines.joined(separator: " ")
        let title = goPayTitle(from: rawDescription)

        return ParsedTransaction(
            date: date,
            amount: amount,
            direction: isDebit ? .debit : .credit,
            rawDescription: rawDescription,
            merchant: title.isEmpty ? nil : title,
            confidence: 1.0
        )
    }

    /// The statement's "ID transaksi" column gets appended right after the
    /// merchant name in the text layer ("MAMA DJEMPOL GOP
    /// 0420260529033702stbA8 87SiAID") and must not be part of the
    /// transaction's display title. The ID always starts with a long digit
    /// run (date+time encoded, ≥12 digits — sometimes with a letter prefix
    /// like "A220260204…"), which never appears in a real merchant name, so
    /// the title is everything before the first such token. Kept out of
    /// `rawDescription` deliberately: the ID is what makes dedup exact.
    private static let goPayTransactionIdToken = try! NSRegularExpression(pattern: #"\S*\d{12,}\S*"#)

    private static func goPayTitle(from description: String) -> String {
        let range = NSRange(description.startIndex..., in: description)
        guard let match = goPayTransactionIdToken.firstMatch(in: description, range: range),
              let matchRange = Range(match.range, in: description) else {
            return description.trimmingCharacters(in: .whitespaces)
        }
        return String(description[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// Returns `(isDebit, amountString)` for a terminal line like
    /// `"GoPay Saldo -Rp5.000"` or `"-Rp47.000"` or `"Rp2.000.000"`.
    private static func parseGoPayAmountLine(_ line: String) -> (Bool, String)? {
        let regex = RuleEngine.goPayAmountLine
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let amountRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let isDebit = Range(match.range(at: 1), in: line) != nil
        return (isDebit, String(line[amountRange]))
    }

    // MARK: - myBCA

    // Rows come from OCRRowExtractor as a fixed 4-tuple: [dateText
    // ("DD/MM"), description, amount string, marker ("DB"/"CR"/"")].
    private static func normalizeBCARow(_ row: RawTransactionRow, rule: IssuerRule) -> ParsedTransaction? {
        guard row.rawLines.count == 4, let periodYear = row.periodYear else { return nil }
        let dayMonth = row.rawLines[0]
        let description = row.rawLines[1]
        let amountText = row.rawLines[2]
        let markerText = row.rawLines[3]

        // OCR occasionally misreads which separator is comma vs. period in
        // a large number — normalize positionally rather than assuming
        // rule.amountFormat's fixed roles (see OCRRowExtractor.normalizeAmount).
        guard let amount = OCRRowExtractor.normalizeAmount(amountText) else { return nil }
        let marker: String? = markerText.isEmpty ? nil : markerText
        let (direction, confidence) = inferBCADirection(description: description, marker: marker)

        let dayMonthParts = dayMonth.split(separator: "/")
        guard dayMonthParts.count == 2, let day = Int(dayMonthParts[0]), let month = Int(dayMonthParts[1]) else { return nil }
        var dateComponents = DateComponents()
        dateComponents.day = day
        dateComponents.month = month
        dateComponents.year = periodYear
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .current
        guard let date = calendar.date(from: dateComponents) else { return nil }

        return ParsedTransaction(
            date: date,
            amount: amount,
            direction: direction,
            rawDescription: description,
            merchant: nil,
            confidence: confidence
        )
    }

    /// Direction marker ("DB"/"CR") is usually on the amount line itself,
    /// but for some rows (e.g. "TRSF E-BANKING CR ...") it only appears
    /// embedded in the description. Confidence is lowered when neither is
    /// found and a default has to be assumed — surfaced via the review
    /// screen rather than silently guessed.
    private static func inferBCADirection(description: String, marker: String?) -> (Direction, Double) {
        if let marker {
            return (marker == "DB" ? .debit : .credit, 1.0)
        }
        let upper = description.uppercased()
        if upper.contains(" DB") || upper.contains("DEBIT") {
            return (.debit, 0.9)
        }
        if upper.contains(" CR") || upper.contains("KREDIT") {
            return (.credit, 0.9)
        }
        if upper.contains("BUNGA") {
            // Bank-paid interest; always a credit even with no marker.
            return (.credit, 0.8)
        }
        return (.credit, 0.4)
    }

    // MARK: - Grab

    // Rows come from OCRRowExtractor as a fixed 5-tuple:
    // [dateText ("30 Apr 2026,"), timeText ("12:13PM"), amountText
    // ("37000.00"), joined description, title]. The title is the
    // service-type-aware display name (restaurant for GrabFood, destination
    // for rides) and becomes the transaction's merchant. Validated against
    // all 5 real statements: exact match on both order count and total
    // amount vs. the statement's own printed summary.
    private static let grabDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy h:mma"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        return formatter
    }()

    private static func normalizeGrabRow(_ row: RawTransactionRow, rule: IssuerRule) -> ParsedTransaction? {
        guard row.rawLines.count >= 4 else { return nil }
        let dateText = row.rawLines[0].trimmingCharacters(in: CharacterSet(charactersIn: ","))
        let timeText = row.rawLines[1]
        let amountText = row.rawLines[2]
        let description = row.rawLines[3]
        let title = row.rawLines.count >= 5 ? row.rawLines[4] : ""

        // A record's time can be missing when it's the very last row on a
        // page and OCR clips it at the page edge (confirmed against the
        // real corpus). The date (which day) is what matters for the
        // ledger — don't silently drop a real transaction with a valid
        // amount just because the time-of-day is unavailable.
        guard !amountText.isEmpty else { return nil }
        let effectiveTime = timeText.isEmpty ? "12:00PM" : timeText
        let confidence: Double = timeText.isEmpty ? 0.7 : 1.0

        guard let date = grabDateTimeFormatter.date(from: "\(dateText) \(effectiveTime)") else { return nil }
        guard let amount = parseAmount(amountText, format: rule.amountFormat) else { return nil }

        return ParsedTransaction(
            date: date,
            amount: amount,
            // Grab's order history is always spend from the user's
            // perspective — no credits/refunds observed in the real corpus.
            direction: .debit,
            rawDescription: description,
            merchant: title.isEmpty ? nil : title,
            confidence: confidence
        )
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    /// Applies `rule.amountFormat` to turn a locale-formatted amount string
    /// into a `Decimal` (e.g. "2.701.056" with thousandSeparator "." → 2701056,
    /// or "26,240,945.79" with thousandSeparator "," → 26240945.79).
    private static func parseAmount(_ raw: String, format: IssuerRule.AmountFormat) -> Decimal? {
        var cleaned = raw
        if !format.thousandSeparator.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: format.thousandSeparator, with: "")
        }
        if !format.decimalSeparator.isEmpty && format.decimalSeparator != "." {
            cleaned = cleaned.replacingOccurrences(of: format.decimalSeparator, with: ".")
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}
