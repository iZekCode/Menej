//
//  RemoteConfigService.swift
//  Menej
//
//  Parser rules refresh — see PRD §6 F1. Versioned JSON, bundled in the app
//  and refreshable from a CDN, cached locally, checked on app open (max once
//  per day). The app must remain fully functional offline using cached rules.
//  This is the only network call in v1, and it transmits no user data.
//
//  TODO(M2): implement CDN fetch + local cache with a once-per-day check.
//

import Foundation

protocol RemoteConfigServiceProtocol {
    func refreshRulesIfNeeded() async throws
    func loadBundledRules() -> [IssuerRule]
}

struct RemoteConfigService: RemoteConfigServiceProtocol {
    func refreshRulesIfNeeded() async throws {
        // No-op in v1 scaffold: bundled rules are the only source until M2.
    }

    func loadBundledRules() -> [IssuerRule] {
        let decoder = JSONDecoder()
        return Issuer.statementIssuers.compactMap { issuer in
            guard let url = Bundle.main.url(
                forResource: issuer.rawValue,
                withExtension: "json",
                subdirectory: "Service/Parsing/Rules"
            ) ?? Bundle.main.url(forResource: issuer.rawValue, withExtension: "json") else {
                return nil
            }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(IssuerRule.self, from: data)
        }
    }
}
