//
//  ParsingServiceTests.swift
//  MenejTests
//
//  Acceptance criteria per PRD §6 F1: ≥95% of transaction rows extracted
//  correctly across a test corpus of ≥20 statements per issuer.
//
//  NOTE: this file is not yet part of any Xcode target. Add a Unit Testing
//  Bundle target (File > New > Target > Unit Testing Bundle, name it
//  "MenejTests") and point it at this folder to start running these.
//  Fixtures: start from Menej/Financial Statement Examples/*.pdf and grow
//  the corpus per issuer per PRD §10's release-plan note (≥20 statements,
//  covering different date ranges, empty-month cases, unusually long
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
