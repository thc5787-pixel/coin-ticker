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
        if let saved = UserDefaults.standard.string(forKey: "customCoin"),
           var coin = Coin.make(from: saved) {
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

    private func fetchSpot(coin: Coin, symbol: String, generation: UInt64) {
        let path = "/api/v3/ticker/24hr?symbol=\(symbol)"
        tryHosts(Self.binanceHosts, path: path, index: 0, generation: generation) { [weak self] dict in
            guard let self else { return }
            guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else {
                DispatchQueue.main.async { self.finishFetch() }
                return
            }
            guard let quote = SpotQuote.parse(symbol: symbol, response: dict) else {
                self.fetchFallback(for: coin, generation: generation) { [weak self] in
                    self?.finishFetch()
                }
                return
            }
            DispatchQueue.main.async {
                defer { self.finishFetch() }
                guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
                self.update(price: quote.price, change: quote.changePercent)
            }
        }
    }

    private func finishFetch() {
        fetchInProgress = false
        guard fetchPending else { return }
        fetchPending = false
        fetch()
    }

    private func isCurrentFetch(_ generation: UInt64, symbol: String, market: Market) -> Bool {
        generation == fetchGeneration && currentCoin.binanceSymbol == symbol && currentCoin.market == market
    }

    /// 依次尝试给定域名，只接受 HTTP 200 的有效 JSON。
    private func tryHosts(_ hosts: [String], path: String, index: Int, generation: UInt64,
                          completion: @escaping ([String: Any]) -> Void) {
        guard generation == fetchGeneration else {
            completion([:])
            return
        }
        guard index < hosts.count else {
            completion([:])  // 全部节点均失败
            return
        }
        requestHTTP(hosts[index] + path) { [weak self] status, dict in
            guard let self else { return }
            if status == 200, !dict.isEmpty {
                completion(dict)
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
        let path = "/fapi/v1/ticker/24hr?symbol=\(symbol)"
        tryHosts(Self.stockContractHosts, path: path, index: 0,
                 generation: generation) { [weak self] dict in
            guard let self else { return }
            guard let quote = StockContractQuote.parse(symbol: symbol, response: dict) else {
                DispatchQueue.main.async {
                    defer { self.finishFetch() }
                    guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
                    self.showOffline()
                }
                return
            }
            DispatchQueue.main.async {
                defer { self.finishFetch() }
                guard self.isCurrentFetch(generation, symbol: symbol, market: coin.market) else { return }
                self.update(price: quote.price, change: quote.changePercent)
            }
        }
    }

    private func requestHTTP(_ urlString: String, timeout: TimeInterval = 8,
                             completion: @escaping (Int?, [String: Any]) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(nil, [:]) }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            var json: [String: Any] = [:]
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = object
            }
            // 所有回调都会读写主线程状态（currentCoin / fetchGeneration / UI），
            // 统一回主线程交付，避免 URLSession 后台队列与主线程发生数据竞争。
            DispatchQueue.main.async { completion(status, json) }
        }.resume()
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
        title.append(NSAttributedString(string: "\(symbol) $\(priceText) ",
            attributes: [.font: font]))
        title.append(NSAttributedString(string: ChangeFormatter.text(change), attributes: [
            .font: NSFont.boldSystemFont(ofSize: font.pointSize),
            .foregroundColor: color
        ]))
    }

    private func update(price: Double, change: Double) {
        cryptoQuote = (price, change)
        cryptoUnavailable = false
        lastUpdated = Date()
        render()
    }

    private func beginLoading() {
        cryptoQuote = nil
        cryptoUnavailable = false
        lastUpdated = nil
        render()
    }

    private func showOffline() {
        // 短暂断网时保留上一次价格；只有从未取到价格时才显示占位符。
        cryptoUnavailable = true
        render()
    }

    /// 菜单栏始终只渲染当前选择的一个标的。
    private func render() {
        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString()
        let priceText = cryptoQuote.map {
            currentCoin.market == .stockContract
                ? PriceFormatter.stock($0.price)
                : PriceFormatter.crypto($0.price, base: currentCoin.base)
        } ?? ""

        if let quote = cryptoQuote {
            appendQuote(to: title, symbol: currentCoin.displaySymbol,
                        priceText: priceText, change: quote.change, font: baseFont)
            if cryptoUnavailable {
                title.append(NSAttributedString(string: " ⚠", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemOrange,
                ]))
            }
        } else {
            title.append(NSAttributedString(string: "\(currentCoin.displaySymbol) …",
                attributes: [.font: baseFont]))
        }
        statusItem.button?.attributedTitle = title

        let pairLabel = currentCoin.market == .stockContract
            ? "\(currentCoin.pair) \(L("menu.stockContract"))"
            : currentCoin.pair
        coinGeckoItem.isHidden = currentCoin.market == .stockContract

        if let quote = cryptoQuote {
            let changeStr = ChangeFormatter.text(quote.change)
            priceMenuItem.title = "\(pairLabel)  $\(priceText)"
            changeMenuItem.title = cryptoUnavailable
                ? L("menu.offlineStale")
                : String(format: L("menu.change24h"), changeStr)
        } else {
            priceMenuItem.title = cryptoUnavailable ? L("menu.offline") : L("menu.price.loading")
            changeMenuItem.title = ""
        }

        if let lastUpdated {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            updateMenuItem.title = String(format: L("menu.updatedAt"), df.string(from: lastUpdated))
        } else {
            updateMenuItem.title = cryptoUnavailable ? String(format: L("menu.updatedAt"), "--:--:--") : ""
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
        case .network:
            DispatchQueue.main.async {
                completion(.failure(CoinValidationError(message: L("alert.error.network"))))
            }
        }
    }

    /// 并行探测所有现货域名：5 秒超时，第一个有结论的结果胜出。
    /// 避免主域名被阻断时逐个等待 8 秒（最坏 40 秒）。
    private func validateSpot(_ coin: Coin, completion: @escaping (MarketValidation) -> Void) {
        let path = "/api/v3/exchangeInfo?symbol=\(coin.binanceSymbol)"
        let symbol = coin.binanceSymbol
        var race = ValidationRace(hostCount: Self.binanceHosts.count)
        for host in Self.binanceHosts {
            requestHTTP(host + path, timeout: 5) { status, dict in
                let result = SpotValidation.classify(status: status, symbol: symbol, response: dict)
                if let resolved = race.record(result) {
                    completion(resolved)
                }
            }
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
        fetchStockEquitySymbols(for: coin.binanceSymbol, index: 0, completion: completion)
    }

    /// 依次尝试 fapi / www 域名获取 exchangeInfo，成功后只缓存 symbol 集合。
    private func fetchStockEquitySymbols(for symbol: String, index: Int,
                                         completion: @escaping (MarketValidation) -> Void) {
        guard index < Self.stockContractHosts.count else {
            DispatchQueue.main.async { completion(.network) }
            return
        }
        requestHTTP(Self.stockContractHosts[index] + "/fapi/v1/exchangeInfo") { [weak self] status, dict in
            guard let self else { return }
            guard status == 200, dict["symbols"] is [[String: Any]] else {
                self.fetchStockEquitySymbols(for: symbol, index: index + 1, completion: completion)
                return
            }
            let symbols = StockContractQuote.equitySymbols(in: dict)
            DispatchQueue.main.async {
                self.cacheStockSymbols(symbols)
                completion(symbols.contains(symbol) ? .valid : .invalid)
            }
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
        UserDefaults.standard.set(coin.binanceSymbol, forKey: "customCoin")
        UserDefaults.standard.set(coin.market == .stockContract ? "stock" : "spot", forKey: "customMarket")
        if let id = currentCoin.coingeckoId {
            UserDefaults.standard.set(id, forKey: "customCoinId")
        } else {
            UserDefaults.standard.removeObject(forKey: "customCoinId")
        }
        fetchGeneration &+= 1  // 让旧的进行中请求失效
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
            open(url: "https://www.binance.com/\(webLanguage)/futures/\(currentCoin.binanceSymbol)")
        } else {
            open(url: "https://www.binance.com/\(webLanguage)/trade/\(currentCoin.tradePath)")
        }
    }
    @objc private func openCoinGecko() {
        if let id = currentCoin.coingeckoId {
            open(url: "https://www.coingecko.com/\(coinGeckoLanguage)/coins/\(id)")
        } else {
            open(url: "https://www.coingecko.com/\(coinGeckoLanguage)/search?query=\(currentCoin.base)")
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
