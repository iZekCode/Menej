//
//  InventoryView.swift
//  Menej
//
//  Physical inventory (PRD §6 F6) — electronics, vehicles, watches, jewelry.
//  Some categories appreciate (watches, jewelry), so the value curve runs
//  both directions. Promoted to a top-level tab; each item can carry a photo.
//

import SwiftUI
import SwiftData
import PhotosUI

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    // A `#Predicate` with several `||` enum comparisons hits a known Swift
    // compiler type-checking limit ("unable to type-check in reasonable
    // time"). Filtering in Swift after a plain fetch sidesteps it.
    @Query private var allAssets: [Asset]

    @State private var itemBeingEdited: Asset?
    @State private var isAddingItem = false

    private let reminderService = WarrantyReminderService()

    private var items: [Asset] {
        allAssets.filter(\.type.isPhysical)
            .sorted { $0.currentValue > $1.currentValue }
    }

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack
    // from the Breakdown card.
    var body: some View {
        List {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "No items yet",
                    message: "Add electronics, vehicles, watches, or jewelry to track them and include them in your net worth."
                )
            } else {
                Section {
                    ForEach(items) { item in
                        Button {
                            itemBeingEdited = item
                        } label: {
                            InventoryRow(item: item, isHidden: appState.areAmountsHidden)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteItems)
                } footer: {
                    Text("Tap an item to edit it.")
                }
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.areAmountsHidden.toggle()
                } label: {
                    Image(systemName: appState.areAmountsHidden ? "eye.slash" : "eye")
                }
                .accessibilityLabel(appState.areAmountsHidden ? "Show amounts" : "Hide amounts")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Item", systemImage: "plus") {
                    isAddingItem = true
                }
            }
        }
        .sheet(isPresented: $isAddingItem) {
            InventoryItemFormView(item: nil)
        }
        .sheet(item: $itemBeingEdited) { item in
            InventoryItemFormView(item: item)
        }
        .onAppear(perform: applyCurves)
    }

    /// Depreciation/appreciation drifts with time, not with edits — re-apply
    /// curves whenever the list appears so displayed values (and net worth,
    /// which reads the same stored `currentValue`) stay current.
    private func applyCurves() {
        for item in items {
            item.applyCurveIfNeeded()
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            reminderService.cancelReminders(assetId: item.id)
            modelContext.delete(item)
        }
    }
}

private struct InventoryRow: View {
    let item: Asset
    var isHidden: Bool = false

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            ItemThumbnail(photoData: item.photoData)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: item.currentValue, isHidden: isHidden)
        }
    }

    private var subtitle: String {
        var parts = [item.type.displayName]
        if let warrantyExpiresAt = item.warrantyExpiresAt {
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

/// Small square thumbnail — the item's photo, or a category-neutral
/// placeholder when there isn't one.
private struct ItemThumbnail: View {
    let photoData: Data?

    var body: some View {
        Group {
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InventoryItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new item.
    let item: Asset?

    @State private var type: AssetType = .electronics
    @State private var name = ""
    @State private var acquiredAt = Date()
    @State private var acquisitionCost: Decimal?
    @State private var usesCurve = true
    @State private var manualValue: Decimal?
    @State private var hasWarranty = false
    @State private var warrantyExpiresAt = Date()
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingCamera = false

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
                photoSection

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
            .navigationTitle(item == nil ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: populateFromExisting)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(isPresented: $isShowingCamera) { data in
                    photoData = data
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            HStack(spacing: AppSpacing.margin) {
                ItemThumbnail(photoData: photoData)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    if CameraPicker.isAvailable {
                        Button {
                            isShowingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(photoData == nil ? "Choose from Library" : "Change Photo", systemImage: "photo")
                    }
                    if photoData != nil {
                        Button(role: .destructive) {
                            photoData = nil
                            selectedPhoto = nil
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                        }
                    }
                }
            }
        } footer: {
            Text("Pick a photo from your library. It's stored on-device only.")
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
        guard let item else { return }
        type = item.type
        name = item.name
        acquiredAt = item.acquiredAt
        acquisitionCost = item.acquisitionCost
        usesCurve = item.depreciationCurve != nil
        manualValue = item.currentValue
        hasWarranty = item.warrantyExpiresAt != nil
        warrantyExpiresAt = item.warrantyExpiresAt ?? Date()
        photoData = item.photoData
    }

    private func save() {
        let curveId = usesCurve ? type.rawValue : nil
        let value = usesCurve ? (estimatedValue ?? acquisitionCost ?? 0) : (manualValue ?? 0)
        let warranty = hasWarranty ? warrantyExpiresAt : nil

        let saved: Asset
        if let item {
            item.type = type
            item.name = name.trimmingCharacters(in: .whitespaces)
            item.acquiredAt = acquiredAt
            item.acquisitionCost = acquisitionCost ?? 0
            item.currentValue = value
            item.depreciationCurve = curveId
            item.warrantyExpiresAt = warranty
            item.photoData = photoData
            saved = item
        } else {
            saved = Asset(
                type: type,
                name: name.trimmingCharacters(in: .whitespaces),
                acquiredAt: acquiredAt,
                acquisitionCost: acquisitionCost ?? 0,
                currentValue: value,
                depreciationCurve: curveId,
                warrantyExpiresAt: warranty,
                photoData: photoData
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
        InventoryView()
    }
    .environment(AppState())
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
