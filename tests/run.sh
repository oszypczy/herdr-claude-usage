#!/bin/sh
# Runs the plugin scripts against a fake `herdr` that serves canned pane lists and
# logs every report-metadata call. No real herdr session is touched.
#   sh tests/run.sh
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# --- fake herdr -------------------------------------------------------------
cat > "$tmp/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "pane list") cat "$FAKE/list.json" ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"api"},{"workspace_id":"w2","label":"web"}]}}' ;;
  "pane report-metadata") shift 2; echo "$*" >> "$FAKE/calls.log" ;;
esac
EOF
chmod +x "$tmp/herdr"
export FAKE="$tmp" HERDR_BIN_PATH="$tmp/herdr" HERDR_SOCKET_PATH="$tmp/herdr.sock"
export HERDR_PLUGIN_CONFIG_DIR="$tmp/cfg"
mkdir -p "$tmp/cfg"
ln -s "$repo/report.sh" "$tmp/cfg/report.sh"

enable() { echo "[{\"plugin_id\":\"oszypczy.claude-usage\",\"enabled\":$1}]" > "$tmp/plugins.json"; }

# panes: <focused pane id> ; claude w1:p1, codex w1:p2, shell w2:p1, claude w2:p2
panes() {
  extra=${2:-}; [ -n "$extra" ] || extra='{}'
  jq -n --arg f "$1" --argjson extra "$extra" '{result: {panes: [
    {pane_id: "w1:p1", workspace_id: "w1", agent: "claude", agent_status: "working", label: "fix auth"},
    {pane_id: "w1:p2", workspace_id: "w1", agent: "codex", agent_status: "idle", label: "codex task"},
    {pane_id: "w2:p1", workspace_id: "w2", label: "zsh"},
    {pane_id: "w2:p2", workspace_id: "w2", agent: "claude", agent_status: "idle", label: "landing page"}
  ] | map(.focused = (.pane_id == $f) | .tokens = ($extra[.pane_id] // {}))}}' > "$tmp/list.json"
}

statusline() { # <pane> <json>
  printf '%s' "$2" | HERDR_PANE_ID=$1 sh "$tmp/cfg/report.sh"
}

check() { # <description> <condition...>
  d=$1; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi
}
calls_for() { grep "^$1 " "$tmp/calls.log" 2>/dev/null; }
has() { calls_for "$1" | grep -qF -- "$2"; }
none_for() { ! calls_for "$1" | grep -q .; }

now=$(date +%s)
full="{\"context_window\":{\"used_percentage\":12.5},\"rate_limits\":{\"five_hour\":{\"used_percentage\":62.4,\"resets_at\":$((now + 7980))},\"seven_day\":{\"used_percentage\":85,\"resets_at\":$((now + 280000))}}}"

# 1. Focused Claude pane gets bars; Codex and shell panes are never touched.
enable true; panes w1:p1; : > "$tmp/calls.log"
LC_ALL=pl_PL.UTF-8 statusline w1:p1 "$full"
check "ctx rounds 12.5 under pl_PL locale"      has w1:p1 "cu_ctx_ok=ctx ━───── 13%"
check "5h at 62% is warn with countdown"        has w1:p1 "cu_5h_warn=5h  ━━━━── 62% 2h13m"
check "7d at 85% is hot"                        has w1:p1 "cu_7d_hot=7d  ━━━━━─ 85% 3d5h"
check "working Claude head: ✳ + tag + name"     has w1:p1 "cu_head=$(printf '\342\234\263\342\201\241') api"
check "idle Claude head has no tag"             has w2:p2 "cu_head=$(printf '\342\234\263') web"
check "Codex pane untouched"                    none_for w1:p2
check "shell pane untouched"                    none_for w2:p1

# 2. Focus moves to Codex: bars leave the Claude pane, Codex still untouched.
panes w1:p2 '{"w1:p1":{"cu_ctx_ok":"x","cu_head":"h"}}'; : > "$tmp/calls.log"
sh "$repo/sync.sh"
check "bars hidden on unfocused Claude pane"    has w1:p1 "--clear-token cu_ctx_ok"
check "Codex pane untouched when focused"       none_for w1:p2
check "no bars drawn anywhere"                  sh -c "! grep -q -- '--token cu_ctx' '$tmp/calls.log'"

# 3. Focus on the other Claude pane before its statusline ran: nothing to draw yet.
panes w2:p2; : > "$tmp/calls.log"
sh "$repo/sync.sh"
check "no bars without cached data"             sh -c "! grep -q -- '--token cu_ctx' '$tmp/calls.log'"

# 4. API-key session (no rate_limits): only the ctx bar.
panes w2:p2; : > "$tmp/calls.log"; rm -f "$tmp/cfg/state/limits"
statusline w2:p2 '{"context_window":{"used_percentage":40}}'
check "ctx bar drawn"                           has w2:p2 "cu_ctx_ok=ctx ━━──── 40%"
check "no 5h / 7d bars"                         sh -c "! grep -q -- '--token cu_5h\|--token cu_7d' '$tmp/calls.log'"

# 5. Reset already passed: shows 0% until the next update, no countdown.
echo "90 $((now - 60)) 20 $((now + 3600))" > "$tmp/cfg/state/limits"; : > "$tmp/calls.log"
sh "$repo/sync.sh"
check "expired 5h window shows 0%"              has w2:p2 "cu_5h_ok=5h  ────── 0%"

# 6. Plugin disabled: bars are cleared, nothing drawn.
enable false; panes w2:p2 '{"w2:p2":{"cu_ctx_ok":"x"}}'; : > "$tmp/calls.log"
statusline w2:p2 '{"context_window":{"used_percentage":40}}'
check "disabled: bars cleared"                  has w2:p2 "--clear-token cu_ctx_ok"
check "disabled: nothing drawn"                 sh -c "! grep -q -- '--token cu_ctx' '$tmp/calls.log'"

# 7. Outside herdr the statusline hook is a no-op.
: > "$tmp/calls.log"
printf '%s' "$full" | env -u HERDR_PANE_ID sh "$tmp/cfg/report.sh"
check "no calls outside herdr"                  sh -c "! [ -s '$tmp/calls.log' ]"

[ "$fail" = 0 ] && echo "all passed" || { echo "some tests failed"; exit 1; }
