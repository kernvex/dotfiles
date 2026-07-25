# Rust tools at the prompt, coreutils in the scripts

`setup.sh` installs `eza`, `bat`, `ripgrep`, `fd` and `zoxide` on every machine, and
`config.fish` aliases `ls`, `cat`, `grep`, `egrep` and `fgrep` onto them and points fzf's
walker at `fd`. The obvious next step is to finish the job — convert the shell scripts too,
starting with the tmux ones. That conversion was proposed, surveyed, measured, and rejected.

**There is almost nothing to convert.** Across `tmux/.tmux.conf`, `tmux-cht.sh`,
`tmux-windowizer` and the sessionizer, the entire coreutils surface is: one `find` (the
sessionizer's directory walk), six `grep`s, one `cut`, and one `cat`. There is no `ls`, no
`sed`, no `du` and no `cd` anywhere in them, so `eza`, `sd`, `dust` and `zoxide` have zero
call sites between them. `sd` and `dust` are not installed and are not in `setup.sh`'s brew
list either — the deliberate choice there was `gnu-sed`.

**`fd` is slower here, and lossy by default.** Warm cache, five runs, over the real search
paths (`~/:2`, `~/Documents/Projects:2`, `~/.config:2`, `~/Documents/Learning:1`):

| walker | time | directories found |
| --- | --- | --- |
| `find` (current) | ~15ms | 563 |
| `fd` at parity flags | ~30ms | 563 |
| `fd` at defaults | — | 318 |

The ~15ms gap held across two separate timing harnesses. The reason is workload shape: this
walk is shallow and wide — 563 directories, max depth 2 — so `fd`'s thread-pool spin-up and
larger startup cost dominate, with nothing deep enough for parallelism to earn them back.
`fd` wins on deep recursive walks of large trees, which is the opposite of a sessionizer's
top-of-tree scan.

The count is the more serious column. `fd` honours `.gitignore`/`.ignore` and skips hidden
entries by default, so out of the box it drops 245 of 563 session candidates — 44% — silently.
Reaching parity needs `--hidden --no-ignore --exclude .git --max-depth N --absolute-path .`,
which is the existing `find` line rewritten longer in a tool that is not a `find` replacement.
The sessionizer specifically *must* see hidden and ignored directories: `~/.config` is itself
hidden, and it is a search path on purpose.

**The remaining call sites are not worth converting.** The six `grep`s filter fewer than fifty
lines of `tmux list-sessions`/`list-panes` output and a small pane-cache file, where `rg`'s
startup exceeds any scanning win. `tmux-cht.sh`'s `cat` is piped straight into fzf, and `bat`
auto-strips decorations when piped — a second process for identical bytes.

**Decision:** the rust tools live at the interactive layer — aliases, fzf integration,
`MANPAGER` — and scripts call the coreutils directly. `config.fish` already states this at the
alias block (`command cat`/`command ls`/`command grep` for the originals, plus the explicit
note that `fd` is not a POSIX `find` replacement); this ADR is the reasoning behind it.
Reverse it only against a measurement on the actual workload, not on the tools' reputations.

**Consequence:** the split is enforced by nothing. Fish aliases never reached these scripts in
the first place — they are `#!/usr/bin/env bash`, so `grep` there has always been `grep(1)`
regardless of what fish does at a prompt. Anyone converting a script must therefore do it
deliberately, which is exactly the moment this ADR is meant to be read.

**Also from this investigation:** the sessionizer's walk had no stderr redirect, so macOS TCC
denials on protected directories (`find: /Users/…/.Trash: Operation not permitted`) rendered
inside the `display-popup` that `tmux.conf` launches the picker in. Fixed with `2>/dev/null`,
matching the same function's existing treatment of `tmux list-sessions` noise two lines above.
The `[[ -d "$path" ]]` guard means the only errors this can hide are unreadable subtrees, which
are never actionable for a directory picker.
