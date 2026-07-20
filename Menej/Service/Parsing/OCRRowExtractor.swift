//
//  OCRRowExtractor.swift
//  Menej
//
//  Two issuers need Vision OCR instead of plain text-layer extraction:
//
//  Grab's PDF export loses every digit character on plain text-layer
//  extraction (confirmed across 5 real statements — a font-subsetting issue
//  with no ToUnicode mapping for digit glyphs).
//
//  myBCA's PDF extracts digits fine, but PDFKit's `PDFPage.string` scrambles
//  row/column order on pages with many same-day transactions (confirmed:
//  found six amounts piled together, divorced from their transaction rows)
//  — a content-stream ordering quirk in the PDF itself, not a digit problem.
//  Vision's OCR bounding boxes reflect true rendered pixel position, so
//  reconstructing rows from those coordinates sidesteps the scrambling
//  entirely (unlike `PDFPage.characterBounds`, whose per-character
//  positions have an inconsistent baseline offset between table columns —
//  tried and confirmed unreliable).
//
//  Both are rendered to an image and OCR'd, which reads digits correctly
//  since it's visual recognition, not text-layer decoding.
//
//  Validated against all 5 real statements per issuer using the actual
//  ParsingService pipeline: Grab is exact (delta 0) on order count and
//  total; myBCA reconciles exactly against the statement's own "SALDO
//  AWAL"/"SALDO AKHIR" footer on all 5 months (the last two months' ~30k
//  gaps were records whose date the OCR misread — "27102" for "27/02" —
//  recovered by the tolerant date-anchor matching below).
//

import Foundation
import PDFKit
import Vision
import CoreGraphics

enum OCRRowExtractor {
    struct Item {
        let text: String
        let x: Double
        let y: Double
    }

    static func render(page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    static func recognizeText(in image: CGImage) -> [Item] {
        var results: [Item] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                results.append(Item(
                    text: candidate.string,
                    x: observation.boundingBox.origin.x,
                    y: observation.boundingBox.origin.y
                ))
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return results
    }

    static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    // MARK: - Grab

    // Each record: a date line ("30 Apr 2026,") anchors the record; every
    // other text block whose Y falls in that anchor's band belongs to the
    // same record — robust to Grab's two-line-per-record wrapping
    // (addresses/merchant names wrap to a second line).
    //
    // A record's first description line renders slightly ABOVE its own date
    // anchor (up to ~0.002 in normalized Y, measured across the corpus), so
    // both band edges get the same tolerance. The bands must be disjoint:
    // an overlap here duplicated the next record's first line into the
    // previous record's description (the "overlapping transactions" bug).
    private static let grabAnchorTolerance = 0.005
    private static let grabDateAnchor = try! NSRegularExpression(pattern: #"^\d{1,2} \w+ \d{4},?$"#)
    private static let grabTimeLine = try! NSRegularExpression(pattern: #"^\d{1,2}:\d{2}(AM|PM)$"#)
    private static let grabAmountLine = try! NSRegularExpression(pattern: #"^[\d]+\.\d{2}$"#)

    static func extractGrabRows(fileURL: URL) -> [RawTransactionRow] {
        guard let document = PDFDocument(url: fileURL) else { return [] }

        var rows: [RawTransactionRow] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let image = render(page: page, scale: 3.0) else { continue }
            let items = recognizeText(in: image)
            rows.append(contentsOf: extractGrabRecords(from: items, sourceLineNumber: pageIndex))
        }
        return rows
    }

    private static func extractGrabRecords(from items: [Item], sourceLineNumber: Int) -> [RawTransactionRow] {
        let sorted = items.sorted { $0.y > $1.y }
        let anchorIndices = sorted.indices.filter { sorted[$0].x < 0.1 && matches(grabDateAnchor, sorted[$0].text) }

        var rows: [RawTransactionRow] = []
        for (position, anchorIndex) in anchorIndices.enumerated() {
            let anchorY = sorted[anchorIndex].y
            let nextAnchorY = position + 1 < anchorIndices.count ? sorted[anchorIndices[position + 1]].y : -Double.infinity
            let bucket = sorted.filter { $0.y <= anchorY + grabAnchorTolerance && $0.y > nextAnchorY + grabAnchorTolerance }

            let dateText = sorted[anchorIndex].text
            let timeText = bucket.first { matches(grabTimeLine, $0.text) }?.text ?? ""
            let amountText = bucket.first { $0.x > 0.85 && matches(grabAmountLine, $0.text) }?.text ?? ""

            guard !amountText.isEmpty else { continue }
            rows.append(RawTransactionRow(
                rawLines: [dateText, timeText, amountText, grabDescription(from: bucket)],
                sourceLineNumber: sourceLineNumber
            ))
        }
        return rows
    }

    /// The statement's table columns sit at stable X positions: booking code
    /// ~0.156, pickup address ~0.31, destination address ~0.54, service type
    /// ~0.75 ("Car"+"Standard", "GrabFood", …), then "IDR" and the amount.
    /// Reassembling by column instead of quasi-reading-order fixes the old
    /// word salad ("Lobby Oak Apartment Car A-99… Green Office Park 9 …")
    /// and yields a description both the categorizer and the on-device LLM
    /// can actually read: "GrabFood: Moon Chicken - AlamSutera → Silkwood
    /// Residences (A-98QWXJ8WX4BDAV)".
    private static func grabDescription(from bucket: [Item]) -> String {
        // "IDR" is the currency column, not part of any text column — but in
        // some months' layout it renders left enough to land inside the
        // service-type column's X range, so it's dropped by name.
        func column(_ range: Range<Double>) -> String {
            bucket
                .filter { range.contains($0.x) && $0.text != "IDR" }
                .sorted { abs($0.y - $1.y) > 0.003 ? $0.y > $1.y : $0.x < $1.x }
                .map(\.text)
                .joined(separator: " ")
        }
        let booking = column(0.10..<0.25)
        let pickup = column(0.25..<0.45)
        let destination = column(0.45..<0.70)
        let serviceType = column(0.70..<0.83)

        var parts: [String] = []
        if !serviceType.isEmpty { parts.append("\(serviceType):") }
        if !pickup.isEmpty { parts.append(pickup) }
        if !destination.isEmpty { parts.append("→ \(destination)") }
        if !booking.isEmpty { parts.append("(\(booking))") }
        return parts.joined(separator: " ")
    }

    // MARK: - myBCA

    // Each row of the ledger table renders date/description/amount/balance
    // all at the same true Y position (unlike PDFKit's character-level
    // extraction, whose baselines drift between columns). A record anchors
    // on its date ("DD/MM" at the left column); the amount is usually on
    // that same row (column ~0.60–0.80), occasionally on a continuation
    // row below when the row wraps. Continuation rows (extra description
    // lines) are consumed until the next date row or a recognized
    // furniture/footer row.
    // The separator class accepts OCR misreads of the slash: real statements
    // produced "27102" for "27/02" and "27106" for "27/06" (slash read as a
    // digit 1), which made the whole record invisible as an anchor — it was
    // then swallowed into the previous record's continuation lines and its
    // amount silently dropped (the source of both months' ~30k
    // reconciliation gaps). Day/month are validated in bcaCanonicalDate so
    // the loosened separator can't promote arbitrary 4–5 char strings.
    private static let bcaDateAnchor = try! NSRegularExpression(pattern: #"^(\d{2})[/1Il|\\](\d{2})$"#)

    /// Returns the canonical "DD/MM" for a date-column token, tolerating
    /// OCR-misread separators, or nil when the token isn't a plausible date.
    static func bcaCanonicalDate(_ text: String) -> String? {
        guard let match = bcaDateAnchor.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dayRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let day = Int(text[dayRange]), let month = Int(text[monthRange]),
              (1...31).contains(day), (1...12).contains(month) else { return nil }
        return "\(text[dayRange])/\(text[monthRange])"
    }
    private static let bcaAmountToken = try! NSRegularExpression(pattern: #"^([\d,.]+)\s*(DB|CR)?$"#)
    private static let bcaLooseAmountToken = try! NSRegularExpression(pattern: #"^[\d,.]{4,}$"#)
    private static let bcaPeriodLine = try! NSRegularExpression(pattern: #"PERIODE"#)
    private static let bcaMonthYear = try! NSRegularExpression(pattern: #"\S+\s+(\d{4})"#)

    private static let bcaFurnitureKeywords = [
        "SALDO AWAL", "SALDOAWAL", "AWAL", "MUTASI CR", "MUTASI DB", "MUTASI", "SALDO AKHIR", "AKHIR",
        "TANGGAL", "KETERANGAN", "CBG", "Bersambung",
        "CATATAN", "REKENING TAHAPAN", "HALAMAN", "NO.REKENING", "PERIODE", "MATA UANG", "BCA", "INDONESIA",
        "Apabila", "Rekening ini", "telah menyetujui", "berhak setiap",
    ]

    private struct Row {
        let items: [Item]
        let y: Double
    }

    /// OCR occasionally misreads which separator is which in a large number
    /// (e.g. "13.316,424.52" instead of "13,316,424.52"), but the LAST
    /// separator before the final 2 digits is reliably the decimal point
    /// regardless — normalize positionally instead of assuming comma vs.
    /// period.
    static func normalizeAmount(_ raw: String) -> Decimal? {
        guard let lastSeparatorIndex = raw.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return Decimal(string: raw)
        }
        let integerPart = raw[raw.startIndex..<lastSeparatorIndex].filter(\.isNumber)
        let decimalPart = raw[raw.index(after: lastSeparatorIndex)...].filter(\.isNumber)
        guard decimalPart.count == 2 else {
            return Decimal(string: raw.filter { $0.isNumber || $0 == "." })
        }
        return Decimal(string: "\(integerPart).\(decimalPart)")
    }

    private static func clusterRows(_ items: [Item], tolerance: Double = 0.004) -> [Row] {
        let sorted = items.sorted { $0.y > $1.y }
        var rows: [Row] = []
        var current: [Item] = []
        var currentY: Double?
        for item in sorted {
            if let y = currentY, abs(item.y - y) > tolerance {
                rows.append(Row(items: current, y: y))
                current = [item]
                currentY = item.y
            } else {
                current.append(item)
                if currentY == nil { currentY = item.y }
            }
        }
        if !current.isEmpty, let y = currentY { rows.append(Row(items: current, y: y)) }
        return rows
    }

    private static func isBCAFurnitureRow(_ row: Row) -> Bool {
        let joined = row.items.map(\.text).joined(separator: " ")
        return bcaFurnitureKeywords.contains { joined.contains($0) }
    }

    static func extractBCARows(fileURL: URL) -> [RawTransactionRow] {
        guard let document = PDFDocument(url: fileURL) else { return [] }

        var periodYear: Int?
        var rows: [RawTransactionRow] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let image = render(page: page, scale: 3.0) else { continue }
            let items = recognizeText(in: image)
            let pageRows = clusterRows(items)

            if periodYear == nil {
                periodYear = pageRows.lazy.compactMap { row -> Int? in
                    let joined = row.items.map(\.text).joined(separator: " ")
                    guard matches(bcaPeriodLine, joined),
                          let match = bcaMonthYear.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
                          let range = Range(match.range(at: 1), in: joined) else { return nil }
                    return Int(joined[range])
                }.first
            }

            rows.append(contentsOf: extractBCARecords(rows: pageRows, sourceLineNumber: pageIndex, periodYear: periodYear))
        }
        return rows
    }

    private static func extractBCARecords(rows: [Row], sourceLineNumber: Int, periodYear: Int?) -> [RawTransactionRow] {
        var records: [RawTransactionRow] = []
        var i = 0
        while i < rows.count {
            let row = rows[i]
            guard let canonicalDate = row.items.lazy
                .filter({ $0.x < 0.10 })
                .compactMap({ bcaCanonicalDate($0.text) })
                .first else {
                i += 1
                continue
            }

            var descParts = row.items.filter { $0.x >= 0.10 && $0.x < 0.60 }.sorted { $0.x < $1.x }.map(\.text)
            var amountText = row.items.first { $0.x >= 0.60 && $0.x < 0.80 }?.text

            // "SALDO AWAL" on a date row is the opening balance, not a
            // transaction — statementBalances() reads the footer instead.
            if descParts.joined(separator: " ").hasPrefix("SALDO AWAL") {
                i += 1
                continue
            }

            var j = i + 1
            while j < rows.count {
                let next = rows[j]
                if isBCAFurnitureRow(next) { break }
                if next.items.contains(where: { $0.x < 0.10 && bcaCanonicalDate($0.text) != nil }) { break }
                descParts.append(contentsOf: next.items.filter { $0.x >= 0.10 && $0.x < 0.60 }.sorted { $0.x < $1.x }.map(\.text))
                if amountText == nil, let amount = next.items.first(where: { $0.x >= 0.60 && $0.x < 0.80 }) {
                    amountText = amount.text
                }
                j += 1
            }

            guard let amountText,
                  let amountMatch = bcaAmountToken.firstMatch(in: amountText, range: NSRange(amountText.startIndex..., in: amountText)),
                  let amountRange = Range(amountMatch.range(at: 1), in: amountText) else {
                i = j
                continue
            }
            let marker = Range(amountMatch.range(at: 2), in: amountText).map { String(amountText[$0]) } ?? ""

            records.append(RawTransactionRow(
                rawLines: [canonicalDate, descParts.joined(separator: " "), String(amountText[amountRange]), marker],
                sourceLineNumber: sourceLineNumber,
                periodYear: periodYear
            ))
            i = j
        }
        return records
    }

    /// `SALDO AWAL`/`SALDO AKHIR`/`MUTASI CR`/`MUTASI DB` footer, for
    /// reconciliation — the OCR text for these can merge words
    /// ("SALDOAWAL", "MUTASIDB") or split a colon into its own token, so
    /// this matches on substring containment and pulls the first
    /// amount-shaped/integer-shaped token from the row rather than
    /// assuming a fixed position.
    static func extractBCABalances(fileURL: URL) -> (opening: Decimal?, closing: Decimal?) {
        guard let document = PDFDocument(url: fileURL) else { return (nil, nil) }

        var opening: Decimal?
        var closing: Decimal?
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let image = render(page: page, scale: 3.0) else { continue }
            let rows = clusterRows(recognizeText(in: image))
            for row in rows {
                let sortedItems = row.items.sorted { $0.x < $1.x }
                let joined = sortedItems.map(\.text).joined(separator: " ")
                let firstDecimal = sortedItems.first { matches(bcaLooseAmountToken, $0.text) }.flatMap { normalizeAmount($0.text) }
                if joined.contains("AWAL") { opening = firstDecimal }
                else if joined.contains("AKHIR") { closing = firstDecimal }
            }
        }
        return (opening, closing)
    }
}
