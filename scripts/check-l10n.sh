#!/usr/bin/env bash
# 检查本地化：代码里每个 L("…") 的 key 在英文、日文表里都有翻译，
# 且翻译中的格式占位符（%@ %d %.1f 及位置参数）与原文一致。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -I - "$ROOT" <<'EOF'
import glob, os, re, sys

root = sys.argv[1]
src = os.path.join(root, "Sources", "Doorman")
lit = re.compile(r'L\("((?:[^"\\]|\\.)*)"')
entry = re.compile(r'^\s*"((?:[^"\\]|\\.)*)":\s*"((?:[^"\\]|\\.)*)",?\s*$', re.M)
spec = re.compile(r'%(?:\d+\$)?(?:\.\d+)?[@dfs]')

used = set()
for path in glob.glob(os.path.join(src, "**", "*.swift"), recursive=True):
    if os.sep + "Localization" + os.sep in path:
        continue
    with open(path, encoding="utf-8") as f:
        used.update(m.group(1) for m in lit.finditer(f.read()))

def kind(s):
    # 只比较占位符类型的多重集合，位置参数不影响
    return sorted(re.sub(r'\d+\$', '', x) for x in spec.findall(s))

ok = True
for lang in ("en", "ja"):
    with open(os.path.join(src, "Localization", f"Strings.{lang}.swift"), encoding="utf-8") as f:
        table = dict(entry.findall(f.read()))
    missing = sorted(used - table.keys())
    unused = sorted(table.keys() - used)
    bad = sorted(k for k in used & table.keys() if kind(k) != kind(table[k]))
    print(f"[{lang}] keys={len(table)} used={len(used)} missing={len(missing)} unused={len(unused)} placeholder_mismatch={len(bad)}")
    for k in missing: print(f"  missing: {k}")
    for k in unused: print(f"  unused:  {k}")
    for k in bad: print(f"  placeholder: {k} -> {table[k]}")
    ok = ok and not missing and not bad

sys.exit(0 if ok else 1)
EOF
