//
//  DepreciationService.swift
//  Menej
//
//  Per-category value curves for physical assets — see PRD §6 F6. Some
//  categories appreciate (watches, jewelry), so the curve runs in both
//  directions. An asset with `depreciationCurve == nil` is manually valued
//  and never touched by this service.
//
//  Deliberately free of SwiftData imports so it stays typecheckable with
//  the CLT-only swiftc harness (no macro plugins) — callers pass the
//  asset's fields, not the @Model itself.
//

import Foundation

struct DepreciationCurve: Identifiable {
    let id: String
    /// Compounded yearly; negative depreciates, positive appreciates.
    let annualRate: Double
    /// Depreciating assets keep some resale value forever — the curve
    /// flattens out at this fraction of acquisition cost.
    let floorFraction: Double
}

protocol DepreciationServiceProtocol {
    func curve(id: String) -> DepreciationCurve?
    func defaultCurveId(for type: AssetType) -> String?
    func estimatedValue(acquisitionCost: Decimal, acquiredAt: Date, curveId: String, asOf: Date) -> Decimal?
}

struct DepreciationService: DepreciationServiceProtocol {
    /// Rates are deliberately round, conservative figures — this is an
    /// estimate the user can override per-asset, not an appraisal.
    static let curves: [DepreciationCurve] = [
        DepreciationCurve(id: "electronics", annualRate: -0.25, floorFraction: 0.05),
        DepreciationCurve(id: "vehicle", annualRate: -0.12, floorFraction: 0.10),
        DepreciationCurve(id: "watch", annualRate: 0.03, floorFraction: 1.0),
        DepreciationCurve(id: "jewelry", annualRate: 0.02, floorFraction: 1.0),
    ]

    func curve(id: String) -> DepreciationCurve? {
        Self.curves.first { $0.id == id }
    }

    func defaultCurveId(for type: AssetType) -> String? {
        type.isPhysical ? type.rawValue : nil
    }

    func estimatedValue(acquisitionCost: Decimal, acquiredAt: Date, curveId: String, asOf: Date = .now) -> Decimal? {
        guard let curve = curve(id: curveId), acquisitionCost > 0 else { return nil }
        let years = max(0, asOf.timeIntervalSince(acquiredAt)) / (365.25 * 24 * 3600)
        // Double is plenty here: the multiplier is an estimate, and rounding
        // to whole rupiah below removes any FP noise from the Decimal result.
        let multiplier = max(pow(1 + curve.annualRate, years), curve.floorFraction)
        var value = acquisitionCost * Decimal(multiplier)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded
    }
}

extension DepreciationServiceProtocol {
    func estimatedValue(acquisitionCost: Decimal, acquiredAt: Date, curveId: String) -> Decimal? {
        estimatedValue(acquisitionCost: acquisitionCost, acquiredAt: acquiredAt, curveId: curveId, asOf: .now)
    }
}
