# tmux Session Persistence (resurrect + continuum) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tmux sessions survive a reboot or server kill — autosaved every 15 minutes by tmux-continuum and auto-restored when the server next starts, with tmux-resurrect providing the save/restore machinery.

**Architecture:** Two new TPM plugins added to the existing pinned-plugin setup in `tmux/.tmux.conf`. Options ride with the existing theme options; plugin lines join the existing `@plugin` list with continuum last; the spacer block stays untouched after the TPM run line. Continuum's autosave hook rides `status-right`, which the spacer's copied default bar format pulls by option name at render time — so the hook fires through our custom two-row bar.

**Tech Stack:** tmux 3.7b, TPM, tmux-resurrect v4.0.0, tmux-continuum v3.1.0, GNU stow (`~/.tmux.conf` is a symlink into this repo).

**Spec:** `docs/superpowers/specs/2026-08-09-tmux-session-persistence-design.md`

## Global Constraints

- **NEVER kill, restart, or `kill-server` the user's live tmux server** (the default socket). Destructive steps run ONLY on an isolated socket (`tmux -L persisttest`). Any `kill-server` in this plan MUST carry `-L persisttest`. `tmux source-file` on the live server is allowed and safe.
- Pins are verified by **commit hash equality against the upstream peeled tag**, never by `git describe --tags` (tags in a local clone can lie; the previous plan's ambiguity here caused a mess). Expected hashes: resurrect `v4.0.0` = `e87d7d592cac97fa38c12395ebec042c154a1844`, continuum `v3.1.0` = `46e0e0023476018ddb4cc0d44783eede27e5a8ec`.
- Continuum must be the **last `@plugin` line**: on load it plants `#(continuum_save.sh)` in `status-right`, and any plugin that rewrites the bar after it silently disarms the autosave.
- The spacer block (the `set -g status 2` + `run-shell` lines at the end of `tmux/.tmux.conf`) stays byte-identical and stays after the `run '~/.tmux/plugins/tpm/tpm'` line.
- All other resurrect/continuum behavior stays default: 15-minute interval, default process relaunch list, no `@resurrect-processes`, no nvim strategy, no `@continuum-boot`.
- **Concurrent-edit guard:** the user works in this repo in parallel. Before `git add`, run `git diff` and confirm the diff contains ONLY the hunks this plan specifies. If foreign hunks are present, do not stage them — report BLOCKED with the diff.
- resurrect v4.0.0 stores state in `~/.tmux/resurrect/` if that directory already exists, otherwise in `${XDG_DATA_HOME:-~/.local/share}/tmux/resurrect/`. Every check for state files must look in **both** locations.
- The shell running these commands is fish. Quote any ref containing `^{}` (e.g. `"refs/tags/v4.0.0^{}"`) — unquoted braces are expanded by fish and the match silently fails.

---

### Task 1: Wire resurrect + continuum into .tmux.conf and verify on the live server

**Files:**
- Modify: `tmux/.tmux.conf` (two edits: options block near line 220, plugin lines near line 226)

**Interfaces:**
- Consumes: existing TPM bootstrap + `run '~/.tmux/plugins/tpm/tpm'` line; existing catppuccin `status-right` modules.
- Produces: `~/.tmux/plugins/tmux-resurrect/` and `~/.tmux/plugins/tmux-continuum/` at the pinned commits; `status-right` carrying the `continuum_save.sh` interpolation. Task 2 relies on the committed conf bootstrapping both plugins from nothing.

- [ ] **Step 1: Insert the options block**

In `tmux/.tmux.conf`, find:

```tmux
set -g status-right "#{E:@catppuccin_status_session}"
set -ag status-right "#{E:@catppuccin_status_date_time}"

set -g @plugin 'tmux-plugins/tpm'
```

and insert between the `status-right` lines and the `@plugin` line:

```tmux
# Sessions survive a reboot: resurrect saves sessions/windows/layouts/cwds,
# continuum re-saves every 15 minutes and restores when the server next
# starts. Pane text comes back as static content — orientation, not live
# programs. Deliberately default everywhere else: no custom process list
# (a relaunched `claude` would start a NEW conversation; `claude --continue`
# in the restored cwd is the deliberate way back), no nvim session strategy.
set -g @resurrect-capture-pane-contents 'on'
set -g @continuum-restore 'on'
```

- [ ] **Step 2: Add the plugin lines**

Find:

```tmux
set -g @plugin 'catppuccin/tmux#v2.3.0'

# TPM wants to be the last line of the file. The spacer block below is the
```

and make it:

```tmux
set -g @plugin 'catppuccin/tmux#v2.3.0'
set -g @plugin 'tmux-plugins/tmux-resurrect#v4.0.0'
# Continuum stays LAST in this list: on load it plants its autosave hook
# (#(continuum_save.sh)) inside status-right, and anything that rewrites the
# bar after it disarms the autosave silently.
set -g @plugin 'tmux-plugins/tmux-continuum#v3.1.0'

# TPM wants to be the last line of the file. The spacer block below is the
```

Touch nothing else. The spacer block at the end of the file stays byte-identical.

- [ ] **Step 3: Install the new plugins and load them on the live server**

```bash
tmux source-file ~/.tmux.conf
~/.tmux/plugins/tpm/bin/install_plugins
tmux source-file ~/.tmux.conf
```

Expected: `install_plugins` reports both `tmux-resurrect` and `tmux-continuum` installed; no errors from either `source-file`. (Sourcing the live server's config is safe and idempotent — proven for this file in the previous plan.)

- [ ] **Step 4: Verify the pins by commit hash**

```bash
git -C ~/.tmux/plugins/tmux-resurrect rev-parse HEAD
git ls-remote https://github.com/tmux-plugins/tmux-resurrect "refs/tags/v4.0.0^{}"
git -C ~/.tmux/plugins/tmux-continuum rev-parse HEAD
git ls-remote https://github.com/tmux-plugins/tmux-continuum "refs/tags/v3.1.0^{}"
```

Expected: resurrect HEAD = `e87d7d592cac97fa38c12395ebec042c154a1844` = the ls-remote hash; continuum HEAD = `46e0e0023476018ddb4cc0d44783eede27e5a8ec` = the ls-remote hash. Hash equality is the verdict; do NOT use `git describe`.

- [ ] **Step 5: Verify the autosave hook survived our custom bar**

```bash
tmux show -gv status-right
tmux show -gv @catppuccin_flavor
tmux show -gv status
tmux show -gv 'status-format[0]'
```

Expected: `status-right` contains BOTH `continuum_save.sh` (inside a `#(...)` interpolation) AND the two catppuccin module references (`@catppuccin_status_session`, `@catppuccin_status_date_time`); flavor is `mocha`; `status` is `2`; `status-format[0]` is `#[fill=terminal]`. If `continuum_save.sh` is absent, the hook was clobbered — report BLOCKED, do not commit.

- [ ] **Step 6: Prove a save writes state (non-destructive, live server)**

```bash
~/.tmux/plugins/tmux-resurrect/scripts/save.sh
ls -la ~/.tmux/resurrect/ 2>/dev/null; ls -la ~/.local/share/tmux/resurrect/ 2>/dev/null
```

Expected: `save.sh` exits 0; exactly one of the two directories exists and contains a dated `tmux_resurrect_*.txt` plus a `last` symlink to it; the file is non-empty and contains `window` and `pane` lines for the live sessions. This only reads server state and writes a file — it does not touch the server.

- [ ] **Step 7: Commit (with concurrent-edit guard)**

```bash
git -C ~/kernvex/dotfiles diff
```

Confirm the diff is ONLY the two hunks from Steps 1–2. If anything else appears, report BLOCKED with the diff. Then:

```bash
git -C ~/kernvex/dotfiles add tmux/.tmux.conf
git -C ~/kernvex/dotfiles commit -m "feat(tmux): sessions survive reboots via resurrect + continuum

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Prove the kill → auto-restore round trip on an isolated server

**Files:**
- None created or modified. This task produces a verification report only; the working tree must be clean before and after.

**Interfaces:**
- Consumes: the committed `tmux/.tmux.conf` from Task 1 (including its TPM self-bootstrap block).
- Produces: proof that `@continuum-restore` works end to end from a cold bootstrap.

**Safety:** every tmux command in this task carries `-L persisttest`. The bare `kill-server` variant is forbidden — it would destroy the user's live sessions.

- [ ] **Step 1: Bootstrap a scratch server from the committed conf**

```bash
SCRATCH=$(mktemp -d)
mkdir -p "$SCRATCH/projA" "$SCRATCH/projB"
cp ~/kernvex/dotfiles/tmux/.tmux.conf "$SCRATCH/.tmux.conf"
env HOME="$SCRATCH" tmux -L persisttest -f "$SCRATCH/.tmux.conf" new-session -d -s alpha -c "$SCRATCH"
```

Then poll (up to ~90s) until the bootstrap clone finishes:

```bash
until [ -d "$SCRATCH/.tmux/plugins/tmux-continuum" ]; do sleep 3; done
tmux -L persisttest source-file "$SCRATCH/.tmux.conf"
tmux -L persisttest show -gv status-right
```

Expected: all three plugin dirs appear under `$SCRATCH/.tmux/plugins/`; after the re-source, `status-right` contains `continuum_save.sh`.

- [ ] **Step 2: Shape distinctive state to restore**

```bash
tmux -L persisttest rename-window -t alpha:1 editor
tmux -L persisttest new-window -t alpha -c "$SCRATCH/projA" -n worker
tmux -L persisttest new-session -d -s beta -c "$SCRATCH/projB"
tmux -L persisttest ls
```

Expected: `alpha` with 2 windows (`editor`, `worker`), `beta` with 1.

- [ ] **Step 3: Save from inside the scratch server**

Run the save inside a scratch pane so the script inherits the scratch server's `$TMUX` and `$HOME` (running it from this shell would target the LIVE server):

```bash
tmux -L persisttest send-keys -t alpha:editor "~/.tmux/plugins/tmux-resurrect/scripts/save.sh; echo SAVED_RC=\$?" Enter
sleep 3
tmux -L persisttest capture-pane -p -t alpha:editor | tail -3
ls "$SCRATCH/.tmux/resurrect/" 2>/dev/null; ls "$SCRATCH/.local/share/tmux/resurrect/" 2>/dev/null
```

Expected: `SAVED_RC=0` in the pane; a `tmux_resurrect_*.txt` + `last` in one of the two scratch locations (NOT in the real `~`).

- [ ] **Step 4: Kill the scratch server and restart it**

```bash
tmux -L persisttest kill-server
env HOME="$SCRATCH" tmux -L persisttest -f "$SCRATCH/.tmux.conf" new-session -d -s probe -c /tmp
```

(`-L persisttest` on the kill is the entire safety story — check it twice.) Continuum's auto-restore fires as the plugins load on the fresh server. Poll (up to ~30s):

```bash
until tmux -L persisttest ls 2>/dev/null | grep -q "^beta:"; do sleep 2; done
tmux -L persisttest ls
```

Expected: `alpha` and `beta` are back alongside `probe`.

- [ ] **Step 5: Verify restored shape**

```bash
tmux -L persisttest list-windows -t alpha -F '#{window_name}'
tmux -L persisttest display -p -t alpha:worker '#{pane_current_path}'
tmux -L persisttest display -p -t beta '#{pane_current_path}'
```

Expected: alpha's windows are `editor` and `worker`; `worker`'s cwd is `$SCRATCH/projA` (possibly with a `/private` prefix on macOS); beta's cwd is `$SCRATCH/projB` likewise.

- [ ] **Step 6: Tear down and confirm the live server was never touched**

```bash
tmux -L persisttest kill-server
rm -rf "$SCRATCH"
tmux ls
git -C ~/kernvex/dotfiles status --porcelain
```

Expected: the plain `tmux ls` still lists the user's live sessions, unchanged; the working tree is clean. Report the full evidence chain — no commit in this task.
