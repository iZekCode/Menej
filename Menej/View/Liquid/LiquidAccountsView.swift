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
            if !missingIssuers.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(missingIssuers) { issuer in
                            Button(issuer.displayName) { addAccount(for: issuer) }
                        }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $accountBeingEdited) { account in
            AccountBalanceFormView(account: account)
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
        Issuer.allCases.filter { issuer in !accounts.contains { $0.issuer == issuer } }
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
                Image(systemName: account.type == .bankAccount ? "building.columns" : "wallet.bifold")
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

private struct AccountBalanceFormView: View {
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var nickname = ""
    @State private var balance: Decimal?
    @State private var asOf = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(account.issuer.displayName, text: $nickname)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Leave blank to use \(account.issuer.displayName).")
                }

                Section {
                    TextField("Balance", value: $balance, format: .number)
                        .keyboardType(.decimalPad)
                    DatePicker("As of", selection: $asOf, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text(balanceFooter)
                }
            }
            .navigationTitle(account.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(balance == nil)
                }
            }
            .onAppear(perform: populateFromExisting)
        }
    }

    private var balanceFooter: String {
        account.issuer == .bcaMyBCA
            ? "Transactions after this date are added automatically. Importing a myBCA statement replaces this with its printed closing balance."
            : "\(account.issuer.displayName) statements don't print a balance, so this is the only way to set one. Transactions after this date are added automatically."
    }

    private func populateFromExisting() {
        nickname = account.nickname ?? ""
        // Only prefill an anchor that actually exists — a stored 0 from an
        // account that was never anchored isn't a balance the user set.
        if account.hasBalanceAnchor {
            balance = account.balance
            asOf = account.lastSyncedAt ?? Date()
        }
    }

    private func save() {
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
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
