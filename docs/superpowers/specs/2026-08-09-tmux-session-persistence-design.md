# tmux session persistence: resurrect + continuum

**Date:** 2026-08-09
**Status:** Approved

## Problem

A reboot or a killed tmux server erases every session — all the long-lived
named sessionizer projects — and they have to be rebuilt by hand. The setup
needs sessions to survive a server restart without anyone remembering to
save first.

## Decision

Install both `tmux-plugins/tmux-resurrect` and `tmux-plugins/tmux-continuum`
via the existing TPM setup. Continuum is a layer over resurrect, not an
alternative: resurrect provides save/restore, continuum automates it
(autosave every 15 minutes, auto-restore on server start).

Considered and rejected: resurrect alone (a restore is only as fresh as the
last manual save, and an unplanned reboot is exactly when nobody saved).

## What gets restored

- **Always (resurrect core):** sessions, window names and order, pane
  layouts, each pane's working directory.
- **Pane text** (`@resurrect-capture-pane-contents 'on'`): panes come back
  showing the text they held, as static content — orientation, not live
  programs.
- **Programs:** resurrect's default relaunch list only (vim/nvim, less, man,
  tail, top, htop, ...). No custom `@resurrect-processes`. Notably `claude`
  is *not* relaunched: a bare restart would begin a new conversation anyway;
  `claude --continue` in the restored pane's cwd is the deliberate way back.
- **No nvim session strategy.** Relaunched nvim starts fresh; restoring
  buffers needs a `Session.vim` workflow (vim-obsession) that kickstart does
  not have. Revisit only if the pain shows up.

## Configuration

Options live with the other theme/plugin options, before the `@plugin`
lines:

```tmux
set -g @resurrect-capture-pane-contents 'on'
set -g @continuum-restore 'on'
```

Plugin lines, pinned to release tags like catppuccin (exact tags resolved
against upstream at implementation time, verified by commit hash, not by
`git describe`):

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect#<tag>'
set -g @plugin 'tmux-plugins/tmux-continuum#<tag>'
```

Everything else stays default:

- Autosave interval: 15 minutes (default).
- No `@continuum-boot`: WezTerm is launched by hand, and continuum's boot
  option does not support WezTerm.
- Manual keys come free and stay default: `prefix + Ctrl-s` save,
  `prefix + Ctrl-r` restore. Both are unbound in the current prefix table —
  no conflicts.

## Ordering constraints

1. **Continuum is the last `@plugin` line.** On load it plants a
   `#(continuum_save.sh)` interpolation in `status-right`; any plugin or
   theme that rewrites the bar after it silently disarms the autosave.
2. **The spacer block stays after the TPM run line**, unchanged. The spacer
   copies tmux's *default* bar format into `status-format[1]`, and that
   default pulls `status-right` by option name at render time — so
   continuum's hook flows through the copied row and fires on each status
   refresh. This is the one real integration risk and is verified
   explicitly, never assumed.

## Verification

The live tmux server is never killed or restarted. Two proof tiers:

- **Live server (non-destructive):** after re-sourcing, `tmux show -gv
  status-right` contains `continuum_save`; a manual `prefix + Ctrl-s`
  drops a state file in `~/.tmux/resurrect/`; `~/.tmux/plugins/` contains
  both plugins at the pinned commits.
- **Scratch server (destructive round-trip):** on an isolated socket
  (`tmux -L`), with a scratch `$HOME` as in the catppuccin bootstrap proof:
  create throwaway sessions and windows, save, kill that server, restart
  it, and confirm the sessions come back with names, layouts, and cwds
  intact — proving `@continuum-restore` end to end.

> **Amendment (2026-08-10).** Continuum arms its autosave hook and startup
> auto-restore only on the first tmux server on the machine (ps-based,
> machine-wide detection), so the scratch server — always the second
> server while the live one runs — can never observe the auto-fire. The
> scratch tier therefore proves the save → kill → restore machinery by
> invoking resurrect's `scripts/restore.sh` directly; continuum's
> auto-trigger is vouched by source reading plus the armed, firing hook on
> the live server, and first executes for real at the next reboot.

## Out of scope

- `@continuum-boot` / autostart at login
- Custom `@resurrect-processes` entries (including `claude`)
- nvim session restore via vim-obsession
- Changing the autosave interval
