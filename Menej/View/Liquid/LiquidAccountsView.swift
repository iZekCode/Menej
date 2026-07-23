//
//  LiquidAccountsView.swift
//  Menej
//
//  The "Liquid" half of net worth (PRD §6 F5) — the three issuer accounts,
//  their current balances, and the transfers between them.
//
//  Balances roll forward from an anchor (LiquidBalanceService); only myBCA
//  prints one, so GoPay/Grab are anchored by hand here. Accounts can also be
//  created before any statement is imported, so a balance can be recorded on
//  day one.
//

import SwiftUI
import SwiftData

struct LiquidAccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]

    @State private var accountBeingEdited: Account?
    @State private var isAddingManualAccount = false

    private let balanceService = LiquidBalanceService()
    private let transferService = TransferService()

    /// How many transfers the summary section shows before deferring to the
    /// full history.
    private static let recentTransferLimit = 5

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack
    // from the Breakdown card.
    var body: some View {
        List {
            if accounts.isEmpty {
                EmptyStateView(
                    systemImage: "banknote",
                    title: "No accounts yet",
                    message: "Add MyBCA, GoPay, or Grab to record a balance, or import a statement to create one automatically."
                )
            } else {
                summarySection
                accountsSection
                transfersSection
            }
        }
        // Matches PortfolioView — List's default section spacing is wider than
        // the AppSpacing.margin rhythm the rest of the app uses between blocks.
        .listSectionSpacing(AppSpacing.margin)
        .navigationTitle("Liquid")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // The three parseable providers are offered only while
                    // they don't exist yet — each is a single identity that
                    // imports look up by issuer. "Other" has no such limit.
                    ForEach(missingIssuers) { issuer in
                        Button(issuer.displayName) { addAccount(for: issuer) }
                    }
                    if !missingIssuers.isEmpty {
                        Divider()
                    }
                    Button("Other Account…") { isAddingManualAccount = true }
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
        .sheet(item: $accountBeingEdited) { account in
            AccountBalanceFormView(mode: .edit(account))
        }
        .sheet(isPresented: $isAddingManualAccount) {
            AccountBalanceFormView(mode: .addManual)
        }
    }

    // MARK: - Sections

    /// Same shape as PortfolioView's and InventoryView's headline: label,
    /// inline eye, total. All three are net-worth components reached from the
    /// same Breakdown card, so they should open the same way — and this
    /// figure is the one that card shows for "Liquid".
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AppSpacing.grid) {
                    Text("Total Liquid")
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
                AmountText(amount: liquidTotal, isHidden: appState.areAmountsHidden)
                    .font(.title.bold())
                // An unanchored account still rolls forward from zero, so it
                // contributes a figure that isn't a real balance. Say so
                // rather than letting the total imply more than it knows.
                if unanchoredCount > 0 {
                    Text(unanchoredCount == 1
                         ? "1 account has no balance set."
                         : "\(unanchoredCount) accounts have no balance set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var accountsSection: some View {
        Section {
            ForEach(sortedAccounts) { account in
                Button {
                    accountBeingEdited = account
                } label: {
                    AccountRow(
                        account: account,
                        balance: balances[account.id] ?? account.balance,
                        isHidden: appState.areAmountsHidden
                    )
                }
                .buttonStyle(.plain)
                // Only hand-added accounts can be removed. A statement-backed
                // account owns imported transactions and is what an import
                // looks up by issuer — deleting it would orphan the former
                // and silently recreate the latter on the next import.
                .swipeActions(edge: .trailing) {
                    if account.issuer == .manual {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            modelContext.delete(account)
                        }
                    }
                }
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Tap an account to set its balance. Transactions dated after that are added automatically.")
        }
    }

    @ViewBuilder
    private var transfersSection: some View {
        let transfers = derivedTransfers
        Section {
            if transfers.isEmpty {
                Text("No transfers between your accounts yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transfers.prefix(Self.recentTransferLimit)) { transfer in
                    TransferRow(
                        transfer: transfer,
                        accountsById: accountsById,
                        isHidden: appState.areAmountsHidden
                    )
                }
                if transfers.count > Self.recentTransferLimit {
                    NavigationLink {
                        TransferHistoryView()
                    } label: {
                        Text("See all \(transfers.count) transfers")
                            .font(.subheadline)
                    }
                }
            }
        } header: {
            Text("Transfers")
        }
    }

    // MARK: - Derived data

    private var balances: [UUID: Decimal] {
        balanceService.balances(accounts: accounts, transactions: transactions)
    }

    /// Summed exactly the way `NetWorthHomeView.liquidTotal` does it, so the
    /// headline here and the Breakdown row that leads to it can't disagree.
    private var liquidTotal: Decimal {
        balances.values.reduce(Decimal(0), +)
    }

    private var unanchoredCount: Int {
        accounts.filter { !$0.hasBalanceAnchor }.count
    }

    private var derivedTransfers: [DerivedTransfer] {
        transferService.derive(transactions: transactions, accounts: accounts)
    }

    private var accountsById: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    /// Bank first, then e-wallets — matches how the money actually flows
    /// (salary lands in BCA and is topped up outward from there).
    private var sortedAccounts: [Account] {
        accounts.sorted { a, b in
            if (a.type == .bankAccount) != (b.type == .bankAccount) { return a.type == .bankAccount }
            return a.displayName < b.displayName
        }
    }

    private var missingIssuers: [Issuer] {
        Issuer.statementIssuers.filter { issuer in !accounts.contains { $0.issuer == issuer } }
    }

    private func addAccount(for issuer: Issuer) {
        // Same issuer→type mapping the import path uses when it auto-creates
        // an account (ImportViewModel.findOrCreateAccount).
        let type: AssetType = issuer == .bcaMyBCA ? .bankAccount : .eWallet
        let account = Account(issuer: issuer, type: type)
        modelContext.insert(account)
        accountBeingEdited = account
    }
}

// MARK: - Rows

private struct AccountRow: View {
    let account: Account
    let balance: Decimal
    var isHidden: Bool = false

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                // Now that accounts can be cash as well as bank/e-wallet, the
                // icon comes from the type itself rather than a two-way test.
                Image(systemName: account.type.systemImage)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if account.hasBalanceAnchor {
                AmountText(amount: balance, isHidden: isHidden)
                    .font(.subheadline)
            } else {
                Text("Not set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// States the balance's provenance plainly — a figure the user typed
    /// three months ago shouldn't look like one read off a statement.
    private var subtitle: String {
        guard let lastSyncedAt = account.lastSyncedAt else {
            return "\(account.type.displayName) · balance not set"
        }
        let date = lastSyncedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
        return account.isBalanceManual
            ? "as of \(date) · set manually"
            : "as of \(date) · from statement"
    }
}

/// One derived movement between two of the user's own accounts.
struct TransferRow: View {
    let transfer: DerivedTransfer
    let accountsById: [UUID: Account]
    var isHidden: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name(transfer.fromAccountId))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(name(transfer.toAccountId))
                }
                .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: transfer.amount, isHidden: isHidden)
                .font(.subheadline)
        }
    }

    private func name(_ id: UUID?) -> String {
        guard let id, let account = accountsById[id] else { return "Unknown" }
        return account.displayName
    }

    private var subtitle: String {
        var parts = [transfer.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))]
        if let fee = transfer.fee {
            parts.append("\(AmountText.string(amount: fee)) fee")
        }
        // Never let an inference read as a confirmed fact.
        if transfer.isInferred {
            parts.append("matched by description")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Balance form

/// Editing an existing account and creating a hand-added one share this form:
/// the fields are the same balance anchor either way, and only what Save does
/// differs. Same shape as PortfolioView's HoldingFormView.
private struct AccountBalanceFormView: View {
    enum Mode {
        case edit(Account)
        /// A new `.manual` account. Nothing is inserted until Save, so
        /// cancelling can't leave a nameless empty account behind.
        case addManual

        var account: Account? {
            if case .edit(let account) = self { return account }
            return nil
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode

    @State private var nickname: String
    @State private var type: AssetType
    @State private var balance: Decimal?
    @State private var asOf: Date

    init(mode: Mode) {
        self.mode = mode
        let account = mode.account
        _nickname = State(initialValue: account?.nickname ?? "")
        _type = State(initialValue: account?.type ?? .bankAccount)
        // Only prefill an anchor that actually exists — a stored 0 from an
        // account that was never anchored isn't a balance the user set.
        let isAnchored = account?.hasBalanceAnchor ?? false
        _balance = State(initialValue: isAnchored ? account?.balance : nil)
        _asOf = State(initialValue: (isAnchored ? account?.lastSyncedAt : nil) ?? Date())
    }

    /// The three parseable providers have a fixed kind — MyBCA is a bank,
    /// GoPay and Grab are wallets — so the picker is only meaningful for a
    /// hand-added account.
    private static let manualTypes: [AssetType] = [.bankAccount, .eWallet, .cash]

    private var issuer: Issuer { mode.account?.issuer ?? .manual }
    private var isManual: Bool { issuer == .manual }

    /// A hand-added account has no issuer name to fall back on, so its name
    /// is the only thing that distinguishes it from another one.
    private var canSave: Bool {
        guard balance != nil else { return false }
        return !isManual || !nickname.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(namePrompt, text: $nickname)
                    if isManual {
                        Picker("Kind", selection: $type) {
                            ForEach(Self.manualTypes) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                    }
                } header: {
                    Text("Name")
                } footer: {
                    Text(isManual
                         ? "Shown wherever this account appears."
                         : "Leave blank to use \(issuer.displayName).")
                }

                Section {
                    TextField("Balance", value: $balance, format: .number)
                        .keyboardType(.decimalPad)
                    DatePicker("As of", selection: $asOf, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text(balanceFooter)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.account == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var title: String {
        mode.account.map(\.displayName) ?? "New Account"
    }

    private var namePrompt: String {
        isManual ? "Name (Jago, Mandiri, Wallet…)" : issuer.displayName
    }

    private var balanceFooter: String {
        switch issuer {
        case .bcaMyBCA:
            return "Transactions after this date are added automatically. Importing a myBCA statement replaces this with its printed closing balance."
        case .manual:
            // No statement will ever arrive for this one, so nothing will
            // ever roll it forward — say so rather than implying upkeep the
            // app can't do.
            return "This account has no statement to import, so its balance only changes when you edit it here."
        default:
            return "\(issuer.displayName) statements don't print a balance, so this is the only way to set one. Transactions after this date are added automatically."
        }
    }

    private func save() {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        let account: Account
        switch mode {
        case .edit(let existing):
            account = existing
            if isManual { account.type = type }
        case .addManual:
            account = Account(issuer: .manual, type: type)
            modelContext.insert(account)
        }

        account.nickname = trimmed.isEmpty ? nil : trimmed
        account.balance = balance ?? 0
        account.lastSyncedAt = asOf
        account.isBalanceManual = true
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LiquidAccountsView()
    }
    .environment(AppState())
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
