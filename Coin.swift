import Foundation

/// 标的所在市场。
enum Market: Equatable {
    case spot
    case stockContract
}

/// 币种/合约模型：由用户输入解析而来。
struct Coin {
    let base: String
    let quote: String
    var coingeckoId: String?
    var market: Market = .spot

    var binanceSymbol: String { base + quote }
    var displaySymbol: String { base }
    var pair: String { "\(base)/\(quote)" }
    var tradePath: String { "\(base)_\(quote)" }

    /// 常见计价币（用于自动拆分 base/quote）。
    static let quoteCurrencies = [
        "USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USDS", "USD1", "DAI",
        "TRY", "EUR", "GBP", "JPY", "AUD", "BRL",
        "BTC", "ETH", "BNB",
    ]

    /// 加密资产计价币：简称可能本身就是以它们结尾的资产名（WBTC / WBETH）。
    private static let cryptoQuoteCurrencies: Set<String> = ["BTC", "ETH", "BNB"]

    /// 常见币种的 CoinGecko 资产 id（仅 USDT 交易对需要回退）。
    static let coingeckoMap: [String: String] = [
        "BTCUSDT":  "bitcoin",
        "ETHUSDT":  "ethereum",
        "XRPUSDT":  "ripple",
        "BNBUSDT":  "binancecoin",
        "SOLUSDT":  "solana",
        "DOGEUSDT": "dogecoin",
        "ADAUSDT":  "cardano",
        "TRXUSDT":  "tron",
        "AVAXUSDT": "avalanche-2",
        "LINKUSDT": "chainlink",
        "SUIUSDT":  "sui",
        "TONUSDT":  "the-open-network",
        "XLMUSDT":  "stellar",
        "DOTUSDT":  "polkadot",
        "HBARUSDT": "hedera-hashgraph",
        "BCHUSDT":  "bitcoin-cash",
        "LTCUSDT":  "litecoin",
        "UNIUSDT":  "uniswap",
        "SHIBUSDT": "shiba-inu",
        "NEARUSDT": "near",
    ]

    /// 从用户输入解析币种：支持 "ETH"、"ethusdt"、"ETH/USDT"、"ETH-USDT" 等。
    static func make(from input: String) -> Coin? {
        let cleaned = input.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return nil }

        var base = cleaned
        var quote = "USDT"
        for q in quoteCurrencies {
            guard cleaned.hasSuffix(q), cleaned.count > q.count else { continue }
            let candidate = String(cleaned.dropLast(q.count))
            // WBTC / WBETH 这类包装资产的简称：剩余部分只有 1-2 个字符时，
            // 整体更可能是 base（默认 /USDT），而不是 "W/BTC"。
            if cryptoQuoteCurrencies.contains(q), candidate.count < 3 {
                continue
            }
            base = candidate
            quote = q
            break
        }
        let symbol = base + quote
        return Coin(base: base, quote: quote, coingeckoId: coingeckoMap[symbol])
    }
}

/// 菜单栏价格格式化。
enum PriceFormatter {
    private static let fourDigitSymbols: Set<String> = [
        "XRP", "ADA", "DOGE", "TRX", "XLM", "HBAR", "DOT",
    ]

    /// 普通币种保留 2 位；常见低价币保留 4 位，极低价格自动增加精度。
    static func crypto(_ price: Double, base: String, locale: Locale = .current) -> String {
        let absPrice = abs(price)
        let usesFourDigits = fourDigitSymbols.contains(base)
        let minDigits = usesFourDigits ? 4 : 2
        let maxDigits: Int
        if absPrice < 0.000001 { maxDigits = 12 }
        else if absPrice < 0.0001 { maxDigits = 10 }
        else if absPrice < 0.01 { maxDigits = 8 }
        else if usesFourDigits { maxDigits = 4 }
        else { maxDigits = 2 }

        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.minimumFractionDigits = minDigits
        f.maximumFractionDigits = maxDigits
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: price)) ?? String(format: "%.*f", maxDigits, price)
    }

    /// 美股合约固定按美元两位小数展示。
    static func stock(_ price: Double, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }
}

/// 24 小时涨跌的统一文案。
enum ChangeFormatter {
    static func arrow(_ change: Double) -> String { change >= 0 ? "▲" : "▼" }
    static func percent(_ change: Double) -> String { String(format: "%+.2f%%", change) }
    static func text(_ change: Double) -> String { arrow(change) + percent(change) }
}