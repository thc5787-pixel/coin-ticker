#!/usr/bin/env bash
# 运行 StockContractQuote 的轻量单元测试（项目未使用 SwiftPM/Xcode 测试目标）
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc "$SRC_DIR/StockContract.swift" "$SRC_DIR/Coin.swift" "$SRC_DIR/SpotQuote.swift" "$SRC_DIR/MarketSelection.swift" "$SRC_DIR/Localization.swift" "$SRC_DIR/Tests/main.swift" -o "$TMP_DIR/cointicker-tests"
"$TMP_DIR/cointicker-tests"
