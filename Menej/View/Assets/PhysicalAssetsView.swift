//
//  PhysicalAssetsView.swift
//  Menej
//
//  See PRD §6 F6. Electronics, vehicles, watches, jewelry — some categories
//  appreciate (watches, gold), so the curve runs both directions.
//

import SwiftUI
import SwiftData

struct PhysicalAssetsView: View {
    // A `#Predicate` with several `||` enum comparisons hits a known Swift
    // compiler type-checking limit ("unable to type-check in reasonable
    // time"). Filtering in Swift after a plain fetch sidesteps it.
    @Query private var allAssets: [Asset]

    private var assets: [Asset] {
        allAssets.filter(\.type.isPhysical)
    }

    var body: some View {
        NavigationStack {
            List {
                if assets.isEmpty {
                    EmptyStateView(
                        systemImage: "briefcase",
                        title: "No physical assets yet",
                        message: "Add electronics, vehicles, watches, or jewelry to include them in your net worth."
                    )
                } else {
                    ForEach(assets) { asset in
                        AssetRow(asset: asset)
                    }
                }
            }
            .navigationTitle("Physical Assets")
        }
    }
}

private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(asset.name)
                if let warrantyExpiresAt = asset.warrantyExpiresAt {
                    Text("Warranty until \(warrantyExpiresAt, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            AmountText(amount: asset.currentValue)
        }
    }
}

#Preview {
    PhysicalAssetsView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
