#!/usr/bin/env bash
# EthTicker 构建脚本：编译源码 → 生成图标 → 组装 .app → ad-hoc 签名
# 用法:
#   ./build.sh            # 仅构建到 build/EthTicker.app
#   ./build.sh --install  # 构建后安装到 /Applications 并重启
set -euo pipefail

APP_NAME="EthTicker"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SRC_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ARCH="$(uname -m)"

echo "==> 清理并准备构建目录"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources"

echo "==> 生成应用图标（AppIcon.iconset → AppIcon.icns）"
swiftc -O "$SRC_DIR/make_icon.swift" -o "$BUILD_DIR/make_icon"
(cd "$BUILD_DIR" && ./make_icon)
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"

echo "==> 编译主程序（$ARCH, macOS 13.0+）"
swiftc -O -target "$ARCH-apple-macos13.0" "$SRC_DIR/main.swift" -o "$BUILD_DIR/$APP_NAME"

echo "==> 组装 $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME"    "$APP_DIR/Contents/MacOS/"
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/"
cp "$SRC_DIR/Info.plist"     "$APP_DIR/Contents/"

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP_DIR"

echo "==> 构建完成: $APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> 安装到 /Applications 并重启"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
    sleep 1
    open "/Applications/$APP_NAME.app"
    echo "==> 已安装并启动"
fi
