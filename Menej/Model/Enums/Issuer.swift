//
//  Issuer.swift
//  Menej
//
//  v1 issuers per PRD §6 F1. ShopeePay/OVO deferred to v1.1 (needs OCR pipeline).
//

import Foundation

enum Issuer: String, Codable, CaseIterable, Identifiable {
    case bcaMyBCA = "bca_mybca"
    case gopay
    case grab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bcaMyBCA: return "myBCA"
        case .gopay: return "GoPay"
        case .grab: return "Grab"
        }
    }
}
