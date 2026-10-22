import Foundation

/// Binance 现货 24 小时行情快照。
struct SpotQuote: Equatable {
    let price: Double
    let changePercent: Double

    static func parse(symbol: String, response: [String: Any]) -> SpotQuote? {
        guard response["symbol"] as? String == symbol,
              let priceString = response["lastPrice"] as? String,
              let price = Double(priceString),
              price.isFinite, price > 0,
              let changeString = response["priceChangePercent"] as? String,
              let change = Double(changeString),
              change.isFinite else {
            return nil
        }
        return SpotQuote(price: price, changePercent: change)
    }
}