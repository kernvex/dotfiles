# claude

Claude Code config worth version-controlling. Two files, handled differently
because Claude Code writes one of them and not the other.

| file | how it reaches `~/.claude` | why |
|---|---|---|
| `.claude/statusline-pace.py` | **symlink** (stowed) | Your script; Claude never writes it, so a live symlink is safe and bidirectional |
| `.claude/settings.json` | **copy** (by `./install`) | Claude *atomically rewrites* it — see below |

`statusline-pace.py` renders the status line: context window + plan burn-rate,
plus a `cpu N% ram N%` segment from the shared `~/.local/bin/sysusage` script
(the same reading the Starship prompt and the SwiftBar menu bar show).

## Why settings.json is copied, not symlinked

Claude Code writes `~/.claude/settings.json` with a temp-file + rename (atomic
replace) on `/model`, `/config`, enabling a plugin, etc. A rename-over-path
**replaces a stow symlink with a fresh regular file**, silently detaching it from
this repo. Symlinked settings also trip permission-recognition failures and slow
startups (anthropics/claude-code#3575, #40857 — Claude even ships a *"Broken
symlink … for settings.json"* error). So `settings.json` is **copied** in by
`./install`, not stowed. The `.stow-local-ignore` here keeps stow from linking it.

`./install` treats the repo as the source of truth: on install it backs up any
*differing* live `settings.json` to `settings.json.bak.<ts>`, then copies the
repo's version in.

## Syncing changes back

Because the copy flows repo → machine, changing a setting at runtime (a `/model`
switch, a newly-enabled plugin) leaves the repo stale. Pull it back with:

```bash
claude-settings-sync    # copies ~/.claude/settings.json → this repo, shows the diff
```

then review and `git commit`. (`claude-settings-sync` lives in the `bin` package.)

## Work seats (`work-seat/`)

`~/.claude` is the **personal** seat. Every client identity gets its own at
`~/.claude-<slug>`, because the config dir is part of the address of the login —
the Keychain item is namespaced by that path, so a seat is not a setting but a
separate installation.

A seat created by `claude auth login` starts almost empty: no status line, no
plugins, no `CLAUDE.md`. `work-seat/` is the template that fixes that, and
`identity apply` seeds it into every seat directory it creates.

| entry | kind | why |
|---|---|---|
| `settings.json` | file | The work profile: status line, model, and the `disable*` flags that keep a client seat off connectors, remote control and workflows |
| `CLAUDE.md` | relative symlink | Global instructions apply to client work too — one file, not a copy that drifts |
| `plugins` | relative symlink | Plugin installs are large and identical per seat; sharing them avoids re-downloading a marketplace per client |

The two symlinks are **relative** (`../.claude/x`) deliberately. Inside
`~/.claude-<slug>/` that resolves to `~/.claude/x` on any machine and under any
username, where an absolute link breaks the moment `$HOME` differs. The same
relative path also resolves inside this repo, since `claude/` contains
`.claude/` — so they are not dangling links in git either.

Seeding **never overwrites**. An entry already present in a seat is left alone,
for the same reason `settings.json` is copied rather than symlinked here: Claude
rewrites it at runtime, and an `apply` that clobbered it would silently revert
every `/model` switch made in that seat.

## Not tracked on purpose

`~/.claude/settings.local.json` — machine-local `permissions.allow` entries
(local paths, per-machine sudo rules). Deliberately never committed.

The `statusLine` command uses an absolute path
(`/Users/th3g3ntleman/.claude/statusline-pace.py`) — fine as long as every machine
shares that home. On a machine with a different username, edit that one line and
`claude-settings-sync` will surface it in the diff.
