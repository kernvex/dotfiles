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
(including `font-dejavu` for the WezTerm Persian fallback), secrets — lives in a separate
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
| `claude` | `~/.claude/statusline-pace.py`, `CLAUDE.md`, `templates/` (symlinks); `settings.json` is **copied** by `install`, not stowed — see `claude/README.md` |
| `obsidian` | **copied** by `install` into each vault's `.obsidian/` (one subdir per vault: `habits/`, `lingo/` — config + pinned plugins), not stowed — see `obsidian/README.md`. Pairs with the `obsidian-habit-tracker` / `obsidian-lingo` esetup submodules. |
| `ssh` | `~/.ssh/config` (personal github.com default; **no** private keys — company keys route per-folder via git `includeIf`) |
| `hammerspoon` | `~/.hammerspoon` (the window-slot engine `Hyper+<digit>` calls into — see ADR 0009). The slot table itself is `~/.hammerspoon/slot-table.lua`, machine-local and **never committed**: it names real accounts. `slot-table.example.lua` documents the format; you write the real one by pinning, not by hand. |

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

## Teaching workspaces (`teach`)

Lessons and reference docs under `~/Documents/Learning/*` toggle fullscreen on `f`.
The `teach` skill is a fork tracking upstream, so none of this lives in the skill:
the behaviour is a component the skill already knows how to pick up.

| Piece | Role |
|---|---|
| `claude/.claude/templates/teach/fullscreen.js` | The component, and the single source of truth. Self-contained — one `<script>` tag is the whole integration. |
| `claude/.claude/CLAUDE.md` | Global rule that seeds the component into any workspace missing it, so new workspaces get `f` unassisted. |
| `bin/.local/bin/teach-fullscreen` | Installs the component and links it from every `lessons/*.html` and `reference/*.html`. |

Edit the template, never the copies, then re-run `teach-fullscreen --apply` to
propagate. The script is idempotent and doubles as drift repair; it prints a plan and
changes nothing without `--apply`, because these workspaces are not under git.

Rationale in [`docs/adr/0005-teach-lessons-go-fullscreen-without-forking-the-skill.md`](docs/adr/0005-teach-lessons-go-fullscreen-without-forking-the-skill.md).

## Claude global rules

`claude/.claude/CLAUDE.md` → `~/.claude/CLAUDE.md` is read at the start of every
Claude Code session, in every project. It currently carries three rules.

| Section | Rule |
|---|---|
| Teaching workspaces | Lessons and reference pages load `assets/fullscreen.js` (see above) |
| Arabic-script text in HTML | Any page containing U+0600–U+06FF uses `"Vazirmatn", "Geeza Pro", system-ui, sans-serif`, with the font self-hosted beside the page. Never a CDN, never Roboto |
| Text I will send as myself | Drafts meant to be sent onward (email, messages, posts) avoid em-dashes and the other tells that mark text as machine-written |

Keep this file short. It is a standing cost on every session, including the many
where none of it applies, and a long one dilutes everything in it.

### Turning a rule off

Each rule is one `##` section, and nothing outside the file depends on any of them —
no script reads it, no build step enforces it. **Delete the section** and the rule
stops applying to future work. Changes take effect in the next session, not the
running one.

Two of the three leave artifacts behind, which the deletion does not touch:

- **Fullscreen** — pages keep their `<script>` tag and keep working. To unwind
  properly, remove the tag and `assets/fullscreen.js` from each workspace, then
  delete `claude/.claude/templates/teach/` and `bin/.local/bin/teach-fullscreen` and
  re-run `./install`.
- **Arabic-script font** — pages keep their `@font-face` blocks and bundled
  `assets/fonts/*.woff2`. To unwind, delete both and leave the `font-family` stack
  alone: Vazirmatn is installed system-wide, so pages still render correctly *here*
  while quietly losing portability. See the reversal note in
  [`docs/adr/0006-persian-html-ships-its-own-font.md`](docs/adr/0006-persian-html-ships-its-own-font.md).
- **AI tells** — nothing to clean up. It only ever shaped text that was not yet
  written.

To suspend a rule for one session without editing anything, say so at the top of the
conversation; a direct instruction outranks `CLAUDE.md`.
