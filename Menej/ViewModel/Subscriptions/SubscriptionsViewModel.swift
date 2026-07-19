//
//  SubscriptionsViewModel.swift
//  Menej
//
//  Drives SubscriptionsView — see PRD §6 F7. Detected from recurring
//  transaction patterns rather than manual entry.
//
//  Deliberately stateless — see NetWorthViewModel.swift for why: caching a
//  copy of `subscriptions` via `.onAppear` only refreshes once per tab
//  activation, going stale the moment the underlying data changes after
//  that. Taking the live `@Query` array as a parameter lets the View
//  recompute on every body evaluation instead.
//

import Foundation
import Observation

@Observable
@MainActor
final class SubscriptionsViewModel {
    func totalMonthlyCommitment(for subscriptions: [Subscription]) -> Decimal {
        subscriptions
            .filter(\.isActive)
            .reduce(Decimal(0)) { total, subscription in
                switch subscription.cadence {
                case .monthly: return total + subscription.amount
                case .annual: return total + subscription.amount / 12
                }
            }
    }

    /// PRD §6 F7 — flags likely-dead subscriptions ("last charged 4 months ago").
    func likelyDeadSubscriptions(in subscriptions: [Subscription], now: Date = .now, threshold: TimeInterval = 90 * 24 * 60 * 60) -> [Subscription] {
        subscriptions.filter { now.timeIntervalSince($0.lastChargedAt) > threshold }
    }
}
