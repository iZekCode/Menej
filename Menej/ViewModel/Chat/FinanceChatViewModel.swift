//
//  FinanceChatViewModel.swift
//  Menej
//
//  Drives FinanceChatView. Owns the conversation, runs the route → compute →
//  phrase sequence (see FinanceChatService.swift), and does the SwiftData →
//  value-type projection the two pure services need.
//
//  History is in-memory only. Persisting it would mean storing a second,
//  derived copy of the user's financial data on disk for no benefit the ledger
//  doesn't already provide.
//

import Foundation
import Observation
import SwiftData

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    /// The computed result behind an assistant message. FinanceChatView
    /// renders its figures directly from this, so the authoritative numbers
    /// are on screen even if `text` phrases them poorly.
    var answer: FinanceAnswer?
}

@Observable
@MainActor
final class FinanceChatViewModel {
    private let chatService: FinanceChatServiceProtocol
    private let queryService: FinanceQueryServiceProtocol
    private let netWorthService: NetWorthServiceProtocol
    private let balanceService: LiquidBalanceServiceProtocol

    var messages: [ChatMessage] = []
    var isResponding = false
    var errorMessage: String?

    // See ImportViewModel.swift for why defaults are built in the body.
    init(
        chatService: FinanceChatServiceProtocol? = nil,
        queryService: FinanceQueryServiceProtocol? = nil,
        netWorthService: NetWorthServiceProtocol? = nil,
        balanceService: LiquidBalanceServiceProtocol? = nil
    ) {
        self.chatService = chatService ?? FinanceChatService()
        self.queryService = queryService ?? FinanceQueryService()
        self.netWorthService = netWorthService ?? NetWorthService()
        self.balanceService = balanceService ?? LiquidBalanceService()
    }

    var isAvailable: Bool { chatService.isAvailable }
    var unavailabilityReason: String? { chatService.unavailabilityReason }

    /// Questions that are known to map onto a real intent. They double as
    /// documentation of what the tab can do — the honest alternative to
    /// letting the user discover the limits by hitting them.
    static let starterQuestions = [
        "How much did I spend last month?",
        "What did I spend on this month?",
        "What were my biggest purchases?",
        "Am I spending more than last month?",
        "How long will my money last?",
        "Anything unusual lately?",
    ]

    func send(_ question: String, modelContext: ModelContext) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        isResponding = true
        errorMessage = nil
        defer { isResponding = false }

        let asOf = Date()
        do {
            // 1. Route. The model classifies; it never sees an amount.
            let query = try await chatService.route(question: trimmed, asOf: asOf)

            // 2. Compute. Every figure comes from here, not the model.
            let entries = InsightsViewModel.analyticsEntries(from: fetch(Transaction.self, from: modelContext))
            let context = financeContext(modelContext: modelContext)
            let answer = queryService.answer(query: query, entries: entries, context: context, asOf: asOf)

            // 3. Phrase. Fed pre-formatted strings and told to reuse them
            // verbatim. A phrasing failure is not an answer failure — the
            // card still renders, so fall back to the plain summary.
            let facts = FinanceAnswerSummary.facts(for: answer)
            let text = (try? await chatService.phrase(question: trimmed, facts: facts))
                ?? FinanceAnswerSummary.fallbackText(for: answer)

            messages.append(ChatMessage(role: .assistant, text: text, answer: answer))
        } catch FinanceChatError.unavailable(let reason) {
            errorMessage = reason
        } catch {
            errorMessage = "I couldn't work that one out. Try rephrasing it."
        }
    }

    // MARK: - Projection

    /// Everything outside the transaction ledger, flattened to values.
    /// Mirrors NetWorthHomeView's arithmetic exactly — the same
    /// `LiquidBalanceService` roll-forward and the same `offlineValueIDR`
    /// holding valuation — so the chat and the home screen can't disagree
    /// about what the user is worth.
    private func financeContext(modelContext: ModelContext) -> FinanceContext {
        let accounts = fetch(Account.self, from: modelContext)
        let transactions = fetch(Transaction.self, from: modelContext)
        let assets = fetch(Asset.self, from: modelContext)
        let holdings = fetch(Holding.self, from: modelContext)
        let liabilities = fetch(Liability.self, from: modelContext)

        let balances = balanceService.balances(accounts: accounts, transactions: transactions)
        let holdingValues = Dictionary(uniqueKeysWithValues: holdings.map { ($0.id, $0.offlineValueIDR) })

        let liquidTotal = balances.values.reduce(Decimal(0), +)
        let portfolioTotal = holdings.reduce(Decimal(0)) { $0 + $1.offlineValueIDR }
        let inventoryTotal = assets.filter(\.type.isPhysical).reduce(Decimal(0)) { $0 + $1.currentValue }
        let totalAssets = netWorthService.totalAssets(
            accounts: accounts,
            accountBalances: balances,
            assets: assets,
            holdings: holdings,
            holdingValues: holdingValues
        )
        let totalLiabilities = netWorthService.totalLiabilities(liabilities)

        return FinanceContext(
            accounts: accounts.map {
                FinanceContext.NamedAmount(name: $0.displayName, amount: balances[$0.id] ?? $0.balance)
            },
            assets: assets.filter(\.type.isPhysical).map {
                FinanceContext.NamedAmount(name: $0.name, amount: $0.currentValue)
            },
            liquidTotal: liquidTotal,
            portfolioTotal: portfolioTotal,
            inventoryTotal: inventoryTotal,
            liabilitiesTotal: totalLiabilities,
            netWorth: netWorthService.netWorth(totalAssets: totalAssets, totalLiabilities: totalLiabilities)
        )
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, from modelContext: ModelContext) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
    }
}
