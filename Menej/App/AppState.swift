//
//  AppState.swift
//  Menej
//
//  App-wide UI state that doesn't belong to any single feature.
//

import Foundation
import Observation

@Observable
final class AppState {
    /// Whether the biometric lock has been passed this session (see AppLockView).
    var isUnlocked: Bool = false
    var hasCompletedOnboarding: Bool = false

    /// PRD §8 — Face ID / Touch ID to open the app, optional, on by default.
    var isFaceIDEnabled: Bool {
        didSet { UserDefaults.standard.set(isFaceIDEnabled, forKey: Keys.faceID) }
    }

    /// PRD §9 — Home Screen widget privacy mode, optional, on by default.
    var isWidgetPrivacyModeEnabled: Bool {
        didSet { UserDefaults.standard.set(isWidgetPrivacyModeEnabled, forKey: Keys.widgetPrivacy) }
    }

    /// The in-app "hide amounts" eye toggle — masks every AmountText and the
    /// net worth headline across the app so numbers can be hidden from
    /// over-the-shoulder glances without locking the whole app.
    var areAmountsHidden: Bool {
        didSet { UserDefaults.standard.set(areAmountsHidden, forKey: Keys.hideAmounts) }
    }

    /// Master switch for every local notification — warranty expiry, payment
    /// due dates, and the monthly import nudge (see ReminderService). On by
    /// default: they're provisional, so they arrive quietly and never prompt.
    var areRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(areRemindersEnabled, forKey: Keys.reminders) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Face ID and widget privacy default ON (PRD §8/§9); amounts default visible.
        defaults.register(defaults: [
            Keys.faceID: true,
            Keys.widgetPrivacy: true,
            Keys.hideAmounts: false,
            Keys.reminders: true,
        ])
        isFaceIDEnabled = defaults.bool(forKey: Keys.faceID)
        isWidgetPrivacyModeEnabled = defaults.bool(forKey: Keys.widgetPrivacy)
        areAmountsHidden = defaults.bool(forKey: Keys.hideAmounts)
        areRemindersEnabled = defaults.bool(forKey: Keys.reminders)
    }

    private enum Keys {
        static let faceID = "isFaceIDEnabled"
        static let widgetPrivacy = "isWidgetPrivacyModeEnabled"
        static let hideAmounts = "areAmountsHidden"
        static let reminders = "areRemindersEnabled"
    }
}
