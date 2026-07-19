//
//  InsightsViewModel.swift
//  Menej
//
//  Drives InsightsView — see PRD §6 F8. Insights are withheld (nil / empty),
//  never shown wrong or as an empty placeholder, until data supports them.
//

import Foundation
import Observation

@Observable
@MainActor
final class InsightsViewModel {
    private let insightService: InsightServiceProtocol

    var runwayMonths: Double?
    var anomalies: [CategoryAnomaly] = []

    /// PRD §6 F8 — anomaly detection requires at least 2 months of data.
    var hasEnoughDataForAnomalies = false

    // See ImportViewModel.swift for why the default is built in the body.
    init(insightService: InsightServiceProtocol? = nil) {
        self.insightService = insightService ?? InsightService()
    }

    func refreshRunway(liquidAssets: Decimal, averageMonthlySpend: Decimal) {
        runwayMonths = insightService.runwayMonths(liquidAssets: liquidAssets, averageMonthlySpend: averageMonthlySpend)
    }

    func refreshAnomalies(currentMonthByCategory: [Category: Decimal], historicalAverageByCategory: [Category: Decimal], monthsOfHistory: Int) {
        guard monthsOfHistory >= 2 else {
            hasEnoughDataForAnomalies = false
            anomalies = []
            return
        }
        hasEnoughDataForAnomalies = true
        anomalies = insightService.anomalies(currentMonthByCategory: currentMonthByCategory, historicalAverageByCategory: historicalAverageByCategory)
    }
}
