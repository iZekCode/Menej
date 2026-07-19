//
//  SubscriptionsView.swift
//  Menej
//
//  See PRD §6 F7. Finding forgotten subscriptions tends to be the single
//  most memorable moment in the product.
//

import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Query private var subscriptions: [Subscription]
    @State private var viewModel = SubscriptionsViewModel()

    var body: some View {
        NavigationStack {
            List {
                if subscriptions.isEmpty {
                    EmptyStateView(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "No subscriptions detected yet",
                        message: "Once you import a few months of statements, recurring charges show up here automatically."
                    )
                } else {
                    Section {
                        LabeledContent("Monthly commitment") {
                            AmountText(amount: viewModel.totalMonthlyCommitment(for: subscriptions))
                        }
                    }
                    Section("Active") {
                        ForEach(subscriptions.filter(\.isActive)) { subscription in
                            SubscriptionRow(subscription: subscription)
                        }
                    }
                    let dead = viewModel.likelyDeadSubscriptions(in: subscriptions)
                    if !dead.isEmpty {
                        Section("Likely dead") {
                            ForEach(dead) { subscription in
                                SubscriptionRow(subscription: subscription)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Subscriptions")
        }
    }
}

private struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(subscription.merchant)
                Text("Last charged \(subscription.lastChargedAt, style: .date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(amount: subscription.amount)
        }
    }
}

#Preview {
    SubscriptionsView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
