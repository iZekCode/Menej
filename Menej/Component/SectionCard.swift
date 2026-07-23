//
//  SectionCard.swift
//  Menej
//

import SwiftUI

struct SectionCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.grid) {
            if let title {
                Text(title)
                    .font(AppTypography.sectionTitle)
            }
            content
        }
        // Always full width. Without this a card sizes to its content, so
        // cards holding rows or a chart filled the column while a text-only
        // one (Runway) came out visibly narrower than its neighbours.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.margin)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius))
    }
}

#Preview {
    SectionCard(title: "Runway") {
        Text("14 months at your current burn rate")
    }
    .padding()
}
