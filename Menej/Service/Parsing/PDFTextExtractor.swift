//
//  PDFTextExtractor.swift
//  Menej
//
//  Text layer extraction via PDFKit — see PRD §6 F1 pipeline.
//

import Foundation
import PDFKit

enum PDFTextExtractionError: Error {
    case unreadableFile
    case noTextLayer
}

protocol PDFTextExtracting {
    func extractText(from fileURL: URL) throws -> String
}

struct PDFTextExtractor: PDFTextExtracting {
    func extractText(from fileURL: URL) throws -> String {
        guard let document = PDFDocument(url: fileURL) else {
            throw PDFTextExtractionError.unreadableFile
        }

        var text = ""
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if let pageText = page.string {
                text += pageText + "\n"
            }
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // v1: reject PDFs without a text layer (scans) with a clear message.
            // v1.1: Vision OCR — see PRD Risks table.
            throw PDFTextExtractionError.noTextLayer
        }

        return text
    }
}
