import AppKit
import ServiceManagement

// 本地化字符串表（内存加载，切换语言即时生效）
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
    LanguageResolver.resolve(selected: UserDefaults.standard.string(forKey: "selectedLanguage"),
                             preferredLanguages: Locale.preferredLanguages)
}

/// 加载当前语言的字符串表；首选语言资源缺失时回退英文。
func applyCurrentLanguage() {
    let language = resolveLanguage()
    var strings = loadLocalizedStrings(language: language)
    if strings.isEmpty, language != "en" {
        strings = loadLocalizedStrings(language: "en")
    }
    localizedStrings = strings
}

// 实时价格 · 原生 macOS 菜单栏 App
// 使用 Binance 公开接口，失败自动回退 CoinGecko，每 30 秒刷新，支持自定义币种

// Market / Coin / PriceFormatter 定义在 Coin.swift

/// 自动获取焦点的输入框：被加入窗口后立即请求成为第一响应者
final class AutoFocusTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.focus()
        }
    }

    /// 请求成为第一响应者并将光标定位到输入框
    func focus() {
        guard let window = self.window, window.isVisible else { return }
        // Menu bar apps can present an alert without becoming the active app.
        // In that state makeFirstResponder silently fails even though the field
        // is visible, so activate and key the alert before assigning focus.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(self) else { return }
        selectText(nil)
    }
}

private struct CoinValidationError: Error {
    let message: String
}

final class CoinInputWindowController: NSObject {
    let window: NSWindow
    let field = AutoFocusTextField(frame: NSRect(x: 20, y: 105, width: 180, height: 24))
    private let marketPopup = NSPopUpButton(frame: NSRect(x: 212, y: 102, width: 128, height: 28), pullsDown: false)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let submitButton = NSButton(title: L("alert.ok"), target: nil, action: nil)
    var onSubmit: ((String, MarketPreference) -> Void)?
    private(set) var isActive = true

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 186),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.delegate = self
        window.title = L("alert.inputCoin.title")
        window.isReleasedWhenClosed = false

        let content = window.contentView!
        let hint = NSTextField(wrappingLabelWithString: L("alert.inputCoin.message"))
        hint.frame = NSRect(x: 20, y: 144, width: 320, height: 36)
        content.addSubview(hint)

        field.placeholderString = "ETH"
        content.addSubview(field)

        marketPopup.addItems(withTitles: [
            L("alert.market.auto"),
            L("alert.market.spot"),
            L("alert.market.stock"),
        ])
        marketPopup.toolTip = L("alert.market")
        marketPopup.selectItem(at: 0)
        content.addSubview(marketPopup)

        errorLabel.frame = NSRect(x: 20, y: 64, width: 320, height: 30)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        content.addSubview(errorLabel)

        let cancelButton = NSButton(title: L("alert.cancel"), target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 170, y: 16, width: 80, height: 28)
        cancelButton.bezelStyle = .rounded
        content.addSubview(cancelButton)

        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.frame = NSRect(x: 260, y: 16, width: 80, height: 28)
        submitButton.bezelStyle = .rounded
        submitButton.keyEquivalent = "\r"
        content.addSubview(submitButton)
    }

    func present() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: window)
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = false
        submitButton.isEnabled = true
        field.isEnabled = true
        marketPopup.isEnabled = true
        field.focus()
    }

    func close() {
        guard isActive else { return }
        isActive = false
        window.close()
        NSApp.stopModal()
    }

    func setValidating(_ validating: Bool) {
        submitButton.isEnabled = !validating
        field.isEnabled = !validating
        marketPopup.isEnabled = !validating
        if validating {
            errorLabel.stringValue = L("menu.price.loading")
            errorLabel.textColor = .secondaryLabelColor
            errorLabel.isHidden = false
        } else {
            errorLabel.textColor = .systemRed
        }
    }

    @objc private func submit() {
        let preference: MarketPreference
        switch marketPopup.indexOfSelectedItem {
        case 1: preference = .spot
        case 2: preference = .stock
        default: preference = .auto
        }
        onSubmit?(field.stringValue, preference)
    }
    @objc private func cancel() { close() }
}

extension CoinInputWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard isActive else { return }
        isActive = false
        NSApp.stopModal()
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
    private let coinGeckoItem = NSMenuItem(title: "CoinGecko", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var currentCoin: Coin = Coin.make(from: "ETHUSDT")!
    private var timer: Timer?
    private var fetchGeneration: UInt64 = 0
    private var fetchInProgress = false
    private var fetchPending = false
    private var cryptoQuote: (price: Double, change: Double)?
    private var cryptoUnavailable = false
    /// 行情接口明确返回"代码无效"（例如已下架）。
    private var cryptoInvalid = false
    /// 现货已停牌：24hr 行情仍返回最后成交价，但不应作为实时价格展示。
    private var cryptoHalted = false
    /// 上次确认现货交易状态的 symbol 与时间（停牌检查不必每 30 秒都做）。
    private var spotStatusChecked: (symbol: String, date: Date)?
    private static let spotStatusTTL: TimeInterval = 300
    private var lastUpdated: Date?
    private var stockEquitySymbols: Set<String>?
    private var stockEquitySymbolsDate: Date?
    private var stockCachePurge: DispatchWorkItem?
    private static let stockExchangeInfoTTL: TimeInterval = 300

    // Binance USDⓈ-M 美股永续合约公开行情（无需 API Key）。
    // www.binance.com 同样提供 fapi 接口，作为 fapi 域名被阻断时的备用入口。
    private static let stockContractHosts = [
        "https://fapi.binance.com",
        "https://www.binance.com",
    ]

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
        // 新版本保存 "AR/BTC" 形式；1.1.3 及更早版本保存的无分隔符值按当时的规则还原。
        if let saved = UserDefaults.standard.string(forKey: "customCoin"),
           var coin = Coin.restore(saved: saved) {
            if let id = UserDefaults.standard.string(forKey: "customCoinId") {
                coin.coingeckoId = id
            }
            if UserDefaults.standard.string(forKey: "customMarket") == "stock" {
                coin.market = .stockContract
            }
            currentCoin = coin
        }
        buildMenu()
        menu.delegate = self
        setupLoginItemIfNeeded()
        render()
        refreshAll()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshAll()
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

        coinGeckoItem.action = #selector(openCoinGecko)
        coinGeckoItem.target = self
        menu.addItem(coinGeckoItem)
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
            if SMAppService.mainApp.status == .enabled {
                d.set(true, forKey: key)
            } else {
                do {
                    try SMAppService.mainApp.register()
                    d.set(true, forKey: key)
                } catch {
                    NSLog("SMAppService register error: %@", String(describing: error))
                }
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
        updateLoginItemState()
        updateLanguageMenuState()
        render()
        refreshNow()
    }

    // MARK: - 网络请求
    private func fetch() {
        guard !fetchInProgress else {
            fetchPending = true
            return
        }
        fetchInProgress = true
        fetchGeneration &+= 1
        let generation = fetchGeneration
        let coin = currentCoin
        let symbol = coin.binanceSymbol
        switch coin.market {
        case .spot:
            fetchSpot(coin: coin, symbol: symbol, generation: generation)
        case .stockContract:
            fetchStockContract(coin: coin, symbol: symbol, generation: generation)
        }
    }

    /// 先按需确认现货仍在交易，再拉取 24hr 行情。
    private func fetchSpot(coin: Coin, symbol: String, generation: UInt64) {
        if let checked = spotStatusChecked, checked.symbol == symbol,
           Date().timeIntervalSince(checked.date) < Self.spotStatusTTL {
            fetchSpotTicker(coin: coin, symbol: symbol, generation: generation)
            return
        }
        let path = "/api/v3/exchangeInfo?symbol=\(coin.urlSymbol)"
        tryHosts(Self.binanceHosts, path: path, index: 0, generation: generation) { [weak self] result in
            guard let self else { return }
            guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else {
                self.finishFetch(generation)
                return
            }
            switch result {
            case .ok(let dict):
                switch SpotValidation.classify(status: 200, symbol: symbol, response: dict) {
                case .notTrading?:
                    // 停牌状态不缓存：恢复交易后下一轮刷新即可重新显示价格。
                    self.spotStatusChecked = nil
                    self.showHalted()
                    self.finishFetch(generation)
                    return
                case .valid?:
                    self.spotStatusChecked = (symbol, Date())
                default:
                    break
                }
            case .invalidSymbol:
                self.showInvalid()
                self.finishFetch(generation)
                return
            case .failed:
                break  // 状态未知时不阻塞行情，交给 ticker 请求与 CoinGecko 回退处理
            }
            self.fetchSpotTicker(coin: coin, symbol: symbol, generation: generation)
        }
    }

    private func fetchSpotTicker(coin: Coin, symbol: String, generation: UInt64) {
        let path = "/api/v3/ticker/24hr?symbol=\(coin.urlSymbol)"
        tryHosts(Self.binanceHosts, path: path, index: 0, generation: generation) { [weak self] result in
            guard let self else { return }
            guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else {
                self.finishFetch(generation)
                return
            }
            switch result {
            case .invalidSymbol:
                // 代码已下架或不存在：明确提示，不回退 CoinGecko 显示其他来源的价格。
                self.showInvalid()
                self.finishFetch(generation)
            case .ok(let dict):
                if let quote = SpotQuote.parse(symbol: symbol, response: dict) {
                    self.update(price: quote.price, change: quote.changePercent)
                    self.finishFetch(generation)
                } else {
                    self.fetchFallback(for: coin, generation: generation) { [weak self] in
                        self?.finishFetch(generation)
                    }
                }
            case .failed:
                self.fetchFallback(for: coin, generation: generation) { [weak self] in
                    self?.finishFetch(generation)
                }
            }
        }
    }

    /// 只有当前这一轮请求结束才释放锁；切换币种后旧请求的回调直接忽略。
    private func finishFetch(_ generation: UInt64) {
        guard generation == fetchGeneration else { return }
        fetchInProgress = false
        guard fetchPending else { return }
        fetchPending = false
        fetch()
    }

    private func isCurrentFetch(_ generation: UInt64, symbol: String, market: Market) -> Bool {
        generation == fetchGeneration && currentCoin.binanceSymbol == symbol && currentCoin.market == market
    }

    private enum HostResult {
        case ok([String: Any])
        /// Binance 明确拒绝了该 symbol（-1121 / -1100 等），换域名也不会有别的结果。
        case invalidSymbol
        case failed
    }

    /// 依次尝试给定域名，只接受 HTTP 200 的有效 JSON；遇到"代码无效"立即结束。
    private func tryHosts(_ hosts: [String], path: String, index: Int, generation: UInt64,
                          completion: @escaping (HostResult) -> Void) {
        guard generation == fetchGeneration, index < hosts.count else {
            completion(.failed)  // 已过期，或全部节点均失败
            return
        }
        requestHTTP(hosts[index] + path) { [weak self] status, dict in
            guard let self else { return }
            if status == 200, !dict.isEmpty {
                completion(.ok(dict))
            } else if BinanceResponse.isDefinitiveRejection(status: status, response: dict) {
                completion(.invalidSymbol)
            } else {
                self.tryHosts(hosts, path: path, index: index + 1,
                              generation: generation, completion: completion)
            }
        }
    }

    private func fetchFallback(for coin: Coin, generation: UInt64, completion: @escaping () -> Void) {
        let symbol = coin.binanceSymbol
        guard let id = coin.coingeckoId else {
            DispatchQueue.main.async { [weak self] in
                defer { completion() }
                guard let self, self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
                self.showOffline()
            }
            return
        }
        request("https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true") { [weak self] dict in
            guard let self else { return }
            guard let e = dict[id] as? [String: Any],
                  let price = e["usd"] as? Double,
                  let change = e["usd_24h_change"] as? Double else {
                DispatchQueue.main.async {
                    defer { completion() }
                    guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
                    self.showOffline()
                }
                return
            }
            DispatchQueue.main.async {
                defer { completion() }
                guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
                self.update(price: price, change: change)
            }
        }
    }

    /// 美股合约行情走 USDⓈ-M 合约接口，失败不回退 CoinGecko。
    private func fetchStockContract(coin: Coin, symbol: String, generation: UInt64) {
        let path = "/fapi/v1/ticker/24hr?symbol=\(coin.urlSymbol)"
        tryHosts(Self.stockContractHosts, path: path, index: 0,
                 generation: generation) { [weak self] result in
            guard let self else { return }
            defer { self.finishFetch(generation) }
            guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
            switch result {
            case .ok(let dict):
                if let quote = StockContractQuote.parse(symbol: symbol, response: dict) {
                    self.update(price: quote.price, change: quote.changePercent)
                } else {
                    self.showOffline()
                }
            case .invalidSymbol:
                self.showInvalid()
            case .failed:
                self.showOffline()
            }
        }
    }

    @discardableResult
    private func requestHTTP(_ urlString: String, timeout: TimeInterval = 8,
                             completion: @escaping (Int?, [String: Any]) -> Void) -> URLSessionDataTask? {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(nil, [:]) }
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: req) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            var json: [String: Any] = [:]
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = object
            }
            // 所有回调都会读写主线程状态（currentCoin / fetchGeneration / UI），
            // 统一回主线程交付，避免 URLSession 后台队列与主线程发生数据竞争。
            DispatchQueue.main.async { completion(status, json) }
        }
        task.resume()
        return task
    }

    private func request(_ urlString: String, completion: @escaping ([String: Any]) -> Void) {
        requestHTTP(urlString) { _, dict in completion(dict) }
    }

    // MARK: - 更新显示
    /// 将「代码 $价格 ▲涨跌」追加到菜单栏标题。
    private func appendQuote(to title: NSMutableAttributedString, symbol: String,
                             priceText: String, change: Double, font: NSFont) {
        let up = change >= 0
        let color: NSColor = up ? .systemGreen : .systemRed
        title.append(NSAttributedString(string: "\(symbol) \(currentCoin.priceLabel(priceText)) ",
            attributes: [.font: font]))
        title.append(NSAttributedString(string: ChangeFormatter.text(change), attributes: [
            .font: NSFont.boldSystemFont(ofSize: font.pointSize),
            .foregroundColor: color
        ]))
    }

    private func update(price: Double, change: Double) {
        cryptoQuote = (price, change)
        cryptoUnavailable = false
        cryptoInvalid = false
        cryptoHalted = false
        lastUpdated = Date()
        render()
    }

    private func beginLoading() {
        cryptoQuote = nil
        cryptoUnavailable = false
        cryptoInvalid = false
        cryptoHalted = false
        lastUpdated = nil
        render()
    }

    private func showInvalid() {
        cryptoQuote = nil
        cryptoUnavailable = false
        cryptoInvalid = true
        cryptoHalted = false
        lastUpdated = nil
        render()
    }

    private func showHalted() {
        cryptoQuote = nil
        cryptoUnavailable = false
        cryptoInvalid = false
        cryptoHalted = true
        lastUpdated = nil
        render()
    }

    private func showOffline() {
        // 断网时不展示过期价格，避免把旧报价误认为实时行情。
        cryptoQuote = nil
        cryptoUnavailable = true
        cryptoInvalid = false
        cryptoHalted = false
        lastUpdated = nil
        render()
    }

    /// 菜单栏始终只渲染当前选择的一个标的。
    private func render() {
        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString()
        let priceText = cryptoQuote.map {
            currentCoin.market == .stockContract
                ? PriceFormatter.stock($0.price, locale: currentCoin.priceLocale)
                : PriceFormatter.crypto($0.price, base: currentCoin.base, quote: currentCoin.quote,
                                        locale: currentCoin.priceLocale)
        } ?? ""

        if let quote = cryptoQuote {
            appendQuote(to: title, symbol: currentCoin.displaySymbol,
                        priceText: priceText, change: quote.change, font: baseFont)
        } else {
            // 离线时菜单栏保持与 4373b43 一致：只显示代码与省略号，不显示旧价格。
            title.append(NSAttributedString(string: "\(currentCoin.displaySymbol) …",
                attributes: [.font: baseFont]))
        }
        statusItem.button?.attributedTitle = title

        let pairLabel = currentCoin.market == .stockContract
            ? "\(currentCoin.pair) \(L("menu.stockContract"))"
            : currentCoin.pair
        coinGeckoItem.isHidden = currentCoin.market == .stockContract

        if let quote = cryptoQuote {
            priceMenuItem.title = "\(pairLabel)  \(currentCoin.priceLabel(priceText))"
            changeMenuItem.title = String(format: L("menu.change24h"),
                                           ChangeFormatter.text(quote.change))
        } else {
            if cryptoInvalid {
                priceMenuItem.title = String(format: L("alert.error.invalid"), currentCoin.binanceSymbol)
            } else if cryptoHalted {
                priceMenuItem.title = String(format: L("alert.error.notTrading"), currentCoin.binanceSymbol)
            } else {
                priceMenuItem.title = cryptoUnavailable ? L("menu.offline") : L("menu.price.loading")
            }
            changeMenuItem.title = ""
        }

        if let lastUpdated {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            updateMenuItem.title = String(format: L("menu.updatedAt"), df.string(from: lastUpdated))
        } else {
            updateMenuItem.title = ""
        }
    }

    // MARK: - 自定义币种
    @objc private func promptCustomCoin() {
        let controller = CoinInputWindowController()
        controller.onSubmit = { [weak self, weak controller] input, preference in
            guard let self, let controller else { return }
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let coin = Coin.make(from: trimmed) else {
                controller.showError(String(format: L("alert.error.invalid"), trimmed))
                return
            }
            controller.setValidating(true)
            self.validate(coin, preference: preference) { result in
                // The user can close the window while the request is in flight.
                // Ignore its result so a canceled selection cannot be applied later.
                guard controller.isActive else { return }
                switch result {
                case .success(let validatedCoin):
                    self.apply(validatedCoin)
                    controller.close()
                case .failure(let error):
                    controller.showError(error.message)
                }
            }
        }
        controller.present()
    }

    /// 按用户选择的市场偏好验证；自动模式先现货，必要时再验证美股永续。
    private func validate(_ coin: Coin, preference: MarketPreference,
                          completion: @escaping (Result<Coin, CoinValidationError>) -> Void) {
        switch preference {
        case .spot:
            validateSpot(coin) { [weak self] spot in
                self?.finishValidation(coin, preference: .spot, spot: spot, stock: .invalid,
                                       completion: completion)
            }
        case .stock:
            validateStockContract(coin) { [weak self] stock in
                self?.finishValidation(coin, preference: .stock, spot: .invalid, stock: stock,
                                       completion: completion)
            }
        case .auto:
            validateSpot(coin) { [weak self] spot in
                guard let self else { return }
                if case .valid = spot {
                    self.finishValidation(coin, preference: .auto, spot: spot, stock: .invalid,
                                          completion: completion)
                    return
                }
                self.validateStockContract(coin) { [weak self] stock in
                    self?.finishValidation(coin, preference: .auto, spot: spot, stock: stock,
                                           completion: completion)
                }
            }
        }
    }

    private func finishValidation(_ coin: Coin, preference: MarketPreference,
                                  spot: MarketValidation, stock: MarketValidation,
                                  completion: @escaping (Result<Coin, CoinValidationError>) -> Void) {
        switch MarketSelection.resolve(preference: preference, spot: spot, stock: stock) {
        case .spot:
            DispatchQueue.main.async { completion(.success(coin)) }
        case .stock:
            DispatchQueue.main.async {
                var stockCoin = coin
                stockCoin.market = .stockContract
                completion(.success(stockCoin))
            }
        case .invalid:
            DispatchQueue.main.async {
                completion(.failure(CoinValidationError(
                    message: String(format: L("alert.error.invalid"), coin.binanceSymbol))))
            }
        case .notTrading:
            DispatchQueue.main.async {
                completion(.failure(CoinValidationError(
                    message: String(format: L("alert.error.notTrading"), coin.binanceSymbol))))
            }
        case .network:
            DispatchQueue.main.async {
                completion(.failure(CoinValidationError(message: L("alert.error.network"))))
            }
        }
    }

    /// 并行探测所有现货域名：5 秒超时，第一个有结论的结果胜出。
    /// 避免主域名被阻断时逐个等待 8 秒（最坏 40 秒）。
    private func validateSpot(_ coin: Coin, completion: @escaping (MarketValidation) -> Void) {
        let path = "/api/v3/exchangeInfo?symbol=\(coin.urlSymbol)"
        let symbol = coin.binanceSymbol
        var race = ValidationRace(hostCount: Self.binanceHosts.count)
        var tasks: [URLSessionDataTask] = []
        for host in Self.binanceHosts {
            let task = requestHTTP(host + path, timeout: 5) { status, dict in
                let result = SpotValidation.classify(status: status, symbol: symbol, response: dict)
                if let resolved = race.record(result) {
                    tasks.forEach { $0.cancel() }  // 已有结论，取消其余域名的请求
                    completion(resolved)
                }
            }
            if let task { tasks.append(task) }
        }
    }

    private func validateStockContract(_ coin: Coin, completion: @escaping (MarketValidation) -> Void) {
        if let symbols = stockEquitySymbols,
           let fetchedAt = stockEquitySymbolsDate,
           Date().timeIntervalSince(fetchedAt) < Self.stockExchangeInfoTTL {
            completion(symbols.contains(coin.binanceSymbol) ? .valid : .invalid)
            return
        }
        stockEquitySymbols = nil
        stockEquitySymbolsDate = nil
        fetchStockEquitySymbols(for: coin.binanceSymbol, completion: completion)
    }

    /// exchangeInfo 有几 MB，慢速网络下 8 秒不够。
    private static let stockExchangeInfoTimeout: TimeInterval = 15

    /// 备用域名先返回时，最多再等首选 fapi 域名这么久。
    private static let stockFallbackGrace: TimeInterval = 3

    /// 并行请求 fapi 与 www 镜像的 exchangeInfo，避免逐个等待超时。
    /// fapi 的结论优先：镜像先返回时，只有 fapi 失败或宽限期结束才采用镜像结果。
    /// 成功后只缓存 symbol 集合。
    private func fetchStockEquitySymbols(for symbol: String,
                                         completion: @escaping (MarketValidation) -> Void) {
        var race = PreferredHostRace<Set<String>>()
        var tasks: [URLSessionDataTask] = []
        let handle: (PreferredHostRace<Set<String>>.Outcome) -> Void = { [weak self] outcome in
            guard case .done(let symbols) = outcome else { return }
            tasks.forEach { $0.cancel() }
            guard let symbols else {
                completion(.network)
                return
            }
            self?.cacheStockSymbols(symbols)
            completion(symbols.contains(symbol) ? .valid : .invalid)
        }
        for (index, host) in Self.stockContractHosts.enumerated() {
            let source: PreferredHostRace<Set<String>>.Source = index == 0 ? .primary : .fallback
            let task = requestHTTP(host + "/fapi/v1/exchangeInfo",
                                   timeout: Self.stockExchangeInfoTimeout) { status, dict in
                let symbols = StockValidation.equitySymbols(status: status, response: dict)
                handle(race.record(symbols, from: source))
                if source == .fallback, symbols != nil, !race.finished {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.stockFallbackGrace) {
                        handle(race.graceExpired())
                    }
                }
            }
            if let task { tasks.append(task) }
        }
    }

    /// 只缓存判定所需的 symbol 集合（几 KB），并在 TTL 后自动释放。
    private func cacheStockSymbols(_ symbols: Set<String>) {
        stockEquitySymbols = symbols
        stockEquitySymbolsDate = Date()
        stockCachePurge?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stockEquitySymbols = nil
            self?.stockEquitySymbolsDate = nil
        }
        stockCachePurge = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stockExchangeInfoTTL, execute: work)
    }

    private func apply(_ coin: Coin) {
        currentCoin = coin
        if coin.market == .stockContract {
            currentCoin.coingeckoId = nil
        }
        // 保存带分隔符的交易对，重启后原样还原，不再依赖 base/quote 的自动拆分。
        UserDefaults.standard.set(coin.pair, forKey: "customCoin")
        UserDefaults.standard.set(coin.market == .stockContract ? "stock" : "spot", forKey: "customMarket")
        if let id = currentCoin.coingeckoId {
            UserDefaults.standard.set(id, forKey: "customCoinId")
        } else {
            UserDefaults.standard.removeObject(forKey: "customCoinId")
        }
        // 让旧的进行中请求失效，并释放请求锁，新币种立即开始请求，不必等旧请求超时。
        fetchGeneration &+= 1
        fetchInProgress = false
        fetchPending = false
        beginLoading()
        refreshNow()
    }

    // MARK: - 动作
    private func refreshAll() {
        fetch()
    }

    @objc private func refreshNow() { refreshAll() }

    /// 外部行情网页语言，跟随 App 当前语言。
    private var webLanguage: String { resolveLanguage() == "zh-Hans" ? "zh-CN" : "en" }
    private var coinGeckoLanguage: String { resolveLanguage() == "zh-Hans" ? "zh" : "en" }

    @objc private func openBinance() {
        if currentCoin.market == .stockContract {
            open(url: "https://www.binance.com/\(webLanguage)/futures/\(currentCoin.urlSymbol)")
        } else {
            open(url: "https://www.binance.com/\(webLanguage)/trade/\(currentCoin.urlTradePath)")
        }
    }
    @objc private func openCoinGecko() {
        if let id = currentCoin.coingeckoId {
            open(url: "https://www.coingecko.com/\(coinGeckoLanguage)/coins/\(id)")
        } else {
            open(url: "https://www.coingecko.com/\(coinGeckoLanguage)/search?query=\(Coin.urlEscaped(currentCoin.base))")
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
