//
//  ParsingServiceTests.swift
//  MenejTests
//
//  Acceptance criteria per PRD §6 F1: ≥95% of transaction rows extracted
//  correctly across a test corpus of ≥20 statements per issuer.
//
//  The corpus lives in Menej/Financial Statement/ — 15 real statements,
//  5 months per issuer. Grow it per README §10 (target ≥20 per issuer,
//  covering different date ranges, empty months, unusually long
//  statements).
//

import Testing
@testable import Menej

struct ParsingServiceTests {
    @Test func parsingWithNoRulesThrows() {
        let service = ParsingService()
        #expect(throws: ParsingError.self) {
            try service.parse(fileURL: URL(fileURLWithPath: "/dev/null"), availableRules: [])
        }
    }
}
