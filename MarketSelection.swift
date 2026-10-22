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
            case .valid, .notTrading:
                return .spot
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
                // 现货已停牌：只有确认美股合约不可用时才回退到现货；
                // 无法确认时宁可报网络错误，也不静默选错标的。
                switch stock {
                case .valid:
                    return .stock
                case .invalid, .notTrading:
                    return .spot
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
        if status == 400, (response["code"] as? Int) == -1121 {
            return .invalid
        }
        return nil
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