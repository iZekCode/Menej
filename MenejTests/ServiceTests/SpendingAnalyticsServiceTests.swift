//
//  SpendingAnalyticsServiceTests.swift
//  MenejTests
//
//  Covers the range-based methods added for the Ask tab, and — most
//  importantly — that the existing period-based methods still return exactly
//  what they did before they became wrappers over them. That last group is the
//  regression guard for the refactor: the dashboard and the chat must never
//  compute the same figure two different ways.
//

import Foundation
import Testing
@testable import Menej

struct SpendingAnalyticsServiceTests {
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

    private static let sample: [AnalyticsEntry] = [
        entry(2026, 4, 2, 50_000, .food, merchant: "Indomaret"),
        entry(2026, 4, 9, 25_000, .food, merchant: "INDOMARET"),
        entry(2026, 4, 15, 120_000, .transport, merchant: "Gojek"),
        entry(2026, 5, 3, 80_000, .food, merchant: "Dapoer Cowek"),
        entry(2026, 5, 20, 3_000_000, .income, merchant: "Salary", direction: .credit),
    ]

    // MARK: - Merchants

    @Test func merchantBreakdownFoldsCasingIntoOneRow() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let breakdown = service.merchantBreakdown(entries: Self.sample, in: nil, limit: 10)

        let indomaret = breakdown.first { $0.merchant.caseInsensitiveCompare("Indomaret") == .orderedSame }
        #expect(indomaret?.total == 75_000)
        #expect(indomaret?.count == 2)
        // Two spellings, one counterparty.
        #expect(breakdown.filter { $0.merchant.caseInsensitiveCompare("Indomaret") == .orderedSame }.count == 1)
    }

    @Test func merchantBreakdownExcludesIncome() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let breakdown = service.merchantBreakdown(entries: Self.sample, in: nil, limit: 10)
        // "Salary" is a credit — it's not spend and must never appear here.
        #expect(!breakdown.contains { $0.merchant == "Salary" })
    }

    @Test func merchantBreakdownKeepsUnnamedSpendAsUnknown() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let entries = [Self.entry(2026, 4, 2, 10_000, .food, merchant: nil)]
        let breakdown = service.merchantBreakdown(entries: entries, in: nil, limit: 10)

        // Dropping it would make the merchant totals quietly disagree with the
        // category totals for the same window.
        #expect(breakdown.count == 1)
        #expect(breakdown.first?.merchant == SpendingAnalyticsService.unknownMerchant)
    }

    @Test func merchantMatchesReturnsEmptyForUnknownName() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        #expect(service.merchantMatches(entries: Self.sample, query: "Starbucks").isEmpty)
        #expect(service.merchantMatches(entries: Self.sample, query: "   ").isEmpty)
    }

    @Test func merchantMatchesPrefersAnExactName() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let entries = [
            Self.entry(2026, 4, 2, 10_000, merchant: "Indomaret Alam Sutera"),
            Self.entry(2026, 4, 3, 10_000, merchant: "Indomaret"),
        ]
        #expect(service.merchantMatches(entries: entries, query: "Indomaret").first == "Indomaret")
    }

    // MARK: - Ranges

    @Test func rangeUpperBoundIsExclusive() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let range = Self.date(2026, 4, 1)..<Self.date(2026, 5, 1)
        // April only: 50k + 25k + 120k. May's 80k sits exactly on the bound.
        #expect(service.expenseTotal(entries: Self.sample, in: range) == 195_000)
    }

    @Test func nilRangeMeansAllTime() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        #expect(service.expenseTotal(entries: Self.sample, in: nil) == 275_000)
    }

    @Test func cashflowSeparatesIncomeFromSpend() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let cashflow = service.cashflow(entries: Self.sample, in: nil)
        #expect(cashflow.income == 3_000_000)
        #expect(cashflow.expense == 275_000)
        #expect(cashflow.net == 2_725_000)
    }

    // MARK: - Wrapper equivalence (refactor guard)

    @Test func periodMethodsMatchTheirRangeEquivalents() {
        let service = SpendingAnalyticsService(calendar: Self.calendar)
        let asOf = Self.date(2026, 5, 15)

        for period in [AnalyticsPeriod.week, .month, .sixMonths, .year, .all] {
            let range = period.dateRange(reference: asOf, calendar: Self.calendar)

            #expect(
                service.expenseTotal(entries: Self.sample, period: period, asOf: asOf)
                    == service.expenseTotal(entries: Self.sample, in: range),
                "expenseTotal diverged for \(period.rawValue)"
            )
            #expect(
                service.cashflow(entries: Self.sample, period: period, asOf: asOf).net
                    == service.cashflow(entries: Self.sample, in: range).net,
                "cashflow diverged for \(period.rawValue)"
            )
            #expect(
                service.categoryBreakdown(entries: Self.sample, period: period, asOf: asOf).map(\.total)
                    == service.categoryBreakdown(entries: Self.sample, in: range).map(\.total),
                "categoryBreakdown diverged for \(period.rawValue)"
            )
            #expect(
                service.largestExpenses(entries: Self.sample, period: period, asOf: asOf, limit: 3).map(\.amount)
                    == service.largestExpenses(entries: Self.sample, in: range, limit: 3).map(\.amount),
                "largestExpenses diverged for \(period.rawValue)"
            )
        }
    }
}
