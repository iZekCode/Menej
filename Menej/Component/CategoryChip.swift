//
//  CategoryChip.swift
//  Menej
//

import SwiftUI

struct CategoryChip: View {
    let category: Category

    var body: some View {
        Label(category.displayName, systemImage: category.systemImage)
            .font(.caption)
            .padding(.horizontal, AppSpacing.grid + 2)
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
