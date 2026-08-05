#!/usr/bin/env python3
"""Every branch of whereami's display-path rule, asserted end to end.

Runs `whereami --json` as the status line runs it — in a cwd, reading its output
— against repos built from scratch in a temp dir. Nothing on the real machine is
touched and no employer path appears here, so this passes anywhere.

The five branches, and what each is guarding against:

  outside a repo      the leaf name, and nothing clever
  main tree, root     <parent>/<repo> — the world stays visible
  main tree, nested   <repo>/<within>
  worktree, inside    anchored on the OWNING repo. The bug this file exists for:
                      a linked checkout is a repo root, so the ordinary rule
                      renders `.worktrees/skills` and never names the repo.
  worktree, outside   the `..` chain collapses to a single `…`

Usage:  python3 test-whereami-path.py         (exit 0 = all passed)
"""

import json
import os
import subprocess
import sys
import tempfile

WHEREAMI = os.path.expanduser("~/.local/bin/whereami")


def git(*args, cwd=None):
    subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
    )


def whereami(cwd):
    out = subprocess.run(
        [sys.executable, WHEREAMI, "--json"],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=15,
    )
    return json.loads(out.stdout)


def make_repo(path):
    """A repo with one commit, and an identity local to it.

    The commit matters: `git worktree add` has nothing to attach a branch to in a
    repo with an unborn HEAD. The local identity keeps the machine's own global
    config — and any includeIf routing on it — out of this test entirely.
    """
    os.makedirs(path, exist_ok=True)
    git("init", "-q", cwd=path)
    git("config", "user.name", "Test", cwd=path)
    git("config", "user.email", "test@example.invalid", cwd=path)
    git("commit", "-q", "--allow-empty", "-m", "root", cwd=path)


# --- the cases --------------------------------------------------------------


def cases(tmp):
    """(name, cwd, expected path, expected repo) for each branch."""
    # A world directory, so the <parent> segment is a real name and not a temp-dir
    # artifact that would differ between runs.
    world = os.path.join(tmp, "world")
    repo = os.path.join(world, "myrepo")
    make_repo(repo)

    nested = os.path.join(repo, "src", "handlers")
    os.makedirs(nested)

    inside = os.path.join(repo, ".worktrees", "feature")
    git("worktree", "add", "-q", "-b", "feature", inside, cwd=repo)
    inside_nested = os.path.join(inside, "src", "handlers")
    os.makedirs(inside_nested)

    elsewhere = os.path.join(tmp, "parked", "wt-feature")
    git("worktree", "add", "-q", "-b", "parked", elsewhere, cwd=repo)

    plain = os.path.join(tmp, "not-a-repo")
    os.makedirs(plain)

    return [
        ("outside a repo", plain, "not-a-repo", None),
        ("main tree, at root", repo, "world/myrepo", "myrepo"),
        ("main tree, nested", nested, "myrepo/src/handlers", "myrepo"),
        ("worktree, at its root", inside,
         "world/myrepo/.worktrees/feature", "myrepo"),
        ("worktree, nested", inside_nested,
         "world/myrepo/.worktrees/feature/src/handlers", "myrepo"),
        ("worktree, parked outside", elsewhere,
         "world/myrepo/…/parked/wt-feature", "myrepo"),
    ]


def main():
    if not os.path.exists(WHEREAMI):
        print(f"whereami not installed at {WHEREAMI} — run ./install first")
        return 1

    failures = []
    # macOS puts temp dirs under /var, a symlink to /private/var. whereami resolves
    # its paths, so the expectations must be built from the resolved root too.
    with tempfile.TemporaryDirectory() as raw:
        tmp = os.path.realpath(raw)
        for name, cwd, want_path, want_repo in cases(tmp):
            info = whereami(cwd)
            got_path, got_repo = info.get("path"), info.get("repo")
            ok = got_path == want_path and got_repo == want_repo
            print(f"  {'ok  ' if ok else 'FAIL'}  {name:26}  {got_path}")
            if not ok:
                print(f"        wanted path={want_path!r} repo={want_repo!r}")
                print(f"           got path={got_path!r} repo={got_repo!r}")
                failures.append(name)

    print()
    print(f"{len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
