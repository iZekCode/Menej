//
//  CorpusFixtures.swift
//  MenejTests
//
//  Locates the real 15-statement corpus and the shipped parser rules for the
//  reconciliation suites. Everything is addressed relative to this source
//  file rather than through `Bundle.module`, so no resource-copy build phase
//  is needed. The trade-off: `#filePath` bakes in a compile-time absolute
//  path, so these suites find the corpus on the machine that built them and
//  nowhere else — fine locally, not portable to CI.
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
        // `SampleStatements/` at the repo root, deliberately outside `Menej/`:
        // the app target is a synchronized folder group, so anything under
        // `Menej/` is copied into the built .app in every configuration. The
        // corpus is real statements, so keeping it out of the target is what
        // stops it shipping. It's gitignored too — restore it from a local
        // copy if these suites can't find it.
        let url = repositoryRoot
            .appendingPathComponent("SampleStatements/\(folder)")
            .appendingPathComponent("\(filename).pdf")
        return try ParsingService().parse(fileURL: url, availableRules: [rule(named: name)])
    }
}
