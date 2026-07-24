# Existing clones need `git submodule sync` after the kernvex rename

`416afd2` rewrote the submodule URLs in `.gitmodules` from `6eniu5/…` to
`kernvex/…`. That file is only read when a submodule is **initialised** — `git
submodule init` copies each URL into the clone's `.git/config`, and every later
`fetch`/`update` uses the `.git/config` copy. Pulling the rename into a clone
that already has `nvim/.config/nvim` and `tmux-sessionizer` checked out
therefore changes nothing: those submodules keep fetching the old URLs, which
survive today only because GitHub redirects renamed accounts.

**Next step — on every machine that already has this repo cloned:**

```bash
cd "$DOTFILES"
git pull
git submodule sync --recursive
git submodule update --init --recursive
```

`sync` is the step that matters: it re-copies the `.gitmodules` URLs over the
stale ones in `.git/config` (and, with `--recursive`, in each submodule's own
config). Verify with:

```bash
git submodule foreach 'git remote -v'   # expect kernvex/… for both
```

Fresh clones need none of this — `init` reads the corrected `.gitmodules`
directly. The machine this note was written on (`~/kernvex/dotfiles`) was
already pointing at `kernvex/…` before the rename was committed, so it needs no
action either.
