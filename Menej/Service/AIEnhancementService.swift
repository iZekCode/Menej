//
//  AIEnhancementService.swift
//  Menej
//
//  On-device LLM cleanup for messy parsed descriptions and categorization,
//  per explicit user request to prioritize accuracy over the PRD's original
//  v1 scope (which deferred any LLM to v2 as "a fallback layer"). Uses
//  Apple's on-device Foundation Models (Apple Intelligence) exclusively —
//  deliberately not a cloud LLM — so the app's core privacy claim ("your
//  financial data never leaves your iPhone") stays true. No network call is
//  made by this service.
//
//  IMPORTANT — not verified against a real build: this environment has no
//  Xcode and no Apple Intelligence–eligible device, so the exact
//  FoundationModels API shape below (SystemLanguageModel, @Generable,
//  @Guide, LanguageModelSession.respond(to:generating:)) is based on
//  Apple's published framework design, not a compiled/run check. Expect to
//  verify member names against Xcode's autocomplete/docs on first build.
//
//  Availability is hardware- and settings-gated (recent-generation Apple
//  Silicon iPhone, Apple Intelligence turned on, supported region/language)
//  — this service degrades to reporting `.unavailable` rather than
//  crashing when it isn't, and callers must keep the existing rule-based
//  CategorizationService as the primary, always-available path.
//

import Foundation
import FoundationModels

@Generable
struct TransactionEnhancement {
    @Guide(description: "A short, clean, human-readable merchant or counterparty name with reference codes, transaction IDs, and bank jargon stripped out — e.g. 'DAPOER COWEK 0420260430044124vkmo' becomes 'Dapoer Cowek'. If no real name can be determined, use \"Unknown\".")
    var merchant: String

    @Guide(description: "The single best-fit category raw value from the allowed list given in the instructions.")
    var categoryRawValue: String
}

enum AIEnhancementError: Error {
    case unavailable(String)
}

protocol AIEnhancementServiceProtocol {
    var isAvailable: Bool { get }
    var unavailabilityReason: String? { get }
    func enhance(rawDescription: String, amount: Decimal, direction: Direction) async throws -> (merchant: String, category: Category)
}

struct AIEnhancementService: AIEnhancementServiceProtocol {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence isn't turned on. Enable it in Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                return "The on-device model is still downloading or preparing — try again shortly."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    private static let categoryList = Category.allCases.map(\.rawValue).joined(separator: ", ")

    func enhance(rawDescription: String, amount: Decimal, direction: Direction) async throws -> (merchant: String, category: Category) {
        guard isAvailable else {
            throw AIEnhancementError.unavailable(unavailabilityReason ?? "Apple Intelligence is unavailable.")
        }

        let session = LanguageModelSession(instructions: """
        You clean up messy bank and e-wallet statement transaction descriptions for a personal finance app. \
        Extract a short, human-readable merchant or counterparty name, and pick the single best category \
        from exactly this list: \(Self.categoryList). \
        Use "transfer" only for a movement between the user's own accounts, or bank fees/interest. \
        Use "income" for money received. Use "other" only if nothing else genuinely fits.
        """)

        let prompt = """
        Raw description: \(rawDescription)
        Amount: \(amount)
        Direction: \(direction == .debit ? "money out" : "money in")
        """

        let response = try await session.respond(to: prompt, generating: TransactionEnhancement.self)
        let category = Category(rawValue: response.content.categoryRawValue) ?? .other
        return (response.content.merchant, category)
    }
}
