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
    ],
]

expect(StockContractQuote.isEquitySymbol("AAPLUSDT", in: exchangeInfo),
       "recognizes a trading USDT equity perpetual")
expect(!StockContractQuote.isEquitySymbol("BTCUSDT", in: exchangeInfo),
       "rejects a crypto perpetual with the same quote asset")
expect(!StockContractQuote.isEquitySymbol("MSFTUSDT", in: exchangeInfo),
       "rejects an equity perpetual that is not trading")
expect(!StockContractQuote.isEquitySymbol("SPCXUSD1", in: exchangeInfo),
       "rejects a non-USDT equity perpetual")
expect(!StockContractQuote.isEquitySymbol("NOPEUSDT", in: exchangeInfo),
       "rejects an unknown symbol")
expect(!StockContractQuote.isEquitySymbol("AAPLUSDT", in: [:]),
       "rejects missing exchange info")

if failures > 0 {
    print("\(failures) test(s) failed")
    exit(1)
}

print("All StockContractQuote tests passed")
