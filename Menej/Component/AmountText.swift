//
//  AmountText.swift
//  Menej
//
//  Monospaced digits, sign, green/red — see PRD §7 Typography and Color.
//  Gains/losses stay green/red regardless of brand accent; always paired
//  with a sign so meaning survives for colorblind users.
//

import SwiftUI

struct AmountText: View {
    let amount: Decimal
    var currencyCode: String = "IDR"
    var showSign: Bool = false
    /// False when the currency is already named next to this text (e.g. a
    /// headline followed by its own "IDR ⌄" picker) — drops the "Rp"/"$"
    /// prefix so the identity isn't stated twice.
    var showsSymbol: Bool = true
    /// Opt-in masking — off by default so most screens are unaffected. The
    /// net-worth cluster (Net Worth, Portfolio, Inventory) passes the
    /// AppState flag through so its "hide amounts" eye can redact figures.
    var isHidden: Bool = false

    private var isNegative: Bool { amount < 0 }

    var body: some View {
        if isHidden {
            // Neutral color when masked — the gain/loss tint would otherwise
            // leak the sign the dots are meant to hide.
            Text(verbatim: "••••••")
                .numericStyle()
                .foregroundStyle(.primary)
        } else {
            Text(formatted)
                .numericStyle()
                .foregroundStyle(showSign ? (isNegative ? AppColor.loss : AppColor.gain) : .primary)
        }
    }

    private var formatted: String {
        Self.string(amount: amount, currencyCode: currencyCode, showSign: showSign, showsSymbol: showsSymbol)
    }

    /// The same formatting as the view, for the places that need the string
    /// itself — a headline in a different font, or an amount embedded in a
    /// caption sentence.
    static func string(amount: Decimal, currencyCode: String = "IDR", showSign: Bool = false, showsSymbol: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = showsSymbol ? (currencyCode == "IDR" ? "Rp" : nil) : ""
        let number = NSDecimalNumber(decimal: abs(amount))
        let raw = formatter.string(from: number) ?? "\(amount)"
        // An empty symbol still leaves the formatter's separator space
        // behind ("  4,369,326" instead of "4,369,326").
        let value = showsSymbol ? raw : raw.trimmingCharacters(in: .whitespaces)
        guard showSign else { return value }
        return (amount < 0 ? "-" : "+") + value
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        AmountText(amount: 4_250_000)
        AmountText(amount: 4_250_000, showSign: true)
        AmountText(amount: -125_000, showSign: true)
    }
    .padding()
}
