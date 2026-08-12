# tmux mode indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** nvim-style COPY / VISUAL / SEARCH pills at the far left of the status bar, drawn only while the pane is in copy-mode.

**Architecture:** Three format conditionals appended into `status-left`, expanded per render — no hooks, no `#()` subprocesses. A bash test drives a scratch tmux server (own socket, sources the repo conf by relative path) through the copy-mode states and asserts on the rendered `#{T:status-left}`.

**Tech Stack:** tmux 3.7c, catppuccin/tmux v2.3.0 (mocha) via TPM, bash test script, GNU stow-managed dotfiles.

## Global Constraints

- Only `status-left` changes. `status-right` (continuum plants its autosave
  hook there) and the spacer block at the end of the conf are untouched.
- Labels exactly `COPY` / `VISUAL` / `SEARCH`; colours `@thm_sky` /
  `@thm_mauve` / `@thm_green`; text `@thm_crust` bold; rounded caps `` ``.
- Gate every pill on `#{==:#{pane_mode},copy-mode}` — never `#{pane_in_mode}`
  (also true in choose-tree/view-mode, where COPY would lie).
- VISUAL triggers on `#{selection_active}`, not `selection_present`
  (present lags until the selection is non-empty; measured on 3.7c).
- The live tmux server is never killed or restarted. Tests use `tmux -L`.
- This branch is built in an isolated worktree; `~/.tmux.conf` symlinks to
  the MAIN checkout, so live-server verification (Task 3) happens only
  after merge, from the main checkout.
- Spec: `docs/superpowers/specs/2026-08-12-tmux-mode-indicator-design.md`.

---

### Task 1: State-driving test for the pills (red)

**Files:**
- Create: `bin/.local/bin/test-tmux-mode-indicator`

**Interfaces:**
- Consumes: `tmux/.tmux.conf` resolved relative to the script
  (`$HERE/../../../tmux/.tmux.conf`), so it tests whichever checkout it
  lives in.
- Produces: executable test; exit 0 only when every state shows exactly
  the pills the spec's table requires. A wiring pre-check fails fast with
  `status-left carries no pill segments` while the conf edit is missing —
  that message is the expected red.

- [ ] **Step 1: Write the test script**

Create `bin/.local/bin/test-tmux-mode-indicator` with exactly:

```bash
#!/usr/bin/env bash
# Tests for the copy/visual/search mode pills — the status-left conditionals.
#
#   ./test-tmux-mode-indicator     exit 0 = pass
#
# A scratch tmux server on its own socket sources this checkout's tmux.conf
# and is driven through the copy-mode states with `send-keys -X`; every
# assertion is on the RENDERED bar (`#{T:status-left}`), not the option
# string — the option is one long conditional and always "present", only the
# render says which pills a state actually shows. T: expands the `#{@thm_*}`
# references inside the style blocks too, so each label is asserted together
# with its resolved theme colour. Plugins are already on disk, so no network;
# this is always a second server, so continuum never arms here (see the
# persistence spec amendment).
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/../../../tmux/.tmux.conf"
[ -f "$CONF" ] || { echo "cannot find tmux.conf at $CONF"; exit 1; }

SOCK="mode-indicator-test"
T() { tmux -L "$SOCK" "$@"; }
trap 'T kill-server 2>/dev/null' EXIT

T -f "$CONF" new-session -d -s modes -x 80 -y 24 \
  'printf "needle one\nneedle two\n"; exec sleep 600' \
  || { echo "could not start scratch server"; exit 1; }

# Wired at all? A missing conf edit would otherwise fail every case with an
# unhelpfully empty render.
case "$(T show -gv status-left)" in
  *VISUAL*COPY*SEARCH*) ;;
  *) echo "status-left carries no pill segments — is the conf edit in place?"
     exit 1 ;;
esac

# The theme lands via TPM's run-shell, which can finish after new-session
# returns; the hex assertions below need @thm_* populated.
for _ in $(seq 50); do
  [ -n "$(T show -gv @thm_sky 2>/dev/null)" ] && break
  sleep 0.2
done
SKY="$(T show -gv @thm_sky)"
MAUVE="$(T show -gv @thm_mauve)"
GREEN="$(T show -gv @thm_green)"
[ -n "$SKY" ] && [ -n "$MAUVE" ] && [ -n "$GREEN" ] \
  || { echo "theme never loaded — @thm_* empty"; exit 1; }

PANE="modes:1.0"   # base-index 1
left() { T display -p -t "$PANE" '#{T:status-left}'; }
x() { T send-keys -t "$PANE" -X "$@"; }

PASS=0
FAIL=0

expect() { # <description> <got>, then pairs: has|not <needle>
  local what="$1" got="$2" ok=1; shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      has) case "$got" in *"$2"*) ;; *) ok=0 ;; esac ;;
      not) case "$got" in *"$2"*) ok=0 ;; esac ;;
    esac
    shift 2
  done
  if [ "$ok" -eq 1 ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n        got: %s\n' "$what" "$got"
  fi
}

expect "live pane shows no pill" "$(left)" \
  not COPY not VISUAL not SEARCH

T copy-mode -t "$PANE"
expect "copy-mode shows COPY on sky" "$(left)" \
  has COPY has "$SKY" not VISUAL not "$MAUVE" not SEARCH

x begin-selection
expect "VISUAL replaces COPY the instant a selection starts" "$(left)" \
  has VISUAL has "$MAUVE" not COPY not "$SKY" not SEARCH

x clear-selection
x search-backward "needle"
expect "search adds SEARCH beside COPY" "$(left)" \
  has COPY has SEARCH has "$GREEN" has "$SKY" not VISUAL

x begin-selection
x search-again
expect "searching during a selection: VISUAL + SEARCH" "$(left)" \
  has VISUAL has SEARCH not COPY

x cancel
expect "cancel clears every pill" "$(left)" \
  not COPY not VISUAL not SEARCH

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

Why the states run in this order: `begin-selection` drops tmux's search
marks, so the search case re-searches after `clear-selection`, and the
combined case reaches VISUAL + SEARCH with `search-again` *during* the
selection — the only order in which both flags are up at once (measured
on 3.7c; see the spec).

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/.local/bin/test-tmux-mode-indicator`

- [ ] **Step 3: Run it — expect the wiring red**

Run: `bin/.local/bin/test-tmux-mode-indicator`
Expected: exit 1 with `status-left carries no pill segments — is the conf
edit in place?` — the conf is unedited, so the pre-check is the failure.
Any OTHER failure (cannot find tmux.conf, could not start scratch server)
is a harness bug: STOP and fix the script, not the conf.

- [ ] **Step 4: Commit**

```bash
git add bin/.local/bin/test-tmux-mode-indicator
git commit -m "test(tmux): drive the mode pills through every copy-mode state"
```

---

### Task 2: The pills in status-left (green)

**Files:**
- Modify: `tmux/.tmux.conf` (the `set -g status-left ""` line and the
  comment two lines above it)

**Interfaces:**
- Consumes: the Task 1 test.
- Produces: `status-left` carrying three appended conditional segments
  (VISUAL, COPY, SEARCH — in that option order).

- [ ] **Step 1: Update the stale comment**

In `tmux/.tmux.conf` find:

```tmux
# Window pills start at the left edge; everything informational lives on the
# right. `#{E:...}` expands at render time, so these can be set before TPM
# actually loads the plugin.
```

Replace the first sentence so the block reads:

```tmux
# Window pills start at the left edge (behind the mode pills below);
# everything informational lives on the right. `#{E:...}` expands at render
# time, so these can be set before TPM actually loads the plugin.
```

- [ ] **Step 2: Replace the empty status-left with the pills**

Replace the line:

```tmux
set -g status-left ""
```

with:

```tmux
# nvim-style mode pills, drawn only while the pane is in copy-mode: COPY
# (sky) reading scrollback, upgraded to VISUAL (mauve) the instant a
# selection starts, SEARCH (green) appended while search results are
# active. Empty when live, so the window pills keep the left edge and
# slide right while a pill shows — the shift is a cue, not a bug.
#
#   - The gate is `#{==:#{pane_mode},copy-mode}`, not `#{pane_in_mode}`:
#     the latter is also true in choose-tree and view-mode, where a COPY
#     pill would lie.
#   - `selection_active`, not `selection_present`: present only flips once
#     the selection is non-empty, which would lag the pill one keystroke
#     behind `v`. Starting a selection drops an existing search highlight
#     (tmux clears the marks), so SEARCH honestly disappears with it.
#   - Three appended segments, one state each; the first two are mutually
#     exclusive, SEARCH rides beside either. Styles inside the branches
#     are space-separated (`bg=x bold`), so no comma ever needs a `#,`
#     escape from the surrounding conditional.
#   - SEARCH means results are active in the pane. While the query is
#     still being typed at / or ?, tmux shows its own prompt here anyway.
set -g status-left "#{?#{&&:#{==:#{pane_mode},copy-mode},#{selection_active}},#[fg=#{@thm_mauve} bg=default]#[fg=#{@thm_crust} bg=#{@thm_mauve} bold]VISUAL#[fg=#{@thm_mauve} bg=default]#[default] ,}"
set -ag status-left "#{?#{&&:#{==:#{pane_mode},copy-mode},#{==:#{selection_active},0}},#[fg=#{@thm_sky} bg=default]#[fg=#{@thm_crust} bg=#{@thm_sky} bold]COPY#[fg=#{@thm_sky} bg=default]#[default] ,}"
set -ag status-left "#{?#{&&:#{==:#{pane_mode},copy-mode},#{search_present}},#[fg=#{@thm_green} bg=default]#[fg=#{@thm_crust} bg=#{@thm_green} bold]SEARCH#[fg=#{@thm_green} bg=default]#[default] ,}"
```

The caps are `` (U+E0B6) and `` (U+E0B4) — the same rounded glyphs the
catppuccin window pills use.

- [ ] **Step 3: Run the test — expect green**

Run: `bin/.local/bin/test-tmux-mode-indicator`
Expected: `6 passed, 0 failed`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add tmux/.tmux.conf
git commit -m "feat(tmux): copy/visual/search mode pills at the left of the status bar"
```

---

### Task 3: Live-server verification (after merge, from the main checkout)

**Files:**
- None modified. Runs in the MAIN checkout after this branch is merged —
  `~/.tmux.conf` is the stow symlink into it, and the live server is the
  only place the colours and caps can actually be seen.

**Interfaces:**
- Consumes: the merged conf from Task 2.

- [ ] **Step 1: Confirm the live file is the merged repo file**

Run: `readlink ~/.tmux.conf && grep -c "mode pills" ~/.tmux.conf`
Expected: a path into `kernvex/dotfiles/tmux/`, then a non-zero count.

- [ ] **Step 2: Reload the live server**

Run: `tmux source-file ~/.tmux.conf`
Expected: no output, no error.

- [ ] **Step 3: Check the neighbours survived**

Run: `tmux show -gv status-right | grep -c continuum_save`
Expected: `1` — continuum's autosave hook still armed (re-planted by the
re-run of TPM).

Run: `tmux display -p '#{status}' && tmux show -gv 'status-format[1]' | grep -c status-left`
Expected: `2`, then a non-zero count — the spacer row still stands and the
copied bar row still pulls `status-left`, so the pills reach the visible
row.

- [ ] **Step 4: Human eyeball**

Ask the human partner to run, in any pane: `prefix [` (sky COPY pill,
window pills nudge right), `v` (mauve VISUAL), `Escape` then `/needle`
Enter (COPY + green SEARCH), `v` again (VISUAL + SEARCH), `q` (bar back to
normal). No commit — report what they see.
