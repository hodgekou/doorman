#!/usr/bin/env bash
# 运行核心逻辑单测。
# 只装 Command Line Tools 时，构建系统偶尔不会自动加载 swift-testing 的宏插件
# （报错 "plugin for module 'TestingMacros' not found"），这里显式传入插件目录。
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
