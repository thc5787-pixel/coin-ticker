import Foundation

/// Binance USDⓈ-M 美股永续合约的 24 小时行情快照。
struct StockContractQuote: Equatable {
    let symbol: String
    let price: Double
    let changePercent: Double

    /// 支持的美股永续计价币。
    static let supportedQuoteAssets: Set<String> = ["USDT", "USD1"]

    /// 判断 exchangeInfo 中的交易对是否为可交易的美股永续合约。
    static func isEquitySymbol(_ symbol: String, in exchangeInfo: [String: Any]) -> Bool {
        equitySymbols(in: exchangeInfo).contains(symbol)
    }

    /// 收集 exchangeInfo 中所有可交易的美股永续合约 symbol。
    static func equitySymbols(in exchangeInfo: [String: Any]) -> Set<String> {
        guard let entries = exchangeInfo["symbols"] as? [[String: Any]] else { return [] }
        return Set(entries.compactMap { entry in
            guard entry["contractType"] as? String == "TRADIFI_PERPETUAL",
                  entry["underlyingType"] as? String == "EQUITY",
                  let quote = entry["quoteAsset"] as? String,
                  supportedQuoteAssets.contains(quote),
                  entry["status"] as? String == "TRADING",
                  let symbol = entry["symbol"] as? String else { return nil }
            return symbol
        })
    }

    static func parse(symbol: String, response: [String: Any]) -> StockContractQuote? {
        guard let responseSymbol = response["symbol"] as? String,
              responseSymbol == symbol,
              let priceString = response["lastPrice"] as? String,
              let price = Double(priceString),
              price.isFinite, price > 0,
              let changeString = response["priceChangePercent"] as? String,
              let change = Double(changeString),
              change.isFinite else {
            return nil
        }
        return StockContractQuote(symbol: responseSymbol, price: price, changePercent: change)
    }
}
