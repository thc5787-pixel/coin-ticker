import Foundation

var failures = 0

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("PASS: \(message)")
    } else {
        failures += 1
        print("FAIL: \(message)")
    }
}

let symbol = "AAPLUSDT"
let validResponse: [String: Any] = [
    "symbol": symbol,
    "lastPrice": "342.37000",
    "priceChangePercent": "-0.436",
]

let validQuote = StockContractQuote.parse(symbol: symbol, response: validResponse)
expect(validQuote != nil, "parses a valid AAPLUSDT 24h ticker response")
expect(validQuote?.symbol == symbol, "keeps the contract symbol")
expect(abs((validQuote?.price ?? 0) - 342.37) < 0.000_001, "parses lastPrice as a number")
expect(abs((validQuote?.changePercent ?? 0) - (-0.436)) < 0.000_001, "parses priceChangePercent as a number")

expect(StockContractQuote.parse(symbol: symbol, response: [:]) == nil,
       "rejects an empty response")
expect(StockContractQuote.parse(symbol: symbol, response: [
    "symbol": symbol,
    "lastPrice": "342.37",
]) == nil, "rejects a response without priceChangePercent")
expect(StockContractQuote.parse(symbol: symbol, response: [
    "symbol": symbol,
    "lastPrice": "not-a-number",
    "priceChangePercent": "1.2",
]) == nil, "rejects a non-numeric lastPrice")
expect(StockContractQuote.parse(symbol: symbol, response: [
    "symbol": symbol,
    "lastPrice": "342.37",
    "priceChangePercent": "nan",
]) == nil, "rejects a non-finite priceChangePercent")
expect(StockContractQuote.parse(symbol: symbol, response: [
    "symbol": symbol,
    "lastPrice": "-1",
    "priceChangePercent": "1.2",
]) == nil, "rejects a non-positive lastPrice")
expect(StockContractQuote.parse(symbol: symbol, response: [
    "symbol": "MSFTUSDT",
    "lastPrice": "342.37",
    "priceChangePercent": "1.2",
]) == nil, "rejects a response for a different contract")

let exchangeInfo: [String: Any] = [
    "symbols": [
        [
            "symbol": "AAPLUSDT",
            "contractType": "TRADIFI_PERPETUAL",
            "underlyingType": "EQUITY",
            "quoteAsset": "USDT",
            "status": "TRADING",
        ],
        [
            "symbol": "BTCUSDT",
            "contractType": "PERPETUAL",
            "underlyingType": "COIN",
            "quoteAsset": "USDT",
            "status": "TRADING",
        ],
        [
            "symbol": "MSFTUSDT",
            "contractType": "TRADIFI_PERPETUAL",
            "underlyingType": "EQUITY",
            "quoteAsset": "USDT",
            "status": "SETTLING",
        ],
        [
            "symbol": "SPCXUSD1",
            "contractType": "TRADIFI_PERPETUAL",
            "underlyingType": "EQUITY",
            "quoteAsset": "USD1",
            "status": "TRADING",
        ],
        [
            "symbol": "TESTUSDC",
            "contractType": "TRADIFI_PERPETUAL",
            "underlyingType": "EQUITY",
            "quoteAsset": "USDC",
            "status": "TRADING",
        ],
    ],
]

expect(StockContractQuote.isEquitySymbol("AAPLUSDT", in: exchangeInfo),
       "recognizes a trading USDT equity perpetual")
expect(!StockContractQuote.isEquitySymbol("BTCUSDT", in: exchangeInfo),
       "rejects a crypto perpetual with the same quote asset")
expect(!StockContractQuote.isEquitySymbol("MSFTUSDT", in: exchangeInfo),
       "rejects an equity perpetual that is not trading")
expect(StockContractQuote.isEquitySymbol("SPCXUSD1", in: exchangeInfo),
       "recognizes a USD1-quoted equity perpetual")
expect(!StockContractQuote.isEquitySymbol("TESTUSDC", in: exchangeInfo),
       "rejects an unsupported equity quote asset")
expect(!StockContractQuote.isEquitySymbol("NOPEUSDT", in: exchangeInfo),
       "rejects an unknown symbol")
expect(!StockContractQuote.isEquitySymbol("AAPLUSDT", in: [:]),
       "rejects missing exchange info")
expect(StockContractQuote.equitySymbols(in: exchangeInfo) == ["AAPLUSDT", "SPCXUSD1"],
       "collects only supported trading equity perpetuals")
expect(StockContractQuote.equitySymbols(in: [:]).isEmpty,
       "returns an empty equity set without exchange info")

// MARK: - Spot response classification

let tradingSpot: [String: Any] = [
    "symbols": [[
        "symbol": "MDTUSDT",
        "status": "TRADING",
        "quoteAsset": "USDT",
    ]]
]
expect(SpotValidation.classify(status: 200, symbol: "MDTUSDT", response: tradingSpot) == .valid,
       "classifies a TRADING spot symbol as valid")
expect(SpotValidation.classify(status: 200, symbol: "MDTUSDT", response: [
    "symbols": [[ "symbol": "MDTUSDT", "status": "BREAK" ]]
]) == .notTrading, "classifies a BREAK spot symbol as notTrading")
expect(SpotValidation.classify(status: 400, symbol: "NOPEUSDT", response: ["code": -1121]) == .invalid,
       "classifies a -1121 response as invalid")
expect(SpotValidation.classify(status: 403, symbol: "MDTUSDT", response: [:]) == nil,
       "leaves non-symbol errors for host fallback")
expect(SpotValidation.classify(status: 400, symbol: "NOPE", response: ["code": -1100]) == .invalid,
       "classifies an illegal-characters response as invalid")
expect(SpotValidation.classify(status: 429, symbol: "MDTUSDT", response: ["code": -1003]) == nil,
       "leaves rate limiting for host fallback")
expect(SpotValidation.classify(status: 418, symbol: "MDTUSDT", response: ["code": -1003]) == nil,
       "leaves an IP ban for host fallback")
expect(SpotValidation.classify(status: 400, symbol: "MDTUSDT", response: [:]) == nil,
       "leaves a 400 without a Binance code for host fallback")
expect(SpotValidation.classify(status: nil, symbol: "MDTUSDT", response: [:]) == nil,
       "leaves a transport failure for host fallback")
expect(BinanceResponse.isDefinitiveRejection(status: 400, response: ["code": -1121, "msg": "Invalid symbol."]),
       "treats -1121 as a definitive rejection")
expect(!BinanceResponse.isDefinitiveRejection(status: 503, response: ["code": -1001]),
       "does not treat a server error as a definitive rejection")
expect(!BinanceResponse.isDefinitiveRejection(status: 451, response: [
    "code": 0, "msg": "Service unavailable from a restricted location",
]), "does not treat a restricted-location response as an invalid symbol")
expect(SpotValidation.classify(status: 451, symbol: "BTCUSDT", response: ["code": 0]) == nil,
       "leaves a restricted-location response for host fallback")
expect(!BinanceResponse.isDefinitiveRejection(status: 400, response: ["code": -1102]),
       "does not treat an unrelated 400 error code as an invalid symbol")

// MARK: - Preferred host race

var primaryWins = PreferredHostRace<Int>()
if case .pending = primaryWins.record(2, from: .fallback) {} else { expect(false, "fallback waits for primary") }
if case .done(1?) = primaryWins.record(1, from: .primary) {
    expect(true, "primary result wins over an earlier fallback result")
} else { expect(false, "primary result wins over an earlier fallback result") }
var primaryFails = PreferredHostRace<Int>()
_ = primaryFails.record(2, from: .fallback)
if case .done(2?) = primaryFails.record(nil, from: .primary) {
    expect(true, "uses the fallback result after primary fails")
} else { expect(false, "uses the fallback result after primary fails") }
var graceRace = PreferredHostRace<Int>()
_ = graceRace.record(2, from: .fallback)
if case .done(2?) = graceRace.graceExpired() {
    expect(true, "uses the fallback result after the grace period")
} else { expect(false, "uses the fallback result after the grace period") }
if case .pending = graceRace.record(1, from: .primary) {
    expect(true, "ignores primary after the race finished")
} else { expect(false, "ignores primary after the race finished") }
var bothFail = PreferredHostRace<Int>()
_ = bothFail.record(nil, from: .primary)
if case .done(nil) = bothFail.record(nil, from: .fallback) {
    expect(true, "reports no result when both hosts fail")
} else { expect(false, "reports no result when both hosts fail") }
var noGrace = PreferredHostRace<Int>()
_ = noGrace.record(nil, from: .fallback)
if case .pending = noGrace.graceExpired() {
    expect(true, "grace does not finish without a fallback result")
} else { expect(false, "grace does not finish without a fallback result") }

// MARK: - Stock exchangeInfo classification

expect(StockValidation.equitySymbols(status: 200, response: exchangeInfo) == ["AAPLUSDT", "SPCXUSD1"],
       "collects equity symbols from a successful exchangeInfo response")
expect(StockValidation.equitySymbols(status: 200, response: [:]) == nil,
       "ignores a 200 exchangeInfo response without symbols")
expect(StockValidation.equitySymbols(status: 403, response: exchangeInfo) == nil,
       "ignores a non-200 exchangeInfo response")
expect(SpotValidation.classify(status: 200, symbol: "MDTUSDT", response: [
    "symbols": [[ "symbol": "OTHERUSDT", "status": "TRADING" ]]
]) == nil, "ignores a response for a different symbol")
expect(SpotValidation.classify(status: 200, symbol: "MDTUSDT", response: [:]) == nil,
       "ignores a 200 response without symbol data")

// MARK: - Market selection

expect(MarketSelection.resolve(preference: .auto, spot: .valid, stock: .invalid) == .spot,
       "auto uses spot when the spot symbol is trading")
expect(MarketSelection.resolve(preference: .auto, spot: .notTrading, stock: .valid) == .stock,
       "auto prefers a trading equity perp over a halted spot symbol")
expect(MarketSelection.resolve(preference: .auto, spot: .notTrading, stock: .invalid) == .notTrading,
       "auto reports a halted spot symbol when no equity perp exists")
expect(MarketSelection.resolve(preference: .auto, spot: .notTrading, stock: .notTrading) == .notTrading,
       "auto reports halted when neither market is trading")
expect(MarketSelection.resolve(preference: .auto, spot: .notTrading, stock: .network) == .network,
       "auto does not guess when the equity check is unavailable")
expect(MarketSelection.resolve(preference: .auto, spot: .invalid, stock: .valid) == .stock,
       "auto falls back to an equity perp")
expect(MarketSelection.resolve(preference: .auto, spot: .invalid, stock: .invalid) == .invalid,
       "auto reports invalid when neither market knows the symbol")
expect(MarketSelection.resolve(preference: .auto, spot: .network, stock: .valid) == .stock,
       "auto still uses an equity perp when spot is unreachable")
expect(MarketSelection.resolve(preference: .auto, spot: .network, stock: .invalid) == .network,
       "auto reports network when spot is unreachable and stock is invalid")
expect(MarketSelection.resolve(preference: .auto, spot: .network, stock: .network) == .network,
       "auto reports network when both checks fail")
expect(MarketSelection.resolve(preference: .spot, spot: .notTrading, stock: .invalid) == .notTrading,
       "explicit spot rejects a halted spot symbol instead of showing a frozen price")
expect(MarketSelection.resolve(preference: .spot, spot: .valid, stock: .invalid) == .spot,
       "explicit spot accepts a trading spot symbol")
expect(MarketSelection.resolve(preference: .spot, spot: .invalid, stock: .valid) == .invalid,
       "explicit spot does not fall back to stock")
expect(MarketSelection.resolve(preference: .stock, spot: .valid, stock: .valid) == .stock,
       "explicit stock overrides a trading spot symbol")
expect(MarketSelection.resolve(preference: .stock, spot: .invalid, stock: .network) == .network,
       "explicit stock reports network")
expect(MarketSelection.resolve(preference: .stock, spot: .valid, stock: .invalid) == .invalid,
       "explicit stock reports invalid when no equity perp exists")

// MARK: - Coin parsing

expect(Coin.make(from: "ETH")?.binanceSymbol == "ETHUSDT",
       "defaults a bare base asset to /USDT")
expect(Coin.make(from: "ethusdt")?.base == "ETH" && Coin.make(from: "ethusdt")?.quote == "USDT",
       "parses a lowercase full pair")
expect(Coin.make(from: "ETH/USDT")?.binanceSymbol == "ETHUSDT",
       "ignores separators in a full pair")
expect(Coin.make(from: "ETH-BTC")?.base == "ETH" && Coin.make(from: "ETH-BTC")?.quote == "BTC",
       "parses an explicit crypto-quoted pair")
expect(Coin.make(from: "WBTC")?.base == "WBTC" && Coin.make(from: "WBTC")?.quote == "USDT",
       "keeps wrapped BTC whole instead of splitting W/BTC")
expect(Coin.make(from: "WBTC")?.binanceSymbol == "WBTCUSDT",
       "resolves WBTC shorthand to WBTCUSDT")
expect(Coin.make(from: "WBETH")?.base == "WBETH" && Coin.make(from: "WBETH")?.quote == "USDT",
       "keeps wrapped ETH whole instead of splitting WB/ETH")
expect(Coin.make(from: "WBTCUSDT")?.base == "WBTC" && Coin.make(from: "WBTCUSDT")?.quote == "USDT",
       "still parses an explicit WBTC/USDT pair")
expect(Coin.make(from: "WUSDT")?.base == "W" && Coin.make(from: "WUSDT")?.quote == "USDT",
       "still splits a short base from a stablecoin quote")
expect(Coin.make(from: "BTCUSDT")?.coingeckoId == "bitcoin",
       "maps a known symbol to its CoinGecko id")
expect(Coin.make(from: "SPCXUSD1")?.base == "SPCX" && Coin.make(from: "SPCXUSD1")?.quote == "USD1",
       "parses a USD1-quoted equity contract")
expect(Coin.make(from: "") == nil, "rejects empty input")
expect(Coin.make(from: "AR/BTC")?.base == "AR" && Coin.make(from: "AR/BTC")?.quote == "BTC",
       "honors an explicit separator for a short base with a BTC quote")
expect(Coin.make(from: "op-eth")?.binanceSymbol == "OPETH",
       "honors a dash separator for a short base with an ETH quote")
expect(Coin.make(from: "ETH/USDT")?.base == "ETH" && Coin.make(from: "ETH/USDT")?.quote == "USDT",
       "splits a slash-separated pair")
expect(Coin.make(from: "ARBTC")?.base == "AR" && Coin.make(from: "ARBTC")?.quote == "BTC",
       "splits a short base from a BTC quote without a separator")
expect(Coin.make(from: "OPETH")?.base == "OP" && Coin.make(from: "OPETH")?.quote == "ETH",
       "splits a short base from an ETH quote without a separator")
expect(Coin.make(from: "BETH")?.binanceSymbol == "BETHUSDT",
       "keeps Beacon ETH whole instead of splitting B/ETH")
expect(Coin.make(from: "WETH")?.binanceSymbol == "WETHUSDT",
       "keeps wrapped ETH whole instead of splitting W/ETH")
expect(Coin.make(from: "WBETH")?.binanceSymbol == "WBETHUSDT",
       "keeps WBETH whole")
expect(Coin.make(from: "W/BTC")?.base == "W" && Coin.make(from: "W/BTC")?.quote == "BTC",
       "an explicit separator still allows a one-letter base")
expect(Coin.make(from: "WBETHETH")?.base == "WBETH" && Coin.make(from: "WBETHETH")?.quote == "ETH",
       "still splits an explicit wrapped-asset pair")
for input in ["AR/BTC", "op-eth", "ETH/XYZ", "WBTC", "BETH", "AAPL/USDT", "SPCX/USD1", "W/BTC"] {
    let coin = Coin.make(from: input)!
    let restored = Coin.restore(saved: coin.pair)
    expect(restored?.base == coin.base && restored?.quote == coin.quote,
           "the saved pair for \(input) restores the same base and quote")
}
// 1.1.3 及更早版本保存的无分隔符 binanceSymbol，必须按当时的规则还原。
for (saved, base, quote) in [
    ("ARBTC", "AR", "BTC"), ("WBTC", "W", "BTC"), ("WBTCUSDT", "WBTC", "USDT"),
    ("BETHUSDT", "BETH", "USDT"), ("ETHUSDT", "ETH", "USDT"), ("AAPLUSDT", "AAPL", "USDT"),
] {
    let restored = Coin.restore(saved: saved)
    expect(restored?.base == base && restored?.quote == quote,
           "restores legacy saved value \(saved) as \(base)/\(quote)")
}
expect(Coin.restore(saved: "AR/BTC")?.binanceSymbol == "ARBTC", "restores a saved pair with a separator")
expect(Coin.restore(saved: "WBTC/USDT")?.binanceSymbol == "WBTCUSDT", "restores a saved wrapped-asset pair")
expect(Coin.restore(saved: "BTCUSDT")?.coingeckoId == "bitcoin", "keeps the CoinGecko id for a legacy value")
expect(Coin.restore(saved: "") == nil, "rejects an empty saved value")
let cjkCoin = Coin.make(from: "币安人生USDT")
expect(cjkCoin?.base == "币安人生" && cjkCoin?.quote == "USDT", "keeps a CJK base asset")
expect(cjkCoin.map { URL(string: "https://api.binance.com/api/v3/ticker/24hr?symbol=\($0.urlSymbol)") != nil } == true,
       "builds a valid URL for a CJK symbol")
expect(cjkCoin?.urlSymbol == "%E5%B8%81%E5%AE%89%E4%BA%BA%E7%94%9FUSDT",
       "percent-encodes non-ASCII symbol characters")
expect(Coin.make(from: "ETHUSDT")?.urlSymbol == "ETHUSDT", "leaves ASCII symbols unchanged")
expect(Coin.make(from: "ETH/USDT")?.priceLabel("1,234.50") == "$1,234.50",
       "labels a stablecoin-quoted price with $")
expect(Coin.make(from: "ETH/BTC")?.priceLabel("0.03456") == "0.03456 BTC",
       "labels a BTC-quoted price with its quote code")
expect(Coin.make(from: "BTC/EUR")?.priceLabel("90,000.00") == "90,000.00 EUR",
       "labels a EUR-quoted price with its quote code")

// MARK: - Spot quote parsing

let validSpotResponse: [String: Any] = [
    "symbol": "ETHUSDT",
    "lastPrice": "342.37000",
    "priceChangePercent": "-0.436",
]
let validSpotQuote = SpotQuote.parse(symbol: "ETHUSDT", response: validSpotResponse)
expect(validSpotQuote != nil, "parses a valid spot ticker response")
expect(abs((validSpotQuote?.price ?? 0) - 342.37) < 0.000_001, "parses spot lastPrice")
expect(abs((validSpotQuote?.changePercent ?? 0) - (-0.436)) < 0.000_001,
       "parses spot priceChangePercent")
expect(SpotQuote.parse(symbol: "ETHUSDT", response: [
    "symbol": "ETHUSDT", "lastPrice": "nan", "priceChangePercent": "1.2",
]) == nil, "rejects a NaN spot price")
expect(SpotQuote.parse(symbol: "ETHUSDT", response: [
    "symbol": "ETHUSDT", "lastPrice": "inf", "priceChangePercent": "1.2",
]) == nil, "rejects an infinite spot price")
expect(SpotQuote.parse(symbol: "ETHUSDT", response: [
    "symbol": "ETHUSDT", "lastPrice": "-1", "priceChangePercent": "1.2",
]) == nil, "rejects a non-positive spot price")
expect(SpotQuote.parse(symbol: "ETHUSDT", response: [
    "symbol": "ETHUSDT", "lastPrice": "342.37", "priceChangePercent": "nan",
]) == nil, "rejects a non-finite spot change")
expect(SpotQuote.parse(symbol: "ETHUSDT", response: [
    "symbol": "ETHUSDT", "lastPrice": "not-a-number", "priceChangePercent": "1.2",
]) == nil, "rejects a non-numeric spot price")
expect(SpotQuote.parse(symbol: "ETHUSDT", response: [
    "symbol": "BTCUSDT", "lastPrice": "342.37", "priceChangePercent": "1.2",
]) == nil, "rejects a spot response for a different symbol")

// MARK: - Price formatting

// en_US_POSIX 在 macOS 14 的 Foundation 上不保证千分位分组，
// 因此这里用行为稳定的 en_US 断言用户可见格式。
let enUS = Locale(identifier: "en_US")
expect(PriceFormatter.crypto(1234.5, base: "ETH", locale: enUS) == "1,234.50",
       "formats a normal crypto price with two decimals")
expect(PriceFormatter.crypto(0.5, base: "XRP", locale: enUS) == "0.5000",
       "formats a low-priced coin with four decimals")
expect(PriceFormatter.crypto(0.0000012345, base: "DOGE", locale: enUS) == "0.0000012345",
       "formats a very small price with adaptive precision")
expect(PriceFormatter.crypto(0.03456, base: "ETH", quote: "BTC", locale: enUS) == "0.03456",
       "keeps significant digits for a BTC-quoted price")
expect(PriceFormatter.crypto(0.2, base: "BNB", quote: "ETH", locale: enUS) == "0.2000",
       "pads an ETH-quoted price to four significant digits")
expect(PriceFormatter.stock(344.01, locale: enUS) == "344.01",
       "formats a stock price with two decimals")
expect(PriceFormatter.stock(1234.5, locale: enUS) == "1,234.50",
       "formats a stock price with grouping")
expect(PriceFormatter.stock(1234.5) == "1,234.50",
       "stock formatting defaults to grouped US dollars")
let ethUSDT = Coin.make(from: "ETH/USDT")!
let aaplUSDT = Coin.make(from: "AAPLUSDT")!
expect(ethUSDT.priceLocale.identifier == "en_US" && aaplUSDT.priceLocale.identifier == "en_US",
       "dollar-labelled crypto and stock prices share the US format")
expect(Coin.make(from: "ETH/BTC")!.priceLocale.identifier == Locale.current.identifier,
       "non-dollar quotes follow the system locale")
expect(ethUSDT.priceLabel(PriceFormatter.crypto(1234.5, base: "ETH", locale: ethUSDT.priceLocale))
       == aaplUSDT.priceLabel(PriceFormatter.stock(1234.5, locale: aaplUSDT.priceLocale)),
       "ETH and AAPL render the same dollar format")

// MARK: - Change formatting

expect(ChangeFormatter.text(1.234) == "▲+1.23%", "formats a positive change")
expect(ChangeFormatter.text(-0.436) == "▼-0.44%", "formats a negative change")
expect(ChangeFormatter.text(0) == "▲+0.00%", "formats a flat change")
expect(ChangeFormatter.arrow(-1) == "▼", "uses a down arrow for negative changes")

// MARK: - Language resolution

expect(LanguageResolver.resolve(selected: "en", preferredLanguages: ["zh-Hans-CN"]) == "en",
       "honors an explicit English selection")
expect(LanguageResolver.resolve(selected: "zh-Hans", preferredLanguages: ["en-US"]) == "zh-Hans",
       "honors an explicit Chinese selection")
expect(LanguageResolver.resolve(selected: nil, preferredLanguages: ["zh-Hant-TW"]) == "zh-Hans",
       "maps Chinese system languages to the bundled zh-Hans table")
expect(LanguageResolver.resolve(selected: "system", preferredLanguages: ["fr-FR"]) == "en",
       "falls back to English for unsupported system languages")
expect(LanguageResolver.resolve(selected: "de", preferredLanguages: ["en-US"]) == "en",
       "ignores an unsupported stored language")

// MARK: - Host probing

var race = ValidationRace(hostCount: 3)
expect(race.record(nil) == nil, "race waits while hosts remain")
expect(race.record(.valid) == .valid, "race finishes on the first conclusive result")
expect(race.record(.invalid) == nil, "race ignores results after finishing")
var allFailed = ValidationRace(hostCount: 2)
expect(allFailed.record(nil) == nil, "race waits after the first inconclusive host")
expect(allFailed.record(nil) == .network, "race returns network after every host fails")
var invalidWins = ValidationRace(hostCount: 5)
expect(invalidWins.record(.invalid) == .invalid, "race finishes immediately on an invalid symbol")

if failures > 0 {
    print("\(failures) test(s) failed")
    exit(1)
}

print("All tests passed")
