#!/bin/sh
# Draws the usage bars next to the focused Claude agent and hides them everywhere else,
# and keeps every Claude agent's head token ($cu_head: icon + workspace) tagged with its state.
# Run by herdr on focus / agent-status events and at startup, and by report.sh after
# each statusline update.

root=$(cd "$(dirname "$0")" && pwd)
. "$root/lib.sh"
state="${HERDR_PLUGIN_CONFIG_DIR:-$HOME/.config/herdr/plugins/config/claude-usage}/state"
plugins_json="$(dirname "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}")/plugins.json"

list=$("$herdr" pane list 2>/dev/null) || exit 0

# Head token: Claude icon + invisible state tag + workspace name, one token so herdr
# puts no " · " after the icon; config.toml colors it through `rules`. Only changed
# ones are sent.
ws=$("$herdr" workspace list 2>/dev/null | jq -c '[.result.workspaces[] | {key: .workspace_id, value: .label}] | from_entries') || ws='{}'
printf '%s' "$list" | jq -r --argjson ws "$ws" '.result.panes[] | select(.agent == "claude")
    | [.pane_id, ("\u2733" + ({working: "\u2061", done: "\u2060", blocked: "\u2062"}[.agent_status] // "")
        + " " + ($ws[.workspace_id] // .workspace_id))]
    as [$id, $want] | select($want != (.tokens.cu_head // "")) | "\($id)\t\($want)"' |
  while IFS='	' read -r p head; do
    "$herdr" pane report-metadata "$p" --source claude-usage.icon --token "cu_head=$head" >/dev/null 2>&1
  done

focus=""
enabled=$(jq -r '[.[] | select(.plugin_id == "claude-usage") | .enabled] | first // false' "$plugins_json" 2>/dev/null)
if [ "$enabled" = true ]; then
  focus=$(printf '%s' "$list" | jq -r '[.result.panes[] | select(.focused and .agent == "claude") | .pane_id] | first // ""')
fi
ctx=""
if [ -n "$focus" ]; then
  ctx=$(cat "$state/ctx.$(printf '%s' "$focus" | tr ':/' '__')" 2>/dev/null)
  [ -n "$ctx" ] || focus=""   # no statusline data yet
fi

# Hide bars on every other pane that still has them.
for p in $(printf '%s' "$list" | jq -r --arg f "$focus" '.result.panes[]
    | select(.pane_id != $f and ((.tokens // {}) | keys | any(startswith("cu_") and . != "cu_head"))) | .pane_id'); do
  hide "$p"
done

[ -n "$focus" ] || exit 0
# shellcheck disable=SC2046 # limits is four space-separated fields
render "$focus" "$ctx" $(cat "$state/limits" 2>/dev/null)
