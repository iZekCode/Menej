//
//  FinanceAnswerSummary.swift
//  Menej
//
//  Turns a computed `FinanceAnswer` into (a) the fact lines handed to the
//  model's phrasing pass and (b) a plain-language fallback used when that pass
//  fails or is unavailable.
//
//  Every amount here goes through `AmountText.string`, so the strings the
//  model is asked to reuse verbatim are formatted identically to the ones the
//  card renders. That's what makes "copy the numbers exactly" a checkable
//  instruction rather than a hope.
//

import Foundation
import SwiftUI

enum FinanceAnswerSummary {
    /// Fed to FinanceChatService.phrase as the *only* material it may use.
    static func facts(for answer: FinanceAnswer) -> [String] {
        switch answer {
        case .spendTotal(let amount, let category, let window):
            let what = category.map { "on \($0.displayName)" } ?? "in total"
            return ["Spent \(what) \(window.label): \(money(amount))"]

        case .categoryBreakdown(let breakdown, let total, let window):
            return ["Total spent \(window.label): \(money(total))"]
                + breakdown.prefix(6).map { slice in
                    "\(slice.category.displayName): \(money(slice.total)) (\(percent(slice.share)))"
                }

        case .merchantSpend(let merchant, let amount, let count, let window):
            return [
                "Spent at \(merchant) \(window.label): \(money(amount))",
                "Number of transactions: \(count)",
            ]

        case .merchantNotFound(let query, let suggestions):
            var facts = ["There is no merchant matching \"\(query)\" in the recorded transactions."]
            if !suggestions.isEmpty {
                facts.append("Similar names on record: \(suggestions.joined(separator: ", "))")
            }
            return facts

        case .merchantAmbiguous(let query, let matches):
            return [
                "\"\(query)\" matches several merchants: \(matches.joined(separator: ", "))",
                "Ask the user which one they mean.",
            ]

        case .largestExpenses(let entries, let window):
            return ["Largest purchases \(window.label):"]
                + entries.map { entry in
                    "\(entry.merchant ?? "Unknown"): \(money(entry.amount)) on \(day(entry.date))"
                }

        case .comparison(let comparison, let window):
            var facts = [
                "Spent this month: \(money(comparison.currentTotal))",
                "Spent last month: \(money(comparison.previousTotal))",
                "Window: \(window.label)",
            ]
            if let delta = comparison.deltaFraction {
                facts.append("Change: \(delta >= 0 ? "up" : "down") \(percent(abs(delta)))")
            }
            facts += comparison.categoryDeltas.prefix(3).map { delta in
                "\(delta.category.displayName): \(money(delta.current)) this month vs \(money(delta.previous)) last month"
            }
            return facts

        case .cashflow(let cashflow, let window):
            var facts = [
                "Money in \(window.label): \(money(cashflow.income))",
                "Money out \(window.label): \(money(cashflow.expense))",
                "Net: \(money(cashflow.net))",
            ]
            if let savingsRate = cashflow.savingsRate {
                facts.append("Savings rate: \(percent(savingsRate))")
            }
            return facts

        case .netWorth(let total, let liquid, let portfolio, let inventory, let liabilities):
            var facts = [
                "Net worth: \(money(total))",
                "Liquid: \(money(liquid))",
                "Portfolio: \(money(portfolio))",
                "Inventory: \(money(inventory))",
            ]
            if liabilities > 0 {
                facts.append("Liabilities: \(money(liabilities))")
            }
            return facts

        case .accountBalance(let name, let amount):
            return ["Balance of \(name): \(money(amount))"]

        case .assetValue(let name, let amount):
            return ["Current estimated value of \(name): \(money(amount))"]

        case .runway(let months, let averageMonthlySpend):
            return [
                "Runway: \(monthsText(months))",
                "Average monthly spend: \(money(averageMonthlySpend))",
                "This counts liquid assets only, not investments or possessions.",
            ]

        case .anomalies(let anomalies):
            return anomalies.map { anomaly in
                "\(anomaly.category.displayName) in \(month(anomaly.month)): \(money(anomaly.currentAmount)) versus a \(money(anomaly.averageAmount)) average"
            }

        case .noData(let reason):
            return [reason]

        case .unsupported:
            return ["This question is outside what the app can answer from the user's recorded data."]
        }
    }

    /// Used when the phrasing pass fails. Deliberately flat and factual rather
    /// than an apology — the card below it carries the same figures.
    static func fallbackText(for answer: FinanceAnswer) -> String {
        switch answer {
        case .unsupported:
            return "I can only answer questions about the money you've recorded here — spending, balances, net worth, and what your things are worth. I can't give advice or predictions."
        case .noData(let reason):
            return reason
        case .merchantNotFound(let query, _):
            return "I don't see any transactions at \"\(query)\"."
        case .merchantAmbiguous(_, let matches):
            return "That matches a few: \(matches.joined(separator: ", ")). Which one did you mean?"
        default:
            return facts(for: answer).joined(separator: "\n")
        }
    }

    /// "14 months", "over 3 years". Past a couple of years an exact month
    /// count is false precision — it comes from an average of a handful of
    /// months. Matches NetWorthHomeView's runway phrasing.
    static func monthsText(_ months: Double) -> String {
        switch months {
        case ..<1:
            return "under a month"
        case ..<24:
            let rounded = Int(months.rounded())
            return rounded == 1 ? "1 month" : "\(rounded) months"
        default:
            return "over \(Int(months / 12)) years"
        }
    }

    private static func money(_ amount: Decimal) -> String {
        AmountText.string(amount: amount)
    }

    private static func percent(_ fraction: Double) -> String {
        "\((fraction * 100).formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
