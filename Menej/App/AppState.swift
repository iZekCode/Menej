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
    var isUnlocked: Bool = false
    var hasCompletedOnboarding: Bool = false

    /// PRD §8 — Face ID / Touch ID to open the app, optional, on by default.
    var isFaceIDEnabled: Bool = true

    /// PRD §9 — Home Screen widget privacy mode, optional, on by default.
    var isWidgetPrivacyModeEnabled: Bool = true
}
