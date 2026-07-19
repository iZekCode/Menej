//
//  Typography.swift
//  Menej
//
//  SF Pro via system text styles. Numerals use monospacedDigit() everywhere
//  a value can change or appear in a column — see PRD §7 Typography.
//

import SwiftUI

enum AppTypography {
    /// The net worth headline is the only element on the home screen allowed this large.
    static let netWorthHeadline: Font = .largeTitle.bold()

    static let sectionTitle: Font = .headline
    static let body: Font = .body
    static let caption: Font = .caption
}

extension Text {
    /// Apply to any Text displaying a value that can change or that sits in a column.
    func numericStyle() -> Text {
        monospacedDigit()
    }
}
