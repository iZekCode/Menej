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

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var viewModel = LedgerViewModel()

    /// `transactions` is already sorted newest-first, so grouping preserves
    /// that order within and across days.
    private var groupedTransactions: [(day: Date, transactions: [Transaction])] {
        let groups = Dictionary(grouping: transactions) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
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
                    ForEach(groupedTransactions, id: \.day) { group in
                        Section(sectionTitle(for: group.day)) {
                            ForEach(group.transactions) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                            }
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
        }
    }

    private func sectionTitle(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: day)
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
