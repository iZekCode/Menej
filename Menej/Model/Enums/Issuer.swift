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
    /// An account the user added by hand — another bank, a second wallet,
    /// cash in a drawer. It has no statement, so nothing in the parsing
    /// pipeline can ever produce or match it: there's no rule file named
    /// `manual.json`, `IssuerDetector` has no pattern for it, and
    /// `ImportViewModel.findOrCreateAccount` only ever looks up a detected
    /// issuer. Unlike the other three it isn't a one-per-app identity —
    /// several accounts can share it, so they're told apart by nickname.
    case manual

    var id: String { rawValue }

    /// The issuers the app can parse a statement for. Anywhere that means
    /// "a real provider" — rule loading, the Add Account menu, issuer
    /// filters — should iterate this rather than `allCases`.
    static var statementIssuers: [Issuer] {
        allCases.filter { $0 != .manual }
    }

    var displayName: String {
        switch self {
        case .bcaMyBCA: return "MyBCA"
        case .gopay: return "GoPay"
        case .grab: return "Grab"
        case .manual: return "Other"
        }
    }
}
