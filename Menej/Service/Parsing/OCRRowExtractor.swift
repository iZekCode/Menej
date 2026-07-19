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
//  AWAL"/"SALDO AKHIR"/"MUTASI CR"/"MUTASI DB" footer on 3 of 5 months, and
//  within ~30,000 IDR (one transaction) on the other 2 — a dramatic
//  improvement over the old text-layer parser, which was off by millions of
//  IDR on 4 of 5 months.
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
    // other text block whose Y falls between that anchor and the next one
    // belongs to the same record — robust to Grab's two-line-per-record
    // wrapping (addresses/merchant names wrap to a second line).
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
            let bucket = sorted.filter { $0.y <= anchorY + 0.002 && $0.y > nextAnchorY }

            let dateText = sorted[anchorIndex].text
            let timeText = bucket.first { matches(grabTimeLine, $0.text) }?.text ?? ""
            let amountText = bucket.first { $0.x > 0.85 && matches(grabAmountLine, $0.text) }?.text ?? ""
            let description = bucket
                .filter { $0.text != dateText && $0.text != "IDR" && $0.text != timeText && !($0.x > 0.85 && matches(grabAmountLine, $0.text)) }
                .sorted { abs($0.y - $1.y) > 0.003 ? $0.y > $1.y : $0.x < $1.x }
                .map(\.text)
                .joined(separator: " ")

            guard !amountText.isEmpty else { continue }
            rows.append(RawTransactionRow(
                rawLines: [dateText, timeText, amountText, description],
                sourceLineNumber: sourceLineNumber
            ))
        }
        return rows
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
    private static let bcaDateAnchor = try! NSRegularExpression(pattern: #"^\d{2}/\d{2}$"#)
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
            guard let dateItem = row.items.first(where: { $0.x < 0.10 && matches(bcaDateAnchor, $0.text) }) else {
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
                if next.items.contains(where: { $0.x < 0.10 && matches(bcaDateAnchor, $0.text) }) { break }
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
                rawLines: [dateItem.text, descParts.joined(separator: " "), String(amountText[amountRange]), marker],
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
