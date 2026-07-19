//
//  TransactionListView.swift
//  Menej
//
//  Simple list screen — queries directly per Appendix C notes
//  (ViewModels are reserved for screens with real logic).
//

import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    var body: some View {
        NavigationStack {
            List {
                if transactions.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.rectangle",
                        title: "No transactions yet",
                        message: "Import a statement to see your transactions here."
                    )
                } else {
                    ForEach(transactions) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
            .navigationTitle("Ledger")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink {
                        DedupReviewView()
                    } label: {
                        Label("Review Duplicates", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
        }
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant ?? transaction.rawDescription)
                if let category = transaction.categoryId {
                    CategoryChip(category: category)
                }
            }
            Spacer()
            AmountText(amount: transaction.signedAmount, showSign: true)
        }
    }
}

#Preview {
    TransactionListView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
