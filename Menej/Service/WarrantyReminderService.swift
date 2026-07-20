//
//  WarrantyReminderService.swift
//  Menej
//
//  Warranty expiry reminders for physical assets — see PRD §6 F6. Local
//  notifications only; nothing leaves the device (PRD §8).
//
//  Notification identifiers embed the asset id, so re-saving an asset
//  replaces its pending reminders instead of stacking duplicates, and
//  deleting an asset can cancel them.
//

import Foundation
import UserNotifications

protocol WarrantyReminderServiceProtocol {
    func scheduleReminders(assetId: UUID, assetName: String, warrantyExpiresAt: Date?) async
    func cancelReminders(assetId: UUID)
}

struct WarrantyReminderService: WarrantyReminderServiceProtocol {
    private static let leadDays = 30

    func scheduleReminders(assetId: UUID, assetName: String, warrantyExpiresAt: Date?) async {
        cancelReminders(assetId: assetId)
        guard let warrantyExpiresAt else { return }

        let center = UNUserNotificationCenter.current()
        // provisional: reminders land quietly in Notification Center without
        // a permission prompt interrupting asset entry.
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .provisional])) == true else {
            return
        }

        let calendar = Calendar.current
        var reminders: [(id: String, date: Date, body: String)] = []
        if let leadDate = calendar.date(byAdding: .day, value: -Self.leadDays, to: warrantyExpiresAt) {
            reminders.append((
                "warranty-\(assetId)-lead",
                leadDate,
                "\(assetName)'s warranty expires in \(Self.leadDays) days."
            ))
        }
        reminders.append((
            "warranty-\(assetId)-expiry",
            warrantyExpiresAt,
            "\(assetName)'s warranty expires today."
        ))

        for reminder in reminders where reminder.date > .now {
            var components = calendar.dateComponents([.year, .month, .day], from: reminder.date)
            components.hour = 9

            let content = UNMutableNotificationContent()
            content.title = "Warranty reminder"
            content.body = reminder.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancelReminders(assetId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "warranty-\(assetId)-lead",
            "warranty-\(assetId)-expiry",
        ])
    }
}
