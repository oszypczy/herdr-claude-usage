#!/bin/sh
# claude-usage plugin helper.
#   setup.sh link     herdr startup: expose report.sh at a stable path in the plugin config dir
#   setup.sh install  add sidebar rows to herdr config.toml + hook into the Claude statusline
#   setup.sh remove   undo `install`
set -e

id=claude-usage
mark="# claude-usage"
root="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
cfg_dir="${HERDR_PLUGIN_CONFIG_DIR:-$(herdr plugin config-dir "$id" 2>/dev/null || echo "$HOME/.config/herdr/plugins/config/$id")}"
herdr_dir="$(dirname "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}")"
herdr_cfg="$herdr_dir/config.toml"
report="$cfg_dir/report.sh"

link() {
  mkdir -p "$cfg_dir"
  ln -sf "$root/report.sh" "$report"
}

# Statusline script named in ~/.claude/settings.json (`sh /path/x.sh` or `/path/x.sh`).
statusline_script() {
  cmd=$(jq -r '.statusLine.command // empty' "$HOME/.claude/settings.json" 2>/dev/null)
  for w in $cmd; do
    w=$(eval echo "$w")
    [ -f "$w" ] && { echo "$w"; return; }
  done
}

hook_line() {
  printf '[ -n "$HERDR_PANE_ID" ] && [ -f "%s" ] && (printf "%%s" "$input" | sh "%s" &) >/dev/null 2>&1 %s\n' \
    "$report" "$report" "$mark"
}

rows_block() {
  ok='fg = "#98b17d", dim = true' warn='fg = "#dec27f"' hot='fg = "#df919b"'
  echo "$mark >>>"
  echo "[ui.sidebar.agents.rows_by_agent]"
  echo "claude = ["
  echo '  ["state_icon", "machine", "workspace", "tab"],'
  for n in ctx 5h 7d; do
    echo "  [{ token = \"\$cu_${n}_ok\", $ok }, { token = \"\$cu_${n}_warn\", $warn }, { token = \"\$cu_${n}_hot\", $hot }],"
  done
  echo "]"
  echo "$mark <<<"
}

install() {
  link

  touch "$herdr_cfg"
  if grep -q "^$mark >>>" "$herdr_cfg"; then
    echo "sidebar rows: already present"
  elif grep -q '^\[ui\.sidebar\.agents\.rows_by_agent\]' "$herdr_cfg"; then
    echo "sidebar rows: SKIPPED, $herdr_cfg already has [ui.sidebar.agents.rows_by_agent]."
    echo "  Add these rows to its claude entry by hand:"
    rows_block | sed -n '/^  \[{/p'
  else
    { echo; rows_block; } >> "$herdr_cfg"
    echo "sidebar rows: added to $herdr_cfg"
  fi
  herdr server reload-config >/dev/null 2>&1 || true

  sl=$(statusline_script)
  if [ -z "$sl" ]; then
    echo "statusline: no statusline script found in ~/.claude/settings.json."
    echo "  Add this line to your statusline script, right after input=\$(cat):"
    echo "  $(hook_line)"
  elif grep -qF "$mark" "$sl"; then
    echo "statusline: already hooked ($sl)"
  elif grep -q '^input=\$(cat)' "$sl"; then
    tmp=$(mktemp)
    awk -v hook="$(hook_line)" '{ print } !done && /^input=\$\(cat\)/ { print hook; done = 1 }' "$sl" > "$tmp"
    cat "$tmp" > "$sl" && rm -f "$tmp"
    echo "statusline: hooked into $sl"
  else
    echo "statusline: $sl has no 'input=\$(cat)' line. Add this after the line that reads stdin:"
    echo "  $(hook_line)"
  fi
}

remove() {
  if [ -f "$herdr_cfg" ]; then
    tmp=$(mktemp)
    awk -v m="$mark" '$0 == m " >>>" { skip = 1 } !skip { print } $0 == m " <<<" { skip = 0 }' "$herdr_cfg" > "$tmp"
    cat "$tmp" > "$herdr_cfg" && rm -f "$tmp"
    herdr server reload-config >/dev/null 2>&1 || true
    echo "sidebar rows: removed"
  fi
  sl=$(statusline_script)
  if [ -n "$sl" ] && grep -qF "$mark" "$sl"; then
    tmp=$(mktemp)
    grep -vF "$mark" "$sl" > "$tmp"
    cat "$tmp" > "$sl" && rm -f "$tmp"
    echo "statusline: unhooked $sl"
  fi
}

case "${1:-link}" in
  link) link ;;
  install) install ;;
  remove) remove ;;
  *) echo "usage: $0 [link|install|remove]" >&2; exit 2 ;;
esac
