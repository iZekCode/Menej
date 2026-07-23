//
//  FinanceQueryServiceTests.swift
//  MenejTests
//
//  The chat's whole safety argument is that the model never computes — so
//  these cover the two ways a computed answer could still be wrong: a merchant
//  that was never in the data being totalled anyway, and a window that
//  silently includes the wrong transactions.
//

import Foundation
import Testing
@testable import Menej

struct FinanceQueryServiceTests {
    // MARK: - Fixtures

    private static let calendar = Calendar(identifier: .gregorian)

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func entry(
        _ year: Int, _ month: Int, _ day: Int,
        _ amount: Decimal,
        _ category: Category = .food,
        merchant: String? = nil,
        direction: Direction = .debit
    ) -> AnalyticsEntry {
        AnalyticsEntry(
            date: date(year, month, day),
            amount: amount,
            direction: direction,
            category: category,
            merchant: merchant
        )
    }

    private static func window(_ from: (Int, Int, Int), _ to: (Int, Int, Int), label: String = "test window") -> DateWindow {
        DateWindow(range: date(from.0, from.1, from.2)..<date(to.0, to.1, to.2), label: label)
    }

    // MARK: - Merchant resolution

    @Test func unknownMerchantIsReportedNotTotalled() {
        let service = FinanceQueryService()
        let entries = [Self.entry(2026, 4, 10, 50_000, merchant: "Dapoer Cowek")]
        let query = FinanceQuery(intent: .merchantSpend, merchant: "Starbucks", window: .allTime)

        let answer = service.answer(query: query, entries: entries, context: FinanceContext(), asOf: Self.date(2026, 5, 1))

        // The failure this guards: answering "Rp 0" for a merchant that was
        // never in the data, which reads as a fact rather than a miss.
        guard case .merchantNotFound(let requested, _) = answer else {
            Issue.record("Expected .merchantNotFound, got \(answer)")
            return
        }
        #expect(requested == "Starbucks")
    }

    @Test func merchantMatchIsCaseInsensitiveAndSumsAllSpellings() {
        let service = FinanceQueryService()
        let entries = [
            Self.entry(2026, 4, 10, 50_000, merchant: "Indomaret"),
            Self.entry(2026, 4, 12, 25_000, merchant: "INDOMARET"),
            Self.entry(2026, 4, 14, 10_000, merchant: "Alfamart"),
        ]
        let query = FinanceQuery(intent: .merchantSpend, merchant: "indomaret", window: .allTime)

        let answer = service.answer(query: query, entries: entries, context: FinanceContext(), asOf: Self.date(2026, 5, 1))

        guard case .merchantSpend(_, let amount, let count, _) = answer else {
            Issue.record("Expected .merchantSpend, got \(answer)")
            return
        }
        #expect(amount == 75_000)
        #expect(count == 2)
    }

    @Test func severalMatchingMerchantsAreDisambiguatedNotGuessed() {
        let service = FinanceQueryService()
        let entries = [
            Self.entry(2026, 4, 10, 50_000, merchant: "Indomaret Alam Sutera"),
            Self.entry(2026, 4, 12, 25_000, merchant: "Indomaret BSD"),
        ]
        let query = FinanceQuery(intent: .merchantSpend, merchant: "Indomaret", window: .allTime)

        let answer = service.answer(query: query, entries: entries, context: FinanceContext(), asOf: Self.date(2026, 5, 1))

        guard case .merchantAmbiguous(_, let matches) = answer else {
            Issue.record("Expected .merchantAmbiguous, got \(answer)")
            return
        }
        #expect(matches.count == 2)
    }

    // MARK: - Windows

    @Test func customWindowExcludesEntriesOutsideIt() {
        let service = FinanceQueryService()
        let entries = [
            Self.entry(2026, 2, 28, 10_000),  // before
            Self.entry(2026, 3, 1, 20_000),   // first instant of the window
            Self.entry(2026, 5, 31, 40_000),  // inside
            Self.entry(2026, 6, 1, 80_000),   // upper bound is exclusive
        ]
        // March through May, i.e. up to (not including) 1 June.
        let query = FinanceQuery(intent: .spendTotal, window: Self.window((2026, 3, 1), (2026, 6, 1)))

        let answer = service.answer(query: query, entries: entries, context: FinanceContext(), asOf: Self.date(2026, 6, 15))

        guard case .spendTotal(let amount, _, _) = answer else {
            Issue.record("Expected .spendTotal, got \(answer)")
            return
        }
        #expect(amount == 60_000)
    }

    @Test func categoryFilterNarrowsTheTotal() {
        let service = FinanceQueryService()
        let entries = [
            Self.entry(2026, 4, 10, 50_000, .food),
            Self.entry(2026, 4, 11, 30_000, .transport),
        ]
        let query = FinanceQuery(intent: .spendTotal, category: .food, window: .allTime)

        let answer = service.answer(query: query, entries: entries, context: FinanceContext(), asOf: Self.date(2026, 5, 1))

        guard case .spendTotal(let amount, let category, _) = answer else {
            Issue.record("Expected .spendTotal, got \(answer)")
            return
        }
        #expect(amount == 50_000)
        #expect(category == .food)
    }

    // MARK: - Withholding

    @Test func unsupportedIntentIsNeverApproximated() {
        let service = FinanceQueryService()
        let query = FinanceQuery(intent: .unsupported, window: .allTime)

        let answer = service.answer(
            query: query,
            entries: [Self.entry(2026, 4, 10, 50_000)],
            context: FinanceContext(),
            asOf: Self.date(2026, 5, 1)
        )

        guard case .unsupported = answer else {
            Issue.record("Expected .unsupported, got \(answer)")
            return
        }
    }

    @Test func runwayWithholdsWithoutACompleteMonth() {
        let service = FinanceQueryService()
        // A single, barely-started month — InsightService refuses to prorate
        // this, and the chat has to report that rather than divide anyway.
        let entries = [Self.entry(2026, 5, 2, 100_000)]
        var context = FinanceContext()
        context.liquidTotal = 10_000_000
        let query = FinanceQuery(intent: .runway, window: .allTime)

        let answer = service.answer(query: query, entries: entries, context: context, asOf: Self.date(2026, 5, 3))

        guard case .noData = answer else {
            Issue.record("Expected .noData, got \(answer)")
            return
        }
    }

    @Test func namedAccountResolvesCaseInsensitively() {
        let service = FinanceQueryService()
        var context = FinanceContext()
        context.accounts = [FinanceContext.NamedAmount(name: "GoPay", amount: 250_000)]
        let query = FinanceQuery(intent: .accountBalance, subject: "gopay", window: .allTime)

        let answer = service.answer(query: query, entries: [], context: context, asOf: Self.date(2026, 5, 1))

        guard case .accountBalance(let name, let amount) = answer else {
            Issue.record("Expected .accountBalance, got \(answer)")
            return
        }
        #expect(name == "GoPay")
        #expect(amount == 250_000)
    }
}
