//
//  PersistenceService.swift
//  Menej
//
//  Local only (SwiftData), encrypted at rest — see PRD §8 Privacy & Security.
//

import Foundation
import SwiftData

@MainActor
protocol PersistenceServiceProtocol {
    var modelContainer: ModelContainer { get }
}

@MainActor
final class PersistenceService: PersistenceServiceProtocol {
    let modelContainer: ModelContainer

    /// SwiftUI's `.modelContainer(for:)` view modifier takes model types
    /// directly (`[any PersistentModel.Type]`), not a `Schema` — use this
    /// in `#Preview`s. `ModelContainer(for:configurations:)` below accepts
    /// either, so `schema` remains the source of truth for real setup.
    static var modelTypes: [any PersistentModel.Type] {
        [
            Account.self,
            Transaction.self,
            Statement.self,
            Asset.self,
            Holding.self,
            Liability.self,
            Subscription.self,
            NetWorthSnapshot.self,
        ]
    }

    static var schema: Schema {
        Schema(modelTypes)
    }

    init(inMemory: Bool = false) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            modelContainer = try ModelContainer(for: Self.schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
