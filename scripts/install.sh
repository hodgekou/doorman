#!/usr/bin/env bash
# 构建并安装到 /Applications/Doorman.app，然后启动。
# 只会覆盖 Bundle ID 为 dev.doorman.Doorman 的旧版本，其他同名 App 不动。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="dev.doorman.Doorman"
DEST="/Applications/Doorman.app"

"$ROOT/scripts/build-app.sh" release

if [ -e "$DEST" ]; then
  existing="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$existing" != "$BUNDLE_ID" ]; then
    echo "$DEST 不是 Doorman（Bundle ID：${existing:-未知}），停止安装。" >&2
    exit 1
  fi
fi

# 退出正在运行的 Doorman（包括从 dist/ 启动的）
pkill -x Doorman 2>/dev/null || true

rm -rf "$DEST"
cp -R "$ROOT/dist/Doorman.app" "$DEST"
# 让 Finder / 启动台刷新图标
touch "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

echo "已安装：$DEST"
open "$DEST"
