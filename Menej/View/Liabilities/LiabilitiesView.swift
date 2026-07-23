//
//  LiabilitiesView.swift
//  Menej
//
//  What you owe (PRD §6 F5). The `Liability` schema has been in place since
//  day one so net worth and snapshots wouldn't need retrofitting; this is the
//  screen that finally lets one exist.
//
//  Everything here is hand-entered. No statement the app parses carries a loan
//  or card balance, so unlike an account there's nothing to roll forward and
//  nothing to reconcile against — the figure is exactly what the user last
//  typed.
//

import SwiftUI
import SwiftData

struct LiabilitiesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var liabilities: [Liability]

    @State private var liabilityBeingEdited: Liability?
    @State private var isAddingLiability = false

    private let netWorthService = NetWorthService()

    private var sortedLiabilities: [Liability] {
        liabilities.sorted { $0.outstanding > $1.outstanding }
    }

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack
    // from the Breakdown card.
    var body: some View {
        List {
            if liabilities.isEmpty {
                EmptyStateView(
                    systemImage: "creditcard",
                    title: "Nothing owed",
                    message: "Add a loan, credit card balance, or anything else you owe, and it's subtracted from your net worth."
                )
            } else {
                summarySection
                Section {
                    ForEach(sortedLiabilities) { liability in
                        Button {
                            liabilityBeingEdited = liability
                        } label: {
                            LiabilityRow(liability: liability, isHidden: appState.areAmountsHidden)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Tap to edit. Swipe to remove.")
                }
            }
        }
        .listSectionSpacing(AppSpacing.margin)
        .navigationTitle("Liabilities")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Liability", systemImage: "plus") {
                    isAddingLiability = true
                }
            }
        }
        .sheet(isPresented: $isAddingLiability) {
            LiabilityFormView(mode: .add)
        }
        .sheet(item: $liabilityBeingEdited) { liability in
            LiabilityFormView(mode: .edit(liability))
        }
    }

    /// Same headline shape as Liquid, Portfolio and Inventory — but this one
    /// is money owed, so it's rendered in the loss color with a minus. A bare
    /// positive total here would read as an asset.
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AppSpacing.grid) {
                    Text("Total Owed")
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
                if appState.areAmountsHidden {
                    Text(verbatim: "••••••")
                        .font(.title.bold())
                        .numericStyle()
                } else {
                    Text("-\(AmountText.string(amount: netWorthService.totalLiabilities(liabilities)))")
                        .font(.title.bold())
                        .numericStyle()
                        .foregroundStyle(AppColor.loss)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sortedLiabilities[index])
        }
    }
}

private struct LiabilityRow: View {
    let liability: Liability
    var isHidden: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(liability.type)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isHidden {
                Text(verbatim: "••••••")
                    .font(.subheadline)
                    .numericStyle()
            } else {
                Text("-\(AmountText.string(amount: liability.outstanding))")
                    .font(.subheadline)
                    .numericStyle()
                    .foregroundStyle(AppColor.loss)
            }
        }
        .contentShape(Rectangle())
    }

    /// Interest rate and due date are both optional in practice (a 0% rate and
    /// no date are both normal), so the line only states what's actually set.
    private var subtitle: String {
        var parts: [String] = []
        if liability.interestRate > 0 {
            let percent = (liability.interestRate * 100).formatted(.number.precision(.fractionLength(0...2)))
            parts.append("\(percent)% p.a.")
        }
        if let dueDate = liability.dueDate {
            let date = dueDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
            parts.append(dueDate > .now ? "due \(date)" : "was due \(date)")
        }
        return parts.isEmpty ? "No rate or due date set" : parts.joined(separator: " · ")
    }
}

/// Adding and editing share one form — identical fields, only Save differs.
/// Same `Mode` pattern as HoldingFormView and AccountBalanceFormView.
private struct LiabilityFormView: View {
    enum Mode {
        case add
        case edit(Liability)

        var liability: Liability? {
            if case .edit(let liability) = self { return liability }
            return nil
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode

    @State private var type: String
    @State private var outstanding: Decimal?
    @State private var principal: Decimal?
    @State private var interestPercent: Double?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date

    init(mode: Mode) {
        self.mode = mode
        let liability = mode.liability
        _type = State(initialValue: liability?.type ?? "")
        _outstanding = State(initialValue: liability?.outstanding)
        _principal = State(initialValue: liability?.principal)
        // Stored as a fraction, entered as a percentage — 0.065 is a rate,
        // "6.5" is what a person types.
        _interestPercent = State(initialValue: liability.map { $0.interestRate * 100 })
        _hasDueDate = State(initialValue: liability?.dueDate != nil)
        _dueDate = State(initialValue: liability?.dueDate ?? Date())
    }

    /// Common kinds, offered as suggestions rather than a fixed Picker:
    /// `Liability.type` is a free String and the list of things a person can
    /// owe money on isn't one this app should try to enumerate.
    private static let suggestions = ["Credit Card", "Personal Loan", "Mortgage", "Car Loan", "Paylater"]

    private var canSave: Bool {
        !type.trimmingCharacters(in: .whitespaces).isEmpty && (outstanding ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kind (Credit Card, KPR…)", text: $type)
                    if type.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.grid) {
                                ForEach(Self.suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { type = suggestion }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                        .padding(.horizontal, AppSpacing.grid)
                                        .padding(.vertical, 4)
                                        .background(AppColor.accentSoft, in: Capsule())
                                        .foregroundStyle(AppColor.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Outstanding balance", value: $outstanding, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Original amount (optional)", value: $principal, format: .number)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("The outstanding balance is what's subtracted from your net worth.")
                }

                Section {
                    TextField("Interest rate % per year (optional)", value: $interestPercent, format: .number)
                        .keyboardType(.decimalPad)
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                if mode.liability != nil {
                    Section {
                        Button("Delete Liability", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(mode.liability == nil ? "Add Liability" : "Edit Liability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.liability == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func delete() {
        guard let liability = mode.liability else { return }
        modelContext.delete(liability)
        dismiss()
    }

    private func save() {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        let balance = outstanding ?? 0
        let rate = (interestPercent ?? 0) / 100
        let due = hasDueDate ? dueDate : nil

        switch mode {
        case .edit(let liability):
            liability.type = trimmed
            liability.outstanding = balance
            // Nothing borrowed less than what's still owed — an omitted
            // original amount defaults to the current balance rather than 0,
            // which would make any later payoff math nonsense.
            liability.principal = principal ?? balance
            liability.interestRate = rate
            liability.dueDate = due
        case .add:
            modelContext.insert(Liability(
                type: trimmed,
                principal: principal ?? balance,
                outstanding: balance,
                interestRate: rate,
                dueDate: due
            ))
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LiabilitiesView()
    }
    .environment(AppState())
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
