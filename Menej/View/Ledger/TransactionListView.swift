//
//  TransactionListView.swift
//  Menej
//
//  Simple list screen — queries directly per Appendix C notes. The AI
//  enhancement action is real logic, so it's driven by LedgerViewModel
//  rather than living inline here.
//

import SwiftUI
import SwiftData

/// Ledger date-range filter. `.custom` reads the separate start/end state on
/// the view, so the enum stays a plain Hashable value the Picker can bind to.
private enum LedgerDateRange: Hashable {
    case all, last7, last30, last90, custom
}

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]
    @State private var viewModel = LedgerViewModel()
    @State private var dateFilter: LedgerDateRange = .all
    @State private var isPickingFilter = false
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var customEnd = Date.now
    // Empty set = no filter (everything shown); a non-empty set narrows to
    // exactly those sources/categories — so filtering to one category is a
    // single tap, not unchecking every other one.
    @State private var selectedIssuers: Set<Issuer> = []
    @State private var selectedCategories: Set<Category> = []

    /// Resolves each transaction's source issuer (Grab / GoPay / myBCA) for
    /// the per-row tag — Transaction only stores `accountId`.
    private var issuerByAccount: [UUID: Issuer] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.issuer) })
    }

    /// Half-open [start, end) window for the active filter; nil means All Time.
    private var activeRange: Range<Date>? {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: .now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? .now
        // "Last N days" = today plus the previous N-1 days.
        func window(_ days: Int) -> Range<Date> {
            (cal.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday)..<endOfToday
        }
        switch dateFilter {
        case .all: return nil
        case .last7: return window(7)
        case .last30: return window(30)
        case .last90: return window(90)
        case .custom:
            let start = cal.startOfDay(for: customStart)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd)) ?? customEnd
            return start..<end
        }
    }

    /// Sources/categories actually present in the data — the filter sheet only
    /// offers options the user could meaningfully pick.
    private var availableIssuers: [Issuer] {
        let present = Set(transactions.compactMap { issuerByAccount[$0.accountId] })
        return Issuer.allCases.filter { present.contains($0) }
    }

    private var availableCategories: [Category] {
        let present = Set(transactions.map { $0.categoryId ?? .other })
        return Category.allCases.filter { present.contains($0) }
    }

    private var isFiltering: Bool {
        dateFilter != .all || !selectedIssuers.isEmpty || !selectedCategories.isEmpty
    }

    private var filteredTransactions: [Transaction] {
        transactions.filter { transaction in
            if let range = activeRange, !range.contains(transaction.date) { return false }
            if !selectedIssuers.isEmpty {
                guard let issuer = issuerByAccount[transaction.accountId], selectedIssuers.contains(issuer) else { return false }
            }
            if !selectedCategories.isEmpty {
                guard selectedCategories.contains(transaction.categoryId ?? .other) else { return false }
            }
            return true
        }
    }

    /// `filteredTransactions` is already sorted newest-first, so grouping
    /// preserves that order within and across days.
    private var groupedTransactions: [(day: Date, transactions: [Transaction])] {
        let groups = Dictionary(grouping: filteredTransactions) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    private var filterDescription: String {
        switch dateFilter {
        case .all: return "All time"
        case .last7: return "Last 7 days"
        case .last30: return "Last 30 days"
        case .last90: return "Last 90 days"
        case .custom:
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM yyyy"
            return "\(formatter.string(from: customStart)) – \(formatter.string(from: customEnd))"
        }
    }

    /// One-line recap of every active filter, for the header chip.
    private var activeFilterSummary: String {
        var parts: [String] = []
        if dateFilter != .all { parts.append(filterDescription) }
        if !selectedIssuers.isEmpty {
            let names = availableIssuers.filter { selectedIssuers.contains($0) }.map(\.displayName)
            parts.append(names.joined(separator: ", "))
        }
        if !selectedCategories.isEmpty {
            let names = availableCategories.filter { selectedCategories.contains($0) }.map(\.displayName)
            parts.append(names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) categories")
        }
        return parts.joined(separator: " · ")
    }

    private func clearFilters() {
        dateFilter = .all
        selectedIssuers = []
        selectedCategories = []
    }

    var body: some View {
        NavigationStack {
            List {
                if let progress = viewModel.enhancementProgress {
                    Section {
                        HStack {
                            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                            Text("\(progress.completed)/\(progress.total)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel", role: .destructive) {
                            viewModel.cancelEnhancement()
                        }
                    }
                }

                if transactions.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.rectangle",
                        title: "No transactions yet",
                        message: "Import a statement to see your transactions here."
                    )
                } else {
                    if isFiltering {
                        Section {
                            HStack {
                                // Tapping the summary reopens the sheet to edit
                                // the active filter; only the Clear button clears.
                                // `.borderless` makes each a separate hit target
                                // instead of the whole row triggering one action.
                                Button {
                                    isPickingFilter = true
                                } label: {
                                    Label(activeFilterSummary, systemImage: "line.3.horizontal.decrease.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.borderless)
                                Spacer()
                                Button("Clear") { clearFilters() }
                                    .font(.subheadline)
                                    .buttonStyle(.borderless)
                            }
                        }
                    }

                    if filteredTransactions.isEmpty {
                        EmptyStateView(
                            systemImage: "calendar.badge.exclamationmark",
                            title: "No transactions in this range",
                            message: "Try a wider date range or clear the filter."
                        )
                    } else {
                        ForEach(groupedTransactions, id: \.day) { group in
                            Section(sectionTitle(for: group.day)) {
                                ForEach(group.transactions) { transaction in
                                    NavigationLink {
                                        TransactionDetailView(transaction: transaction)
                                    } label: {
                                        TransactionRow(transaction: transaction, issuer: issuerByAccount[transaction.accountId])
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            modelContext.delete(transaction)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ledger")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPickingFilter = true
                    } label: {
                        Label(
                            "Filter",
                            systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink {
                        DedupReviewView()
                    } label: {
                        Label("Review Duplicates", systemImage: "arrow.left.arrow.right")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        viewModel.startEnhancement(transactions: transactions, modelContext: modelContext)
                    } label: {
                        Label("Enhance with AI", systemImage: "sparkles")
                    }
                    .disabled(viewModel.enhancementProgress != nil || transactions.isEmpty)
                }
            }
            .alert(
                "Can't Enhance with AI",
                isPresented: Binding(
                    get: { viewModel.enhancementError != nil },
                    set: { if !$0 { viewModel.enhancementError = nil } }
                )
            ) {
                Button("OK") { viewModel.enhancementError = nil }
            } message: {
                Text(viewModel.enhancementError ?? "")
            }
            .sheet(isPresented: $isPickingFilter) {
                LedgerFilterSheet(
                    filter: $dateFilter,
                    start: $customStart,
                    end: $customEnd,
                    selectedIssuers: $selectedIssuers,
                    selectedCategories: $selectedCategories,
                    availableIssuers: availableIssuers,
                    availableCategories: availableCategories
                )
            }
        }
    }

    private func sectionTitle(for day: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        // Today/Yesterday keep the date, e.g. "Today, 21 July 2026"; other days
        // lead with the weekday name via `.full`, e.g. "Tuesday, 21 July 2026".
        formatter.dateStyle = .long
        let dateString = formatter.string(from: day)
        if calendar.isDateInToday(day) { return "Today, \(dateString)" }
        if calendar.isDateInYesterday(day) { return "Yesterday, \(dateString)" }
        formatter.dateStyle = .full
        return formatter.string(from: day)
    }
}

/// Shared ledger-style row (title, source + category tags, signed amount).
/// Also reused by the Insights month transactions list.
struct TransactionRow: View {
    let transaction: Transaction
    let issuer: Issuer?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant ?? transaction.rawDescription)
                HStack(spacing: 6) {
                    if let issuer {
                        IssuerTag(issuer: issuer)
                    }
                    if let category = transaction.categoryId {
                        CategoryChip(category: category)
                    }
                }
            }
            Spacer()
            AmountText(amount: transaction.signedAmount, showSign: true)
        }
    }
}

/// Small source tag showing which statement a transaction came from
/// (Grab / GoPay / myBCA), tinted in each provider's brand color. Same font
/// size and pill height as the category chip beside it.
struct IssuerTag: View {
    let issuer: Issuer

    var body: some View {
        Text(issuer.displayName)
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, AppSpacing.grid)
            .padding(.vertical, 4)
            .background(brandColor.opacity(0.18), in: Capsule())
            .foregroundStyle(brandColor)
    }

    /// Provider brand colors, with a lighter step for dark mode so the tint
    /// stays legible on a dark surface. Grab green, GoPay cyan, BCA blue —
    /// distinct from each other and from the lilac category chip.
    private var brandColor: Color {
        switch issuer {
        case .grab:     return Color(light: "#00A651", dark: "#3AD183")
        case .gopay:    return Color(light: "#00AAD6", dark: "#3EC6EC")
        case .bcaMyBCA: return Color(light: "#0060AF", dark: "#5AA6E8")
        // A hand-added account has no brand to borrow a color from. Neutral
        // gray, so it never reads as a fourth provider.
        case .manual:   return Color(light: "#6E6E73", dark: "#98989D")
        }
    }
}

/// Half-sheet date filter: preset quick ranges and a manual start/end range in
/// one place. Edits happen on local drafts so Cancel leaves the active filter
/// untouched; Apply commits everything at once. Adjusting either date picker
/// implicitly selects the custom range.
private struct LedgerFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: LedgerDateRange
    @Binding var start: Date
    @Binding var end: Date
    @Binding var selectedIssuers: Set<Issuer>
    @Binding var selectedCategories: Set<Category>
    let availableIssuers: [Issuer]
    let availableCategories: [Category]

    @State private var draftFilter: LedgerDateRange
    @State private var draftStart: Date
    @State private var draftEnd: Date
    @State private var draftIssuers: Set<Issuer>
    @State private var draftCategories: Set<Category>

    // Drafts are seeded in init (not `.onAppear`) so the date-picker onChange
    // handlers don't misfire during setup and force `.custom`.
    init(
        filter: Binding<LedgerDateRange>,
        start: Binding<Date>,
        end: Binding<Date>,
        selectedIssuers: Binding<Set<Issuer>>,
        selectedCategories: Binding<Set<Category>>,
        availableIssuers: [Issuer],
        availableCategories: [Category]
    ) {
        _filter = filter
        _start = start
        _end = end
        _selectedIssuers = selectedIssuers
        _selectedCategories = selectedCategories
        self.availableIssuers = availableIssuers
        self.availableCategories = availableCategories
        _draftFilter = State(initialValue: filter.wrappedValue)
        _draftStart = State(initialValue: start.wrappedValue)
        _draftEnd = State(initialValue: end.wrappedValue)
        _draftIssuers = State(initialValue: selectedIssuers.wrappedValue)
        _draftCategories = State(initialValue: selectedCategories.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    presetRow("All Time", .all, subtitle: "Every transaction")
                    presetRow("Last 7 Days", .last7, subtitle: presetRangeText(.last7))
                    presetRow("Last 30 Days", .last30, subtitle: presetRangeText(.last30))
                    presetRow("Last 90 Days", .last90, subtitle: presetRangeText(.last90))

                    // One row so the pickers sit tight under the label instead
                    // of a full inter-row gap.
                    VStack(alignment: .leading, spacing: AppSpacing.grid) {
                        Button {
                            draftFilter = .custom
                        } label: {
                            filterRow(title: "Custom Range", subtitle: nil, isSelected: draftFilter == .custom)
                        }
                        .buttonStyle(.plain)
                        HStack(alignment: .top, spacing: AppSpacing.margin) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("From").font(.caption).foregroundStyle(.secondary)
                                DatePicker("From", selection: $draftStart, in: ...draftEnd, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To").font(.caption).foregroundStyle(.secondary)
                                DatePicker("To", selection: $draftEnd, in: draftStart..., displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                if !availableIssuers.isEmpty {
                    Section {
                        ForEach(availableIssuers) { issuer in
                            multiSelectRow(title: issuer.displayName, isSelected: draftIssuers.contains(issuer)) {
                                if draftIssuers.contains(issuer) { draftIssuers.remove(issuer) }
                                else { draftIssuers.insert(issuer) }
                            }
                        }
                    } header: {
                        sectionHeader("Source", isFiltered: !draftIssuers.isEmpty) {
                            draftIssuers = []
                        }
                    }
                }

                if !availableCategories.isEmpty {
                    Section {
                        ForEach(availableCategories) { category in
                            multiSelectRow(title: category.displayName, systemImage: category.systemImage, isSelected: draftCategories.contains(category)) {
                                if draftCategories.contains(category) { draftCategories.remove(category) }
                                else { draftCategories.insert(category) }
                            }
                        }
                    } header: {
                        sectionHeader("Category", isFiltered: !draftCategories.isEmpty) {
                            draftCategories = []
                        }
                    } footer: {
                        Text("Pick the sources and categories you want. Leave a group unselected to include all of them.")
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = draftFilter
                        start = draftStart
                        end = draftEnd
                        selectedIssuers = draftIssuers
                        selectedCategories = draftCategories
                        dismiss()
                    }
                }
            }
            .onChange(of: draftStart) { draftFilter = .custom }
            .onChange(of: draftEnd) { draftFilter = .custom }
        }
        .presentationDetents([.large])
    }

    private func presetRow(_ title: String, _ value: LedgerDateRange, subtitle: String?) -> some View {
        Button {
            draftFilter = value
        } label: {
            filterRow(title: title, subtitle: subtitle, isSelected: draftFilter == value)
        }
        .buttonStyle(.plain)
    }

    private func filterRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AppColor.accent : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Section header with a right-aligned Clear button, shown only while the
    /// group is narrowing the results. Clearing re-selects everything.
    private func sectionHeader(_ title: String, isFiltered: Bool, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isFiltered {
                Button("Clear", action: clear)
                    .font(.caption)
                    .textCase(nil)
            }
        }
    }

    /// Multi-select row (source / category): a trailing checkmark when chosen.
    private func multiSelectRow(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.grid + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                }
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The concrete date range a preset resolves to, for the row subtitle.
    private func presetRangeText(_ value: LedgerDateRange) -> String? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func windowStart(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        }
        switch value {
        case .last7: return dateRangeString(windowStart(7), today)
        case .last30: return dateRangeString(windowStart(30), today)
        case .last90: return dateRangeString(windowStart(90), today)
        default: return nil
        }
    }

    private func dateRangeString(_ from: Date, _ to: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return "\(formatter.string(from: from)) – \(formatter.string(from: to))"
    }
}

#Preview {
    TransactionListView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
