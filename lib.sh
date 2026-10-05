# Shared helpers, sourced by sync.sh.
# Tokens: $cu_ctx_*, $cu_5h_*, $cu_7d_* where * is ok | warn | hot.

herdr="${HERDR_BIN_PATH:-$(command -v herdr || echo "$HOME/.local/bin/herdr")}"

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

# line <name> <label> <pct|-> [reset_epoch|-]: appends to $args / $tokens
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

# render <pane> <ctx> <5h> <5h_reset> <7d> <7d_reset>
render() {
  pane=$1 args="" tokens=""
  line ctx ctx "$2"
  line 5h 5h "${3:--}" "${4:--}"
  line 7d 7d "${5:--}" "${6:--}"
  set -- pane report-metadata "$pane" --source claude-usage $args
  old_ifs=$IFS
  IFS='
'
  for t in $tokens; do set -- "$@" --token "$t"; done
  IFS=$old_ifs
  "$herdr" "$@" >/dev/null 2>&1
}

# hide <pane>
hide() {
  set -- pane report-metadata "$1" --source claude-usage
  for n in ctx 5h 7d; do for l in ok warn hot; do set -- "$@" --clear-token "cu_${n}_$l"; done; done
  "$herdr" "$@" >/dev/null 2>&1
}
