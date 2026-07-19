//
//  AnalyticsService.swift
//  Menej
//
//  Aggregate, anonymous events only — see PRD §8 Privacy & Security.
//  No amounts, no merchant names.
//
//  TODO(M6): wire to Aptabase or similar.
//

import Foundation

protocol AnalyticsServiceProtocol {
    func track(event: String, properties: [String: String]?)
}

struct AnalyticsService: AnalyticsServiceProtocol {
    func track(event: String, properties: [String: String]? = nil) {
        #if DEBUG
        print("[Analytics] \(event) \(properties ?? [:])")
        #endif
    }
}
