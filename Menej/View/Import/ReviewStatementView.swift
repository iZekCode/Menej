//
//  ReviewStatementView.swift
//  Menej
//
//  Users always confirm before data enters the ledger — see PRD §6 F1.
//  No silent imports in v1.
//

import SwiftUI

struct ReviewStatementView: View {
    @Environment(\.dismiss) private var dismiss
    let statement: ParsedStatement
    var onConfirm: () -> Void = {}

    var body: some View {
        List {
            Section {
                ConfidenceBanner(confidence: statement.confidence, unaccountedAmount: statement.unaccountedAmount)
            }

            Section("\(statement.issuer.displayName) — \(statement.transactions.count) transactions") {
                ForEach(Array(statement.transactions.enumerated()), id: \.offset) { _, transaction in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(transaction.merchant ?? transaction.rawDescription)
                            Text(transaction.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountText(amount: transaction.signedAmount, showSign: true)
                    }
                }
            }
        }
        .navigationTitle("Review Statement")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    onConfirm()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReviewStatementView(statement: ParsedStatement(issuer: .bcaMyBCA, transactions: [], confidence: 0.72, unaccountedAmount: 15_000, closingBalance: nil))
    }
}
