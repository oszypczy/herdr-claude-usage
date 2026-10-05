#!/bin/sh
# Called from the Claude Code statusline with its JSON payload on stdin.
# Caches the numbers, then lets sync.sh draw them next to the focused agent.
#   state/ctx.<pane>  context %
#   state/limits      "5h% 5h_reset 7d% 7d_reset" (account-wide, latest wins)

[ -n "$HERDR_PANE_ID" ] || exit 0
state="$(dirname "$0")/state"
mkdir -p "$state"

# Percentages are rounded here: shell printf %.0f breaks on "12.5" under a comma-decimal locale.
set -- $(jq -r 'def pct: if . == null then "-" else round | tostring end;
  def ts: if . == null then "-" else floor | tostring end; [
  (.context_window.used_percentage | pct),
  (.rate_limits.five_hour.used_percentage | pct),
  (.rate_limits.five_hour.resets_at | ts),
  (.rate_limits.seven_day.used_percentage | pct),
  (.rate_limits.seven_day.resets_at | ts)
] | join(" ")' 2>/dev/null)
[ $# -eq 5 ] || exit 0

f=$(printf '%s' "$HERDR_PANE_ID" | tr ':/' '__')
printf '%s\n' "$1" > "$state/ctx.$f.tmp.$$" && mv "$state/ctx.$f.tmp.$$" "$state/ctx.$f"
if [ "$2" != "-" ] || [ "$4" != "-" ]; then
  printf '%s %s %s %s\n' "$2" "$3" "$4" "$5" > "$state/limits.tmp.$$" && mv "$state/limits.tmp.$$" "$state/limits"
fi

# Redraw now so the focused session updates live.
real=$(readlink "$0" 2>/dev/null || echo "$0")
HERDR_PLUGIN_CONFIG_DIR="$(dirname "$0")" sh "$(dirname "$real")/sync.sh"
