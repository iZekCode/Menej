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

    init(
        id: UUID = UUID(),
        type: AssetType,
        name: String,
        acquiredAt: Date,
        acquisitionCost: Decimal,
        currentValue: Decimal,
        depreciationCurve: String? = nil,
        warrantyExpiresAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.acquiredAt = acquiredAt
        self.acquisitionCost = acquisitionCost
        self.currentValue = currentValue
        self.depreciationCurve = depreciationCurve
        self.warrantyExpiresAt = warrantyExpiresAt
    }
}
