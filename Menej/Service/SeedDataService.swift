//
//  SeedDataService.swift
//  Menej
//
//  Imports the real sample statements bundled with the app (the same PDFs
//  used throughout development to calibrate the parsers, under
//  `Menej/Financial Statement/`) through the normal parse → categorize →
//  persist pipeline, so the app has real data to look at instead of being
//  empty.
//
//  DEBUG-only, deliberately: these are real personal financial documents —
//  a real bank account number, a real name, real transactions. Bundling
//  them into a release build would ship that data inside the binary for
//  anyone to extract. Never remove the `#if DEBUG` guard without replacing
//  the source PDFs with synthetic/redacted ones first.
//

#if DEBUG
import Foundation
import SwiftData

struct SeedResult: CustomStringConvertible {
    var filesFound: [String] = []
    var filesMissing: [String] = []
    /// Covers both parse failures (bad PDF, no matching rule) and
    /// persistence failures (SwiftData save errors) — both mean this file
    /// didn't actually make it into the ledger.
    var failures: [(file: String, error: Error)] = []
    var transactionsImported: Int = 0

    var description: String {
        var lines = ["Found \(filesFound.count)/15 bundled files."]
        if !filesMissing.isEmpty {
            lines.append("Missing from bundle: \(filesMissing.joined(separator: ", "))")
        }
        if !failures.isEmpty {
            lines.append(contentsOf: failures.map { "Failed: \($0.file): \($0.error)" })
        }
        lines.append("Transactions imported: \(transactionsImported)")
        return lines.joined(separator: "\n")
    }
}

enum SeedDataService {
    private static let sampleStatementFilenames = [
        "MyBCA_Feb_26", "MyBCA_Mar_26", "MyBCA_Apr_26", "MyBCA_May_26", "MyBCA_Jun_26",
        "GoPay_Feb_26", "GoPay_Mar_26", "GoPay_Apr_26", "GoPay_Mei_26", "GoPay_Jun_26",
        "Grab_Feb_26", "Grab_Mar_26", "Grab_Apr_26", "Grab_May_26", "Grab_Jun_26",
    ]

    /// Seeds only if the ledger is empty, so this never overwrites or
    /// duplicates real imported data.
    @MainActor
    @discardableResult
    static func seedIfNeeded(modelContext: ModelContext) -> SeedResult? {
        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<Statement>())) ?? 0
        guard existingCount == 0 else { return nil }
        let result = seed(modelContext: modelContext)
        print("[SeedDataService] \(result)")
        return result
    }

    /// Wipes existing Accounts/Statements/Transactions before reseeding —
    /// for iterating on parsing/categorization changes without needing to
    /// delete and reinstall the app.
    @MainActor
    @discardableResult
    static func resetAndSeed(modelContext: ModelContext) -> SeedResult {
        try? modelContext.delete(model: Transaction.self)
        try? modelContext.delete(model: Statement.self)
        try? modelContext.delete(model: Account.self)
        try? modelContext.save()
        let result = seed(modelContext: modelContext)
        print("[SeedDataService] \(result)")
        return result
    }

    @MainActor
    static func seed(modelContext: ModelContext) -> SeedResult {
        var result = SeedResult()
        let parsingService = ParsingService()
        let importViewModel = ImportViewModel(parsingService: parsingService)
        let rules = RemoteConfigService().loadBundledRules()
        print("[SeedDataService] loaded \(rules.count) bundled parser rules")

        for filename in sampleStatementFilenames {
            guard let url = resolveSampleURL(filename: filename) else {
                result.filesMissing.append(filename)
                continue
            }
            result.filesFound.append(filename)

            do {
                let parsed = try parsingService.parse(fileURL: url, availableRules: rules)
                let imported = try importViewModel.confirmImport(url: url, statement: parsed, modelContext: modelContext)
                result.transactionsImported += imported
            } catch {
                result.failures.append((filename, error))
            }
        }
        return result
    }

    /// The synchronized group's exact bundling of nested folders (flattened
    /// to the bundle root vs. preserved as `Financial Statement/<Issuer>/`)
    /// isn't verified against a real build in this environment — try the
    /// nested path, a couple of likely variants, then a flat lookup.
    private static func resolveSampleURL(filename: String) -> URL? {
        let issuerFolder: String
        if filename.hasPrefix("MyBCA") { issuerFolder = "MyBCA" }
        else if filename.hasPrefix("GoPay") { issuerFolder = "GoPay" }
        else { issuerFolder = "Grab" }

        let candidates = [
            "Financial Statement/\(issuerFolder)",
            "Menej/Financial Statement/\(issuerFolder)",
            issuerFolder,
        ]
        for subdirectory in candidates {
            if let url = Bundle.main.url(forResource: filename, withExtension: "pdf", subdirectory: subdirectory) {
                return url
            }
        }
        return Bundle.main.url(forResource: filename, withExtension: "pdf")
    }
}
#endif
