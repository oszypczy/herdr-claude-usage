# herdr-claude-usage

Minimal Claude usage bars for the [herdr](https://herdr.dev) agents sidebar: context window, 5-hour limit and 7-day limit, each with its reset countdown. Only the focused Claude agent shows them, so a long agent list stays compact.

```
 VSCode · 1 · Herdr Claude…
ctx ━───── 10%
5h  ━━──── 38% 2h50m
7d  ────── 1% 4d16h
```

Bars go yellow at 50% and red at 80%. Every Claude agent gets the Claude mark in place of herdr's state dot, colored by state: green idle, yellow working, teal done, red blocked.

## How it works

There is no daemon and no polling. Claude Code already pipes context and rate-limit data to its statusline command as JSON. A one-line hook in your statusline script hands that JSON to `report.sh`, which caches the numbers. `sync.sh` then pushes three pane tokens (`herdr pane report-metadata`) to the focused Claude agent and clears them from every other pane. The sidebar renders them through `rows_by_agent.claude`.

The Claude mark is `$cu_icon`: U+E1A0 from the bundled *Herdr Agent Icons Max* font plus an invisible state tag (U+2061 working, U+2060 done, U+2062 blocked) that the config colors with `rules`.

`sync.sh` runs after every statusline update, on `pane.agent_status_changed` / `pane.agent_detected`, and on herdr's `pane.focused`, `tab.focused` and `workspace.focused` events, so the bars follow your focus. The 5h/7d limits are account-wide, so the latest values from any session are shown. Values refresh on activity in a session or when you switch to it.

## Requirements

- herdr ≥ 0.9.0
- Claude Code with a statusline script (`statusLine.command` in `~/.claude/settings.json`) that reads stdin into `input=$(cat)`
- `jq`

## Install

```sh
herdr plugin install oszypczy/herdr-claude-usage   # or: herdr plugin link /path/to/herdr-claude-usage
herdr plugin action invoke setup --plugin claude-usage
```

`setup` is idempotent. It:

1. adds a marked `[ui.sidebar.agents.rows_by_agent]` block to herdr's `config.toml` and reloads it;
2. inserts one marked line after `input=$(cat)` in your statusline script;
3. installs the icon font (`~/Library/Fonts` or `~/.local/share/fonts`) and maps U+E1A0 to it in Ghostty (`font-codepoint-map`) or kitty (`symbol_map`). Reload the terminal config afterwards. For other terminals add the font to its fallback list, or the icon shows as a box.

If either step can't be done automatically (for example, you already have your own `rows_by_agent` table), it prints what to add by hand.

## Disable / uninstall

- `herdr plugin disable claude-usage` hides the bars. They come back with `enable`.
- `herdr plugin action invoke remove --plugin claude-usage` removes the config block, the statusline line and the terminal font map (the font file stays installed). Run it before `herdr plugin uninstall claude-usage`.

The statusline hook is guarded, so a leftover line is a no-op once the plugin is gone.

## Customizing

- Thresholds: `line()` in `report.sh` (50 / 80).
- Bar width: `bar()` in `report.sh` (6 cells).
- Colors and layout: the `claude-usage` block in herdr's `config.toml`. Tokens are `$cu_{ctx,5h,7d}_{ok,warn,hot}`; only the token for the current level is set.

## License

MIT. The icon font in `assets/fonts` is under the SIL Open Font License 1.1, see `assets/fonts/NOTICE.md`.
