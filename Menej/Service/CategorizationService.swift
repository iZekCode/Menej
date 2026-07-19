//
//  CategorizationService.swift
//  Menej
//
//  Rules-based merchant matching — see PRD §6 F3.
//  Learns from corrections: one correction creates a permanent merchant rule
//  and applies retroactively to past transactions sharing that merchant.
//
//  The bundled dictionary (MerchantDictionary.json) only covers recognizable
//  national brands (Indomaret, Netflix, GrabFood, etc.) — real statements
//  are full of hyper-local merchants (a specific warung, a specific kos-an)
//  no bundled dictionary can know in advance. Those stay `.other` until the
//  user corrects one once, same as the PRD describes.
//
//  Retroactive correction only applies to transactions whose merchant is a
//  known dictionary/learned keyword — deliberately not to a heuristically
//  guessed merchant name from arbitrary raw text, since a wrong guess there
//  could silently mass-recategorize unrelated transactions (e.g. every BCA
//  bank transfer shares the same "TRSF E-BANKING DB" boilerplate prefix,
//  which is not a merchant). See LedgerViewModel.correctCategory.
//

import Foundation

protocol CategorizationServiceProtocol {
    /// Matches known keywords (bundled or learned) against `rawDescription`.
    /// Returns `(nil, .other)` when nothing matches — the description alone
    /// isn't a safe key for retroactive corrections (see file header).
    ///
    /// `issuer`, when known, disambiguates cases the description text alone
    /// can't: a Grab *ride* description is just pickup/dropoff addresses —
    /// it never contains the word "Grab" — so without the issuer hint every
    /// non-GrabFood ride would fall through to `.other`.
    func categorize(rawDescription: String, issuer: Issuer?) -> (merchant: String?, category: Category)
    func recordCorrection(merchant: String, category: Category)
}

final class CategorizationService: CategorizationServiceProtocol {
    private struct MerchantRule: Codable {
        let keyword: String
        let merchant: String
        let category: Category
    }

    private static let userCorrectionsKey = "Menej.merchantCorrections"

    /// Bundled rules ordered most-specific-keyword-first (e.g. "grabfood"
    /// before "grab") so substring matching picks the right one — see
    /// MerchantDictionary.json.
    private let bundledRules: [MerchantRule]
    private var userCorrections: [String: Category]
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.bundledRules = Self.loadBundledRules()
        self.userCorrections = Self.loadUserCorrections(from: userDefaults)
    }

    func categorize(rawDescription: String, issuer: Issuer? = nil) -> (merchant: String?, category: Category) {
        let lowered = rawDescription.lowercased()

        // User corrections take priority over the bundled dictionary so a
        // fixed miscategorization stays fixed.
        for (merchant, category) in userCorrections where lowered.contains(merchant.lowercased()) {
            return (merchant, category)
        }
        for rule in bundledRules where lowered.contains(rule.keyword) {
            return (rule.merchant, rule.category)
        }
        // Every Grab statement transaction is either a ride or a GrabFood
        // order — GrabFood already matched above via the bundled dictionary
        // ("grabfood"), so anything left from this issuer is a ride.
        if issuer == .grab {
            return ("Grab", .transport)
        }
        return (nil, .other)
    }

    func recordCorrection(merchant: String, category: Category) {
        userCorrections[merchant] = category
        Self.saveUserCorrections(userCorrections, to: userDefaults)
    }

    private static func loadBundledRules() -> [MerchantRule] {
        guard let url = Bundle.main.url(forResource: "MerchantDictionary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([MerchantRule].self, from: data) else {
            return []
        }
        return rules
    }

    private static func loadUserCorrections(from userDefaults: UserDefaults) -> [String: Category] {
        guard let raw = userDefaults.dictionary(forKey: userCorrectionsKey) as? [String: String] else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, entry in
            if let category = Category(rawValue: entry.value) {
                result[entry.key] = category
            }
        }
    }

    private static func saveUserCorrections(_ corrections: [String: Category], to userDefaults: UserDefaults) {
        let raw = corrections.mapValues(\.rawValue)
        userDefaults.set(raw, forKey: userCorrectionsKey)
    }
}
