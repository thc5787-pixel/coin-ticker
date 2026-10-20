import Foundation

/// Binance USDⓈ-M 美股永续合约的 24 小时行情快照。
struct StockContractQuote: Equatable {
    let symbol: String
    let price: Double
    let changePercent: Double

    /// 判断 exchangeInfo 中的交易对是否为可交易的 USDT 美股永续合约。
    static func isEquitySymbol(_ symbol: String, in exchangeInfo: [String: Any]) -> Bool {
        guard let entries = exchangeInfo["symbols"] as? [[String: Any]] else { return false }
        return entries.contains {
            $0["symbol"] as? String == symbol &&
            $0["contractType"] as? String == "TRADIFI_PERPETUAL" &&
            $0["underlyingType"] as? String == "EQUITY" &&
            $0["quoteAsset"] as? String == "USDT" &&
            $0["status"] as? String == "TRADING"
        }
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
