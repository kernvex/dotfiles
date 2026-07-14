# obsidian

Each Obsidian vault's `.obsidian` config + pinned community-plugin binaries, **one
subdir per vault**. Copy-managed, **not stowed** — the vaults live in the iCloud
container (symlinks misbehave there) and Obsidian rewrites its own JSON at
runtime, same reasons as `claude/settings.json`.

## Vaults

| subdir | vault | plugins |
|---|---|---|
| `habits/` | `Documents/Habits` | Bases (core) · Dataview · Heatmap Tracker · Charts for Bases |
| `lingo/`  | `Documents/Lingo`  | obsidian-spaced-repetition (FSRS) · Templates (core) |

Each holds a `vault-obsidian/` tree — the files `./install` copies into
`<vault>/.obsidian/`: `core-plugins.json`, `community-plugins.json`, per-vault
settings, and pinned `plugins/<id>/` binaries (with a seeded `data.json` where a
plugin needs a non-default setting — Dataview's `enableDataviewJs`,
spaced-repetition's `algorithm: FSRS`).

## How it's applied

`./install` runs, per vault, `rsync -a obsidian/<name>/vault-obsidian/ <vault>/.obsidian/`
(no `--delete`), laying down config + plugins while leaving untouched:

- `.obsidian/types.json` — owned by the vault's generator (`obsidian-habit-tracker`
  / `obsidian-lingo`).
- `.obsidian/workspace.json`, `workspace-mobile.json` — runtime layout.
- `plugins/<id>/data.json` — plugin runtime settings, except the seeds we ship.

Vault paths default to the iCloud container; override with `OBSIDIAN_HABITS_VAULT`
/ `OBSIDIAN_LINGO_VAULT`. If a vault doesn't exist yet, install skips it — create
it (via the generator's deploy), then re-run `./install`.

## Adding a vault

Add `obsidian/<name>/vault-obsidian/` plus one `obsidian_copy <name> <path>` line
in `install`. Pairs with a generator submodule in esetup.

## Syncing runtime changes back

```bash
obsidian-config-sync [habits|lingo]   # copies tracked .obsidian/*.json back here, shows the diff
```

then review and `git commit`. (In the `bin` package; config JSON only — never
plugin binaries or the generator-owned `types.json`.)
