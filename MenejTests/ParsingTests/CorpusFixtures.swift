//
//  CorpusFixtures.swift
//  MenejTests
//
//  Locates the real 15-statement corpus and the shipped parser rules for the
//  reconciliation suites. Everything is addressed relative to this source
//  file rather than through `Bundle.module`, so the tests run as soon as the
//  files are added to a test target, with no resource-copy build phase to
//  configure first.
//
//  Rules are decoded from the same JSON the app bundles, so a change to
//  `Rules/*.json` is covered by these tests too.
//

import Foundation
@testable import Menej

enum CorpusFixtures {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ParsingTests
            .deletingLastPathComponent()  // MenejTests
            .deletingLastPathComponent()  // repo root
    }

    static func rule(named name: String) throws -> IssuerRule {
        let url = repositoryRoot.appendingPathComponent("Menej/Service/Parsing/Rules/\(name).json")
        return try JSONDecoder().decode(IssuerRule.self, from: Data(contentsOf: url))
    }

    /// Parses one statement through the real `ParsingService` pipeline —
    /// issuer detection included, so a fingerprint that stops matching fails
    /// here rather than silently falling back.
    static func statement(_ filename: String, folder: String, rule name: String) throws -> ParsedStatement {
        let url = repositoryRoot
            .appendingPathComponent("Menej/Financial Statement/\(folder)")
            .appendingPathComponent("\(filename).pdf")
        return try ParsingService().parse(fileURL: url, availableRules: [rule(named: name)])
    }
}
