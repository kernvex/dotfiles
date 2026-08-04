#!/usr/bin/env python3
"""Every row of the Claude seat state table, asserted end to end.

Runs `statusline-pace.py` as Claude Code runs it — a fixture payload on stdin,
a cwd, an environment — and checks the colour of the seat segment it renders.

Two things keep this honest and portable:

  * SEATS ARE SYNTHETIC. Each is a temp dir holding a hand-written `.claude.json`
    with nothing but an `oauthAccount` block, so no real login is touched and the
    test passes on a machine where no company seat has been provisioned yet.
  * FOLDERS ARE FOUND, NOT NAMED. The routed folder is discovered by asking git
    for its own `includeIf gitdir:` rules, so no employer path appears in this
    file. If no routed repo exists on this machine, those rows skip rather than
    fail.

Usage:  python3 test-statusline-seat.py         (exit 0 = all passed)

Spec: docs/superpowers/specs/2026-08-03-claude-seat-statusline-design.md
"""

import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
STATUSLINE = os.path.join(HERE, "statusline-pace.py")
REPO = os.path.realpath(os.path.join(HERE, "..", ".."))

DIM, RED, YELLOW, BLUE = "2", "31", "33", "94"
NAMES = {DIM: "dim", RED: "red", YELLOW: "yellow", BLUE: "blue"}

# The seat segment is the first thing on line two: ESC[<code>m ◈ <label> ESC[0m
SEAT_RE = re.compile(r"\x1b\[(\d+)m◈ ([^\x1b]*)\x1b\[0m")


def git(*args, cwd=None):
    try:
        out = subprocess.run(["git", *args], cwd=cwd, capture_output=True,
                             text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


# --- finding a routed folder without naming one -----------------------------


def routed_repo():
    """A repo an `includeIf gitdir:` rule covers, discovered from git itself."""
    listing = git("config", "-l", "--show-origin") or ""
    for line in listing.splitlines():
        _, _, kv = line.partition("\t")
        key, sep, _ = kv.partition("=")
        if not sep or not key.startswith("includeif.gitdir"):
            continue
        prefix = ("includeif.gitdir/i:" if key.startswith("includeif.gitdir/i:")
                  else "includeif.gitdir:")
        body = key[len(prefix):]
        if not body.endswith(".path"):
            continue
        root = os.path.expanduser(body[: -len(".path")]).rstrip("/")
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            candidate = os.path.join(root, entry)
            if os.path.isdir(os.path.join(candidate, ".git")):
                return candidate
    return None


def routed_email(repo):
    return git("config", "user.email", cwd=repo)


# --- synthetic seats --------------------------------------------------------


def make_seat(tmp, name, email=None, tier="claude_max"):
    """A config dir holding just enough .claude.json to be read."""
    path = os.path.join(tmp, name)
    os.makedirs(path, exist_ok=True)
    body = {}
    if email is not None:
        body["oauthAccount"] = {"emailAddress": email, "organizationType": tier}
    with open(os.path.join(path, ".claude.json"), "w", encoding="utf-8") as fh:
        json.dump(body, fh)
    return path


PAYLOAD = json.dumps({
    "model": {"display_name": "Opus 5 (1M context)", "id": "claude-opus-5"},
    "effort": {"level": "high"},
    "context_window": {"used_percentage": 12.0},
    "workspace": {"current_dir": None},
    "session_id": "test",
})


def seat_segment(cwd, config_dir):
    """Render the status line; return (ansi code, label) of the seat segment."""
    env = dict(os.environ)
    env.pop("CLAUDE_CONFIG_DIR", None)
    if config_dir is not None:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    payload = json.loads(PAYLOAD)
    payload["workspace"]["current_dir"] = cwd

    out = subprocess.run(
        [sys.executable, STATUSLINE],
        input=json.dumps(payload), cwd=cwd, env=env,
        capture_output=True, text=True, timeout=20,
    ).stdout
    m = SEAT_RE.search(out)
    return (m.group(1), m.group(2)) if m else (None, None)


def seat_colour(cwd, config_dir):
    return seat_segment(cwd, config_dir)[0]


def default_seat_resolves_its_account():
    """Regression guard: the machine owner's config file is NOT in ~/.claude.

    Verified against Claude Code 2.1.221 — with CLAUDE_CONFIG_DIR unset the file
    is `~/.claude.json`, a SIBLING of `~/.claude`. Reading `<config dir>/.claude.json`
    for the default seat silently finds nothing and renders the `personal`
    fallback, which is a wrong label with a right colour, so no colour assertion
    in the table above can catch it.
    """
    _, label = seat_segment(REPO, None)
    if label is None:
        return False, "no seat segment rendered"
    if label.strip() == "personal":
        return False, "fell back to 'personal' - config file not found"
    if "@" not in label:
        return False, f"expected an account address, got {label.strip()!r}"
    return True, "resolved an account rather than the directory fallback"


# --- the table --------------------------------------------------------------


def main():
    failures, skipped, ran = [], [], 0
    default_dir = os.path.expanduser("~/.claude")

    with tempfile.TemporaryDirectory() as tmp:
        not_a_repo = os.path.join(tmp, "plain")
        os.makedirs(not_a_repo)

        repo = routed_repo()
        r_email = routed_email(repo) if repo else None

        # A named seat logged into the routed folder's own identity, and one
        # logged into something else. Both synthetic.
        matching = make_seat(tmp, ".claude-a-person-company", r_email) if r_email else None
        other = make_seat(tmp, ".claude-b-person-company", "someone.else@example.invalid")
        accountless = make_seat(tmp, ".claude-c-person-company", None)

        cases = [
            ("routed   + seat matches      ", repo,        matching,    BLUE),
            ("routed   + seat differs      ", repo,        other,       RED),
            ("routed   + seat has no acct  ", repo,        accountless, YELLOW),
            ("unrouted + default seat      ", REPO,        None,        DIM),
            ("unrouted + named seat        ", REPO,        other,       RED),
            ("no repo  + default seat      ", not_a_repo,  None,        DIM),
            ("no repo  + named seat        ", not_a_repo,  other,       YELLOW),
        ]

        print(f"statusline : {STATUSLINE}")
        print(f"routed repo: {'<found>' if repo else 'NOT FOUND - routed rows skip'}")
        print(f"default dir: {default_dir}\n")

        for label, cwd, seat, expected in cases:
            if cwd is None or (seat is None and "named" in label):
                skipped.append(label)
                print(f"  SKIP  {label}  (no routed repo on this machine)")
                continue
            got = seat_colour(cwd, seat)
            ran += 1
            ok = got == expected
            mark = "ok  " if ok else "FAIL"
            print(f"  {mark}  {label}  expected {NAMES[expected]:<6} "
                  f"got {NAMES.get(got, repr(got))}")
            if not ok:
                failures.append(label)

    print("\n  -- label, not just colour --")
    ok, why = default_seat_resolves_its_account()
    ran += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  default seat reads its config file    {why}")
    if not ok:
        failures.append("default seat resolves its account")

    print()
    print(f"{ran} ran, {len(failures)} failed, {len(skipped)} skipped")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
