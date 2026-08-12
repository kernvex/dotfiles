# tmux mode indicator: COPY / VISUAL / SEARCH pills

**Date:** 2026-08-12
**Status:** Approved

## Problem

Nothing on screen says whether a pane is live or in copy-mode scrollback.
Keystrokes land somewhere unexpected, and scroll position quietly diverges
from the live tail. nvim solves this with a coloured mode indicator at the
bottom-left; tmux should give the same signal for copy-mode, selection,
and search.

## Decision

Render up to two coloured pills in `status-left` — currently empty, so the
bottom-left corner is free — built from pure format conditionals evaluated
at render time. No hooks, no `#()` subprocesses: tmux has no hook for
selection/search changes, so hooks cannot express this, and `#()` polls a
shell on every status interval. Formats re-render on every state change
for free.

## States and pills

The first pill names the mode; SEARCH is an additive second pill.

| Pane state                          | Pills               |
| ----------------------------------- | ------------------- |
| Live (not in copy-mode)             | none                |
| Copy-mode, no selection, no search  | `COPY`              |
| Selection active                    | `VISUAL`            |
| Search active, no selection         | `COPY` + `SEARCH`   |
| Selection and search both active    | `VISUAL` + `SEARCH` |

- Gate on `#{==:#{pane_mode},copy-mode}`, not `#{pane_in_mode}` — the
  latter is also true in choose-tree and view-mode, where a COPY pill
  would lie.
- `VISUAL` replaces `COPY` while `#{selection_active}` is on — live from
  the instant `v` (or a mouse drag) starts the selection. Not
  `selection_present`: that only flips once the selection is non-empty,
  which would lag the pill one keystroke behind the mode (measured on
  tmux 3.7c).
- `SEARCH` appears while `#{search_present}` is on: search results are
  active in the pane. It cannot mean "typing the query" — during `/` and
  `?` tmux replaces the status line with its own prompt. The flag is
  copy-mode state, so leaving copy mode clears it. Starting a selection
  also drops it (tmux clears the search marks), so VISUAL + SEARCH is
  reached by searching *during* a selection; the pills just report the
  flags honestly.

## Appearance

Catppuccin mocha throughout, via the theme's render-time `@thm_*`
variables (the same seam `@catppuccin_window_current_text` already uses —
no literal hexes):

- `COPY` on `@thm_sky` — calm "you're reading"
- `VISUAL` on `@thm_mauve` — nvim's visual purple
- `SEARCH` on `@thm_green` — search-highlight convention

Full words, `@thm_crust` bold text, rounded end caps matching the window
pills. The pills push the window row right while visible and it snaps
back on exit; accepted, and useful as a secondary cue.

## Placement in tmux.conf

With the other status/theme options, before the `@plugin` lines.
`#{@thm_*}` references expand at render time, so setting `status-left`
before TPM loads the theme is safe — the existing window-pill overrides
already rely on this.

Constraints inherited from the persistence spec hold untouched:

1. This feature writes `status-left` only. Continuum's autosave hook
   lives in `status-right`; nothing here rewrites it.
2. The spacer block stays last. Its copied row `[1]` pulls `status-left`
   by option name at render time, so the pills flow into the visible bar
   with no extra wiring.

## Verification

The live server is never restarted. Two tiers:

- **Format truth (scratch socket):** on `tmux -L` with a throwaway
  session, drive states with `send-keys -X` (`begin-selection`,
  `search-backward`, `cancel`) and assert
  `tmux display -p '#{pane_mode} #{selection_active} #{search_present}'`
  flips as the table above requires, and that
  `tmux display -p '#{T:status-left}'` renders the expected pill text in
  each state.
- **Live eyeball:** after `bind r` re-source, enter copy mode, select,
  search — three pills, three colours, gone on `q`.

## Out of scope

- Indicators for other modes (choose-tree, client, view-mode)
- Reserving fixed width so window pills never shift (rejected — the
  shift is itself a cue)
- Indicators for non-active panes or in the spacer row
- Any change to `status-right`
