//
//  ReminderServiceTests.swift
//  MenejTests
//
//  All the date arithmetic, with no UserNotifications involved — `reminders`
//  and `importNudge` are pure, which is exactly why they were split out from
//  `sync`. The failures worth guarding are the embarrassing ones: reminding
//  about a date that's already gone, and nagging someone to import a month
//  they already imported.
//

import Foundation
import Testing
@testable import Menej

struct ReminderServiceTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func service() -> ReminderService {
        ReminderService(calendar: calendar)
    }

    // MARK: - Warranty

    @Test func warrantyGetsLeadAndExpiryReminders() {
        let asset = WarrantyReminderItem(assetId: UUID(), name: "MacBook Pro", expiresAt: Self.date(2026, 9, 1))
        let reminders = Self.service().reminders(
            warranties: [asset],
            payments: [],
            newestStatementPeriodEnd: nil,
            asOf: Self.date(2026, 7, 1)
        )
        .filter { $0.identifier.hasPrefix("warranty-") }

        #expect(reminders.count == 2)
        // 30-day lead: 1 Sep minus 30 days is 2 Aug.
        let lead = reminders.first { $0.identifier.hasSuffix("-lead") }
        #expect(Self.calendar.component(.month, from: lead!.date) == 8)
        #expect(Self.calendar.component(.day, from: lead!.date) == 2)
    }

    @Test func passedDatesAreNotScheduled() {
        let asset = WarrantyReminderItem(assetId: UUID(), name: "Old Laptop", expiresAt: Self.date(2026, 1, 1))
        let reminders = Self.service().reminders(
            warranties: [asset],
            payments: [],
            newestStatementPeriodEnd: nil,
            asOf: Self.date(2026, 7, 1)
        )
        // A UNCalendarNotificationTrigger built from year/month/day components
        // in the past would otherwise match again next year.
        #expect(reminders.isEmpty)
    }

    @Test func warrantyStillInsideItsLeadWindowKeepsOnlyTheExpiryReminder() {
        // 20 days out: the 30-day lead has already passed, the expiry hasn't.
        let asset = WarrantyReminderItem(assetId: UUID(), name: "Camera", expiresAt: Self.date(2026, 7, 21))
        let reminders = Self.service().reminders(
            warranties: [asset],
            payments: [],
            newestStatementPeriodEnd: nil,
            asOf: Self.date(2026, 7, 1)
        )
        #expect(reminders.count == 1)
        #expect(reminders.first?.identifier.hasSuffix("-expiry") == true)
    }

    // MARK: - Payments

    @Test func paymentUsesAThreeDayLead() {
        let payment = PaymentReminderItem(liabilityId: UUID(), label: "Credit Card", dueAt: Self.date(2026, 7, 20))
        let reminders = Self.service().reminders(
            warranties: [],
            payments: [payment],
            newestStatementPeriodEnd: nil,
            asOf: Self.date(2026, 7, 1)
        )
        .filter { $0.identifier.hasPrefix("payment-") }

        #expect(reminders.count == 2)
        let lead = reminders.first { $0.identifier.hasSuffix("-lead") }
        #expect(Self.calendar.component(.day, from: lead!.date) == 17)
    }

    @Test func paymentBodyNeverContainsAnAmount() {
        let payment = PaymentReminderItem(liabilityId: UUID(), label: "Credit Card", dueAt: Self.date(2026, 7, 20))
        let reminders = Self.service().reminders(
            warranties: [],
            payments: [payment],
            newestStatementPeriodEnd: nil,
            asOf: Self.date(2026, 7, 1)
        )
        // These land on a lock screen; the app hides figures everywhere else.
        for reminder in reminders {
            #expect(!reminder.body.contains("Rp"))
        }
    }

    // MARK: - Import nudge

    @Test func nudgesWhenLastMonthIsMissing() {
        // Newest statement covers April; it's July, so June is missing.
        let nudge = Self.service().importNudge(
            newestStatementPeriodEnd: Self.date(2026, 4, 30),
            asOf: Self.date(2026, 7, 1)
        )
        #expect(nudge != nil)
        #expect(nudge?.body.contains("June") == true)
        // The 5th of the current month, since that's still ahead.
        #expect(Self.calendar.component(.day, from: nudge!.date) == 5)
        #expect(Self.calendar.component(.month, from: nudge!.date) == 7)
    }

    @Test func staysQuietWhenLastMonthIsAlreadyImported() {
        let nudge = Self.service().importNudge(
            newestStatementPeriodEnd: Self.date(2026, 6, 30),
            asOf: Self.date(2026, 7, 15)
        )
        // Nagging someone to import a month they just imported is the worst
        // thing this feature could do.
        #expect(nudge == nil)
    }

    @Test func nudgeMovesToNextMonthOnceThisMonthsDateHasPassed() {
        let nudge = Self.service().importNudge(
            newestStatementPeriodEnd: Self.date(2026, 4, 30),
            asOf: Self.date(2026, 7, 15)
        )
        #expect(Self.calendar.component(.month, from: nudge!.date) == 8)
        #expect(Self.calendar.component(.day, from: nudge!.date) == 5)
    }

    @Test func nudgesWithNoStatementsAtAll() {
        let nudge = Self.service().importNudge(newestStatementPeriodEnd: nil, asOf: Self.date(2026, 7, 1))
        #expect(nudge != nil)
    }

    @Test func nudgeIdentifierIsFixedSoReschedulingReplaces() {
        let nudge = Self.service().importNudge(
            newestStatementPeriodEnd: Self.date(2026, 4, 30),
            asOf: Self.date(2026, 7, 1)
        )
        // Sync runs on every launch and after every import — a per-run
        // identifier would stack a new nudge each time.
        #expect(nudge?.identifier == "import-monthly")
    }
}
