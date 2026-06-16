#!/usr/bin/env bash
#
# smoke-liney-cli.sh — end-to-end smoke test for the Liney agent control CLI
# (status / read / agents / session list / send-keys auth model).
#
# Requires: a *freshly built* Liney running (the new commands only exist in the
# new binary AND the running app). jq.
#
# Usage:
#   scripts/smoke-liney-cli.sh            # auto-detect the Debug binary
#   LINEY=/path/to/Liney scripts/smoke-liney-cli.sh
#
# Exit code: 0 if all checks pass, 1 otherwise.

set -u

# --- locate the liney binary -------------------------------------------------
LINEY="${LINEY:-}"
if [[ -z "$LINEY" ]]; then
  LINEY="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/Build/Products/Debug/Liney.app/Contents/MacOS/Liney' 2>/dev/null | head -1)"
fi
if [[ -z "$LINEY" ]]; then
  for c in /usr/local/bin/liney /Applications/Liney.app/Contents/MacOS/Liney; do
    [[ -x "$c" ]] && LINEY="$c" && break
  done
fi
if [[ -z "$LINEY" || ! -x "$LINEY" ]]; then
  echo "✗ 找不到 liney 二进制。先 build,或用 LINEY=/path/... 指定。"
  exit 1
fi
echo "binary: $LINEY"

command -v jq >/dev/null || { echo "✗ 需要 jq(brew install jq)"; exit 1; }

SOCK="$HOME/Library/Application Support/Liney/agent-notify.sock"
[[ -S "$SOCK" ]] || { echo "✗ socket 不存在,Liney 没在跑:$SOCK"; exit 1; }

# --- tiny assertion harness --------------------------------------------------
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

# run liney, capture stdout + exit code
run() { OUT="$("$LINEY" "$@" 2>/dev/null)"; RC=$?; }

echo "── 只读命令(应免 token)────────────────────────────"

run session list --json
if [[ $RC -eq 0 ]] && echo "$OUT" | jq -e 'type=="array"' >/dev/null 2>&1; then
  ok "session list --json → 退出 0 且是 JSON 数组"
else
  bad "session list --json(rc=$RC)— 确认运行的是新构建的 Liney"
fi

# 取一个 pane uuid 作为后续目标
PANE="$(echo "$OUT" | jq -r '.[0].pane // empty' 2>/dev/null)"
if [[ -n "$PANE" ]]; then
  ok "拿到 pane: $PANE"
else
  bad "session list 没有任何 pane——先在 Liney 里开一个终端 pane 再跑"
  echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

run read --pane "$PANE" --last 5
[[ $RC -eq 0 ]] && ok "read --pane(免 token)→ 退出 0" || bad "read --pane(rc=$RC)"

run read --pane "$PANE" --last 5 --json
if [[ $RC -eq 0 ]] && echo "$OUT" | jq -e 'has("ok") and has("text")' >/dev/null 2>&1; then
  ok "read --json → 有 .ok / .text 字段"
else
  bad "read --json 结构不对(rc=$RC)"
fi

run agents --json
if [[ $RC -eq 0 ]] && echo "$OUT" | jq -e 'type=="array"' >/dev/null 2>&1; then
  ok "agents --json → 退出 0 且是 JSON 数组(当前 $(echo "$OUT" | jq 'length') 个 agent)"
else
  bad "agents --json(rc=$RC)"
fi

echo "── status 自报 + 往返 ──────────────────────────────"

run status running --pane "$PANE"
[[ $RC -eq 0 ]] && ok "status running → 退出 0" || bad "status running(rc=$RC)"
sleep 0.4
run session list --json
RB="$(echo "$OUT" | jq -r --arg p "$PANE" '.[] | select(.pane==$p) | .status // empty')"
[[ "$RB" == "running" ]] && ok "session list 回读到 status=running" || bad "status 没往返回来(读到 '$RB')"

echo "── 受保护命令仍需 token ────────────────────────────"

# 去掉注入的 token,send-keys 应被拒(退出码 77 = authRequired)
env -u LINEY_CONTROL_TOKEN "$LINEY" send-keys "$PANE" 'true' >/dev/null 2>&1; RC=$?
[[ $RC -eq 77 ]] && ok "无 token 的 send-keys → 退出 77(被拒,符合预期)" \
                 || bad "无 token 的 send-keys 退出码应为 77,实际 $RC"

# 同样无 token,read 仍应成功(证明只放宽了只读命令)
env -u LINEY_CONTROL_TOKEN "$LINEY" read --pane "$PANE" --last 1 >/dev/null 2>&1; RC=$?
[[ $RC -eq 0 ]] && ok "无 token 的 read → 退出 0(只读放宽生效)" \
               || bad "无 token 的 read 应退出 0,实际 $RC"

echo "─────────────────────────────────────────────────────"
echo "结果:PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]] && { echo "✅ 全部通过"; exit 0; } || { echo "❌ 有失败项"; exit 1; }
