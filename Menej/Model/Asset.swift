//
//  Asset.swift
//  Menej
//
//  Physical assets (PRD §6 F6). Depreciation curve is looked up by type;
//  some categories (watches, gold) appreciate, so the curve runs both directions.
//

import Foundation
import SwiftData

@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var type: AssetType
    var name: String
    var acquiredAt: Date
    var acquisitionCost: Decimal
    var currentValue: Decimal
    /// Identifier for the depreciation/appreciation curve to apply; nil means manual value only.
    var depreciationCurve: String?
    var warrantyExpiresAt: Date?
    /// User-supplied photo (camera or library), stored outside the SQLite
    /// store to keep row reads cheap. nil = no photo.
    @Attribute(.externalStorage) var photoData: Data?

    init(
        id: UUID = UUID(),
        type: AssetType,
        name: String,
        acquiredAt: Date,
        acquisitionCost: Decimal,
        currentValue: Decimal,
        depreciationCurve: String? = nil,
        warrantyExpiresAt: Date? = nil,
        photoData: Data? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.acquiredAt = acquiredAt
        self.acquisitionCost = acquisitionCost
        self.currentValue = currentValue
        self.depreciationCurve = depreciationCurve
        self.warrantyExpiresAt = warrantyExpiresAt
        self.photoData = photoData
    }
}

extension Asset {
    /// Re-applies the depreciation/appreciation curve into `currentValue`.
    /// `currentValue` stays the single stored source of truth that
    /// NetWorthService and monthly snapshots read synchronously; this just
    /// keeps it current for curve-managed assets (no-op for manual ones,
    /// and never writes an unchanged value — SwiftData change tracking
    /// would otherwise see every read path as a mutation).
    func applyCurveIfNeeded(service: DepreciationServiceProtocol = DepreciationService(), asOf: Date = .now) {
        guard let curveId = depreciationCurve,
              let estimated = service.estimatedValue(
                  acquisitionCost: acquisitionCost,
                  acquiredAt: acquiredAt,
                  curveId: curveId,
                  asOf: asOf
              ),
              estimated != currentValue else { return }
        currentValue = estimated
    }
}
