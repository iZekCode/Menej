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

    private var isNegative: Bool { amount < 0 }

    var body: some View {
        Text(formatted)
            .numericStyle()
            .foregroundStyle(showSign ? (isNegative ? AppColor.loss : AppColor.gain) : .primary)
    }

    private var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.currencySymbol = currencyCode == "IDR" ? "Rp" : nil
        let number = NSDecimalNumber(decimal: abs(amount))
        let value = formatter.string(from: number) ?? "\(amount)"
        guard showSign else { return value }
        return (isNegative ? "-" : "+") + value
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
