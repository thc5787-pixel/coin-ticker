import Foundation

/// 用户在输入框中指定的市场偏好。
enum MarketPreference {
    case auto
    case spot
    case stock
}

/// 单个市场的验证结果。
enum MarketValidation: Equatable {
    case valid
    /// symbol 存在，但当前不是 TRADING 状态（例如 BREAK / FAIL）。
    case notTrading
    case invalid
    case network
}

/// 两个市场验证后最终选择的标的类型。
enum ResolvedMarket: Equatable {
    case spot
    case stock
    case invalid
    /// 现货 symbol 存在但已停牌，且没有可用的同名美股合约。
    case notTrading
    case network
}

/// 根据用户偏好与两个市场的验证结果，决定最终使用哪个市场。
///
/// 自动模式的关键规则：现货存在但不是 TRADING（如 MDT：现货已停牌，同名美股合约
/// 仍在交易）时，若同名美股合约可交易则选择美股合约，避免静默显示错误标的。
enum MarketSelection {
    static func resolve(preference: MarketPreference,
                        spot: MarketValidation,
                        stock: MarketValidation) -> ResolvedMarket {
        switch preference {
        case .spot:
            switch spot {
            case .valid:
                return .spot
            case .notTrading:
                // 停牌现货只有冻结的最后成交价，展示出来会被误认为实时行情。
                return .notTrading
            case .invalid:
                return .invalid
            case .network:
                return .network
            }
        case .stock:
            switch stock {
            case .valid:
                return .stock
            case .invalid, .notTrading:
                return .invalid
            case .network:
                return .network
            }
        case .auto:
            switch spot {
            case .valid:
                return .spot
            case .notTrading:
                // 现货已停牌：有可交易的美股合约就用合约；确认没有时报停牌，
                // 无法确认时宁可报网络错误，也不静默选错标的。
                switch stock {
                case .valid:
                    return .stock
                case .invalid, .notTrading:
                    return .notTrading
                case .network:
                    return .network
                }
            case .invalid, .network:
                switch stock {
                case .valid:
                    return .stock
                case .network:
                    return .network
                case .invalid, .notTrading:
                    return spot == .invalid ? .invalid : .network
                }
            }
        }
    }
}

/// Binance 接口错误响应的判定。
enum BinanceResponse {
    /// 表示 symbol 本身不合法的错误码：-1121 Invalid symbol，-1100 非法字符。
    static let symbolErrorCodes: Set<Int> = [-1121, -1100]

    /// Binance 对 symbol 给出的明确拒绝：每个域名都会给出同样的答案，不必再换域名重试。
    /// 只认 HTTP 400 + 已知 symbol 错误码；451（受限地区，`code: 0`）、403、418/429 限流等
    /// 都与 symbol 无关，仍走换域名 / CoinGecko 回退 / 网络错误路径。
    static func isDefinitiveRejection(status: Int?, response: [String: Any]) -> Bool {
        guard status == 400, let code = response["code"] as? Int else { return false }
        return symbolErrorCodes.contains(code)
    }
}

/// 解析 Binance 现货 `exchangeInfo?symbol=` 的响应。
/// 返回 nil 表示该响应不能下结论，应继续等待/尝试其他域名。
enum SpotValidation {
    static func classify(status: Int?, symbol: String,
                         response: [String: Any]) -> MarketValidation? {
        if status == 200,
           let symbols = response["symbols"] as? [[String: Any]],
           let entry = symbols.first(where: { $0["symbol"] as? String == symbol }) {
            return entry["status"] as? String == "TRADING" ? .valid : .notTrading
        }
        if BinanceResponse.isDefinitiveRejection(status: status, response: response) {
            return .invalid
        }
        return nil
    }
}

/// 解析 Binance USDⓈ-M `exchangeInfo` 的响应：返回可交易美股合约集合，
/// nil 表示该域名的响应不能下结论。
enum StockValidation {
    static func equitySymbols(status: Int?, response: [String: Any]) -> Set<String>? {
        guard status == 200, response["symbols"] is [[String: Any]] else { return nil }
        return StockContractQuote.equitySymbols(in: response)
    }
}

/// 首选域名 + 备用域名并行请求时的结果聚合：首选域名的结论优先；
/// 备用域名先给出结论时，需等首选域名失败或宽限期结束才采用。
struct PreferredHostRace<Result> {
    enum Source { case primary, fallback }
    enum Outcome {
        case pending
        /// nil 表示两个域名都无法下结论。
        case done(Result?)
    }

    private var primaryFailed = false
    private var fallbackReported = false
    private var fallbackResult: Result?
    private(set) var finished = false

    /// 传入 nil 表示该域名无法下结论。
    mutating func record(_ result: Result?, from source: Source) -> Outcome {
        guard !finished else { return .pending }
        switch source {
        case .primary:
            if let result { return finish(result) }
            primaryFailed = true
            return fallbackReported ? finish(fallbackResult) : .pending
        case .fallback:
            fallbackReported = true
            fallbackResult = result
            return primaryFailed ? finish(result) : .pending
        }
    }

    /// 宽限期结束：首选域名仍未回应时，采用备用域名已有的结论。
    mutating func graceExpired() -> Outcome {
        guard !finished, let fallbackResult else { return .pending }
        return finish(fallbackResult)
    }

    private mutating func finish(_ result: Result?) -> Outcome {
        finished = true
        return .done(result)
    }
}

/// 并发探测多个域名时的结果聚合：第一个有结论的结果胜出，
/// 全部无法下结论时才返回 .network。
struct ValidationRace {
    private var remaining: Int
    private var finished = false

    init(hostCount: Int) {
        remaining = hostCount
    }

    /// 传入 nil 表示该域名无法下结论。返回非 nil 表示可以结束等待。
    mutating func record(_ result: MarketValidation?) -> MarketValidation? {
        guard !finished else { return nil }
        if let result {
            finished = true
            return result
        }
        remaining -= 1
        guard remaining > 0 else {
            finished = true
            return .network
        }
        return nil
    }
}