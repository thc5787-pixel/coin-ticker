import AppKit
import ServiceManagement

// ETH 实时价格 · 原生 macOS 菜单栏 App
// 使用 Binance 公开接口，失败自动回退 CoinGecko，每 60 秒刷新
final class Ticker: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let updateMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let priceMenuItem = NSMenuItem(title: "加载中…", action: nil, keyEquivalent: "")
    private let changeMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItemMenuItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
    private var timer: Timer?
    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        menu.delegate = self
        let font = NSFont.menuBarFont(ofSize: 0)
        statusItem.button?.attributedTitle = NSAttributedString(string: "ETH …",
            attributes: [.font: font])
        setupLoginItemIfNeeded()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    // MARK: - 菜单
    private func buildMenu() {
        menu.addItem(updateMenuItem)
        menu.addItem(priceMenuItem)
        menu.addItem(changeMenuItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

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

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
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
            loginItemMenuItem.title = "开机自启（已开启）"
        case .requiresApproval:
            loginItemMenuItem.state = .off
            loginItemMenuItem.title = "开机自启（需在系统设置允许）"
        case .notRegistered, .notFound:
            loginItemMenuItem.state = .off
            loginItemMenuItem.title = "开机自启（未开启）"
        @unknown default:
            loginItemMenuItem.state = .off
            loginItemMenuItem.title = "开机自启"
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

    // MARK: - 网络请求
    private func fetch() {
        request("https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT") { [weak self] dict in
            guard let p = dict["lastPrice"] as? String, let price = Double(p),
                  let c = dict["priceChangePercent"] as? String, let change = Double(c) else {
                self?.fetchFallback()
                return
            }
            DispatchQueue.main.async { self?.update(price: price, change: change) }
        }
    }

    private func fetchFallback() {
        request("https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd&include_24hr_change=true") { [weak self] dict in
            guard let e = dict["ethereum"] as? [String: Any],
                  let price = e["usd"] as? Double,
                  let change = e["usd_24h_change"] as? Double else {
                DispatchQueue.main.async { self?.showOffline() }
                return
            }
            DispatchQueue.main.async { self?.update(price: price, change: change) }
        }
    }

    private func request(_ urlString: String, completion: @escaping ([String: Any]) -> Void) {
        guard let url = URL(string: urlString) else { return }
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

        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString(string: "ETH $\(priceStr) ",
            attributes: [.font: baseFont])
        title.append(NSAttributedString(string: "\(arrow)\(changeStr)", attributes: [
            .font: NSFont.boldSystemFont(ofSize: baseFont.pointSize),
            .foregroundColor: color
        ]))
        statusItem.button?.attributedTitle = title

        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        updateMenuItem.title = "上次更新  \(df.string(from: Date()))"
        priceMenuItem.title = "ETH/USDT  $\(priceStr)"
        changeMenuItem.title = "24h 涨跌  \(arrow)\(changeStr)"
    }

    private func showOffline() {
        let font = NSFont.menuBarFont(ofSize: 0)
        statusItem.button?.attributedTitle = NSAttributedString(string: "ETH …", attributes: [.font: font])
        updateMenuItem.title = "上次更新  --:--:--"
        priceMenuItem.title = "网络不可用，稍后自动重试"
        changeMenuItem.title = ""
    }

    // MARK: - 动作
    @objc private func refreshNow() { fetch() }
    @objc private func openBinance() { open(url: "https://www.binance.com/zh-CN/trade/ETH_USDT") }
    @objc private func openCoinGecko() { open(url: "https://www.coingecko.com/en/coins/ethereum") }
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
let ticker = Ticker()
app.run()
