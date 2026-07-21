//
//  CategoryPalette.swift
//  Menej
//
//  Categorical chart palette for spending categories — see PRD §7 Color and
//  §6 F8. This is CHART-ONLY: it is deliberately separate from the lilac
//  brand accent (AppColor.accent) and from the reserved gain/red loss colors.
//  Color follows the category (a fixed hue per entity), never its spending
//  rank, so a category keeps its color as totals shift between periods.
//
//  The seven spending hues are the dataviz reference categorical palette,
//  validated colorblind-safe (validate_palette.js): worst adjacent CVD ΔE 9.1
//  light / 8.4 dark, normal-vision ΔE 19.6 / 19.3, in both light and dark. In
//  light mode three hues fall below 3:1 on the surface — every chart that uses
//  these pairs a directly-labeled breakdown list (the relief rule), so hue is
//  never the sole carrier of identity. "Other" is a neutral gray catch-all,
//  which also keeps red free for the gain/loss semantic used elsewhere.
//
//  transfer / investment / income are never drawn as spend categories (income
//  uses the gain color in the cashflow chart), so they fall through to gray.
//

import SwiftUI

extension Category {
    var chartTint: Color {
        switch self {
        case .transport:     return Color(light: "#2A78D6", dark: "#3987E5") // blue
        case .bills:         return Color(light: "#008300", dark: "#008300") // green
        case .shopping:      return Color(light: "#E87BA4", dark: "#D55181") // magenta
        case .education:     return Color(light: "#EDA100", dark: "#C98500") // yellow
        case .health:        return Color(light: "#1BAF7A", dark: "#199E70") // aqua
        case .food:          return Color(light: "#EB6834", dark: "#D95926") // orange
        case .entertainment: return Color(light: "#4A3AA7", dark: "#9085E9") // violet
        case .other, .transfer, .investment, .income:
            return Color(light: "#8A8A8E", dark: "#8E8E93") // neutral gray
        }
    }
}
