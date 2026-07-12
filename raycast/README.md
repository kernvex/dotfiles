# Raycast baseline config

Raycast does not read a plain text config from `~/.config/`. Use **export/import** (`.rayconfig`).

## Optional: ship a baseline for `setup.sh`

1. On a Mac with Raycast configured how you want: **Raycast → Settings → Advanced → Export Settings & Data**.
2. Remove the default export password if you want an unencrypted file (easier to review in git).
3. Save the export as **`baseline.rayconfig`** in this directory (`esetup/raycast/baseline.rayconfig`).
4. Commit it. During `setup.sh`, if this file exists, you will be prompted to import it (opens the file so Raycast handles import).

## Optional: JSON for readable diffs

```bash
cd esetup/raycast
cp baseline.rayconfig baseline.rayconfig.bak
gzip --decompress --keep --suffix .rayconfig baseline.rayconfig
# produces decompressed file; rename to baseline.json if desired
```

## Spotlight

`setup.sh` disables the **Show Spotlight search** shortcut (Cmd+Space) so Raycast can use it. Spotlight **indexing** stays on. Log out/in after setup for the hotkey change to apply.
