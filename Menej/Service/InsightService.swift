//
//  InsightService.swift
//  Menej
//
//  See PRD §6 F8. Insights must be withheld until the data supports them —
//  a wrong insight in week one does more damage than no insight at all.
//  All computation is rules-based and statistical, on-device. No LLM in v1.
//

import Foundation

struct CategoryAnomaly {
    let category: Category
    let currentAmount: Decimal
    let averageAmount: Decimal
    let ratio: Double
}

protocol InsightServiceProtocol {
    /// Runway in months. Requires only liquid assets and average spend —
    /// works with a single month of data.
    func runwayMonths(liquidAssets: Decimal, averageMonthlySpend: Decimal) -> Double?

    /// Requires at least 2 months of data; caller should hide the module
    /// entirely (not an empty placeholder) until then.
    func anomalies(currentMonthByCategory: [Category: Decimal], historicalAverageByCategory: [Category: Decimal]) -> [CategoryAnomaly]
}

struct InsightService: InsightServiceProtocol {
    /// Anomaly flagged when current spend exceeds this multiple of the average.
    let anomalyRatioThreshold: Double = 2.0

    func runwayMonths(liquidAssets: Decimal, averageMonthlySpend: Decimal) -> Double? {
        guard averageMonthlySpend > 0 else { return nil }
        let liquidAssetsDouble = NSDecimalNumber(decimal: liquidAssets).doubleValue
        let spendDouble = NSDecimalNumber(decimal: averageMonthlySpend).doubleValue
        return liquidAssetsDouble / spendDouble
    }

    func anomalies(currentMonthByCategory: [Category: Decimal], historicalAverageByCategory: [Category: Decimal]) -> [CategoryAnomaly] {
        currentMonthByCategory.compactMap { category, currentAmount in
            guard let averageAmount = historicalAverageByCategory[category], averageAmount > 0 else { return nil }
            let ratio = NSDecimalNumber(decimal: currentAmount).doubleValue / NSDecimalNumber(decimal: averageAmount).doubleValue
            guard ratio >= anomalyRatioThreshold else { return nil }
            return CategoryAnomaly(category: category, currentAmount: currentAmount, averageAmount: averageAmount, ratio: ratio)
        }
    }
}
