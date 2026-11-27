#!/usr/bin/env bash
# 启动打包好的 App，确认运行一段时间内不崩溃。CI 和发布前都会跑。
# 用法：scripts/smoke-test.sh [App 路径]   默认 dist/Doorman.app
#   SMOKE_SECONDS=10   运行多久
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Doorman.app}"
DURATION="${SMOKE_SECONDS:-10}"
[[ "$DURATION" =~ ^[0-9]+$ ]] || { echo "SMOKE_SECONDS 应为整数" >&2; exit 2; }
[ -x "$APP/Contents/MacOS/Doorman" ] || { echo "找不到 ${APP}" >&2; exit 1; }

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

"$APP/Contents/MacOS/Doorman" >"$LOG" 2>&1 &
PID=$!
sleep "$DURATION"

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  echo "Smoke test passed: Doorman ran for ${DURATION}s without crashing."
  exit 0
fi

CODE=0
wait "$PID" || CODE=$?
echo "Smoke test failed: Doorman exited after less than ${DURATION}s (exit code ${CODE})." >&2
echo "--- output ---" >&2
cat "$LOG" >&2
REPORT="$(ls -t "$HOME/Library/Logs/DiagnosticReports"/Doorman-*.ips 2>/dev/null | head -1 || true)"
if [ -n "$REPORT" ]; then
  echo "--- crash report: ${REPORT} ---" >&2
  head -c 6000 "$REPORT" >&2
fi
exit 1
