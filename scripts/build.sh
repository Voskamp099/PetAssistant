#!/usr/bin/env bash
# 构建 PetAssistant.app：直接 swiftc 把所有源码一把编进 .app bundle
# 不用 SwiftPM，因为某些 sandbox 环境会拦 SPM 的 atomic rename
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PetAssistant"
BUNDLE_ID="com.zhaozong.petassistant"
APP_DIR="$ROOT/build/$APP_NAME.app"
BIN_PATH="$APP_DIR/Contents/MacOS/$APP_NAME"

cd "$ROOT"
mkdir -p build
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "▶ swiftc (single-shot, -O)"
swiftc -target arm64-apple-macosx14 \
    -framework SwiftUI -framework AppKit -framework EventKit -framework AVFoundation \
    -O \
    Sources/PetAssistant/*.swift \
    -o "$BIN_PATH"

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources"/cat_idle.png "$APP_DIR/Contents/Resources/cat_idle.png" 2>/dev/null || true
cp "$ROOT/Resources"/cat_speaking.jpg "$APP_DIR/Contents/Resources/cat_speaking.jpg" 2>/dev/null || true

# ad-hoc 签名（best-effort；codesign 在严格 sandbox 下可能 EPERM，无所谓）
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ $APP_DIR"
echo "▶ 双击 / open 启动："
echo "    open \"$APP_DIR\""
