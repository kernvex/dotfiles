# tmux status bar: catppuccin mocha via TPM

**Date:** 2026-08-08
**Status:** approved

## Goal

Replace the hand-styled status bar (`bg=#333333 fg=#5eacd3`, stock layout) with
a polished catppuccin mocha bar, keeping everything else in `.tmux.conf` —
including the two-row spacer trick — working unchanged.

## Decisions

| Question | Decision |
| --- | --- |
| Theme delivery | TPM + `catppuccin/tmux` plugin (chosen over hand-rolling the palette and over adopting gpakosz `.tmux`) |
| Flavor | Mocha |
| Plugin version | Pinned: `catppuccin/tmux#v2.3.0` |
| Bar contents | Window pills, session, date/time, prefix indicator. Nothing else. |

## Design

### Plugin management

TPM is cloned to `~/.tmux/plugins/tpm` by a bootstrap line in `.tmux.conf`
(`if-shell` guard: clone only when the directory is missing), so a fresh
machine self-installs the theme on first tmux launch. `run
~/.tmux/plugins/tpm/tpm` is the last line of the config, as TPM requires.

The catppuccin plugin is pinned to `v2.3.0` via TPM's `#tag` syntax. The plugin
rewrote its options API wholesale between v0.x and v2; the pin makes upstream
churn an explicit upgrade rather than a surprise.

### Layout and styling

- `@catppuccin_flavor 'mocha'`, window status style: rounded pills.
- Left of the bar: empty (`status-left ""`); window pills start at the left
  edge, numbered per `base-index 1` and packed by `renumber-windows on`.
- Right of the bar: catppuccin **session** module, then **date/time** module
  with its default format (`%Y-%m-%d %H:%M`).
- Prefix indicator: the session pill changes color while the prefix is armed,
  via a `#{?client_prefix,...}` conditional on the session module color. No
  separate segment.
- The old `set -g status-style 'bg=#333333 fg=#5eacd3'` line is removed; the
  bar background comes from the mocha palette.

### Coexistence with the spacer row

The config keeps `status 2` with a `fill=terminal` blank row at
`status-format[0]` and the real bar at `[1]`. The spacer `run-shell` block
moves to run **after** TPM loads. The copied row `[1]` is tmux's default bar
format, which references `status-left`, `status-right`, and the
`window-status-*` options by name, so catppuccin's option-level styling flows
into it without further plumbing. The spacer row keeps `fill=terminal` and
stays transparent against the WezTerm translucent background.

Known interaction to verify at implementation time: catppuccin must set only
option-level styling, not `status-format` itself. If the pinned version turns
out to write `status-format`, the spacer block re-copies `[0]` to `[1]` after
TPM runs, which restores the two-row arrangement; the visual check below
catches this either way.

## Out of scope

Battery, cpu, hostname, and git segments. No other plugins ride along with
TPM. No changes to keybindings, sessionizer, or copy-mode behavior.

## Verification

1. `tmux source ~/.tmux.conf` in the running server: pills render in mocha,
   spacer gap intact, session and date/time pills on the right.
2. Press the prefix: session pill changes color; release/timeout: reverts.
3. Kill the tmux server, start fresh: TPM bootstrap clones itself and the
   theme applies from nothing (the path a new machine takes).
