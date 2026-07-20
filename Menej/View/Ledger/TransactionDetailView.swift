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
    @Bindable var transaction: Transaction
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                if let merchant = transaction.merchant {
                    LabeledContent("Title") {
                        Text(merchant)
                    }
                }
                LabeledContent("Amount") {
                    AmountText(amount: transaction.signedAmount, showSign: true)
                }
                LabeledContent("Date") {
                    Text(transaction.date, style: .date)
                }
                LabeledContent("Description") {
                    Text(transaction.rawDescription)
                }
                if let category = transaction.categoryId {
                    LabeledContent("Category") {
                        CategoryChip(category: category)
                    }
                }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            TransactionEditView(transaction: transaction)
        }
    }
}

/// Edits title (merchant), amount, date, and description. Direction
/// (debit/credit) and account aren't editable here — see PRD §12 Open
/// Question 2, which only scopes edits to the parsed field values.
private struct TransactionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allTransactions: [Transaction]
    @Bindable var transaction: Transaction
    @State private var viewModel = LedgerViewModel()

    @State private var title = ""
    @State private var amount: Decimal?
    @State private var date = Date()
    @State private var description = ""
    @State private var category: Category = .other

    private var canSave: Bool {
        (amount ?? 0) > 0 && !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Amount", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Description", text: $description, axis: .vertical)
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: populateFromExisting)
        }
    }

    private func populateFromExisting() {
        title = transaction.merchant ?? ""
        amount = transaction.amount
        date = transaction.date
        description = transaction.rawDescription
        category = transaction.categoryId ?? .other
    }

    private func save() {
        // Uses the pre-edit merchant to propagate the category correction,
        // same as the retroactive matching in `correctCategory` itself.
        if category != transaction.categoryId {
            viewModel.correctCategory(for: transaction, to: category, allTransactions: allTransactions)
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        transaction.merchant = trimmedTitle.isEmpty ? nil : trimmedTitle
        transaction.amount = amount ?? transaction.amount
        transaction.date = date
        transaction.rawDescription = description.trimmingCharacters(in: .whitespaces)
        transaction.isEdited = true
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        TransactionDetailView(transaction: Transaction(accountId: UUID(), date: .now, amount: 45_000, direction: .debit, rawDescription: "INDOMARET JAKARTA"))
    }
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
