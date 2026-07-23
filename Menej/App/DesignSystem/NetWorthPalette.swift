//
//  NetWorthPalette.swift
//  Menej
//
//  Hues for the net worth allocation donut — see PRD §7 Color and §6 F5.
//
//  Color follows the component, not its size: Liquid, Portfolio and Inventory
//  are three fixed identities that exist whether or not they hold anything, so
//  each keeps its hue as the balance between them shifts. That's
//  CategoryPalette's rule, not PortfolioPalette's — a holding has no intrinsic
//  hue and gets colored by rank, but "Liquid" always means the same thing.
//
//  Three hues from the same colorblind-validated categorical set the other two
//  palettes draw from, and as there the donut is always paired with a
//  directly-labeled breakdown row per slice (the relief rule), so hue is never
//  the only thing telling two components apart.
//
//  Liabilities are deliberately absent: they're subtracted, not allocated, and
//  the donut shows what the assets are made of.
//

import SwiftUI

enum NetWorthComponent: String, CaseIterable, Identifiable {
    case liquid
    case portfolio
    case inventory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquid: return "Liquid"
        case .portfolio: return "Portfolio"
        case .inventory: return "Inventory"
        }
    }

    var systemImage: String {
        switch self {
        case .liquid: return "banknote"
        case .portfolio: return "chart.pie"
        case .inventory: return "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .liquid:    return Color(light: "#2A78D6", dark: "#3987E5") // blue
        case .portfolio: return Color(light: "#1BAF7A", dark: "#199E70") // aqua
        case .inventory: return Color(light: "#EB6834", dark: "#D95926") // orange
        }
    }
}
