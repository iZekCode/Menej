//
//  AIEnhancementService.swift
//  Menej
//
//  On-device LLM cleanup for messy parsed descriptions and categorization,
//  per explicit user request to prioritize accuracy over the PRD's original
//  v1 scope (which deferred any LLM to v2 as "a fallback layer"). Uses
//  Apple's on-device Foundation Models (Apple Intelligence) exclusively —
//  deliberately not a cloud LLM — so the app's core privacy claim ("your
//  financial data never leaves your iPhone") stays true. No network call is
//  made by this service.
//
//  IMPORTANT — not verified against a real build: this environment has no
//  Xcode and no Apple Intelligence–eligible device, so the exact
//  FoundationModels API shape below (SystemLanguageModel, @Generable,
//  @Guide, LanguageModelSession.respond(to:generating:)) is based on
//  Apple's published framework design, not a compiled/run check. Expect to
//  verify member names against Xcode's autocomplete/docs on first build.
//
//  Availability is hardware- and settings-gated (recent-generation Apple
//  Silicon iPhone, Apple Intelligence turned on, supported region/language)
//  — this service degrades to reporting `.unavailable` rather than
//  crashing when it isn't, and callers must keep the existing rule-based
//  CategorizationService as the primary, always-available path.
//

import Foundation
import FoundationModels

@Generable
struct TransactionEnhancement {
    @Guide(description: "A short, clean, human-readable merchant or counterparty name in title case, with reference codes, transaction IDs, dates, duplicated amounts, and bank jargon stripped out — e.g. 'DAPOER COWEK 0420260430044124vkmo' becomes 'Dapoer Cowek'. Never invent a name that is not in the text; if no real name can be determined, use \"Unknown\".")
    var merchant: String

    @Guide(description: "The single best-fit category raw value from the allowed list given in the instructions.")
    var categoryRawValue: String
}

enum AIEnhancementError: Error {
    case unavailable(String)
}

protocol AIEnhancementServiceProtocol {
    var isAvailable: Bool { get }
    var unavailabilityReason: String? { get }
    func enhance(rawDescription: String, amount: Decimal, direction: Direction, issuer: Issuer?) async throws -> (merchant: String, category: Category)
}

struct AIEnhancementService: AIEnhancementServiceProtocol {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence isn't turned on. Enable it in Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                return "The on-device model is still downloading or preparing — try again shortly."
            @unknown default:
                return "Apple Intelligence isn't available right now."
            }
        @unknown default:
            return "Apple Intelligence isn't available right now."
        }
    }

    private static let categoryList = Category.allCases.map(\.rawValue).joined(separator: ", ")

    // The instructions are calibrated against the real 15-statement corpus
    // in `Menej/Financial Statement/`: they teach the model each issuer's
    // actual junk patterns (GoPay's trailing transaction IDs, myBCA's
    // e-banking jargon and glued QRIS merchants, Grab's structured
    // "type: pickup → destination" rows) and ground every category in the
    // Indonesian merchant vocabulary the statements really contain. The
    // worked examples are lightly-anonymized real rows from that corpus.
    private static let instructions = """
    You clean up messy Indonesian bank and e-wallet statement lines for a personal finance app. \
    For each transaction, produce a clean merchant/counterparty name and pick the single best \
    category from exactly this list: \(Self.categoryList).

    How to read each statement format:
    - GoPay: the merchant name comes first, followed by transaction-ID junk — a long digit string \
    (often starting with the date) plus a short random token ending in "ID". Drop all of that junk. \
    Example: "MAMA DJEMPOL GOP 0420260529033702stbA8 87SiAID" → merchant "Mama Djempol".
    - myBCA e-banking transfer: "TRSF E-BANKING DB 0104/FTSCY/WS95031 50000.00 nasi filbert CAROLINE ANG" — \
    drop the jargon, the reference code, and the duplicated amount. The trailing UPPERCASE words are the \
    counterparty's name; short lowercase words before it are the user's own note. Merchant is the \
    counterparty ("Caroline Ang"); the note tells you what it was for ("nasi" = food).
    - myBCA card/QRIS: "TRANSAKSI DEBIT TGL: 09/04 QR 912 00000.00PMX KANTIN" — the merchant is glued \
    after the "00000.00" filler and may be truncated. Merchant "PMX Kantin", category food.
    - Grab: "Car Standard: Green Office Park 9 → Lobby Oak Apartment (A-99HTHGQWWCQTAV)" is a ride → \
    the merchant is the destination (the part after "→"), "Lobby Oak Apartment", category transport. \
    "GrabFood: Moon Chicken - AlamSutera → Silkwood Residences (A-…)" is food delivery → merchant is \
    the restaurant without its area suffix, "Moon Chicken", category food.

    Category rules (Indonesian context):
    - food: restaurants, warung/warkop/kantin, ayam/bakso/nasi/sate/martabak and similar dishes, \
    kopi/cafe, bakeries, convenience stores and groceries (Indomaret, Alfamart, Lawson, Farmers Market).
    - transport: ride-hailing (a Gojek ride in a GoPay statement is titled with the destination, e.g. \
    "Green Office Park 9 BSD" or "Silkwood Residences", at a 15,000–60,000 fare), parking, fuel, tolls, trains.
    - bills: pulsa and mobile data (IM3, Telkomsel), GoTagihan, electricity, internet (Netciti, IndiHome), \
    laundry (Wash Xpress), subscriptions, admin fees, transfer fees, taxes (PAJAK).
    - transfer: e-wallet/e-money top-ups (GoPay, OVO, ShopeePay, Flazz) and virtual-account payments.
    - investment: Stockbit and other brokerages — an outgoing bank transfer whose counterparty is the \
    account holder's OWN name is this user's Stockbit RDN top-up (merchant "Stockbit RDN Top Up").
    - income: money received — salary, transfers in from other people, reimbursements, refunds, \
    bank interest (BUNGA).
    - shopping: marketplaces (Shopee, Tokopedia), department and retail stores (AEON, Uniqlo).
    - entertainment: cinema (XXI), streaming and app stores (Netflix, Spotify, Google Play, Apple), \
    games, hotels, Airbnb.
    - health: apotek, klinik, dokter, hospitals. education: universities (UNIV), schools, courses.
    - other: only when nothing else genuinely fits. Never guess a spending category for money in.

    Worked examples:
    - "DAPOER COWEK 0420260518050724h083 hsHbxbID", money out → merchant "Dapoer Cowek", food
    - "GoTagihan 01202605150619233Jnrb 4G40CID", money out → merchant "GoTagihan", bills
    - "TRSF E-BANKING DB 1004/FTFVA/WS95031 70001/GOPAY TOPUP 0895637512739", money out → merchant "GoPay Top Up", transfer
    - "TRSF E-BANKING CR 0306/FTSCY/WS95031 7000000.00 LEDYAWATY", money in → merchant "Ledyawaty", income
    - "TRANSAKSI DEBIT TGL: 22/04 QR 008 00000.00AEON STORE", money out → merchant "AEON Store", shopping
    - "BI-FAST DB BIF TRANSFER KE 022 0T01/19", money out → this user's recurring utility payment → \
    merchant "Electricity & Water" (call it "Electricity, Water & IPL" when the amount exceeds IDR 1,000,000), bills
    - "Ditransfer ke Roy Harianja 0420260622072354Vxgp UJMeQPID", money out → merchant "Roy Harianja", transfer
    - "BYR VIA E-BANKING 30/06 WSID9503103 0404 UNIV. BINUS 270223569622", money out → merchant "BINUS University", education
    - "TRSF E-BANKING DB 2404/FTSCY/WS95031 20000000.00 FILBERT NALDO WIJA", money out → the account \
    holder paying their own name → merchant "Stockbit RDN Top Up", investment
    - "TRSF E-BANKING DB 3004/FTFVA/WS95031 00595/NETCITI PERS D9H105672", money out → merchant "Netciti (WiFi)", bills
    """

    func enhance(rawDescription: String, amount: Decimal, direction: Direction, issuer: Issuer?) async throws -> (merchant: String, category: Category) {
        guard isAvailable else {
            throw AIEnhancementError.unavailable(unavailabilityReason ?? "Apple Intelligence is unavailable.")
        }

        let session = LanguageModelSession(instructions: Self.instructions)

        var promptLines = [
            "Raw description: \(rawDescription)",
            "Amount: IDR \(amount)",
            "Direction: \(direction == .debit ? "money out" : "money in")",
        ]
        if let issuer {
            promptLines.append("Statement source: \(issuer.displayName)")
        }

        let response = try await session.respond(to: promptLines.joined(separator: "\n"), generating: TransactionEnhancement.self)
        let category = Category(rawValue: response.content.categoryRawValue) ?? .other
        return (response.content.merchant, category)
    }
}
