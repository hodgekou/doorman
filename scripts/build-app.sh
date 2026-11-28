#!/usr/bin/env bash
# 把 Swift Package 打包成 dist/Doorman.app 并做 ad-hoc 签名。
# 用法：scripts/build-app.sh [debug|release]   默认 release
#
# 可选环境变量：
#   UNIVERSAL=1        同时编译 arm64 和 x86_64（发布用）
#   VERSION=v1.2.3     写入 CFBundleShortVersionString（发布用，可带 v 前缀）
#   BUILD_NUMBER=42    写入 CFBundleVersion
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "用法：$0 [debug|release]" >&2; exit 2 ;;
esac

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
if [ -n "$VERSION" ] && ! [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION 格式应为 1.2.3 或 v1.2.3，实际：$VERSION" >&2
  exit 2
fi
if [ -n "$BUILD_NUMBER" ] && ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER 应为纯数字，实际：$BUILD_NUMBER" >&2
  exit 2
fi

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

cd "$ROOT"
# 空数组在 bash 3.2 + set -u 下会报错，用 ${arr[@]+...} 写法
swift build -c "$CONFIG" --product Doorman ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$ROOT/dist/Doorman.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Doorman" "$APP/Contents/MacOS/Doorman"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
fi
if [ -n "$BUILD_NUMBER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
if [ ! -f "$ROOT/Support/AppIcon.icns" ]; then
  "$ROOT/scripts/make-icon.sh"
fi
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 系统蓝牙授权弹窗的多语言文案（App 内界面语言见 Sources/Doorman/Localization）
cp -R "$ROOT"/Support/Localization/*.lproj "$APP/Contents/Resources/"

SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"

# ad-hoc 签名 + Hardened Runtime。正式分发改用 Developer ID 签名并公证。
codesign --force --sign - \
  --entitlements "$ROOT/Support/Doorman.entitlements" \
  --options runtime \
  "$APP"
codesign --verify --strict "$APP"

echo "已生成：${APP}（$(lipo -archs "$APP/Contents/MacOS/Doorman")）"
echo "运行：open \"$APP\""
