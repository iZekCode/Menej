//
//  InventoryView.swift
//  Menej
//
//  Physical inventory (PRD §6 F6) — electronics, vehicles, watches, jewelry.
//  Some categories appreciate (watches, jewelry), so the value curve runs
//  both directions. Each item can carry a photo, and the photo is what
//  identifies it: a picture of the motorbike beats the words "NMAX 155", so
//  this is a card grid rather than a list of 44pt thumbnails.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Grid ordering. `.value` is the default because it reproduces the ordering
/// this screen has always had, and because value is what ties inventory to
/// net worth.
private enum InventorySort: String, CaseIterable, Identifiable {
    case value
    case name
    case recentlyAcquired
    case category

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .value: return "Value"
        case .name: return "Name"
        case .recentlyAcquired: return "Recently Acquired"
        case .category: return "Category"
        }
    }
}

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    // A `#Predicate` with several `||` enum comparisons hits a known Swift
    // compiler type-checking limit ("unable to type-check in reasonable
    // time"). Filtering in Swift after a plain fetch sidesteps it.
    @Query private var allAssets: [Asset]

    @State private var itemBeingEdited: Asset?
    @State private var isAddingItem = false
    @State private var sort: InventorySort = .value
    /// nil = "All". Holding an AssetType rather than an index keeps the
    /// selection valid when the last item of a category is deleted — the chip
    /// disappears and `visibleItems` simply comes back empty.
    @State private var filter: AssetType?

    private let reminderService = WarrantyReminderService()

    // Two columns on every iPhone width, three on wider layouts. The gutter is
    // a full margin rather than the 8pt grid — at 8pt two photos read as one
    // banded strip instead of two separate objects.
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: AppSpacing.margin)]
    /// Rows sit further apart than columns: each cell's caption block runs
    /// right up to the next photo, so it needs more clearance than two photos
    /// side by side do.
    private let rowSpacing: CGFloat = AppSpacing.margin + AppSpacing.grid

    private var items: [Asset] {
        allAssets.filter(\.type.isPhysical)
    }

    private var visibleItems: [Asset] {
        let filtered = filter.map { type in items.filter { $0.type == type } } ?? items
        return filtered.sorted(by: isOrderedBefore)
    }

    /// Only categories the user actually owns something in — offering an
    /// empty "Jewelry" chip would just be a dead end.
    private var availableTypes: [AssetType] {
        let present = Set(items.map(\.type))
        return AssetType.allCases.filter { $0.isPhysical && present.contains($0) }
    }

    /// The total reflects the *filter*, not the whole inventory — the figure
    /// under a "Vehicle" chip has to be the vehicles' total, or the number
    /// contradicts the grid right below it.
    private var visibleTotal: Decimal {
        visibleItems.reduce(Decimal(0)) { $0 + $1.currentValue }
    }

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack
    // from the Breakdown card.
    var body: some View {
        ScrollView {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "No items yet",
                    message: "Add electronics, vehicles, watches, or jewelry to track them and include them in your net worth."
                )
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.margin) {
                    header
                    controlsRow
                    grid
                }
                .padding(AppSpacing.margin)
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
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

    /// Same shape as PortfolioView's summary: label, inline eye, headline.
    /// The eye lives here rather than in the toolbar so it sits next to the
    /// figure it masks, leaving the toolbar to Add alone.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: AppSpacing.grid) {
                Text(filter?.displayName ?? "Inventory Value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    appState.areAmountsHidden.toggle()
                } label: {
                    Image(systemName: appState.areAmountsHidden ? "eye.slash" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.areAmountsHidden ? "Show amounts" : "Hide amounts")
            }
            AmountText(amount: visibleTotal, isHidden: appState.areAmountsHidden)
                .font(.title.bold())
            Text(visibleItems.count == 1 ? "1 item" : "\(visibleItems.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Filter chips and the sort control share one row — both narrow what
    /// you're looking at, so they belong together rather than with Add in the
    /// toolbar. Sort is pinned trailing and never scrolls away.
    private var controlsRow: some View {
        HStack(spacing: AppSpacing.grid) {
            if availableTypes.count > 1 {
                filterChips
            } else {
                Spacer()
            }
            sortMenu
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.grid) {
                InventoryFilterChip(title: "All", isSelected: filter == nil) {
                    filter = nil
                }
                ForEach(availableTypes) { type in
                    InventoryFilterChip(title: type.displayName, isSelected: filter == type) {
                        filter = type
                    }
                }
            }
            // This row sits inside a view that already carries the screen
            // margin; the leading inset is cancelled out below so chips
            // scroll from the true screen edge. The trailing side keeps its
            // padding — that edge stops at the sort button, not the screen.
            .padding(.leading, AppSpacing.margin)
            .padding(.trailing, AppSpacing.grid)
        }
        .padding(.leading, -AppSpacing.margin)
    }

    @ViewBuilder
    private var grid: some View {
        if visibleItems.isEmpty {
            Text("Nothing in this category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppSpacing.margin)
        } else {
            LazyVGrid(columns: columns, spacing: rowSpacing) {
                ForEach(visibleItems) { item in
                    Button {
                        itemBeingEdited = item
                    } label: {
                        InventoryCard(item: item, isHidden: appState.areAmountsHidden)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit item")
                    // A grid has no swipe-to-delete, so the destructive path
                    // moves here.
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            itemBeingEdited = item
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(item)
                        }
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(InventorySort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if option == sort {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            // Sized and shaped like an unselected chip so the row reads as one
            // band of controls. Menu tints its label from `.tint`, not the
            // label's own foregroundStyle.
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.medium))
                .frame(width: 34, height: 34)
                .background(AppColor.accentSoft, in: Circle())
        }
        .tint(AppColor.accent)
        .accessibilityLabel("Sort")
    }

    /// Every order falls back to name so items that tie (two things bought the
    /// same day, or the whole of a `.category` group) don't shuffle between
    /// body evaluations.
    private func isOrderedBefore(_ lhs: Asset, _ rhs: Asset) -> Bool {
        switch sort {
        case .value:
            if lhs.currentValue != rhs.currentValue { return lhs.currentValue > rhs.currentValue }
        case .name:
            break
        case .recentlyAcquired:
            if lhs.acquiredAt != rhs.acquiredAt { return lhs.acquiredAt > rhs.acquiredAt }
        case .category:
            if lhs.type != rhs.type { return lhs.type.displayName < rhs.type.displayName }
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// Depreciation/appreciation drifts with time, not with edits — re-apply
    /// curves whenever the grid appears so displayed values (and net worth,
    /// which reads the same stored `currentValue`) stay current.
    private func applyCurves() {
        for item in items {
            item.applyCurveIfNeeded()
        }
    }

    /// Takes the asset itself rather than an IndexSet: the visible order now
    /// depends on sort and filter, so an index into the grid is only
    /// meaningful for the exact array that produced it.
    private func delete(_ item: Asset) {
        // Reminder identifiers embed the asset id — without this the
        // notifications for a deleted item still fire.
        reminderService.cancelReminders(assetId: item.id)
        modelContext.delete(item)
    }
}

/// Selectable capsule. Deliberately not `Component/CategoryChip` — that one is
/// bound to the spend `Category` enum and has no selected state — but it
/// borrows the same geometry so the two read as the same control.
private struct InventoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                // Taller and wider than CategoryChip: this one is a tap
                // target, not a label, so it needs a comfortable hit area.
                .padding(.horizontal, AppSpacing.margin)
                .padding(.vertical, AppSpacing.grid)
                .background(isSelected ? AppColor.accent : AppColor.accentSoft, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : AppColor.accent)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One grid cell: photo on top, then name, value, and the same secondary line
/// the old list row carried.
private struct InventoryCard: View {
    let item: Asset
    var isHidden: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ItemPhoto(photoData: item.photoData, fallbackSystemImage: item.type.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                AmountText(amount: item.currentValue, isHidden: isHidden)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The category is already implied by the fallback glyph but not by a
    /// photo, so it stays spelled out — except when there's a warranty to
    /// report, which is the more perishable fact.
    private var subtitle: String {
        guard let warrantyExpiresAt = item.warrantyExpiresAt else {
            return item.type.displayName
        }
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return warrantyExpiresAt > .now
            ? "Warranty to \(warrantyExpiresAt.formatted(style))"
            : "Warranty expired"
    }
}

/// The item's photo filling a square, or its category glyph when there isn't
/// one. `scaledToFill` into a fixed aspect ratio keeps every card the same
/// height whatever the photo's own proportions are — the `clipShape` is what
/// discards the overflow.
private struct ItemPhoto: View {
    let photoData: Data?
    let fallbackSystemImage: String
    var aspectRatio: CGFloat = 1
    var cornerRadius: CGFloat = AppSpacing.cardCornerRadius

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: fallbackSystemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    /// Off by default: most things people add are worth roughly what they
    /// paid at the moment they're entered, and a curve silently rewriting
    /// that figure is a surprise. Opting in is the deliberate choice.
    @State private var usesCurve = false
    /// nil means "hasn't been typed in" — `effectiveManualValue` then falls
    /// back to the purchase price rather than to zero.
    @State private var manualValue: Decimal?
    @State private var hasWarranty = false
    @State private var warrantyExpiresAt = Date()
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isShowingPhotoOptions = false
    @State private var isShowingLibrary = false
    @State private var isConfirmingDelete = false

    private let depreciationService = DepreciationService()
    private let reminderService = WarrantyReminderService()

    private static let physicalTypes = AssetType.allCases.filter(\.isPhysical)

    private var canSave: Bool {
        // With the curve off, value defaults to the purchase price, which is
        // already required to be positive — so there's no separate condition
        // for manual valuation to satisfy.
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (acquisitionCost ?? 0) > 0
    }

    /// What a manually-valued item is worth: whatever was typed, or the
    /// purchase price until something is.
    private var effectiveManualValue: Decimal {
        manualValue ?? acquisitionCost ?? 0
    }

    /// Shows the purchase price as the field's live content rather than as a
    /// grey placeholder, so the number the app will actually save is the one
    /// on screen. Typing replaces it; clearing the field falls back again.
    private var manualValueBinding: Binding<Decimal?> {
        Binding(
            get: { manualValue ?? acquisitionCost },
            set: { manualValue = $0 }
        )
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
                        TextField("Current value", value: manualValueBinding, format: .number)
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

                if item != nil {
                    Section {
                        Button("Delete Item", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
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
                        photoData = Self.downsampled(data)
                    }
                }
            }
            // Presented from the action sheet rather than by a PhotosPicker
            // button living in the form row — see photoSection.
            .photosPicker(
                isPresented: $isShowingLibrary,
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            )
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(isPresented: $isShowingCamera) { data in
                    photoData = Self.downsampled(data)
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("Photo", isPresented: $isShowingPhotoOptions, titleVisibility: .hidden) {
                if CameraPicker.isAvailable {
                    Button("Take Photo") { isShowingCamera = true }
                }
                Button("Choose from Library") { isShowingLibrary = true }
                if photoData != nil {
                    Button("Remove Photo", role: .destructive) {
                        photoData = nil
                        selectedPhoto = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete this item?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteItem() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from your inventory and from your net worth.")
            }
        }
    }

    /// One big tappable photo, not a thumbnail beside a stack of buttons.
    /// The old layout put three separate Buttons (plus a PhotosPicker, which
    /// is a button too) inside a single Form row: a Form row is one hit
    /// target, so their tap areas ran together and the wrong action fired.
    /// Here the entire row is the only control, and it opens an action sheet —
    /// which also gives the photo room to actually be looked at.
    @ViewBuilder
    private var photoSection: some View {
        Section {
            Button {
                isShowingPhotoOptions = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ItemPhoto(
                        photoData: photoData,
                        fallbackSystemImage: type.systemImage,
                        aspectRatio: 3.0 / 2.0,
                        cornerRadius: 0
                    )
                    Label(
                        photoData == nil ? "Add Photo" : "Change",
                        systemImage: photoData == nil ? "camera" : "pencil"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, AppSpacing.grid + 2)
                    .padding(.vertical, 6)
                    // Opaque rather than a material: the badge sits over an
                    // arbitrary photo, and a translucent chip over a busy
                    // image is unreadable.
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(AppSpacing.grid + 2)
                }
            }
            .buttonStyle(.plain)
            // Lets the photo bleed to the section's edges instead of sitting
            // inside the default row insets.
            .listRowInsets(EdgeInsets())
            .accessibilityLabel(photoData == nil ? "Add photo" : "Change photo")
        } footer: {
            Text("Photos are stored on-device only.")
        }
    }

    /// Shrinks a camera/library image before it's stored. `photoData` is
    /// decoded at render time, and the grid decodes many at once while
    /// scrolling — a full-resolution 12MP capture is several hundred times
    /// more pixels than a ~180pt card can show. Done on the way in rather
    /// than at render so the cost is paid once, and so the
    /// externalStorage files stay small. Returns the original untouched if
    /// it's already small enough or can't be decoded.
    private static func downsampled(_ data: Data, maxDimension: CGFloat = 1200) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return data }

        let scale = maxDimension / longestSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }

    private var curveFooter: String {
        guard usesCurve, let curve = depreciationService.curve(id: type.rawValue) else {
            return "Defaults to what you paid. The value here is used as-is in your net worth and won't change on its own."
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

    /// Mirrors InventoryView's own delete: cancel the reminders first, since
    /// their identifiers embed the asset id and would otherwise still fire.
    private func deleteItem() {
        guard let item else { return }
        reminderService.cancelReminders(assetId: item.id)
        modelContext.delete(item)
        dismiss()
    }

    private func save() {
        let curveId = usesCurve ? type.rawValue : nil
        let value = usesCurve ? (estimatedValue ?? acquisitionCost ?? 0) : effectiveManualValue
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
