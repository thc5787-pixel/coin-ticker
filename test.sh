#!/usr/bin/env bash
# 运行 StockContractQuote 的轻量单元测试（项目未使用 SwiftPM/Xcode 测试目标）
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc "$SRC_DIR/StockContract.swift" "$SRC_DIR/Tests/main.swift" -o "$TMP_DIR/stock-contract-tests"
"$TMP_DIR/stock-contract-tests"
