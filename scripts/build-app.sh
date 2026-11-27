#!/usr/bin/env bash
# 把 Swift Package 打包成 dist/Doorman.app 并做 ad-hoc 签名。
# 用法：scripts/build-app.sh [debug|release]   默认 release
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "用法：$0 [debug|release]" >&2; exit 2 ;;
esac

cd "$ROOT"
swift build -c "$CONFIG" --product Doorman
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/dist/Doorman.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Doorman" "$APP/Contents/MacOS/Doorman"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [ ! -f "$ROOT/Support/AppIcon.icns" ]; then
  "$ROOT/scripts/make-icon.sh"
fi
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 系统蓝牙授权弹窗的多语言文案（App 内界面语言见 Sources/Doorman/Localization）
cp -R "$ROOT"/Support/Localization/*.lproj "$APP/Contents/Resources/"

# ad-hoc 签名 + Hardened Runtime。正式分发改用 Developer ID 签名并公证（M0 决定渠道）。
codesign --force --sign - \
  --entitlements "$ROOT/Support/Doorman.entitlements" \
  --options runtime \
  "$APP"
codesign --verify --strict "$APP"

echo "已生成：$APP"
echo "运行：open \"$APP\""
