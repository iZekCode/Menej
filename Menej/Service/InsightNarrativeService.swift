//
//  InsightNarrativeService.swift
//  Menej
//
//  On-device rephrasing of pre-computed highlight facts into Health-app-style
//  summary cards — see PRD §6 F8. Uses Apple's Foundation Models (Apple
//  Intelligence) exclusively, like AIEnhancementService, so the privacy claim
//  ("your financial data never leaves your iPhone") holds. No network call.
//
//  The model ONLY writes headlines. Every figure shown to the user comes from
//  the deterministic `HighlightFact.detail` string (see InsightHighlights.swift)
//  and is rendered as the card's second line unchanged — so a drifted or
//  invented number can never reach the UI. If the model is unavailable or its
//  output is unusable, `generateHighlights` returns template cards built from
//  the same facts; it never throws and always returns something to show.
//
//  IMPORTANT — not verified against a real build: same caveat as
//  AIEnhancementService. The FoundationModels API shape (SystemLanguageModel,
//  @Generable/@Guide, LanguageModelSession.respond(to:generating:)) follows
//  Apple's published design, to be confirmed against Xcode on first build.
//

import Foundation
import FoundationModels

/// A rendered highlight card. `detail` is always the deterministic fact text;
/// only `headline` may come from the model.
struct InsightHighlightCard: Identifiable {
    let id: String
    let headline: String
    let detail: String
    let systemImage: String
}

@Generable
private struct NarrativeHeadlines {
    @Guide(description: "One friendly headline per fact, in the exact same order as the numbered facts given. Each headline is at most 8 words, plain language, no emoji. Never state a number, percentage, merchant, or category that wasn't in the corresponding fact.")
    var headlines: [String]
}

protocol InsightNarrativeServiceProtocol {
    var isAvailable: Bool { get }
    /// Always returns a card per fact (model-written headlines when possible,
    /// template headlines otherwise). Never throws.
    func generateHighlights(from facts: [HighlightFact]) async -> [InsightHighlightCard]
}

struct InsightNarrativeService: InsightNarrativeServiceProtocol {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
    You write short, warm, plain-language headlines for a personal finance \
    app's insight cards. You are given a numbered list of facts, each already \
    containing exact figures. For each fact, in the same order, write one \
    friendly headline of at most 8 words that captures its gist.

    Hard rules:
    - Never invent, change, round, or drop a number, percentage, merchant \
    name, or category. The app displays the exact figures separately, so your \
    headline should be a natural hook, not a restatement of the numbers.
    - One headline per fact, same order, same count.
    - No emoji, no hashtags, no exclamation marks. Keep it calm and factual.
    """

    func generateHighlights(from facts: [HighlightFact]) async -> [InsightHighlightCard] {
        guard !facts.isEmpty else { return [] }
        guard isAvailable, let headlines = try? await modelHeadlines(for: facts), headlines.count == facts.count else {
            return facts.map(Self.templateCard)
        }

        return zip(facts, headlines).map { fact, headline in
            let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
            return InsightHighlightCard(
                id: fact.id,
                headline: trimmed.isEmpty ? fact.headlineFallback : trimmed,
                detail: fact.detail,
                systemImage: fact.systemImage
            )
        }
    }

    private func modelHeadlines(for facts: [HighlightFact]) async throws -> [String] {
        let session = LanguageModelSession(instructions: Self.instructions)
        let numbered = facts.enumerated()
            .map { "\($0.offset + 1). \($0.element.detail)" }
            .joined(separator: "\n")
        let response = try await session.respond(
            to: "Facts:\n\(numbered)",
            generating: NarrativeHeadlines.self
        )
        return response.content.headlines
    }

    private static func templateCard(_ fact: HighlightFact) -> InsightHighlightCard {
        InsightHighlightCard(
            id: fact.id,
            headline: fact.headlineFallback,
            detail: fact.detail,
            systemImage: fact.systemImage
        )
    }
}
