# EthTicker

原生 macOS 菜单栏 ETH 实时价格 App。无 Dock 图标，纯 Swift + AppKit 实现，轻量无第三方依赖。

## 功能

- 📈 菜单栏实时显示 ETH 价格与 24h 涨跌幅（红涨绿跌，自动着色）
- 🔁 每 60 秒自动刷新，菜单内可「立即刷新」（快捷键 `R`）
- 🛡️ 双数据源容错：优先 Binance，失败自动回退 CoinGecko
- 🚀 支持开机自启（基于 `SMAppService`，macOS 13+）
- 🔗 菜单快捷跳转 Binance / CoinGecko 行情页
- 🖥️ `LSUIElement` 菜单栏常驻，不占用 Dock

## 技术要点

- 语言：Swift 6，框架仅用 AppKit + ServiceManagement
- 数据源：
  - [Binance `ticker/24hr?symbol=ETHUSDT`](https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT)
  - [CoinGecko `simple/price`](https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd&include_24hr_change=true)
- 开机自启：`SMAppService.mainApp`，首次启动自动注册
- 最低系统版本：macOS 13.0

## 构建

需要 Xcode Command Line Tools（`swiftc`、`iconutil`、`codesign`）。

```bash
./build.sh              # 构建到 build/EthTicker.app
./build.sh --install    # 构建并安装到 /Applications、重启
```

构建产物（`build/`、`AppIcon.icns`、`EthTicker.app` 等）均已在 `.gitignore` 中忽略，图标由 `make_icon.swift` 自动生成。

## 目录结构

```
.
├── main.swift          # 主程序（菜单栏、网络请求、刷新、开机自启）
├── make_icon.swift     # 图标生成脚本（蓝紫渐变 + Ξ 符号）
├── Info.plist          # 应用 bundle 配置
├── build.sh            # 一键构建 / 安装脚本
└── README.md
```

## 使用

1. 构建后打开 `build/EthTicker.app`，或 `./build.sh --install` 安装
2. 菜单栏出现 `ETH $…` 即开始工作，点击展开菜单
3. 首次启动会自动注册开机自启（菜单内可手动开关）

> 说明：本项目使用 ad-hoc 签名，仅适合本机使用。如需分享给他人，请替换为 Developer ID 签名并公证。

## License

[MIT](LICENSE)
