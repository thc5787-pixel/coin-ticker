# CoinTicker

原生 macOS 菜单栏实时价格 App，支持加密货币现货与 Binance 美股永续合约。菜单栏始终只显示当前选择的一个标的。无 Dock 图标，纯 Swift + AppKit 实现，轻量无第三方依赖。

## 功能

- 📈 菜单栏实时显示价格与 24h 涨跌幅（绿涨红跌，自动着色）
- ⌨️ 自定义标的：菜单「输入代码…」输入 Binance 现货交易对或币种代码（如 `BTC`、`ETHUSDT`），也可输入美股永续合约（如 `AAPLUSDT`）；输入窗口可指定「自动识别 / 现货 / 美股合约」，同名代码（如 `MDT`）也能正确选择，自动识别并记忆
- 🔁 每 30 秒自动刷新，菜单内可「立即刷新」（⌘R）
- 🛡️ 数据源容错：现货优先 Binance，内置 20 个主流币种在失败时回退 CoinGecko，其余币种显示离线；美股合约使用 Binance USDⓈ-M 合约行情，不回退现货价格
- 📶 断网时不展示过期价格与更新时间，菜单栏显示「代码 …」，菜单中提示「网络不可用，稍后自动重试」
- 🚀 支持开机自启（基于 `SMAppService`，macOS 13+）
- 🔗 菜单快捷跳转当前币种的 Binance / CoinGecko 行情页
- 🖥️ `LSUIElement` 菜单栏常驻，不占用 Dock

## 技术要点

- 语言：Swift 6 编译器（Swift 5 语言模式），框架仅用 AppKit + ServiceManagement
- 数据源：
  - Binance 现货 [`ticker/24hr?symbol=<交易对>`](https://api.binance.com/api/v3/ticker/24hr)（自动依次尝试 api、api1~api4 备用域名）
  - Binance USDⓈ-M 美股合约 [`fapi/v1/ticker/24hr?symbol=<交易对>`](https://fapi.binance.com/fapi/v1/ticker/24hr?symbol=AAPLUSDT)；通过 `fapi/v1/exchangeInfo` 的 `TRADIFI_PERPETUAL` / `EQUITY` 元数据识别（支持 USDT / USD1 计价）；`fapi.binance.com` 不可用时自动回退 `www.binance.com` 的同名接口
  - CoinGecko [`simple/price`](https://api.coingecko.com/api/v3/simple/price?ids=<资产id>&vs_currencies=usd&include_24hr_change=true)（仅现货回退）
- 开机自启：`SMAppService.mainApp`，首次启动自动注册
- 最低系统版本：macOS 13.0

## 构建

需要 Xcode Command Line Tools（`swiftc`、`codesign`）和 Python 3（用于打包应用图标）。

```bash
./test.sh               # 运行解析、合约识别与市场判定测试
./build.sh              # 构建到 build/CoinTicker.app
./build.sh --install    # 构建并安装到 /Applications、重启
```

构建产物（`build/`、`AppIcon.icns`、`CoinTicker.app` 等）均已在 `.gitignore` 中忽略，图标由 `make_icon.swift` + `make_icns.py` 自动生成。

CI 发布的 zip 仅包含 arm64（Apple Silicon）版本；Intel Mac 可在本机运行 `./build.sh` 自行构建。

## 目录结构

```
.
├── main.swift          # 主程序（菜单栏、网络请求、刷新、开机自启）
├── Coin.swift          # 币种解析与价格格式化
├── StockContract.swift # 美股永续行情解析与合约识别
├── SpotQuote.swift     # 现货行情解析
├── MarketSelection.swift # 市场判定（自动/现货/美股合约）
├── Localization.swift  # 语言选择逻辑
├── Tests/main.swift    # 解析/识别/市场判定/格式化测试
├── test.sh             # 测试脚本
├── make_icon.swift     # 图标生成脚本（金色渐变 + $ 符号）
├── make_icns.py        # 将图标尺寸打包为 .icns
├── Info.plist          # 应用 bundle 配置
├── build.sh            # 一键构建 / 安装脚本
└── README.md
```

## 使用

1. 构建后打开 `build/CoinTicker.app`，或 `./build.sh --install` 安装
2. 菜单栏出现 `ETH $…` 即开始工作；通过「输入代码…」在现货与美股合约之间切换，菜单栏始终只显示当前一个标的
3. 首次启动会自动注册开机自启（菜单内可手动开关）

> 说明：本项目使用 ad-hoc 签名，仅适合本机使用。如需分享给他人，请替换为 Developer ID 签名并公证。从 GitHub Release 下载的 zip 因未公证，首次打开需右键 → 打开。

## License

[MIT](LICENSE)
