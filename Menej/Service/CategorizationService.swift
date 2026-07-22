//
//  CategorizationService.swift
//  Menej
//
//  Rules-based merchant matching — see PRD §6 F3.
//  Learns from corrections: one correction creates a permanent merchant rule
//  and applies retroactively to past transactions sharing that merchant.
//
//  Matching is layered, calibrated against the real 15-statement corpus in
//  `Menej/Financial Statement/`:
//    1. user corrections (a fixed miscategorization stays fixed)
//    2. bundled dictionary (MerchantDictionary.json — recognizable brands
//       plus this corpus's recurring merchants)
//    3. generic Indonesian merchant-word heuristics ("kantin", "ayam",
//       "pulsa", "apotek", …) — category only, merchant left nil, because a
//       generic word is not a safe retroactive-correction key
//    4. issuer/boilerplate fallbacks (BCA transfer jargon, Grab rides)
//    5. direction sanity: money IN can only be income/transfer/investment —
//       a keyword match against a spending category (e.g. an incoming
//       reimbursement whose note mentions "airbnb") is coerced to income
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
    ///
    /// `direction`, when known, keeps money-in sane: credits can only be
    /// income/transfer/investment (see file header).
    func categorize(rawDescription: String, issuer: Issuer?, direction: Direction?) -> (merchant: String?, category: Category)
    func recordCorrection(merchant: String, category: Category)
}

final class CategorizationService: CategorizationServiceProtocol {
    /// `direction`, when present, restricts the rule to money moving that
    /// way. Most rules are direction-agnostic and leave it nil — a credit in
    /// a wallet account ("gopay topup", "ovo", "shopeepay") really is an
    /// own-account transfer and must stay `.transfer`, or net worth
    /// double-counts it as income. It exists for keywords whose meaning
    /// flips with direction: "switching" outbound is the user transferring
    /// money out, but inbound it's someone else's money arriving over the
    /// interbank switching network — income, not a self-transfer.
    private struct MerchantRule: Codable {
        let keyword: String
        let merchant: String
        let category: Category
        var direction: Direction? = nil

        func applies(to direction: Direction?) -> Bool {
            guard let ruleDirection = self.direction else { return true }
            return ruleDirection == direction
        }
    }

    private static let userCorrectionsKey = "Menej.merchantCorrections"

    /// Bundled rules ordered most-specific-keyword-first (e.g. "grabfood"
    /// before "grab") so substring matching picks the right one — see
    /// MerchantDictionary.json.
    private let bundledRules: [MerchantRule]
    private var userCorrections: [String: Category]
    private let userDefaults: UserDefaults

    // MARK: - Generic keyword heuristics (category only, merchant nil)
    //
    // Words that recognizably describe what a hyper-local merchant *is*
    // ("PMX KANTIN KASTURI", "RM Sinar Minang", "Ayam Gepuk Pak Gembus")
    // even when the merchant itself can't be in any bundled dictionary.
    // Checked in this order; keep entries lowercase. Trailing spaces are
    // deliberate where a bare prefix would over-match ("rm " vs "warm").

    private static let foodKeywords = [
        "warung", "warkop", "kantin", "kopitiam", "restoran", "resto", "rumah makan", "rm ",
        "masakan", "dapoer", "dapur", "catering", "kuliner",
        "ayam", "bakso", "bakmi", "mie ", "nasi", "sate", "soto", "seafood", "tahu",
        "martabak", "bubur", "dimsum", "geprek", "penyet", "gepuk", "padang", "minang",
        "bakery", "roti", "donat", "kopi", "coffee", "cafe", "boba", "juice",
        "grill", "steak", "sushi", "ramen", "burger", "pizza", "kebab", "snack", "jajan",
    ]
    private static let billsKeywords = [
        "pulsa", "tagihan", "listrik", "token pln", "laundry", "wash",
        "internet", "wifi", "bpjs", "asuransi", "pajak", "biaya",
    ]
    private static let transportKeywords = [
        "parkir", "parking", "bensin", "pertamina", "spbu", "toll", "tol ",
        "mrt", "transjakarta", "krl", "kereta", "bluebird", "taksi", "taxi",
        // A Gojek ride in a GoPay statement is titled with the destination
        // POI, not "Gojek" — confirmed against the corpus: dozens of
        // payments named after the user's home/office at exact ride-fare
        // amounts (33.5k–51.5k) at commute times, on days complementary to
        // the Grab statements' rides. Grab's own rows never reach this
        // layer (the issuer fallback short-circuits first), so these
        // POI names can't mislabel Grab transactions.
        "green office park", "silkwood residences",
    ]
    private static let healthKeywords = [
        "apotek", "apotik", "farma", "klinik", "dokter", "rumah sakit", "hospital", "medika",
    ]
    private static let educationKeywords = [
        "univ", "sekolah", "kampus", "kursus", "course", "udemy", "coursera",
    ]
    private static let entertainmentKeywords = [
        "hotel", "bioskop", "karaoke", "konser", "concert", "steam", "playstation",
    ]
    private static let keywordLayers: [([String], Category)] = [
        (foodKeywords, .food),
        (billsKeywords, .bills),
        (transportKeywords, .transport),
        (healthKeywords, .health),
        (educationKeywords, .education),
        (entertainmentKeywords, .entertainment),
    ]

    /// Transfer boilerplate — BCA interbank/e-banking jargon plus GoPay's
    /// P2P send ("Ditransfer ke <name>"): a transfer to or from another
    /// person/account, with no merchant in the text. ("biaya txn" fee rows
    /// match the dictionary's "Transfer Fee" first and never reach this.)
    private static let transferMarkers = ["trsf e-banking", "bi-fast", "byr via e-banking", "ditransfer ke", "diterima dari"]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.bundledRules = Self.loadBundledRules()
        self.userCorrections = Self.loadUserCorrections(from: userDefaults)
    }

    func categorize(rawDescription: String, issuer: Issuer? = nil, direction: Direction? = nil) -> (merchant: String?, category: Category) {
        let lowered = rawDescription.lowercased()
        let (merchant, category) = match(lowered, issuer: issuer, direction: direction)

        // Money IN can only be income, a transfer, or an investment
        // return — a spending-category keyword inside a credit (e.g. an
        // incoming reimbursement whose sender note says "airbnb") is about
        // what the *sender* did, not what the user bought. The merchant is
        // dropped along with the coerced category so a later correction on
        // that merchant can't silently recategorize real purchases.
        if direction == .credit, ![.income, .transfer, .investment].contains(category) {
            return (nil, .income)
        }
        return (merchant, category)
    }

    private func match(_ lowered: String, issuer: Issuer?, direction: Direction?) -> (String?, Category) {
        // User corrections take priority over the bundled dictionary so a
        // fixed miscategorization stays fixed.
        for (merchant, category) in userCorrections where lowered.contains(merchant.lowercased()) {
            return (merchant, category)
        }
        // Every Grab statement transaction is either a GrabFood order or a
        // ride — decided by the parser's structured description alone,
        // BEFORE the dictionary and keyword layers: a ride's
        // pickup/destination is an address, and an address like "Apple
        // Developer Academy" or "Hariston Hotel & Suites" must not drag the
        // ride into another category via a keyword match.
        if issuer == .grab {
            return lowered.contains("grabfood") ? ("GrabFood", .food) : ("Grab", .transport)
        }
        for rule in bundledRules where rule.applies(to: direction) && lowered.contains(rule.keyword) {
            return (rule.merchant, rule.category)
        }
        for (keywords, category) in Self.keywordLayers where keywords.contains(where: lowered.contains) {
            return (nil, category)
        }
        if Self.transferMarkers.contains(where: lowered.contains) {
            // The note travelling with a transfer already had its chance to
            // match above ("nasi …" → food); plain transfer boilerplate is a
            // transfer going out, and money coming in from someone else's
            // account is income.
            return (nil, direction == .credit ? .income : .transfer)
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
