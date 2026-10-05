#!/bin/sh
# claude-usage plugin helper.
#   setup.sh link     herdr startup: expose report.sh at a stable path in the plugin config dir
#   setup.sh install  add sidebar rows to herdr config.toml, hook into the Claude statusline,
#                     install the Claude icon font and map it in Ghostty / kitty
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
  # $cu_icon carries an invisible state tag: U+2061 working, U+2060 done, U+2062 blocked.
  echo '  [{ token = "$cu_icon", fg = "#a6e3a1", rules = [{ contains = "\u2061", fg = "#f9e2af" }, { contains = "\u2060", fg = "#94e2d5" }, { contains = "\u2062", fg = "#f38ba8" }] }, "machine", "workspace", "tab"],'
  for n in ctx 5h 7d; do
    echo "  [{ token = \"\$cu_${n}_ok\", $ok }, { token = \"\$cu_${n}_warn\", $warn }, { token = \"\$cu_${n}_hot\", $hot }],"
  done
  echo "]"
  echo "$mark <<<"
}

font_file="$root/assets/fonts/HerdrAgentIconsMax-Regular.ttf"
font_name="Herdr Agent Icons Max"
ghostty_cfg() {
  for c in "$HOME/.config/ghostty/config" "$HOME/.config/ghostty/config.ghostty" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
           "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
    [ -f "$c" ] && { echo "$c"; return; }
  done
}
kitty_cfg="$HOME/.config/kitty/kitty.conf"

# Claude icon (U+E1A0) lives in a bundled icon font the terminal has to map.
install_font() {
  case "$(uname)" in
    Darwin) fonts="$HOME/Library/Fonts" ;;
    *) fonts="$HOME/.local/share/fonts" ;;
  esac
  mkdir -p "$fonts" && cp "$font_file" "$fonts/"
  command -v fc-cache >/dev/null && fc-cache -f "$fonts" >/dev/null 2>&1
  echo "font: installed to $fonts"

  g=$(ghostty_cfg)
  if [ -n "$g" ]; then
    if grep -qF "$mark font" "$g"; then echo "font: ghostty already mapped"; else
      printf '\n%s font\nfont-codepoint-map = U+E1A0="%s"\n' "$mark" "$font_name" >> "$g"
      echo "font: mapped in $g (reload Ghostty config: cmd+shift+,)"
    fi
  fi
  if [ -f "$kitty_cfg" ]; then
    if grep -qF "$mark font" "$kitty_cfg"; then echo "font: kitty already mapped"; else
      printf '\n%s font\nsymbol_map U+E1A0 %s\n' "$mark" "$font_name" >> "$kitty_cfg"
      echo "font: mapped in $kitty_cfg (reload kitty: ctrl+shift+f5)"
    fi
  fi
  [ -n "$g" ] || [ -f "$kitty_cfg" ] ||
    echo "font: map U+E1A0 to \"$font_name\" in your terminal's font fallback, or the icon shows as a box"
}

# Drop the marker line and the setting right after it.
unmap_font() {
  for c in "$(ghostty_cfg)" "$kitty_cfg"; do
    [ -f "$c" ] && grep -qF "$mark font" "$c" || continue
    tmp=$(mktemp)
    awk -v m="$mark font" '$0 == m { skip = 2 } skip { skip--; next } { print }' "$c" > "$tmp"
    cat "$tmp" > "$c" && rm -f "$tmp"
    echo "font: unmapped in $c"
  done
}

strip_rows() {
  tmp=$(mktemp)
  awk -v m="$mark" '$0 == m " >>>" { skip = 1 } !skip { print } $0 == m " <<<" { skip = 0 }' "$herdr_cfg" > "$tmp"
  cat "$tmp" > "$herdr_cfg" && rm -f "$tmp"
}

install() {
  link
  install_font

  touch "$herdr_cfg"
  if grep -q "^$mark >>>" "$herdr_cfg"; then
    strip_rows   # replace our own block so upgrades pick up new rows
    { rows_block; } >> "$herdr_cfg"
    echo "sidebar rows: updated in $herdr_cfg"
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
  unmap_font
  if [ -f "$herdr_cfg" ]; then
    strip_rows
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
