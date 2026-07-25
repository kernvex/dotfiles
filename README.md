# dotfiles

Personal macOS dotfiles (fish + WezTerm + tmux + Neovim). Managed with [GNU stow](https://www.gnu.org/software/stow/),
self-installing, and portable — clone anywhere and run `./install`.

## Install

```bash
git clone git@github.com:kernvex/dotfiles.git ~/kernvex/dotfiles
cd ~/kernvex/dotfiles
./install
```

`./install` inits the submodules (Neovim config, tmux-sessionizer) and stows each package into
`$HOME` with `stow --no-folding` (target directories stay real — nothing folds back into this repo).
Any real file already at a target is moved aside to `*.bak.<timestamp>` first.

Requires `stow` (`brew install stow`). The wider machine bootstrap — Homebrew, runtimes, fonts
(including `font-vazirmatn` for the WezTerm Persian fallback), secrets — lives in a separate
`esetup` installer, which calls this repo's `./install`.

## Layout

**Stow packages** (symlinked into `$HOME`):

| package | target |
|---|---|
| `fish` | `~/.config/fish` |
| `starship` | `~/.config/starship.toml` |
| `wezterm` | `~/.config/wezterm` |
| `tmux` | `~/.tmux.conf`, `~/.tmux-cht-*` |
| `tmux-sessionizer-config` | `~/.config/tmux-sessionizer` |
| `bin` | `~/.local/bin` (scripts + the tmux-sessionizer symlink) |
| `atuin` | `~/.config/atuin` |
| `git` | `~/.gitconfig` |
| `htop` | `~/.config/htop` |
| `lazygit` | `~/.config/lazygit/config.yml` (line-by-line staging default, undoing the v0.54 hunk-mode switch) |
| `nvim` | `~/.config/nvim` (submodule → `kernvex/kickstart.nvim`) |
| `swiftbar` | `~/.config/swiftbar/plugins` (CPU/RAM menu-bar plugin, via SwiftBar) |
| `claude` | `~/.claude/statusline-pace.py` (symlink); `settings.json` is **copied** by `install`, not stowed — see `claude/README.md` |
| `obsidian` | **copied** by `install` into each vault's `.obsidian/` (one subdir per vault: `habits/`, `lingo/` — config + pinned plugins), not stowed — see `obsidian/README.md`. Pairs with the `obsidian-habit-tracker` / `obsidian-lingo` esetup submodules. |
| `ssh` | `~/.ssh/config` (personal github.com default; **no** private keys — company keys route per-folder via git `includeIf`) |

**Submodules**

- `nvim/.config/nvim` → `kernvex/kickstart.nvim`
- `tmux-sessionizer` → `kernvex/tmux-sessionizer` (the tool; `bin/` links to it)

A clone made before the `6eniu5` → `kernvex` rename still fetches the old URLs
until you run `git submodule sync --recursive` — see
[`docs/notes/submodule-url-sync.md`](docs/notes/submodule-url-sync.md).

**Artifact areas** (not stowed — applied by esetup, or by hand):

- `keyboard/` — Advantage360 SmartSet config (`reg.xml`, `layout2.txt`, `led2.txt`)
- `raycast/` — Raycast export instructions
- `macos/` — system `defaults` (key repeat), applied imperatively by `install` via
  `macos/defaults.sh`. Not stowed: cfprefsd rewrites these plists in place and detaches
  symlinks, same as `claude/settings.json`. See
  [`docs/adr/0002-key-repeat-threshold-over-slider-minimum.md`](docs/adr/0002-key-repeat-threshold-over-slider-minimum.md).

## tmux + Claude Code

`tmux/.tmux.conf` carries a few settings that exist specifically because Claude Code (and
any other full-screen TUI) lives in these panes. Reload with `prefix r` after changing it;
already-running Claude processes need a restart to pick up the environment.

| Setting / binding | Why |
|---|---|
| `set-environment -g CLAUDE_CODE_TMUX_TRUECOLOR 1` | Claude clamps itself to 256 colours whenever `$TMUX` is set, which renders its orange (`#d97757`) as pink (colour 174). This opts out. |
| `set -g focus-events on` | Claude tracks focus to pause its spinner when you are in another pane. |
| `set -g mouse on` | Claude renders inline on the normal screen, so without it the wheel does nothing. Drag-select is piped to `pbcopy`; hold Option in WezTerm for a native selection. |
| `set -g history-limit 50000` | One AI turn can exceed the 2000-line default scrollback. |
| `bind -n C-f` (root table) | A fish binding only fires at a fish prompt. Root-table means tmux intercepts Ctrl-f ahead of the TUI, so the sessionizer jump works from inside Claude. vim/`less`/`man`/`fzf` still get it passed through. |
| `bind F` → `tmux-session-here` | Second/third session for the *same* directory (`dotfiles-review`, `dotfiles-2`), for running more than one Claude conversation on one repo. Siblings show up in the Ctrl-f picker as `[TMUX] …`. |
| `bind A` → `<project>-ask` | The common case of the above: a `claude --permission-mode plan` sidecar. Read-only, so you can ask it something while another agent is mid-edit without racing it or breaking its flow. One per project — press again to return to it. |

Rationale in [`docs/adr/0004-tmux-tuned-for-claude-code.md`](docs/adr/0004-tmux-tuned-for-claude-code.md).
