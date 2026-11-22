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

    /// 以美元或美元稳定币计价的交易对显示 "$"。
    static let usdQuoteCurrencies: Set<String> = [
        "USD", "USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USDS", "USD1", "DAI",
    ]
    var isUSDQuoted: Bool { Self.usdQuoteCurrencies.contains(quote) }

    /// 带计价单位的价格文本：美元计价为 "$1,234.50"，其他为 "0.03456 BTC"。
    func priceLabel(_ priceText: String) -> String {
        isUSDQuoted ? "$\(priceText)" : "\(priceText) \(quote)"
    }

    /// 常见计价币（用于自动拆分 base/quote）。
    static let quoteCurrencies = [
        "USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USDS", "USD1", "DAI",
        "TRY", "EUR", "GBP", "JPY", "AUD", "BRL",
        "BTC", "ETH", "BNB",
    ]

    /// 加密资产计价币（BTC / ETH / BNB 计价的价格按有效数字展示）。
    static let cryptoQuoteCurrencies: Set<String> = ["BTC", "ETH", "BNB"]

    /// 名称恰好以 BTC/ETH/BNB 结尾、剩余部分有 2 个以上字符的完整资产名（不能拆成 "WB/ETH"）。
    /// 剩余只有 1 个字符的（WBTC / BETH / WETH）由拆分规则本身保留为整体；
    /// "ARBTC"、"OPETH" 这类 2 字母 base 仍按 AR/BTC、OP/ETH 拆分。
    static let wholeAssetNames: Set<String> = ["WBETH"]

    /// URL 中 symbol 参数允许的字符：只保留 ASCII 字母数字，其余（中文、带重音字母）百分号编码，
    /// 避免 macOS 13 上 `URL(string:)` 因非 ASCII 字符返回 nil。
    private static let urlSafeCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    static func urlEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: urlSafeCharacters) ?? value
    }

    /// 用于拼接请求 URL 的 symbol。
    var urlSymbol: String { Self.urlEscaped(binanceSymbol) }
    var urlTradePath: String { "\(Self.urlEscaped(base))_\(Self.urlEscaped(quote))" }

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
        // 用户写了分隔符（"AR/BTC"、"OP-ETH"）时，直接按分隔符拆分，不再猜测。
        let parts = input.uppercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
        if parts.count == 2 {
            let symbol = parts[0] + parts[1]
            return Coin(base: parts[0], quote: parts[1], coingeckoId: coingeckoMap[symbol])
        }

        let cleaned = input.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return nil }

        var base = cleaned
        var quote = "USDT"
        for q in quoteCurrencies where !wholeAssetNames.contains(cleaned) {
            guard cleaned.hasSuffix(q), cleaned.count > q.count else { continue }
            let candidate = String(cleaned.dropLast(q.count))
            // 单字符 base 配加密计价币几乎都是资产名本身（WBTC、BETH、WETH），按 /USDT 处理。
            if cryptoQuoteCurrencies.contains(q), candidate.count < 2 { continue }
            base = candidate
            quote = q
            break
        }
        let symbol = base + quote
        return Coin(base: base, quote: quote, coingeckoId: coingeckoMap[symbol])
    }

    /// 还原 UserDefaults 中保存的币种。
    ///
    /// 当前版本保存 "AR/BTC" 形式，按分隔符原样拆分；1.1.3 及更早版本保存的是不带分隔符的
    /// `binanceSymbol`，必须沿用当时的拆分规则（第一个匹配的计价币后缀），
    /// 否则 "WBTC"（当时即 W/BTC）等旧值会在升级后变成另一个交易对。
    static func restore(saved: String) -> Coin? {
        let upper = saved.uppercased()
        if upper.contains(where: { !($0.isLetter || $0.isNumber) }) {
            return make(from: saved)
        }
        guard !upper.isEmpty else { return nil }
        for q in quoteCurrencies where upper.hasSuffix(q) && upper.count > q.count {
            let base = String(upper.dropLast(q.count))
            return Coin(base: base, quote: q, coingeckoId: coingeckoMap[upper])
        }
        return Coin(base: upper, quote: "USDT", coingeckoId: coingeckoMap[upper + "USDT"])
    }

    /// 价格数字的格式：带 "$" 前缀的美元价格固定美式写法（"$1,234.50"），
    /// 其他计价币按系统地区格式（"0,03456 BTC"）。现货与美股合约共用同一规则。
    var priceLocale: Locale { isUSDQuoted ? Locale(identifier: "en_US") : .current }
}

/// 菜单栏价格格式化。
enum PriceFormatter {
    private static let fourDigitSymbols: Set<String> = [
        "XRP", "ADA", "DOGE", "TRX", "XLM", "HBAR", "DOT",
    ]

    /// 普通币种保留 2 位；常见低价币保留 4 位，极低价格自动增加精度。
    static func crypto(_ price: Double, base: String, quote: String = "USDT",
                       locale: Locale = .current) -> String {
        // BTC/ETH/BNB 计价的价格通常远小于 1，按有效数字展示，避免 0.03456 变成 0.03。
        if Coin.cryptoQuoteCurrencies.contains(quote) {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = locale
            f.usesSignificantDigits = true
            f.minimumSignificantDigits = 4
            f.maximumSignificantDigits = 6
            f.usesGroupingSeparator = true
            return f.string(from: NSNumber(value: price)) ?? String(format: "%g", price)
        }
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

    /// 美股合约固定按美元两位小数展示（locale 由调用方按 `Coin.priceLocale` 传入）。
    ///
    /// 使用 `en_US` 而非 `en_US_POSIX`：后者不保证千分位分组，
    /// macOS 14 与更新版本的 Foundation 输出会不一致。
    static func stock(_ price: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
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