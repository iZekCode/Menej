//
//  Colors.swift
//  Menej
//
//  Design tokens — see PRD §7 Color.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// A color that resolves to a different hex value in light vs. dark mode.
    init(light: String, dark: String) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self.init(hex: light)
        #endif
    }

    init(hex: String) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor(hex: hex))
        #else
        let (r, g, b, a) = UIColor.components(fromHex: hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: String) {
        let (r, g, b, a) = UIColor.components(fromHex: hex)
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    fileprivate static func components(fromHex hex: String) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 6 { value += "FF" }
        var rgba: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgba)
        let r = CGFloat((rgba & 0xFF00_0000) >> 24) / 255
        let g = CGFloat((rgba & 0x00FF_0000) >> 16) / 255
        let b = CGFloat((rgba & 0x0000_FF00) >> 8) / 255
        let a = CGFloat(rgba & 0x0000_00FF) / 255
        return (r, g, b, a)
    }
}
#endif

/// PRD §7 — lilac accent. Deeper lilac carries text/icons/tints; true light lilac is fills-only.
enum AppColor {
    static let accent = Color(light: "#7C6BC4", dark: "#A99BE0")
    static let accentSoft = Color(light: "#EDE9F9", dark: "#2A2340")
    static let accentPressed = Color(light: "#6455AB", dark: "#BFB3EA")

    /// Gains/losses stay system green/red — never tinted lilac. Always pair with a sign or arrow.
    static let gain = Color(uiColor: .systemGreen)
    static let loss = Color(uiColor: .systemRed)
}
