//
//  ReminderService.swift
//  Menej
//
//  Every local notification the app sends — warranty expiry (PRD §6 F6),
//  liability due dates (F5), and a monthly nudge to import statements.
//  Local only; nothing leaves the device (PRD §8).
//
//  WHY EVERYTHING IS SCHEDULED IN ADVANCE: the app has no background
//  execution — no BGTaskScheduler, no background modes. Statements are
//  hand-imported and prices refresh only when PortfolioView appears, so
//  nothing can ever run later to *notice* something and tell the user. Every
//  notification here is therefore date-triggered from data already known at
//  scheduling time. Anything shaped like "alert me when I overspend" is not
//  implementable in this app, honestly, at all.
//
//  Delivery is `.provisional` throughout: reminders land quietly in
//  Notification Center with no banner, no sound, and no permission prompt.
//  The accepted cost is that a payment reminder can go unseen; promoting just
//  the payment ones to full authorization is the fix if that ever bites.
//
//  Notification bodies never contain amounts. They appear on the lock screen,
//  and the app otherwise goes to some length to keep figures private (Face ID
//  gate, hide-amounts toggle, widget privacy mode).
//
//  KNOWN LIMITATION: `Liability.dueDate` is a single Date, so a payment
//  reminder fires once and that liability then goes quiet until the user edits
//  the date. Recurring reminders need a cadence field on the model — the
//  `SubscriptionCadence` enum is the pattern to copy. Assuming "monthly"
//  would be inventing data the user never entered.
//
//  No SwiftData import, deliberately — same discipline as InsightService, so
//  the date arithmetic below typechecks and unit-tests under the CLT swiftc
//  harness. Callers map @Model types into the value types here.
//

import Foundation
import UserNotifications

// MARK: - Inputs

struct WarrantyReminderItem {
    let assetId: UUID
    let name: String
    let expiresAt: Date
}

struct PaymentReminderItem {
    let liabilityId: UUID
    let label: String
    let dueAt: Date
}

/// One scheduled notification, fully resolved. Split out from the scheduling
/// itself so all the date logic is testable without UserNotifications.
struct PendingReminder: Equatable {
    let identifier: String
    let title: String
    let body: String
    /// Local time the notification should fire.
    let date: Date
}

// MARK: - Service

protocol ReminderServiceProtocol {
    func sync(
        warranties: [WarrantyReminderItem],
        payments: [PaymentReminderItem],
        newestStatementPeriodEnd: Date?,
        isEnabled: Bool
    ) async
}

struct ReminderService: ReminderServiceProtocol {
    /// A month's warning on a warranty is useful — that's how long it takes to
    /// arrange a repair or claim. The same lead on a bill is noise you'd have
    /// forgotten by the due date, so payments get three days.
    static let warrantyLeadDays = 30
    static let paymentLeadDays = 3
    /// Day of the month the import nudge fires on. Early enough that the month
    /// is still current, late enough that statements have plausibly been
    /// issued.
    static let importNudgeDayOfMonth = 5
    /// Notifications fire at 9am local.
    static let deliveryHour = 9

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Cancels everything pending and rebuilds it from the arguments.
    ///
    /// Idempotent by design: call sites don't track which identifiers they own,
    /// so deleting a liability, editing a due date, or toggling reminders off
    /// mid-flight can't leave a stale notification behind. Cheap enough to run
    /// on every launch and after every save.
    func sync(
        warranties: [WarrantyReminderItem],
        payments: [PaymentReminderItem],
        newestStatementPeriodEnd: Date?,
        isEnabled: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }

        // Provisional never prompts, so requesting it lazily here costs the
        // user nothing.
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .provisional])) == true else {
            return
        }

        for reminder in reminders(
            warranties: warranties,
            payments: payments,
            newestStatementPeriodEnd: newestStatementPeriodEnd
        ) {
            var components = calendar.dateComponents([.year, .month, .day], from: reminder.date)
            components.hour = Self.deliveryHour

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    // MARK: - Date logic (pure)

    /// Everything that should be pending right now. Past dates are dropped —
    /// `UNCalendarNotificationTrigger` would otherwise match the same
    /// components next year.
    func reminders(
        warranties: [WarrantyReminderItem],
        payments: [PaymentReminderItem],
        newestStatementPeriodEnd: Date?,
        asOf: Date = .now
    ) -> [PendingReminder] {
        var result: [PendingReminder] = []

        for warranty in warranties {
            if let lead = calendar.date(byAdding: .day, value: -Self.warrantyLeadDays, to: warranty.expiresAt) {
                result.append(PendingReminder(
                    identifier: "warranty-\(warranty.assetId)-lead",
                    title: "Warranty reminder",
                    body: "\(warranty.name)'s warranty expires in \(Self.warrantyLeadDays) days.",
                    date: lead
                ))
            }
            result.append(PendingReminder(
                identifier: "warranty-\(warranty.assetId)-expiry",
                title: "Warranty reminder",
                body: "\(warranty.name)'s warranty expires today.",
                date: warranty.expiresAt
            ))
        }

        for payment in payments {
            if let lead = calendar.date(byAdding: .day, value: -Self.paymentLeadDays, to: payment.dueAt) {
                result.append(PendingReminder(
                    identifier: "payment-\(payment.liabilityId)-lead",
                    title: "Payment due soon",
                    body: "\(payment.label) is due in \(Self.paymentLeadDays) days.",
                    date: lead
                ))
            }
            result.append(PendingReminder(
                identifier: "payment-\(payment.liabilityId)-due",
                title: "Payment due",
                body: "\(payment.label) is due today.",
                date: payment.dueAt
            ))
        }

        if let nudge = importNudge(newestStatementPeriodEnd: newestStatementPeriodEnd, asOf: asOf) {
            result.append(nudge)
        }

        return result.filter { $0.date > asOf }
    }

    /// Nudges about the most recent *completed* month, and only when nothing
    /// has been imported covering it — the sync runs often enough that this
    /// self-corrects rather than needing to track what's been sent.
    ///
    /// The body says statements are "probably" ready because the app genuinely
    /// can't know: it has no connection to any issuer and only learns anything
    /// when the user hands it a PDF.
    func importNudge(newestStatementPeriodEnd: Date?, asOf: Date = .now) -> PendingReminder? {
        guard let currentMonth = calendar.dateInterval(of: .month, for: asOf)?.start,
              let targetMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) else {
            return nil
        }

        // Already up to date for that month.
        if let newestStatementPeriodEnd,
           calendar.isDate(newestStatementPeriodEnd, equalTo: targetMonth, toGranularity: .month)
            || newestStatementPeriodEnd >= currentMonth {
            return nil
        }

        guard let fireDate = nextNudgeDate(asOf: asOf, currentMonth: currentMonth) else { return nil }

        return PendingReminder(
            identifier: "import-monthly",
            title: "Import your statements",
            body: "\(monthName(targetMonth)) statements are probably ready. Importing them keeps your net worth current.",
            date: fireDate
        )
    }

    /// The 5th of this month if it's still ahead, otherwise the 5th of next
    /// month.
    private func nextNudgeDate(asOf: Date, currentMonth: Date) -> Date? {
        guard let thisMonthNudge = calendar.date(
            byAdding: .day,
            value: Self.importNudgeDayOfMonth - 1,
            to: currentMonth
        ) else { return nil }

        // Compare against the delivery hour, not midnight: on the 5th before
        // 9am the nudge is still ahead and shouldn't be pushed a month out.
        let deadline = calendar.date(bySettingHour: Self.deliveryHour, minute: 0, second: 0, of: thisMonthNudge)
            ?? thisMonthNudge
        if deadline > asOf { return thisMonthNudge }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { return nil }
        return calendar.date(byAdding: .day, value: Self.importNudgeDayOfMonth - 1, to: nextMonth)
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
