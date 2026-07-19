//
//  IssuerRule.swift
//  Menej
//
//  Parser rules as remote config — see PRD §6 F1 and Appendix B.
//  Versioned JSON, bundled in the app and refreshable from a CDN.
//

import Foundation

struct IssuerRule: Codable {
    let issuer: String
    let version: Int
    let fingerprint: Fingerprint
    let dateFormats: [String]
    let amountFormat: AmountFormat
    let transactionPattern: String
    let columnMap: [String: Int]
    let validation: Validation

    struct Fingerprint: Codable {
        let textContains: [String]
    }

    struct AmountFormat: Codable {
        let decimalSeparator: String
        let thousandSeparator: String
    }

    struct Validation: Codable {
        let requireBalanceContinuity: Bool
    }
}
