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

## Not tracked on purpose

`~/.claude/settings.local.json` — machine-local `permissions.allow` entries
(local paths, per-machine sudo rules). Deliberately never committed.

The `statusLine` command uses an absolute path
(`/Users/th3g3ntleman/.claude/statusline-pace.py`) — fine as long as every machine
shares that home. On a machine with a different username, edit that one line and
`claude-settings-sync` will surface it in the diff.
