//
//  ConfidenceBanner.swift
//  Menej
//
//  Flags problem rows and the reconciliation gap — see PRD §6 F1.
//  Users always confirm before data enters the ledger; no silent imports.
//

import SwiftUI

struct ConfidenceBanner: View {
    let confidence: Double
    var unaccountedAmount: Decimal = 0

    private var isLowConfidence: Bool { confidence < 0.9 }

    var body: some View {
        if isLowConfidence || unaccountedAmount != 0 {
            HStack(alignment: .top, spacing: AppSpacing.grid) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.loss)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Some rows need review")
                        .font(.subheadline.bold())
                    if unaccountedAmount != 0 {
                        HStack(spacing: 4) {
                            Text("Unaccounted:")
                            AmountText(amount: unaccountedAmount)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(AppSpacing.grid)
            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppSpacing.chipCornerRadius))
        }
    }
}

#Preview {
    ConfidenceBanner(confidence: 0.72, unaccountedAmount: 15_000)
        .padding()
}
