# tmux catppuccin status bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-styled tmux status bar with catppuccin mocha via TPM, keeping the two-row spacer trick working.

**Architecture:** TPM self-bootstraps from `.tmux.conf` and loads a pinned `catppuccin/tmux`. The bar is composed from catppuccin's session and date/time modules; the existing spacer block (blank `status-format[0]`, real bar at `[1]`) moves after TPM so themed options flow into the copied row.

**Tech Stack:** tmux 3.7b, TPM, catppuccin/tmux v2.3.0, GNU stow-managed dotfiles.

## Global Constraints

- Plugin pin is exactly `catppuccin/tmux#v2.3.0` — never unpinned.
- Flavor: `mocha`. Window style: `rounded`.
- Bar contents: window pills, session, date/time (`%Y-%m-%d %H:%M` default), prefix indicator via session pill color. Nothing else — no battery/cpu/hostname/git.
- The two-row status (`status 2`, `fill=terminal` spacer at `status-format[0]`) must survive.
- All edits go to `tmux/.tmux.conf` in the repo; the live file `~/.tmux.conf` is the stow symlink to it.
- Spec: `docs/superpowers/specs/2026-08-08-tmux-catppuccin-status-bar-design.md`.

---

### Task 1: TPM bootstrap and plugin loading

**Files:**
- Modify: `tmux/.tmux.conf` (append at end of file)

**Interfaces:**
- Produces: `~/.tmux/plugins/tpm` and `~/.tmux/plugins/tmux` (catppuccin clones under its repo name, `tmux`) installed and loaded; `run '~/.tmux/plugins/tpm/tpm'` as the plugin-load line that Task 3 will place the spacer after.

- [ ] **Step 1: Confirm the live config is the repo file**

Run: `readlink ~/.tmux.conf`
Expected: a path into `kernvex/dotfiles/tmux/` (stow symlink). If it is not a symlink into the repo, STOP and report — editing the repo file would otherwise change nothing.

- [ ] **Step 2: Append the plugins section**

Append to the end of `tmux/.tmux.conf`:

```tmux

# ---------------------------------------------------------------------------
# Plugins (TPM)
# ---------------------------------------------------------------------------
# TPM self-bootstraps so a fresh machine gets the theme on first launch
# instead of a broken bar and a manual clone step. `install_plugins` runs in
# the same breath so that first launch is also fully themed, not
# themed-after-remembering-prefix-I.
if "test ! -d ~/.tmux/plugins/tpm" \
   "run 'git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm && ~/.tmux/plugins/tpm/bin/install_plugins'"

set -g @plugin 'tmux-plugins/tpm'
# Pinned: catppuccin rewrote its whole options API between v0.x and v2, so an
# upstream change should be an explicit upgrade here, never a surprise on the
# next machine that clones this repo.
set -g @plugin 'catppuccin/tmux#v2.3.0'

# TPM wants to be the last line of the file. The spacer block below is the
# one deliberate exception: it must run after the theme has loaded.
run '~/.tmux/plugins/tpm/tpm'
```

- [ ] **Step 3: Load it into the running server**

Run: `tmux source-file ~/.tmux.conf`
Expected: no output, no error. First run takes a few seconds (two git clones).

- [ ] **Step 4: Verify both plugins are installed**

Run: `test -d ~/.tmux/plugins/tpm && test -d ~/.tmux/plugins/tmux && echo ok`
Expected: `ok`

Run: `git -C ~/.tmux/plugins/tmux describe --tags`
Expected: `v2.3.0`

- [ ] **Step 5: Commit**

```bash
git add tmux/.tmux.conf
git commit -m "feat(tmux): bootstrap TPM and load catppuccin pinned to v2.3.0"
```

---

### Task 2: Mocha theme, status modules, prefix indicator

**Files:**
- Modify: `tmux/.tmux.conf` (remove old status-style line; add options above the `set -g @plugin 'tmux-plugins/tpm'` line)

**Interfaces:**
- Consumes: plugin loading from Task 1 (`#{E:@catppuccin_status_*}` options exist once the plugin has run).
- Produces: final `status-right` composition; the retired `status-style` line no longer exists for later tasks to trip on.

- [ ] **Step 1: Remove the old hand-styled bar**

In `tmux/.tmux.conf`, delete this line (currently directly below `bind r source-file ~/.tmux.conf`):

```tmux
set -g status-style 'bg=#333333 fg=#5eacd3'
```

- [ ] **Step 2: Add theme options and bar composition**

Insert immediately BEFORE the `set -g @plugin 'tmux-plugins/tpm'` line:

```tmux
set -g @catppuccin_flavor 'mocha'
set -g @catppuccin_window_status_style 'rounded'

# Window pills start at the left edge; everything informational lives on the
# right. `#{E:...}` expands at render time, so these can be set before TPM
# actually loads the plugin.
set -g status-left-length 100
set -g status-right-length 100
set -g status-left ""
set -g status-right "#{E:@catppuccin_status_session}"
set -ag status-right "#{E:@catppuccin_status_date_time}"
```

- [ ] **Step 3: Reload and verify options landed**

Run: `tmux source-file ~/.tmux.conf && tmux show -gv @catppuccin_flavor && tmux show -gv status-right`
Expected: `mocha`, then a string containing both `@catppuccin_status_session` and `@catppuccin_status_date_time`.

- [ ] **Step 4: Verify the prefix indicator is built in**

Run: `tmux show -gv @catppuccin_status_session | grep -c client_prefix || tmux show -gv @catppuccin_session_color | grep -c client_prefix`
Expected: `1` (v2's session module flips color on `client_prefix` by default).

ONLY IF the count is `0`: add this line directly after `set -g @catppuccin_window_status_style 'rounded'`, then reload and re-run the check:

```tmux
set -g @catppuccin_session_color "#{?client_prefix,#{E:@thm_red},#{E:@thm_green}}"
```

- [ ] **Step 5: Human visual check**

Ask the human partner to look at the bar: mocha rounded window pills on the left, session pill + `YYYY-MM-DD HH:MM` pill on the right, and the session pill changing color while the prefix is held.

- [ ] **Step 6: Commit**

```bash
git add tmux/.tmux.conf
git commit -m "feat(tmux): catppuccin mocha bar with session, date/time, prefix flip"
```

---

### Task 3: Re-plumb the spacer row after TPM

**Files:**
- Modify: `tmux/.tmux.conf` (move two-line spacer block from mid-file to after the `run '~/.tmux/plugins/tpm/tpm'` line)

**Interfaces:**
- Consumes: `run '~/.tmux/plugins/tpm/tpm'` line position from Task 1.
- Produces: final file layout — spacer block is the last thing in the file.

- [ ] **Step 1: Move the spacer block**

Cut these two lines (and the comment block above them that begins `# A breathing row between the pane and the status bar`) from their current mid-file position:

```tmux
set -g status 2
run-shell 'tmux set -gu status-format ; tmux set -g "status-format[1]" "$(tmux show -gv "status-format[0]")" ; tmux set -g "status-format[0]" "#[fill=terminal]"'
```

Paste them (comment included) at the very end of the file, AFTER `run '~/.tmux/plugins/tpm/tpm'`. Append to the existing comment block:

```tmux
# Lives after TPM on purpose: the copied row [1] is tmux's *default* bar
# format, which pulls status-left/right and window-status-* by option name,
# so catppuccin's styling flows into it — but only if nothing re-themes the
# bar after the copy is taken.
```

- [ ] **Step 2: Reload and verify the two-row arrangement survived**

Run: `tmux source-file ~/.tmux.conf && tmux display -p '#{status}' && tmux show -gv 'status-format[0]'`
Expected: `2`, then `#[fill=terminal]`.

- [ ] **Step 3: Human visual check**

Ask the human partner to confirm: transparent breathing row between pane and bar (WezTerm glass shows through), themed bar below it.

- [ ] **Step 4: Commit**

```bash
git add tmux/.tmux.conf
git commit -m "refactor(tmux): run the spacer-row plumbing after the theme loads"
```

---

### Task 4: Fresh-machine bootstrap proof

**Files:**
- None modified. Pure verification of the Task 1 bootstrap path, isolated from the running server.

**Interfaces:**
- Consumes: the complete `tmux/.tmux.conf` from Tasks 1-3.

- [ ] **Step 1: Simulate a machine with no TPM**

Do NOT kill the real server. Use a scratch HOME and a separate socket:

```bash
scratch=$(mktemp -d)
cp ~/kernvex/dotfiles/tmux/.tmux.conf "$scratch/.tmux.conf"
env HOME="$scratch" tmux -L cattest -f "$scratch/.tmux.conf" new-session -d -s boottest
sleep 20   # two git clones on first launch
env HOME="$scratch" tmux -L cattest show -gv @catppuccin_flavor
```

Expected: `mocha` — proving bootstrap cloned TPM, installed the pinned catppuccin, and loaded it from nothing.

- [ ] **Step 2: Tear down the scratch server**

```bash
env HOME="$scratch" tmux -L cattest kill-server
rm -rf "$scratch"
```

- [ ] **Step 3: Report**

No commit (nothing changed). Report bootstrap result to the human partner.
