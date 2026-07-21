//
//  CategoryChip.swift
//  Menej
//

import SwiftUI

struct CategoryChip: View {
    let category: Category

    var body: some View {
        // A hand-rolled HStack rather than `Label` so the icon-to-text gap is
        // tight; `fixedSize` + `lineLimit` keep the pill on one line instead of
        // wrapping ("Fo o d") when the row is width-constrained.
        HStack(spacing: 3) {
            Image(systemName: category.systemImage)
            Text(category.displayName)
        }
        .font(.caption)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, AppSpacing.grid)
        .padding(.vertical, 4)
        .background(AppColor.accentSoft, in: Capsule())
        .foregroundStyle(AppColor.accent)
    }
}

#Preview {
    HStack {
        CategoryChip(category: .food)
        CategoryChip(category: .transport)
        CategoryChip(category: .investment)
    }
    .padding()
}
