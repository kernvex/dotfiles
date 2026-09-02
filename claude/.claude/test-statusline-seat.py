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

import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
STATUSLINE = os.path.join(HERE, "statusline-pace.py")
REPO = os.path.realpath(os.path.join(HERE, "..", ".."))


def _statusline_module():
    """The status line imported as a module, for its palette only.

    Every assertion below still goes through the real process boundary; this is
    read-only access to SEAT_COLORS so the palette has ONE home. Restating the
    codes here was how the table came to assert its own expectations, since an
    expected colour copied out of the source passes whatever the source says.
    """
    spec = importlib.util.spec_from_file_location("statusline_pace", STATUSLINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SL = _statusline_module()
SEAT_COLORS = SL.SEAT_COLORS
# escape code -> the constant's name, so failures read as a colour not a number.
CODE_NAMES = {v: k for k, v in vars(SL).items()
              if isinstance(v, str) and k.isupper() and v.isdigit()}

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


def state_colors_are_distinct():
    """No two seat states may share an escape CODE.

    Reads resolved values, not constant names. The first version of this
    compared identifiers, so binding one constant to another's code — say the
    verified colour to `2` — left four distinct names and it passed green,
    asserting only that four names are four names, which they always are.

    This is the weak half of a guarantee, and the strong half cannot be
    automated: the verified state moved off bright blue because `94` and `2` are
    DIFFERENT codes that this terminal theme renders as the SAME colour, and no
    assertion here can see a rendered pixel. `seat-colour-swatch.sh` is that
    check and it needs a human. See docs/adr/0014.
    """
    states = ("verified", "mismatch", "unverifiable", "neutral")
    missing = [st for st in states if st not in SEAT_COLORS]
    if missing:
        return False, f"the status line has no colour for {missing}"
    codes = {st: SEAT_COLORS[st] for st in states}
    if len(set(codes.values())) != len(codes):
        return False, f"two states share a colour code: {codes}"
    return True, ", ".join(f"{st}={CODE_NAMES.get(c, '?')}({c})" for st, c in codes.items())


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

        # Each row names the STATE the scenario must produce; the colour is
        # looked up from the status line's own palette. So a hue change is one
        # edit there, and this table goes on asserting behaviour rather than
        # re-stating the value it is supposed to be checking.
        cases = [
            ("routed   + seat matches      ", repo,        matching,    "verified"),
            ("routed   + seat differs      ", repo,        other,       "mismatch"),
            ("routed   + seat has no acct  ", repo,        accountless, "unverifiable"),
            ("unrouted + default seat      ", REPO,        None,        "neutral"),
            ("unrouted + named seat        ", REPO,        other,       "mismatch"),
            ("no repo  + default seat      ", not_a_repo,  None,        "neutral"),
            ("no repo  + named seat        ", not_a_repo,  other,       "unverifiable"),
        ]

        print(f"statusline : {STATUSLINE}")
        print(f"routed repo: {'<found>' if repo else 'NOT FOUND - routed rows skip'}")
        print(f"default dir: {default_dir}\n")

        for label, cwd, seat, expected_state in cases:
            if cwd is None or (seat is None and "named" in label):
                skipped.append(label)
                print(f"  SKIP  {label}  (no routed repo on this machine)")
                continue
            expected = SEAT_COLORS[expected_state]
            got = seat_colour(cwd, seat)
            ran += 1
            ok = got == expected
            mark = "ok  " if ok else "FAIL"
            print(f"  {mark}  {label}  expected {expected_state:<12} "
                  f"got {CODE_NAMES.get(got, repr(got)).lower()}")
            if not ok:
                failures.append(label)

    print("\n  -- the palette itself --")
    ok, why = state_colors_are_distinct()
    ran += 1
    print(f"  {'ok  ' if ok else 'FAIL'}  every state has its own code          {why}")
    if not ok:
        failures.append("state colours are distinct")

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
