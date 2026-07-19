//
//  DeltaBadge.swift
//  Menej
//
//  Net worth delta with direction arrow — see PRD §7 Color.
//

import SwiftUI

struct DeltaBadge: View {
    let delta: Decimal
    var percentage: Double?

    private var isPositive: Bool { delta >= 0 }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
            Text(amountText)
                .numericStyle()
            if let percentage {
                Text("(\(percentage, specifier: "%.1f")%)")
                    .numericStyle()
            }
        }
        .font(.subheadline)
        .foregroundStyle(isPositive ? AppColor.gain : AppColor.loss)
    }

    private var amountText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "IDR"
        formatter.currencySymbol = "Rp"
        let value = formatter.string(from: NSDecimalNumber(decimal: abs(delta))) ?? "\(delta)"
        return (isPositive ? "+" : "-") + value
    }
}

#Preview {
    VStack(spacing: 8) {
        DeltaBadge(delta: 1_200_000, percentage: 3.4)
        DeltaBadge(delta: -450_000, percentage: -1.1)
    }
    .padding()
}
