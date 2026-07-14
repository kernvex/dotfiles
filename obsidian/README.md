# obsidian

The **Habits** vault's `.obsidian` config and its pinned community-plugin
binaries — the reproducible half of the habit tracker. (The habit *system* —
`habits.md` + generators — lives in the separate
[`obsidian-habit-tracker`](https://github.com/6eniu5/obsidian-habit-tracker)
repo, an esetup submodule.)

## Copy-managed, not stowed

Like `claude/settings.json`, this is **copied** by `./install`, never
stow-symlinked, for two reasons:

1. The vault lives in the Obsidian **iCloud container**
   (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Habits`), and
   symlinks into an iCloud-synced folder misbehave.
2. Obsidian atomically rewrites its own `.obsidian/*.json` at runtime, which
   would detach a symlink.

`./install` runs `rsync -a vault-obsidian/ <vault>/.obsidian/` (no `--delete`),
so it lays down our config + plugins while leaving untouched:

- `.obsidian/types.json` — owned by the `obsidian-habit-tracker` generator.
- `.obsidian/workspace.json`, `workspace-mobile.json` — runtime layout.
- `plugins/<id>/data.json` — plugin runtime settings, **except** the shipped
  `plugins/dataview/data.json` (seeds `enableDataviewJs: true` so the
  heatmap/dashboard `dataviewjs` blocks work headless out of the box).

The vault path defaults to the iCloud container; override with
`OBSIDIAN_HABITS_VAULT`. If the vault doesn't exist yet, install skips this with
a note — create the vault first (via the generator's deploy), then re-run
`./install`.

## What's tracked

| file | purpose |
|---|---|
| `core-plugins.json` | enables Daily notes, Templates, Properties, **Bases** |
| `community-plugins.json` | Dataview, Heatmap Tracker, Charts for Bases |
| `daily-notes.json` | folder `Daily`, format `YYYY-MM-DD`, template `Templates/daily` |
| `templates.json` | folder `Templates` |
| `app.json`, `appearance.json` | misc vault settings |
| `plugins/{dataview,heatmap-tracker,charts}/` | **pinned** plugin binaries (headless install) |

Requires Obsidian ≥ 1.12.4 (Bases). Bump a plugin by re-downloading its release
assets into `plugins/<id>/` and committing.

## Syncing runtime changes back

Changed a setting in Obsidian and want the repo to match?

```bash
obsidian-config-sync   # copies the tracked .obsidian/*.json back here, shows the diff
```

then review and `git commit`. (Lives in the `bin` package. It syncs config JSON
only — never plugin binaries or the generator-owned `types.json`.)
