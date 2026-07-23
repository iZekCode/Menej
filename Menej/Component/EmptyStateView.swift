//
//  EmptyStateView.swift
//  Menej
//

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.grid) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(AppColor.accent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.margin)
        // Always full width. The contents are centered, but without this the
        // view sizes to its text and gets pushed to the leading edge by any
        // `VStack(alignment: .leading)` parent — which is what Insights,
        // Net Worth and Inventory all are.
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "tray",
        title: "No statements yet",
        message: "Share a PDF statement from Mail, Files, or WhatsApp to get started."
    )
}
