//
//  ReminderScheduler.swift
//  Menej
//
//  The SwiftData half of reminders. ReminderService is deliberately free of
//  SwiftData so its date arithmetic stays testable under the CLT harness; this
//  is the thin layer that reads the store and hands it value types.
//
//  Every call site calls `sync` — there is no per-entity scheduling. It's
//  idempotent (cancels everything, rebuilds from current state), so no caller
//  has to know which notification identifiers it owns, and no path can leave a
//  reminder behind for something the user deleted.
//

import Foundation
import SwiftData

@MainActor
enum ReminderScheduler {
    /// Reads the current state of the store and rebuilds every pending
    /// notification. Call after anything that could change what should be
    /// pending: launch, import, asset or liability edits, and the Settings
    /// toggle.
    static func sync(
        modelContext: ModelContext,
        isEnabled: Bool,
        service: ReminderServiceProtocol = ReminderService()
    ) async {
        // Fetched on the main actor before the await — ModelContext isn't
        // Sendable, so nothing SwiftData-shaped may cross into the async call.
        let warranties = fetchWarranties(modelContext)
        let payments = fetchPayments(modelContext)
        let newestStatementPeriodEnd = fetchNewestStatementPeriodEnd(modelContext)

        await service.sync(
            warranties: warranties,
            payments: payments,
            newestStatementPeriodEnd: newestStatementPeriodEnd,
            isEnabled: isEnabled
        )
    }

    private static func fetchWarranties(_ modelContext: ModelContext) -> [WarrantyReminderItem] {
        let assets = (try? modelContext.fetch(FetchDescriptor<Asset>())) ?? []
        return assets.compactMap { asset in
            guard let expiresAt = asset.warrantyExpiresAt else { return nil }
            return WarrantyReminderItem(assetId: asset.id, name: asset.name, expiresAt: expiresAt)
        }
    }

    private static func fetchPayments(_ modelContext: ModelContext) -> [PaymentReminderItem] {
        let liabilities = (try? modelContext.fetch(FetchDescriptor<Liability>())) ?? []
        return liabilities.compactMap { liability in
            guard let dueAt = liability.dueDate else { return nil }
            // The label is the liability's kind ("Credit Card"), never its
            // balance — notification bodies stay free of amounts.
            return PaymentReminderItem(liabilityId: liability.id, label: liability.type, dueAt: dueAt)
        }
    }

    /// The newest period any imported statement covers — what the import nudge
    /// measures staleness against.
    private static func fetchNewestStatementPeriodEnd(_ modelContext: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<Statement>(sortBy: [SortDescriptor(\.periodEnd, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.periodEnd
    }
}
