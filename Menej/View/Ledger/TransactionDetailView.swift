//
//  TransactionDetailView.swift
//  Menej
//
//  Users can edit parsed transactions, but edits are marked `isEdited` and
//  the original value is retained — see PRD §12 Open Question 2.
//

import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTransactions: [Transaction]
    @Bindable var transaction: Transaction
    @State private var viewModel = LedgerViewModel()

    var body: some View {
        List {
            Section {
                LabeledContent("Amount") {
                    AmountText(amount: transaction.signedAmount, showSign: true)
                }
                LabeledContent("Date") {
                    Text(transaction.date, style: .date)
                }
                LabeledContent("Description") {
                    Text(transaction.rawDescription)
                }
            }

            Section("Category") {
                Picker("Category", selection: Binding(
                    get: { transaction.categoryId ?? .other },
                    set: { newValue in
                        viewModel.correctCategory(for: transaction, to: newValue, allTransactions: allTransactions)
                        try? modelContext.save()
                    }
                )) {
                    ForEach(Category.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                .pickerStyle(.menu)
            }

            if transaction.isTransfer {
                Section {
                    Label("This is a transfer between your own accounts", systemImage: "arrow.left.arrow.right")
                        .foregroundStyle(.secondary)
                }
            }

            if transaction.isEdited {
                Section {
                    Label("Edited from the original parsed value", systemImage: "pencil")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Transaction")
    }
}

#Preview {
    NavigationStack {
        TransactionDetailView(transaction: Transaction(accountId: UUID(), date: .now, amount: 45_000, direction: .debit, rawDescription: "INDOMARET JAKARTA"))
    }
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
