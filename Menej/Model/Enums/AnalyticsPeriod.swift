//
//  AnalyticsPeriod.swift
//  Menej
//
//  Time windows for the spending analytics dashboard — see PRD §6 F8.
//  Health-app-style Week / Month / 6 Months / Year / All, each knowing its
//  own date range, the immediately preceding range (for period-over-period
//  comparison), and the granularity its spending-over-time chart buckets at.
//
//  Pure Foundation so it compiles under the CLT swiftc harness alongside
//  SpendingAnalyticsService.
//

import Foundation

enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case sixMonths
    case year
    case all

    var id: String { rawValue }

    /// Short label for the segmented picker (Health-style: W / M / 6M / Y / All).
    var shortLabel: String {
        switch self {
        case .week: return "W"
        case .month: return "M"
        case .sixMonths: return "6M"
        case .year: return "Y"
        case .all: return "All"
        }
    }

    var longLabel: String {
        switch self {
        case .week: return "This Week"
        case .month: return "This Month"
        case .sixMonths: return "6 Months"
        case .year: return "This Year"
        case .all: return "All Time"
        }
    }

    /// "vs last week/month/…" phrasing for the comparison line. `.all` has no
    /// preceding period, so nil.
    var comparisonLabel: String? {
        switch self {
        case .week: return "vs last week"
        case .month: return "vs last month"
        case .sixMonths: return "vs previous 6 months"
        case .year: return "vs last year"
        case .all: return nil
        }
    }

    /// The Calendar unit each bar in the spending-over-time chart aggregates:
    /// short periods bar by day, long ones by month, so bar counts stay
    /// readable (7 days, ~30 days, 6 months, 12 months).
    var bucketComponent: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .sixMonths, .year, .all: return .month
        }
    }

    /// Half-open date range [start, end) covering this period relative to
    /// `reference`. `.all` returns nil — the caller uses the full data span.
    func dateRange(reference: Date, calendar: Calendar = .current) -> Range<Date>? {
        guard self != .all else { return nil }
        let end = reference
        guard let start = startDate(reference: reference, calendar: calendar) else { return nil }
        return start..<end
    }

    /// The immediately preceding, equal-length range — [prevStart, start) —
    /// for period-over-period comparison. nil for `.all` (no prior period).
    func previousDateRange(reference: Date, calendar: Calendar = .current) -> Range<Date>? {
        guard let current = dateRange(reference: reference, calendar: calendar),
              let previousStart = startDate(reference: current.lowerBound, calendar: calendar) else { return nil }
        return previousStart..<current.lowerBound
    }

    /// Start of the window ending at `reference`. Month/6M/Year subtract whole
    /// calendar units so "this month" means the calendar month to date, not a
    /// rolling 30 days — matching how the ledger and snapshots think in months.
    private func startDate(reference: Date, calendar: Calendar) -> Date? {
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: reference)
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: reference)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: reference)
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: reference)
        case .all:
            return nil
        }
    }
}
