#!/bin/sh
# Reports Claude usage (context, 5h, 7d) to the herdr sidebar as pane tokens.
# Called from the Claude Code statusline with its JSON payload on stdin.
# Tokens: $cu_ctx_*, $cu_5h_*, $cu_7d_* where * is ok | warn | hot.

[ -n "$HERDR_PANE_ID" ] || exit 0
herdr="${HERDR_BIN_PATH:-herdr}"
plugins_json="$(dirname "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}")/plugins.json"

# Plugin disabled (or uninstalled) -> hide the bars.
enabled=$(jq -r '[.[] | select(.plugin_id == "claude-usage") | .enabled] | first // false' "$plugins_json" 2>/dev/null)
if [ "$enabled" != true ]; then
  set -- pane report-metadata "$HERDR_PANE_ID" --source claude-usage
  for n in ctx 5h 7d; do for l in ok warn hot; do set -- "$@" --clear-token "cu_${n}_$l"; done; done
  "$herdr" "$@" >/dev/null 2>&1
  exit 0
fi

set -- $(jq -r '[
  (.context_window.used_percentage // "-"),
  (.rate_limits.five_hour.used_percentage // "-"),
  (.rate_limits.five_hour.resets_at // "-"),
  (.rate_limits.seven_day.used_percentage // "-"),
  (.rate_limits.seven_day.resets_at // "-")
] | map(tostring) | join(" ")')
ctx=$1 h5=$2 h5_reset=$3 d7=$4 d7_reset=$5

# bar <pct> -> "━━────"
bar() {
  filled=$(( ($1 * 6 + 50) / 100 ))
  [ "$filled" -gt 6 ] && filled=6
  i=0 out=""
  while [ $i -lt 6 ]; do
    if [ $i -lt "$filled" ]; then out="${out}━"; else out="${out}─"; fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# left <epoch> -> "2h13m" / "3d4h" / "12m"
left() {
  rem=$(( $1 - $(date +%s) ))
  [ "$rem" -lt 0 ] && rem=0
  if [ "$rem" -ge 86400 ]; then printf '%dd%dh' $((rem / 86400)) $(( (rem % 86400) / 3600 ))
  elif [ "$rem" -ge 3600 ]; then printf '%dh%dm' $((rem / 3600)) $(( (rem % 3600) / 60 ))
  else printf '%dm' $((rem / 60)); fi
}

args=""
# line <name> <label> <pct> [reset_epoch]
line() {
  name=$1 label=$2 pct=$3 reset=$4
  lvl=none
  if [ "$pct" != "-" ]; then
    p=$(printf '%.0f' "$pct")
    if [ "$p" -ge 80 ]; then lvl=hot; elif [ "$p" -ge 50 ]; then lvl=warn; else lvl=ok; fi
  fi
  for l in ok warn hot; do [ "$l" = "$lvl" ] || args="$args --clear-token cu_${name}_$l"; done
  [ "$lvl" = none ] && return
  text=$(printf '%-3s %s %d%%' "$label" "$(bar "$p")" "$p")
  [ -n "$reset" ] && [ "$reset" != "-" ] && text="$text $(left "$reset")"
  tokens="$tokens
cu_${name}_$lvl=$text"
}

tokens=""
line ctx ctx "$ctx"
line 5h 5h "$h5" "$h5_reset"
line 7d 7d "$d7" "$d7_reset"

# Build the final argv: clears first, then the fresh values (values contain spaces).
set -- pane report-metadata "$HERDR_PANE_ID" --source claude-usage $args
old_ifs=$IFS
IFS='
'
for t in $tokens; do set -- "$@" --token "$t"; done
IFS=$old_ifs

"$herdr" "$@" >/dev/null 2>&1
