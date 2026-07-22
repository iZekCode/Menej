//
//  DedupServiceTests.swift
//  MenejTests
//
//  Cases to cover per PRD §6 F4 (the highest-risk feature in v1):
//  GoPay top-up from BCA, paying Grab with GoPay, self-transfers,
//  pending vs. settled from different sources.
//

import Testing
@testable import Menej

struct DedupServiceTests {
    @Test func emptyTransactionListHasNoCandidates() {
        let service = DedupService()
        #expect(service.findCandidates(in: []).isEmpty)
    }
}
