//
//  PhysicalAssetsView.swift
//  Menej
//
//  See PRD §6 F6. Electronics, vehicles, watches, jewelry — some categories
//  appreciate (watches, jewelry), so the curve runs both directions.
//

import SwiftUI
import SwiftData

struct PhysicalAssetsView: View {
    @Environment(\.modelContext) private var modelContext
    // A `#Predicate` with several `||` enum comparisons hits a known Swift
    // compiler type-checking limit ("unable to type-check in reasonable
    // time"). Filtering in Swift after a plain fetch sidesteps it.
    @Query private var allAssets: [Asset]

    @State private var assetBeingEdited: Asset?
    @State private var isAddingAsset = false

    private let reminderService = WarrantyReminderService()

    private var assets: [Asset] {
        allAssets.filter(\.type.isPhysical)
            .sorted { $0.currentValue > $1.currentValue }
    }

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack
    // from the asset breakdown.
    var body: some View {
        List {
            if assets.isEmpty {
                EmptyStateView(
                    systemImage: "briefcase",
                    title: "No physical assets yet",
                    message: "Add electronics, vehicles, watches, or jewelry to include them in your net worth."
                )
            } else {
                Section {
                    ForEach(assets) { asset in
                        Button {
                            assetBeingEdited = asset
                        } label: {
                            AssetRow(asset: asset)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteAssets)
                } footer: {
                    Text("Values follow a per-category curve unless set manually. Tap an asset to edit it.")
                }
            }
        }
        .navigationTitle("Physical Assets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Asset", systemImage: "plus") {
                    isAddingAsset = true
                }
            }
        }
        .sheet(isPresented: $isAddingAsset) {
            AssetFormView(asset: nil)
        }
        .sheet(item: $assetBeingEdited) { asset in
            AssetFormView(asset: asset)
        }
        .onAppear(perform: applyCurves)
    }

    /// Depreciation/appreciation drifts with time, not with edits — re-apply
    /// curves whenever the list appears so displayed values (and net worth,
    /// which reads the same stored `currentValue`) stay current.
    private func applyCurves() {
        for asset in assets {
            asset.applyCurveIfNeeded()
        }
    }

    private func deleteAssets(at offsets: IndexSet) {
        for index in offsets {
            let asset = assets[index]
            reminderService.cancelReminders(assetId: asset.id)
            modelContext.delete(asset)
        }
    }
}

private struct AssetRow: View {
    let asset: Asset

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: asset.currentValue)
        }
    }

    private var subtitle: String {
        var parts = [asset.type.displayName]
        if let warrantyExpiresAt = asset.warrantyExpiresAt {
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
            parts.append(
                warrantyExpiresAt > .now
                    ? "warranty until \(warrantyExpiresAt.formatted(style))"
                    : "warranty expired"
            )
        }
        return parts.joined(separator: " · ")
    }
}

private struct AssetFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new asset.
    let asset: Asset?

    @State private var type: AssetType = .electronics
    @State private var name = ""
    @State private var acquiredAt = Date()
    @State private var acquisitionCost: Decimal?
    @State private var usesCurve = true
    @State private var manualValue: Decimal?
    @State private var hasWarranty = false
    @State private var warrantyExpiresAt = Date()

    private let depreciationService = DepreciationService()
    private let reminderService = WarrantyReminderService()

    private static let physicalTypes = AssetType.allCases.filter(\.isPhysical)

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (acquisitionCost ?? 0) > 0
            && (usesCurve || (manualValue ?? 0) > 0)
    }

    private var estimatedValue: Decimal? {
        guard let acquisitionCost, acquisitionCost > 0 else { return nil }
        return depreciationService.estimatedValue(
            acquisitionCost: acquisitionCost,
            acquiredAt: acquiredAt,
            curveId: type.rawValue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $type) {
                        ForEach(Self.physicalTypes) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Name (MacBook Pro, NMAX…)", text: $name)
                    DatePicker("Acquired", selection: $acquiredAt, in: ...Date(), displayedComponents: .date)
                    TextField("Purchase price", value: $acquisitionCost, format: .number)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Toggle("Estimate value automatically", isOn: $usesCurve)
                    if usesCurve {
                        if let estimatedValue {
                            LabeledContent("Estimated value now") {
                                AmountText(amount: estimatedValue)
                            }
                        }
                    } else {
                        TextField("Current value", value: $manualValue, format: .number)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text(curveFooter)
                }

                Section {
                    Toggle("Warranty", isOn: $hasWarranty)
                    if hasWarranty {
                        DatePicker("Expires", selection: $warrantyExpiresAt, displayedComponents: .date)
                    }
                } footer: {
                    if hasWarranty {
                        Text("You'll get a reminder 30 days before it expires.")
                    }
                }
            }
            .navigationTitle(asset == nil ? "Add Asset" : "Edit Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(asset == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: populateFromExisting)
        }
    }

    private var curveFooter: String {
        guard usesCurve, let curve = depreciationService.curve(id: type.rawValue) else {
            return "The value you set is used as-is in your net worth."
        }
        let percent = abs(curve.annualRate * 100).formatted(.number.precision(.fractionLength(0)))
        return curve.annualRate < 0
            ? "\(type.displayName) is assumed to lose \(percent)% of its value per year."
            : "\(type.displayName) is assumed to gain \(percent)% in value per year."
    }

    private func populateFromExisting() {
        guard let asset else { return }
        type = asset.type
        name = asset.name
        acquiredAt = asset.acquiredAt
        acquisitionCost = asset.acquisitionCost
        usesCurve = asset.depreciationCurve != nil
        manualValue = asset.currentValue
        hasWarranty = asset.warrantyExpiresAt != nil
        warrantyExpiresAt = asset.warrantyExpiresAt ?? Date()
    }

    private func save() {
        let curveId = usesCurve ? type.rawValue : nil
        let value = usesCurve ? (estimatedValue ?? acquisitionCost ?? 0) : (manualValue ?? 0)
        let warranty = hasWarranty ? warrantyExpiresAt : nil

        let saved: Asset
        if let asset {
            asset.type = type
            asset.name = name.trimmingCharacters(in: .whitespaces)
            asset.acquiredAt = acquiredAt
            asset.acquisitionCost = acquisitionCost ?? 0
            asset.currentValue = value
            asset.depreciationCurve = curveId
            asset.warrantyExpiresAt = warranty
            saved = asset
        } else {
            saved = Asset(
                type: type,
                name: name.trimmingCharacters(in: .whitespaces),
                acquiredAt: acquiredAt,
                acquisitionCost: acquisitionCost ?? 0,
                currentValue: value,
                depreciationCurve: curveId,
                warrantyExpiresAt: warranty
            )
            modelContext.insert(saved)
        }

        let reminderService = reminderService
        let assetId = saved.id
        let assetName = saved.name
        Task {
            await reminderService.scheduleReminders(
                assetId: assetId,
                assetName: assetName,
                warrantyExpiresAt: warranty
            )
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PhysicalAssetsView()
    }
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
