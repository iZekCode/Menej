//
//  TransferHistoryView.swift
//  Menej
//
//  Full history of movements between the user's own accounts, grouped by
//  month. Derived on the fly by TransferService from transactions already in
//  the ledger — nothing here is stored.
//

import SwiftUI
import SwiftData

struct TransferHistoryView: View {
    @Environment(AppState.self) private var appState
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]

    private let transferService = TransferService()

    // No NavigationStack of its own — pushed onto NetWorthHomeView's stack.
    var body: some View {
        List {
            if transfers.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.left.arrow.right",
                    title: "No transfers yet",
                    message: "Top-ups between your accounts appear here once both statements are imported, or when one side names the other."
                )
            } else {
                ForEach(groupedTransfers, id: \.month) { group in
                    Section(monthTitle(for: group.month)) {
                        ForEach(group.transfers) { transfer in
                            TransferRow(
                                transfer: transfer,
                                accountsById: accountsById,
                                isHidden: appState.areAmountsHidden
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.areAmountsHidden.toggle()
                } label: {
                    Image(systemName: appState.areAmountsHidden ? "eye.slash" : "eye")
                }
                .accessibilityLabel(appState.areAmountsHidden ? "Show amounts" : "Hide amounts")
            }
        }
    }

    private var transfers: [DerivedTransfer] {
        transferService.derive(transactions: transactions, accounts: accounts)
    }

    private var accountsById: [UUID: Account] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    /// Same date-grouping shape as the ledger (TransactionListView), one
    /// bucket coarser: transfers are rare enough that per-day sections would
    /// be mostly headers.
    private var groupedTransfers: [(month: Date, transfers: [DerivedTransfer])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: transfers) { transfer in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transfer.date)) ?? transfer.date
        }
        return groups
            .map { (month: $0.key, transfers: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.month > $1.month }
    }

    private func monthTitle(for month: Date) -> String {
        month.formatted(.dateTime.month(.wide).year())
    }
}

#Preview {
    NavigationStack {
        TransferHistoryView()
    }
    .environment(AppState())
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
