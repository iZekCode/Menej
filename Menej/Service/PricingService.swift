//
//  PricingService.swift
//  Menej
//
//  Prices refreshed from public sources — see PRD §6 F5/F6. All endpoints
//  are keyless and receive no user data (PRD §8): the only thing sent is
//  the instrument symbol being priced.
//
//  Sources (verified 2026-07-20):
//  - Crypto: Indodax public ticker — quotes directly in IDR.
//  - Stocks: Yahoo Finance v8 chart — IDX tickers get a ".JK" suffix and
//    quote in IDR; US tickers quote in USD and are converted.
//  - Gold: Yahoo "GC=F" (COMEX, USD per troy ounce), converted to IDR per
//    gram — Holding.quantity for gold is grams, the unit Indonesian gold
//    (Antam/Pluang) is bought in.
//  - FX: Frankfurter (ECB reference rates), api.frankfurter.dev — the old
//    .app domain now 301s, which URLSession follows, but the .dev host is
//    the documented one.
//
//  Mutual funds (reksadana), time deposits, and brokerage cash (e.g. an RDN
//  balance) have no keyless public quote source — they throw
//  `.manualValuationOnly` and are valued from `Holding.manualPrice`
//  (falling back to cost basis) by the caller.
//

import Foundation

enum PricingError: LocalizedError {
    /// No public quote source exists for this instrument (mutual funds,
    /// time deposits) — value it from Holding.manualPrice instead.
    case manualValuationOnly
    /// The instrument isn't a priceable holding at all (bank account, cash…).
    case unsupportedInstrument(AssetType)
    case symbolNotFound(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .manualValuationOnly:
            return "This instrument has no public price source — set its value manually."
        case .unsupportedInstrument(let type):
            return "\(type.rawValue) holdings can't be priced from a market feed."
        case .symbolNotFound(let symbol):
            return "No quote found for \(symbol)."
        case .badResponse(let detail):
            return "Price source returned an unexpected response: \(detail)"
        }
    }
}

protocol PricingServiceProtocol {
    /// Current price of **one unit** of the holding, in IDR: one coin for
    /// crypto, one share for stocks, one gram for gold. `currency` is the
    /// currency the holding's cost basis is denominated in — it decides
    /// whether a bare stock symbol is treated as IDX (IDR → ".JK") or US.
    func fetchQuoteIDR(symbol: String, instrument: AssetType, currency: String) async throws -> Decimal
    func fetchFXRate(from currencyCode: String, to currencyCode2: String) async throws -> Decimal
}

actor PricingService: PricingServiceProtocol {
    private let session: URLSession
    /// FX moves slowly; cache per (from,to) so pricing a portfolio with
    /// several USD holdings costs one Frankfurter call, not one per holding.
    private var fxCache: [String: (rate: Decimal, fetchedAt: Date)] = [:]
    private let fxCacheTTL: TimeInterval = 60 * 60

    private static let gramsPerTroyOunce = Decimal(string: "31.1034768")!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Quotes

    func fetchQuoteIDR(symbol: String, instrument: AssetType, currency: String) async throws -> Decimal {
        switch instrument {
        case .crypto:
            return try await indodaxLastPrice(symbol: symbol)
        case .stock:
            return try await yahooPriceIDR(symbol: Self.stockQuerySymbol(symbol: symbol, currency: currency))
        case .gold:
            let usdPerOunce = try await yahooPrice(symbol: "GC=F").price
            let usdPerGram = usdPerOunce / Self.gramsPerTroyOunce
            return try await usdPerGram * fetchFXRate(from: "USD", to: "IDR")
        case .mutualFund, .timeDeposit, .brokerageCash:
            throw PricingError.manualValuationOnly
        case .bankAccount, .eWallet, .cash, .electronics, .vehicle, .watch, .jewelry:
            throw PricingError.unsupportedInstrument(instrument)
        }
    }

    /// An IDR-denominated holding of a bare ticker ("BBCA") is an IDX stock —
    /// Yahoo's suffix for the Jakarta exchange is ".JK". Symbols that already
    /// carry an exchange suffix pass through untouched, as do US tickers
    /// (non-IDR cost basis).
    static func stockQuerySymbol(symbol: String, currency: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard currency == "IDR", !trimmed.contains(".") else { return trimmed }
        return trimmed + ".JK"
    }

    // MARK: - FX

    func fetchFXRate(from currencyCode: String, to currencyCode2: String) async throws -> Decimal {
        let from = currencyCode.uppercased()
        let to = currencyCode2.uppercased()
        guard from != to else { return 1 }

        let cacheKey = "\(from)/\(to)"
        if let cached = fxCache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < fxCacheTTL {
            return cached.rate
        }

        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(from)&symbols=\(to)")!
        let response: FrankfurterResponse = try await get(url)
        guard let rate = response.rates[to], rate > 0 else {
            throw PricingError.badResponse("no \(to) rate for \(from)")
        }
        let decimalRate = Decimal(rate)
        fxCache[cacheKey] = (decimalRate, Date())
        return decimalRate
    }

    // MARK: - Indodax

    private func indodaxLastPrice(symbol: String) async throws -> Decimal {
        let pair = symbol.trimmingCharacters(in: .whitespaces).lowercased() + "idr"
        let url = URL(string: "https://indodax.com/api/ticker/\(pair)")!
        let response: IndodaxTickerResponse = try await get(url)
        guard let ticker = response.ticker, let last = Decimal(string: ticker.last), last > 0 else {
            throw PricingError.symbolNotFound(symbol)
        }
        return last
    }

    // MARK: - Yahoo

    private func yahooPriceIDR(symbol: String) async throws -> Decimal {
        let quote = try await yahooPrice(symbol: symbol)
        guard quote.currency != "IDR" else { return quote.price }
        return try await quote.price * fetchFXRate(from: quote.currency, to: "IDR")
    }

    private func yahooPrice(symbol: String) async throws -> (price: Decimal, currency: String) {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
        components.path += symbol
        components.queryItems = [
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "interval", value: "1d"),
        ]
        let response: YahooChartResponse = try await get(components.url!)
        guard let meta = response.chart.result?.first?.meta,
              let price = meta.regularMarketPrice, price > 0 else {
            throw PricingError.symbolNotFound(symbol)
        }
        return (Decimal(price), meta.currency ?? "USD")
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        // Yahoo rate-limits default library user agents aggressively; a
        // browser UA keeps the keyless endpoint reliable.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, urlResponse) = try await session.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PricingError.badResponse("HTTP \(http.statusCode) from \(url.host ?? "?")")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PricingError.badResponse("undecodable payload from \(url.host ?? "?")")
        }
    }
}

// MARK: - Response payloads

struct IndodaxTickerResponse: Decodable {
    struct Ticker: Decodable {
        let last: String
    }

    /// Indodax returns {"error": "..."} with HTTP 200 for unknown pairs,
    /// so `ticker` must be optional rather than a decode failure.
    let ticker: Ticker?
}

struct FrankfurterResponse: Decodable {
    let base: String
    let rates: [String: Double]
}

struct YahooChartResponse: Decodable {
    struct Chart: Decodable {
        let result: [Result]?
    }

    struct Result: Decodable {
        let meta: Meta
    }

    struct Meta: Decodable {
        let currency: String?
        let regularMarketPrice: Double?
    }

    let chart: Chart
}
