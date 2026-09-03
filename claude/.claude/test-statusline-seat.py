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
    read-only access to SEAT_STATES so the palette has ONE home. Restating the
    codes here was how the table came to assert its own expectations, since an
    expected colour copied out of the source passes whatever the source says.
    """
    spec = importlib.util.spec_from_file_location("statusline_pace", STATUSLINE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SL = _statusline_module()
SEAT_STATES = SL.SEAT_STATES


def colour_of(state):
    """The escape code the status line paints this state in."""
    return SEAT_STATES[state]["colour"]
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


# A path that cannot exist, so the rows below exercise the NO-MAP fallback.
# Those rows pair a real routed folder with a SYNTHETIC seat, which the real map
# would rightly call a mismatch; and the fallback is the path a machine with no
# identity tool takes, so it is worth asserting deliberately rather than by
# accident of whether a map happens to be installed.
ABSENT_MAP = os.path.join(HERE, "no-such-routing-map.json")


def render(cwd, config_dir, map_path, marker=None):
    """Run the status line as Claude Code does; return (ansi code, seat label).

    A payload on stdin, a working directory, an environment — the real process
    boundary. Every row in this file goes through here; the map path and the
    marker are the only things that vary.
    """
    env = dict(os.environ)
    env.pop("CLAUDE_CONFIG_DIR", None)
    env.pop("IDENTITY_SEAT_OVERRIDE", None)
    env["STATUSLINE_IDENTITY_MAP"] = map_path
    if config_dir is not None:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    if marker is not None:
        env["IDENTITY_SEAT_OVERRIDE"] = marker
    payload = json.loads(PAYLOAD)
    payload["workspace"]["current_dir"] = cwd

    out = subprocess.run(
        [sys.executable, STATUSLINE],
        input=json.dumps(payload), cwd=cwd, env=env,
        capture_output=True, text=True, timeout=20,
    ).stdout
    m = SEAT_RE.search(out)
    return (m.group(1), m.group(2)) if m else (None, None)


def seat_segment(cwd, config_dir):
    """The no-map path: git decides, as it does where no identity tool exists."""
    return render(cwd, config_dir, ABSENT_MAP)


def seat_colour(cwd, config_dir):
    return seat_segment(cwd, config_dir)[0]


# --- the map-driven rows ----------------------------------------------------
#
# Everything above discovers a routed folder by asking git for its own rules, so
# no employer path appears in this file. These rows need something git cannot
# supply — which folders route a SEAT, and where a folder's root begins — so they
# build a whole synthetic machine instead: fake work folders, a fake map, fake
# seats. Nothing here touches the real map or the real routing.


def make_map(tmp, name, work, seat_dir_path, noseat, email, samestore=None):
    """A routing map in the shape `identity apply` emits.

    `email` matters: the map carries each identity's address, and the segment
    compares the SEAT's account against it. Selecting the right directory is not
    the same as being signed into the right account, and a check that compared
    only paths would call the wrong account verified.
    """
    # Named per fixture: three maps live at once here, and a shared filename had
    # them silently overwriting each other.
    path = os.path.join(tmp, f"map-{name}.json")
    identities = [
            {"slug": "a-company", "work_folder": work, "routed": True,
             "email": email,
             "tools": {"gh": {"store": os.path.join(tmp, "gh-a"), "env": {}},
                       "claude": {"store": seat_dir_path,
                                  "env": {"CLAUDE_CONFIG_DIR": seat_dir_path}}}},
            # Routes git but NO seat: the default seat is the only one there is.
            {"slug": "b-company", "work_folder": noseat, "routed": True,
             "email": "person@b-company.invalid",
             "tools": {"gh": {"store": os.path.join(tmp, "gh-b"), "env": {}}}},
            {"slug": "owner", "work_folder": None, "routed": False,
             "email": "owner@example.invalid",
             "tools": {"claude": {"store": os.path.expanduser("~/.claude"), "env": {}}}},
    ]
    if samestore is not None:
        # A folder that routes the DEFAULT store: it displaces nothing, so a
        # marker there must not be allowed to claim an override.
        identities.append(
            {"slug": "c-company", "work_folder": samestore, "routed": True,
             "email": "person@c-company.invalid",
             "tools": {"claude": {"store": os.path.expanduser("~/.claude"),
                                  "env": {"CLAUDE_CONFIG_DIR": os.path.expanduser("~/.claude")}}}})
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "identities": identities}, fh)
    return path


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
    """A colour means one thing: states share one exactly when they assert the same.

    Reads resolved values, not constant names. The first version of this
    compared identifiers, so binding one constant to another's code — say the
    verified colour to `2` — left four distinct names and it passed green,
    asserting only that four names are four names, which they always are.

    It also enumerates SEAT_STATES rather than a hand-written list, so a state
    added later is checked without anyone remembering to add it here.

    This is the weak half of a guarantee, and the strong half cannot be
    automated: the verified state moved off bright blue because `94` and `2` are
    DIFFERENT codes that this terminal theme renders as the SAME colour, and no
    assertion here can see a rendered pixel. `seat-colour-swatch.sh` is that
    check and it needs a human. See docs/adr/0014.
    """
    # The groups are DERIVED from what each state asserts, not restated here — so
    # a state added to the table is checked without anyone remembering to.
    claims = {}
    for state, row in SEAT_STATES.items():
        claims.setdefault(row["asserts"], []).append(state)

    # Same claim => same colour. Re-point `overridden` at red and this fails.
    for claim, states in claims.items():
        codes = {SEAT_STATES[st]["colour"] for st in states}
        if len(codes) != 1:
            return False, (f"{' and '.join(states)} both assert {claim!r}, "
                           "so they must share a colour: "
                           + ", ".join(f"{st}={SEAT_STATES[st]['colour']}" for st in states))

    # Different claim => different colour.
    owners = {}
    for claim, states in claims.items():
        owners.setdefault(SEAT_STATES[states[0]]["colour"], []).append(claim)
    clashes = {c: sorted(k) for c, k in owners.items() if len(k) > 1}
    if clashes:
        return False, f"one colour asserting two different things: {clashes}"

    # A badge is the only thing separating states that share a colour, so a
    # shared colour with no badge would be two verdicts nothing distinguishes.
    for claim, states in claims.items():
        if len(states) > 1 and sum(1 for st in states if not SEAT_STATES[st]["badge"]) != 1:
            return False, (f"{' and '.join(states)} share a colour, so exactly one "
                           "may be badgeless; the others need a badge to be told apart")

    shown = ", ".join(f"{st}={CODE_NAMES.get(SEAT_STATES[st]['colour'], '?')}"
                      f"({SEAT_STATES[st]['colour']})"
                      + (f"+{SEAT_STATES[st]['badge']}" if SEAT_STATES[st]["badge"] else "")
                      for st in SEAT_STATES)
    return True, shown


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

        print("  (git decides these: no map)")
        print(f"statusline : {STATUSLINE}")
        print(f"routed repo: {'<found>' if repo else 'NOT FOUND - routed rows skip'}")
        print(f"default dir: {default_dir}\n")

        for label, cwd, seat, expected_state in cases:
            if cwd is None or (seat is None and "named" in label):
                skipped.append(label)
                print(f"  SKIP  {label}  (no routed repo on this machine)")
                continue
            expected = colour_of(expected_state)
            got = seat_colour(cwd, seat)
            ran += 1
            ok = got == expected
            mark = "ok  " if ok else "FAIL"
            print(f"  {mark}  {label}  expected {expected_state:<12} "
                  f"got {CODE_NAMES.get(got, repr(got)).lower()}")
            if not ok:
                failures.append(label)

    print("\n  -- work folders, decided by the map --")
    with tempfile.TemporaryDirectory() as tmp:
        work = os.path.join(tmp, "work", "Acme")
        noseat = os.path.join(tmp, "work", "Other")
        os.makedirs(os.path.join(work, "a-repo"))
        os.makedirs(os.path.join(noseat, "b-repo"))
        assigned = make_seat(tmp, ".claude-a-company", "person@a-company.invalid")
        foreign = make_seat(tmp, ".claude-b-company", "person@b-company.invalid")
        samestore = os.path.join(tmp, "work", "Same")
        os.makedirs(samestore)
        map_path = make_map(tmp, "main", work, assigned, noseat,
                            "person@a-company.invalid", samestore)

        # The assigned STORE, signed into the wrong account, and into none at
        # all. Both live at the assigned path, so only the account tells them
        # apart from the row above.
        wrong_account = os.path.join(tmp, "wrong-account")
        os.makedirs(wrong_account)
        with open(os.path.join(wrong_account, ".claude.json"), "w", encoding="utf-8") as fh:
            json.dump({"oauthAccount": {"emailAddress": "someone.else@example.invalid",
                                        "organizationType": "claude_team"}}, fh)
        no_account = os.path.join(tmp, "no-account")
        os.makedirs(no_account)
        with open(os.path.join(no_account, ".claude.json"), "w", encoding="utf-8") as fh:
            json.dump({}, fh)
        map_wrong = make_map(tmp, "wrong", work, wrong_account, noseat,
                             "person@a-company.invalid")
        map_none = make_map(tmp, "none", work, no_account, noseat,
                            "person@a-company.invalid")

        rows = [
            # label, cwd, seat, marker, expected state, expect the word
            ("work ROOT + assigned seat   ", work, assigned, None, "verified", False),
            ("work repo + assigned seat   ", os.path.join(work, "a-repo"), assigned, None, "verified", False),
            ("work ROOT + default + marker", work, None, "owner", "overridden", True),
            ("work repo + default + marker", os.path.join(work, "a-repo"), None, "owner", "overridden", True),
            ("work ROOT + default, no mark", work, None, None, "mismatch", False),
            ("work ROOT + WRONG marker    ", work, None, "not-a-slug", "mismatch", False),
            ("no-seat folder + default    ", os.path.join(noseat, "b-repo"), None, None, "verified", False),
            ("no-seat folder + other seat ", os.path.join(noseat, "b-repo"), foreign, None, "mismatch", False),
            # The folder routes the default store, so nothing is displaced and a
            # marker must not manufacture a badge.
            ("folder assigns default store", samestore, None, "owner", "verified", False),
        ]
        for label, cwd, seat, marker, state, want_word in rows:
            expected = colour_of(state)
            got, seg = render(cwd, seat, map_path, marker)
            ran += 1
            has_word = "OVERRIDDEN" in (seg or "")
            ok = got == expected and has_word == want_word
            print(f"  {'ok  ' if ok else 'FAIL'}  {label}  expected {state:<12} "
                  f"got {CODE_NAMES.get(got, repr(got)).lower()}"
                  f"{'  +OVERRIDDEN' if has_word else ''}")
            if not ok:
                failures.append(label.strip())

        # The assigned store is selected, but signed into the wrong account, or
        # into none. Path equality alone would call both of these verified.
        for label, seat_dir_path, which_map, state in (
            ("assigned store + WRONG account", wrong_account, map_wrong, "mismatch"),
            ("assigned store + no account   ", no_account, map_none, "unverifiable"),
        ):
            ran += 1
            expected = colour_of(state)
            got, _ = render(os.path.join(work, "a-repo"), seat_dir_path, which_map)
            ok = got == expected
            print(f"  {'ok  ' if ok else 'FAIL'}  {label}  expected {state:<12} "
                  f"got {CODE_NAMES.get(got, repr(got)).lower()}")
            if not ok:
                failures.append(label.strip())

        # A machine with no identity tool must keep working: absent map, git decides.
        ran += 1
        got, _ = render(os.path.join(work, "a-repo"), assigned,
                             os.path.join(tmp, "nope.json"))
        ok = got == colour_of("unverifiable")
        print(f"  {'ok  ' if ok else 'FAIL'}  absent map falls back to git  "
              f"expected unverifiable got {CODE_NAMES.get(got, repr(got)).lower()}")
        if not ok:
            failures.append("absent map falls back")

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
