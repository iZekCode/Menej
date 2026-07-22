//
//  MonthTransactionsView.swift
//  Menej
//
//  Every transaction for one month, grouped by day like the Ledger — pushed
//  from the Insights "Last Transactions" section's chevron. Reuses the ledger's
//  TransactionRow and TransactionDetailView so it looks and behaves the same.
//

import SwiftUI
import SwiftData

struct MonthTransactionsView: View {
    let month: Date

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var accounts: [Account]

    private var issuerByAccount: [UUID: Issuer] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.issuer) })
    }

    private var monthTransactions: [Transaction] {
        guard let range = AnalyticsPeriod.singleMonth.dateRange(reference: month) else { return transactions }
        return transactions.filter { range.contains($0.date) }
    }

    private var grouped: [(day: Date, transactions: [Transaction])] {
        let groups = Dictionary(grouping: monthTransactions) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        List {
            if monthTransactions.isEmpty {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "No transactions",
                    message: "Nothing recorded this month."
                )
            } else {
                ForEach(grouped, id: \.day) { group in
                    Section(sectionTitle(for: group.day)) {
                        ForEach(group.transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction, issuer: issuerByAccount[transaction.accountId])
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    private func sectionTitle(for day: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let dateString = formatter.string(from: day)
        if calendar.isDateInToday(day) { return "Today, \(dateString)" }
        if calendar.isDateInYesterday(day) { return "Yesterday, \(dateString)" }
        formatter.dateStyle = .full
        return formatter.string(from: day)
    }
}

#Preview {
    NavigationStack {
        MonthTransactionsView(month: .now)
    }
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
