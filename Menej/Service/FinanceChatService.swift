//
//  FinanceChatService.swift
//  Menej
//
//  The routing half of Ask. On-device Apple Foundation Models only —
//  same reasoning as AIEnhancementService.swift: Settings promises "your
//  financial data never leaves this device", and a cloud model would make that
//  false. No network call is made by this service.
//
//  THE MODEL DOES NOT COMPUTE. A ~3B on-device model is good at language and
//  unreliable at arithmetic, and the ledger doesn't fit in its context window
//  anyway. So this runs two passes with FinanceQueryService in between:
//
//    1. route   — question in, a typed `ChatQuery` out (intent, category,
//                 merchant, time window). No figures involved.
//    2. (app)   — FinanceQueryService computes the real numbers from the
//                 same services the dashboards use.
//    3. phrase  — question + the already-formatted figures in, a sentence
//                 out. The model is told to reuse those strings verbatim.
//
//  Deliberately two `respond(to:...)` passes rather than tool-calling: nothing
//  in this repo has ever been compiled against FoundationModels, and this
//  reuses exactly the API shape AIEnhancementService already commits to rather
//  than betting on a second unverified surface. FinanceChatView renders every
//  figure from the `FinanceAnswer` struct, so pass 3 misphrasing something
//  can't put a wrong number on screen unchallenged.
//
//  IMPORTANT — not verified against a real build: this environment has no
//  Xcode and no Apple Intelligence–eligible device. The API shape below
//  (SystemLanguageModel, @Generable, @Guide, LanguageModelSession.respond)
//  follows Apple's published framework design; verify member names against
//  Xcode's autocomplete on first build, as AIEnhancementService says too.
//

import Foundation
import FoundationModels

/// Pass 1's output. Every field is a non-optional String with a "none"
/// sentinel rather than an Optional — matching AIEnhancementService's
/// conservative use of the @Generable surface.
@Generable
struct ChatQuery {
    @Guide(description: "The single best-fit intent raw value from the allowed list given in the instructions. Use \"unsupported\" for anything the list doesn't cover, including opinions, advice, and predictions.")
    var intentRawValue: String

    @Guide(description: "The spending category raw value from the allowed list, when the question is about one specific category. Otherwise exactly \"none\".")
    var categoryRawValue: String

    @Guide(description: "The merchant, shop, or person named in the question, copied as the user wrote it. Never invent one. Exactly \"none\" if no merchant is named.")
    var merchant: String

    @Guide(description: "The account or inventory item named in the question, for balance and item-value questions. Exactly \"none\" if none is named.")
    var subject: String

    @Guide(description: "The time window: one of thisWeek, thisMonth, lastMonth, last3Months, last6Months, thisYear, allTime, customMonths. Use customMonths only when the question names specific months. Default to thisMonth when the question implies now, and allTime when it implies no period at all.")
    var windowKind: String

    @Guide(description: "First month of the range as yyyy-MM, only when windowKind is customMonths. Otherwise exactly \"none\".")
    var startMonth: String

    @Guide(description: "Last month of the range (inclusive) as yyyy-MM, only when windowKind is customMonths. Otherwise exactly \"none\".")
    var endMonth: String
}

enum FinanceChatError: Error {
    case unavailable(String)
}

protocol FinanceChatServiceProtocol {
    var isAvailable: Bool { get }
    var unavailabilityReason: String? { get }
    func route(question: String, asOf: Date) async throws -> FinanceQuery
    func phrase(question: String, facts: [String]) async throws -> String
}

struct FinanceChatService: FinanceChatServiceProtocol {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

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

    // MARK: - Pass 1: route

    private static let intentList = FinanceIntent.allCases.map(\.rawValue).joined(separator: ", ")
    private static let categoryList = Category.allCases.map(\.rawValue).joined(separator: ", ")

    private static let routingInstructions = """
    You turn questions about a personal finance app into a structured query. You never answer \
    the question yourself and you never state or estimate any amount — the app computes every \
    figure from the user's real data after you classify the question.

    Pick exactly one intent from: \(Self.intentList).

    What each intent means:
    - spendTotal: how much was spent, overall or in one category.
    - categoryBreakdown: what the spending was made up of, where the money went.
    - merchantSpend: spending at one named shop, restaurant, or person.
    - largestExpenses: the biggest purchases.
    - comparison: this month against last month.
    - cashflow: money in vs money out, income, savings.
    - netWorth: total worth, or how assets split across liquid, portfolio, and inventory.
    - accountBalance: the balance of one named account (MyBCA, GoPay, Grab, or one the user added).
    - runway: how long their money lasts at the current spending rate.
    - anomalies: whether anything looks unusual or has spiked.
    - assetValue: what one owned item is worth now.
    - unsupported: everything else.

    Use unsupported — do not guess an intent — for: investment or financial advice, whether to \
    buy or sell anything, predictions about the future beyond runway, tax or legal questions, \
    and anything not about this user's own recorded money.

    Categories, when the question is about one: \(Self.categoryList). Indonesian words map onto \
    these: makan/makanan/jajan → food, transportasi/ojek/bensin → transport, belanja → shopping, \
    tagihan/pulsa/listrik → bills, hiburan → entertainment, kesehatan → health, \
    pendidikan/kuliah → education, gaji/pemasukan → income.

    Time windows: read relative phrases against today's date, which is given in the prompt. \
    "bulan lalu"/"last month" → lastMonth. "bulan ini"/"this month" → thisMonth. \
    "minggu ini" → thisWeek. "tahun ini" → thisYear. "3 bulan terakhir" → last3Months. \
    Only use customMonths when specific months are named, e.g. "March to May" or "from January \
    until March", and then give startMonth and endMonth as yyyy-MM. When no period is mentioned \
    at all, use allTime for netWorth, accountBalance, assetValue and runway, and thisMonth for \
    everything else.

    Examples:
    - "berapa pengeluaran makan bulan lalu?" → spendTotal, food, lastMonth
    - "how much did I spend at Indomaret this year?" → merchantSpend, merchant "Indomaret", thisYear
    - "what did I spend money on in March to May?" → categoryBreakdown, customMonths, 2026-03, 2026-05
    - "biggest purchases?" → largestExpenses, thisMonth
    - "am I spending more than last month?" → comparison
    - "how much is in my GoPay?" → accountBalance, subject "GoPay", allTime
    - "berapa lama uang saya cukup?" → runway, allTime
    - "should I buy Bitcoin?" → unsupported
    """

    func route(question: String, asOf: Date) async throws -> FinanceQuery {
        guard isAvailable else {
            throw FinanceChatError.unavailable(unavailabilityReason ?? "Apple Intelligence is unavailable.")
        }

        let session = LanguageModelSession(instructions: Self.routingInstructions)
        // Today's date has to be in the prompt or "last month" has nothing to
        // resolve against — the model has no clock.
        let prompt = """
        Today is \(Self.dayFormatter.string(from: asOf)).
        Question: \(question)
        """
        let response = try await session.respond(to: prompt, generating: ChatQuery.self)
        return Self.resolve(response.content, asOf: asOf, calendar: calendar)
    }

    // MARK: - Pass 3: phrase

    private static let phrasingInstructions = """
    You write one or two short sentences answering a personal finance question, in the same \
    language the question was asked in.

    You are given the facts the app computed from the user's real data. Use only those facts. \
    Copy every number and amount exactly as written — never reformat, round, convert, or add \
    them up, and never introduce a figure that isn't in the facts. If the facts don't answer \
    the question, say so plainly.

    Be plain and factual. Do not give advice, do not suggest what the user should do with their \
    money, do not praise or scold their spending, and do not add encouragement.
    """

    func phrase(question: String, facts: [String]) async throws -> String {
        guard isAvailable else {
            throw FinanceChatError.unavailable(unavailabilityReason ?? "Apple Intelligence is unavailable.")
        }

        let session = LanguageModelSession(instructions: Self.phrasingInstructions)
        let prompt = """
        Question: \(question)
        Facts:
        \(facts.map { "- \($0)" }.joined(separator: "\n"))
        """
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Resolution

    /// ChatQuery (loose strings from a model) → FinanceQuery (typed, bounded).
    /// Anything unrecognized degrades to a safe default rather than throwing:
    /// an unknown intent becomes `.unsupported`, an unknown window becomes
    /// this month, "none" becomes nil.
    static func resolve(_ raw: ChatQuery, asOf: Date, calendar: Calendar = .current) -> FinanceQuery {
        let intent = FinanceIntent(rawValue: raw.intentRawValue.trimmingCharacters(in: .whitespaces)) ?? .unsupported
        return FinanceQuery(
            intent: intent,
            category: value(raw.categoryRawValue).flatMap { Category(rawValue: $0) },
            merchant: value(raw.merchant),
            subject: value(raw.subject),
            window: window(raw, asOf: asOf, calendar: calendar)
        )
    }

    /// The model is instructed to write "none" for absent fields; empty and
    /// "null" are defended against too because it's one token away from either.
    private static func value(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.compare("none", options: .caseInsensitive) != .orderedSame,
              trimmed.compare("null", options: .caseInsensitive) != .orderedSame else { return nil }
        return trimmed
    }

    private static func window(_ raw: ChatQuery, asOf: Date, calendar: Calendar) -> DateWindow {
        switch raw.windowKind.trimmingCharacters(in: .whitespaces) {
        case "thisWeek":
            return relative(.day, -7, asOf: asOf, calendar: calendar, label: "this week")
        case "lastMonth":
            guard let thisMonth = calendar.dateInterval(of: .month, for: asOf),
                  let start = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) else {
                return .allTime
            }
            return DateWindow(range: start..<thisMonth.start, label: "last month")
        case "last3Months":
            return relative(.month, -3, asOf: asOf, calendar: calendar, label: "the last 3 months")
        case "last6Months":
            return relative(.month, -6, asOf: asOf, calendar: calendar, label: "the last 6 months")
        case "thisYear":
            guard let interval = calendar.dateInterval(of: .year, for: asOf) else { return .allTime }
            return DateWindow(range: interval.start..<asOf, label: "this year")
        case "allTime":
            return .allTime
        case "customMonths":
            return customMonths(raw, calendar: calendar) ?? thisMonth(asOf: asOf, calendar: calendar)
        default:
            // Includes "thisMonth" and anything unrecognized. Defaulting to
            // the current month is the least surprising fallback, and the
            // window label is always stated back so a wrong guess is visible.
            return thisMonth(asOf: asOf, calendar: calendar)
        }
    }

    private static func thisMonth(asOf: Date, calendar: Calendar) -> DateWindow {
        guard let interval = calendar.dateInterval(of: .month, for: asOf) else { return .allTime }
        return DateWindow(range: interval.start..<interval.end, label: "this month")
    }

    private static func relative(
        _ component: Calendar.Component,
        _ value: Int,
        asOf: Date,
        calendar: Calendar,
        label: String
    ) -> DateWindow {
        guard let start = calendar.date(byAdding: component, value: value, to: asOf) else { return .allTime }
        return DateWindow(range: start..<asOf, label: label)
    }

    /// Month precision, not day: statements are monthly, and "yyyy-MM" is far
    /// more robust to generate than an ISO timestamp. The end month is
    /// inclusive, so the range runs to the start of the month after it.
    private static func customMonths(_ raw: ChatQuery, calendar: Calendar) -> DateWindow? {
        guard let startText = value(raw.startMonth), let start = monthFormatter.date(from: startText) else {
            return nil
        }
        let endText = value(raw.endMonth) ?? startText
        let endMonth = monthFormatter.date(from: endText) ?? start
        guard let endInterval = calendar.dateInterval(of: .month, for: endMonth), endInterval.end > start else {
            return nil
        }

        let label: String
        if calendar.isDate(start, equalTo: endMonth, toGranularity: .month) {
            label = start.formatted(.dateTime.month(.wide).year())
        } else {
            label = "\(start.formatted(.dateTime.month(.wide).year())) to \(endMonth.formatted(.dateTime.month(.wide).year()))"
        }
        return DateWindow(range: start..<endInterval.end, label: label)
    }

    /// Fixed format, POSIX locale — this parses model output, not user-facing
    /// text, so it must not vary with the device's region.
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter
    }()
}
