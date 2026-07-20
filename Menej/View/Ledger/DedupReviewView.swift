//
//  DedupReviewView.swift
//  Menej
//
//  Surfaces DedupService candidates for the user to confirm or reject —
//  see PRD §6 F4: "Pairs landing in the grey zone go to the user rather
//  than being decided by the app."
//

import SwiftUI
import SwiftData

struct DedupReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var transactions: [Transaction]
    @State private var viewModel = LedgerViewModel()

    var body: some View {
        List {
            if viewModel.pendingDedupCandidates.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No possible duplicates",
                    message: "Menej checks new imports against your existing ledger for transfers between your own accounts and expenses recorded by more than one source."
                )
            } else {
                Section {
                    ForEach(Array(viewModel.pendingDedupCandidates.enumerated()), id: \.offset) { _, candidate in
                        if let first = transactions.first(where: { $0.id == candidate.transactionId }),
                           let second = transactions.first(where: { $0.id == candidate.matchedTransactionId }) {
                            DedupCandidateRow(first: first, second: second, candidate: candidate)
                                .swipeActions(edge: .trailing) {
                                    Button("Confirm", systemImage: "checkmark") {
                                        viewModel.confirmMatch(candidate, in: transactions)
                                        try? modelContext.save()
                                    }
                                    .tint(AppColor.gain)
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Not a match", systemImage: "xmark") {
                                        viewModel.rejectMatch(candidate)
                                    }
                                    .tint(AppColor.loss)
                                }
                        }
                    }
                } footer: {
                    Text("Auto-Resolve confirms transfers over Rp100,000, and rejects everything else — smaller transfers and all duplicate expenses.")
                }
            }
        }
        .navigationTitle("Possible Duplicates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Auto-Resolve") {
                    viewModel.bulkResolvePendingCandidates(in: transactions, transferAmountThreshold: 100_000)
                    try? modelContext.save()
                }
                .disabled(viewModel.pendingDedupCandidates.isEmpty)
            }
        }
        .onAppear {
            viewModel.refreshDedupCandidates(transactions: transactions)
        }
    }
}

private struct DedupCandidateRow: View {
    let first: Transaction
    let second: Transaction
    let candidate: DedupCandidate

    private var isTransfer: Bool { first.direction != second.direction }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.grid) {
            Label(
                isTransfer ? "Possible transfer between your accounts" : "Possible duplicate expense",
                systemImage: isTransfer ? "arrow.left.arrow.right" : "doc.on.doc"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            row(for: first)
            Divider()
            row(for: second)

            if !candidate.isConfidentMatch {
                Text("Lower confidence match — review carefully.")
                    .font(.caption)
                    .foregroundStyle(AppColor.loss)
            }
        }
        .padding(.vertical, 4)
    }

    private func row(for transaction: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.merchant ?? transaction.rawDescription)
                    .lineLimit(1)
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: transaction.signedAmount, showSign: true)
        }
    }
}

#Preview {
    NavigationStack {
        DedupReviewView()
            .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
    }
}
