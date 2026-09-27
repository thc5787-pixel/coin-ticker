import AppKit
import ServiceManagement

// 当前语言与本地化字符串表（内存加载，切换语言即时生效）
var currentLanguage: String = "en"
var localizedStrings: [String: String] = [:]

/// 本地化字符串
func L(_ key: String) -> String { localizedStrings[key] ?? key }

/// 从 .lproj/Localizable.strings（openStep plist）加载字符串表
func loadLocalizedStrings(language: String) -> [String: String] {
    guard let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"),
          let data = try? Data(contentsOf: url) else { return [:] }
    var fmt = PropertyListSerialization.PropertyListFormat.openStep
    guard let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: &fmt) as? [String: String] else { return [:] }
    return dict
}

/// 解析当前应使用的语言
func resolveLanguage() -> String {
    if let sel = UserDefaults.standard.string(forKey: "selectedLanguage"), sel == "en" || sel == "zh-Hans" {
        return sel
    }
    if let first = Locale.preferredLanguages.first, first.hasPrefix("zh") {
        return "zh-Hans"
    }
    return "en"
}

/// 加载当前语言的字符串表
func applyCurrentLanguage() {
    currentLanguage = resolveLanguage()
    localizedStrings = loadLocalizedStrings(language: currentLanguage)
}

// 实时价格 · 原生 macOS 菜单栏 App
// 使用 Binance 公开接口，失败自动回退 CoinGecko，每 30 秒刷新，支持自定义币种

// 币种模型：由用户自定义输入 Binance 交易对（如 ETHUSDT / ETH / SOL-USDT）
struct Coin {
    let base: String         // 基础币，如 "ETH"
    let quote: String        // 计价币，如 "USDT"
    var coingeckoId: String? // CoinGecko 资产 id（可选，用于 Binance 失败时回退）

    var binanceSymbol: String { base + quote }   // Binance 请求用，如 "ETHUSDT"
    var displaySymbol: String { base }           // 菜单栏展示，如 "ETH"
    var pair: String { "\(base)/\(quote)" }      // 展示交易对，如 "ETH/USDT"
    var tradePath: String { "\(base)_\(quote)" } // Binance 行情页路径，如 "ETH_USDT"

    // 常见计价币（用于自动拆分 base/quote）
    static let quoteCurrencies = [
        "USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USDS", "DAI",
        "TRY", "EUR", "GBP", "JPY", "AUD", "BRL",
        "BTC", "ETH", "BNB",
    ]

    // 常见币种的 CoinGecko 资产 id（仅 USDT 交易对需要回退）
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

    /// 从用户输入解析币种：支持 "ETH"、"ethusdt"、"ETH/USDT"、"ETH-USDT" 等
    static func make(from input: String) -> Coin? {
        let cleaned = input.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return nil }

        var base = cleaned
        var quote = "USDT"
        for q in quoteCurrencies {
            if cleaned.hasSuffix(q), cleaned.count > q.count {
                base = String(cleaned.dropLast(q.count))
                quote = q
                break
            }
        }
        let symbol = base + quote
        return Coin(base: base, quote: quote, coingeckoId: coingeckoMap[symbol])
    }
}

final class Ticker: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let updateMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let priceMenuItem = NSMenuItem(title: L("menu.price.loading"), action: nil, keyEquivalent: "")
    private let changeMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItemMenuItem = NSMenuItem(title: L("menu.loginItem"), action: #selector(toggleLoginItem), keyEquivalent: "")
    private let langSystemItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let langZhItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let langEnItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let customCoinItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let languageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var currentCoin: Coin = Coin.make(from: "ETHUSDT")!
    private var timer: Timer?
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    // Binance 主接口与备用接口（部分网络环境下主域名可能被屏蔽）
    private static let binanceHosts = [
        "https://api.binance.com",
        "https://api1.binance.com",
        "https://api2.binance.com",
        "https://api3.binance.com",
        "https://api4.binance.com",
    ]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let saved = UserDefaults.standard.string(forKey: "customCoin"),
           var coin = Coin.make(from: saved) {
            if let id = UserDefaults.standard.string(forKey: "customCoinId") {
                coin.coingeckoId = id
            }
            currentCoin = coin
        }
        buildMenu()
        menu.delegate = self
        let font = NSFont.menuBarFont(ofSize: 0)
        statusItem.button?.attributedTitle = NSAttributedString(string: "\(currentCoin.displaySymbol) …",
            attributes: [.font: font])
        setupLoginItemIfNeeded()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    // MARK: - 菜单
    private func buildMenu() {
        menu.addItem(updateMenuItem)
        menu.addItem(priceMenuItem)
        menu.addItem(changeMenuItem)
        menu.addItem(.separator())

        customCoinItem.title = L("menu.inputCoin")
        customCoinItem.action = #selector(promptCustomCoin)
        customCoinItem.keyEquivalent = "c"
        customCoinItem.target = self
        menu.addItem(customCoinItem)

        refreshItem.title = L("menu.refresh")
        refreshItem.action = #selector(refreshNow)
        refreshItem.keyEquivalent = "r"
        refreshItem.target = self
        menu.addItem(refreshItem)

        // 语言选择
        languageItem.title = L("menu.language")
        let languageSubmenu = NSMenu()

        langSystemItem.title = L("menu.language.system")
        langSystemItem.action = #selector(selectLanguage(_:))
        langSystemItem.target = self
        langSystemItem.representedObject = "system"
        languageSubmenu.addItem(langSystemItem)

        langZhItem.title = "简体中文"
        langZhItem.action = #selector(selectLanguage(_:))
        langZhItem.target = self
        langZhItem.representedObject = "zh-Hans"
        languageSubmenu.addItem(langZhItem)

        langEnItem.title = "English"
        langEnItem.action = #selector(selectLanguage(_:))
        langEnItem.target = self
        langEnItem.representedObject = "en"
        languageSubmenu.addItem(langEnItem)

        languageItem.submenu = languageSubmenu
        menu.addItem(languageItem)

        loginItemMenuItem.target = self
        menu.addItem(loginItemMenuItem)
        menu.addItem(.separator())

        let binance = NSMenuItem(title: "Binance", action: #selector(openBinance), keyEquivalent: "")
        binance.target = self
        menu.addItem(binance)

        let cg = NSMenuItem(title: "CoinGecko", action: #selector(openCoinGecko), keyEquivalent: "")
        cg.target = self
        menu.addItem(cg)
        menu.addItem(.separator())

        quitItem.title = L("menu.quit")
        quitItem.action = #selector(quit)
        quitItem.keyEquivalent = "q"
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateLanguageMenuState()
    }

    // MARK: - 开机自启（SMAppService）
    private func setupLoginItemIfNeeded() {
        let key = "loginItemConfigured"
        let d = UserDefaults.standard
        if !d.bool(forKey: key) {
            d.set(true, forKey: key)
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("SMAppService register error: %@", String(describing: error))
            }
        }
        updateLoginItemState()
    }

    private func updateLoginItemState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItemMenuItem.state = .on
            loginItemMenuItem.title = L("menu.loginItem.enabled")
        case .requiresApproval:
            loginItemMenuItem.state = .off
            loginItemMenuItem.title = L("menu.loginItem.requiresApproval")
        case .notRegistered, .notFound:
            loginItemMenuItem.state = .off
            loginItemMenuItem.title = L("menu.loginItem.disabled")
        @unknown default:
            loginItemMenuItem.state = .off
            loginItemMenuItem.title = L("menu.loginItem")
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("SMAppService toggle error: %@", String(describing: error))
        }
        updateLoginItemState()
    }

    // MARK: - 语言
    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? String else { return }
        UserDefaults.standard.set(lang, forKey: "selectedLanguage")
        applyCurrentLanguage()   // 重新加载字符串表
        relocalize()             // 立即更新界面
    }

    private func updateLanguageMenuState() {
        let lang = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "system"
        langSystemItem.state = (lang == "system") ? .on : .off
        langZhItem.state = (lang == "zh-Hans") ? .on : .off
        langEnItem.state = (lang == "en") ? .on : .off
    }

    /// 立即用当前语言刷新所有界面文案
    private func relocalize() {
        customCoinItem.title = L("menu.inputCoin")
        refreshItem.title = L("menu.refresh")
        languageItem.title = L("menu.language")
        quitItem.title = L("menu.quit")
        langSystemItem.title = L("menu.language.system")
        priceMenuItem.title = L("menu.price.loading")
        updateMenuItem.title = ""
        changeMenuItem.title = ""
        updateLoginItemState()
        updateLanguageMenuState()
        refreshNow()
    }

    // MARK: - 网络请求
    private func fetch() {
        let symbol = currentCoin.binanceSymbol
        let path = "/api/v3/ticker/24hr?symbol=\(symbol)"
        tryBinance(path: path, index: 0) { [weak self] dict in
            guard let p = dict["lastPrice"] as? String, let price = Double(p),
                  let c = dict["priceChangePercent"] as? String, let change = Double(c) else {
                self?.fetchFallback()
                return
            }
            DispatchQueue.main.async { self?.update(price: price, change: change) }
        }
    }

    /// 依次尝试 Binance 主接口与备用接口，直到某个返回有效 JSON
    private func tryBinance(path: String, index: Int, completion: @escaping ([String: Any]) -> Void) {
        guard index < Self.binanceHosts.count else {
            completion([:])  // 全部节点均失败
            return
        }
        request(Self.binanceHosts[index] + path) { [weak self] dict in
            if dict.isEmpty {
                self?.tryBinance(path: path, index: index + 1, completion: completion)
            } else {
                completion(dict)
            }
        }
    }

    private func fetchFallback() {
        guard let id = currentCoin.coingeckoId else {
            DispatchQueue.main.async { self.showOffline() }
            return
        }
        request("https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true") { [weak self] dict in
            guard let e = dict[id] as? [String: Any],
                  let price = e["usd"] as? Double,
                  let change = e["usd_24h_change"] as? Double else {
                DispatchQueue.main.async { self?.showOffline() }
                return
            }
            DispatchQueue.main.async { self?.update(price: price, change: change) }
        }
    }

    private func request(_ urlString: String, completion: @escaping ([String: Any]) -> Void) {
        guard let url = URL(string: urlString) else { completion([:]); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion([:])
                return
            }
            completion(json)
        }.resume()
    }

    // MARK: - 更新显示
    private func update(price: Double, change: Double) {
        let up = change >= 0
        let arrow = up ? "▲" : "▼"
        let color: NSColor = up ? .systemGreen : .systemRed
        let priceStr = formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
        let changeStr = String(format: "%+.2f%%", change)

        let symbol = currentCoin.displaySymbol
        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString(string: "\(symbol) $\(priceStr) ",
            attributes: [.font: baseFont])
        title.append(NSAttributedString(string: "\(arrow)\(changeStr)", attributes: [
            .font: NSFont.boldSystemFont(ofSize: baseFont.pointSize),
            .foregroundColor: color
        ]))
        statusItem.button?.attributedTitle = title

        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        updateMenuItem.title = String(format: L("menu.updatedAt"), df.string(from: Date()))
        priceMenuItem.title = "\(currentCoin.pair)  $\(priceStr)"
        changeMenuItem.title = String(format: L("menu.change24h"), "\(arrow)\(changeStr)")
    }

    private func showOffline() {
        let font = NSFont.menuBarFont(ofSize: 0)
        statusItem.button?.attributedTitle = NSAttributedString(string: "\(currentCoin.displaySymbol) …", attributes: [.font: font])
        updateMenuItem.title = String(format: L("menu.updatedAt"), "--:--:--")
        priceMenuItem.title = L("menu.offline")
        changeMenuItem.title = ""
    }

    // MARK: - 自定义币种
    @objc private func promptCustomCoin() {
        let alert = NSAlert()
        alert.messageText = L("alert.inputCoin.title")
        alert.informativeText = L("alert.inputCoin.message")
        alert.addButton(withTitle: L("alert.ok"))
        alert.addButton(withTitle: L("alert.cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "ETH"
        field.stringValue = currentCoin.displaySymbol   // 预填当前币种代码（如 ETH）
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let coin = Coin.make(from: field.stringValue) else {
            showError(String(format: L("alert.error.invalid"), field.stringValue))
            return
        }
        let previous = currentCoin
        apply(coin)                  // 立即切换，后台再校验
        validate(coin, previous: previous)
    }

    /// 后台异步校验币种；无效则回滚到之前的币种并提示
    private func validate(_ coin: Coin, previous: Coin) {
        let path = "/api/v3/ticker/24hr?symbol=\(coin.binanceSymbol)"
        tryBinance(path: path, index: 0) { [weak self] dict in
            guard let self else { return }
            let valid = (dict["lastPrice"] as? String) != nil && (dict["priceChangePercent"] as? String) != nil
            DispatchQueue.main.async {
                guard self.currentCoin.binanceSymbol == coin.binanceSymbol else { return }
                if valid { return }   // 校验通过，保持当前币种
                self.apply(previous)  // 回滚
                self.showError(dict.isEmpty ? L("alert.error.network") : String(format: L("alert.error.invalid"), coin.binanceSymbol))
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("alert.error.title")
        alert.informativeText = message
        alert.addButton(withTitle: L("alert.error.ok"))
        alert.runModal()
    }

    private func apply(_ coin: Coin) {
        currentCoin = coin
        UserDefaults.standard.set(coin.binanceSymbol, forKey: "customCoin")
        if let id = coin.coingeckoId {
            UserDefaults.standard.set(id, forKey: "customCoinId")
        } else {
            UserDefaults.standard.removeObject(forKey: "customCoinId")
        }
        showOffline()  // 先清空旧币种数据，避免短暂显示错误价格
        refreshNow()
    }

    // MARK: - 动作
    @objc private func refreshNow() { fetch() }
    @objc private func openBinance() { open(url: "https://www.binance.com/zh-CN/trade/\(currentCoin.tradePath)") }
    @objc private func openCoinGecko() {
        if let id = currentCoin.coingeckoId {
            open(url: "https://www.coingecko.com/en/coins/\(id)")
        } else {
            open(url: "https://www.coingecko.com/en/search?query=\(currentCoin.base)")
        }
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func open(url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

extension Ticker: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateLoginItemState()
    }
}

// CLI 检查模式：打印登录项注册状态后退出
if CommandLine.arguments.contains("--print-login-status") {
    print("SMAppService status: \(String(describing: SMAppService.mainApp.status))")
    exit(0)
}

// 入口：无 Dock 图标的 accessory 应用
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
applyCurrentLanguage()
let ticker = Ticker()
app.run()
