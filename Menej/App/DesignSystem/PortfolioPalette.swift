//
//  PortfolioPalette.swift
//  Menej
//
//  Categorical palette for the Portfolio allocation donut — see PRD §7 Color.
//  Unlike CategoryPalette (a fixed hue per spend category, an identity that
//  persists across periods), a holding has no intrinsic hue: symbols are
//  arbitrary and user-added, so color is assigned by rank instead — the
//  largest holding always gets the first hue. Reuses the same
//  colorblind-validated categorical hues as CategoryPalette so both charts
//  read consistently; every chart that uses these pairs a directly-labeled
//  legend (the relief rule), so hue is never the sole carrier of identity.
//

import SwiftUI

enum PortfolioPalette {
    private static let hues: [Color] = [
        Color(light: "#2A78D6", dark: "#3987E5"), // blue
        Color(light: "#EB6834", dark: "#D95926"), // orange
        Color(light: "#1BAF7A", dark: "#199E70"), // aqua
        Color(light: "#E87BA4", dark: "#D55181"), // magenta
        Color(light: "#EDA100", dark: "#C98500"), // yellow
        Color(light: "#4A3AA7", dark: "#9085E9"), // violet
        Color(light: "#008300", dark: "#008300"), // green
        Color(light: "#8A8A8E", dark: "#8E8E93"), // gray
    ]

    static func color(at index: Int) -> Color {
        hues[index % hues.count]
    }
}
