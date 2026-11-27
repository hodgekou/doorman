#!/usr/bin/env bash
# 把 dist/Doorman.app 打成拖拽安装的 DMG（含「应用程序」快捷方式），并生成 SHA-256 校验文件。
# 用法：scripts/build-app.sh && scripts/make-dmg.sh
# 输出：dist/Doorman.dmg、dist/Doorman.dmg.sha256
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Doorman.app"
DMG="$ROOT/dist/Doorman.dmg"

if [ ! -d "$APP" ]; then
  echo "找不到 $APP，请先运行 scripts/build-app.sh" >&2
  exit 1
fi
codesign --verify --strict "$APP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Doorman.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG" "$DMG.sha256"
# 新系统上 hdiutil create 已弃用（且可能报 Resource busy），优先用 diskutil image；
# 老系统（如 CI 的 macOS 15）没有 diskutil image，回退到 hdiutil。生成的 UDZO 镜像在 macOS 13+ 都能打开。
if diskutil image create from -h >/dev/null 2>&1; then
  diskutil image create from --format UDZO --volumeName "Doorman" "$STAGE" "$DMG" >/dev/null
else
  hdiutil create -volname "Doorman" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
fi
hdiutil verify "$DMG" >/dev/null 2>&1 || diskutil image info "$DMG" >/dev/null

# 校验文件只写文件名，用户可在下载目录里直接 shasum -a 256 -c 校验
(cd "$ROOT/dist" && shasum -a 256 Doorman.dmg > Doorman.dmg.sha256)

echo "已生成：$DMG"
cat "$DMG.sha256"
