#!/usr/bin/env python3
"""Claude Code status line: context window + plan burn-rate projection.

Claude Code pipes a JSON blob to this script on stdin before each render.
Two independent meters live in there, and conflating them is the classic
mistake:

  context_window.*  -- how much the model can currently SEE. Per session.
                       Freed by /clear and /compact.
  rate_limits.*     -- how much you have SPENT against your subscription.
                       Per account. Freed only by the clock.

`rate_limits` is the only programmatic surface for plan consumption; no
slash command emits it in a pipeable form. It appears for Claude.ai
Pro/Max subscribers after the first API response of a session, and either
window may be independently absent. Handle absence, never assume presence.

Schema: https://code.claude.com/docs/en/statusline

Line two additionally leads with the CLAUDE SEAT — which account is answering —
coloured by whether it agrees with the git identity of the folder you're standing
in. See the `claude seat` section below and
docs/superpowers/specs/2026-08-03-claude-seat-statusline-design.md.

Side effect: throttled append of each sample to ~/.claude/usage-log.jsonl,
building the history that makes week-over-week projection possible.
"""

import sys
import json
import os
import re
import subprocess
import time

FIVE_HOURS = 5 * 3600
SEVEN_DAYS = 7 * 24 * 3600

# A pace above 1.0 is not news. Ten minutes into a window, one long request puts
# you at 3x and it means nothing. Two guards keep the alarm honest:
#
#   MIN_ELAPSED  -- say nothing until enough of the window has passed that the
#                   rate is a rate and not a single sample.
#   PACE_ALARM   -- since exhaust_fraction == 1 / pace (see pace()), a threshold
#                   of 1.15 fires only when you would run dry at 87% of the
#                   window: ~39 min early on the 5-hour, ~22 h early on the week.
#                   Below that, being "over pace" costs you nothing you'd notice.
#   PACE_WARN    -- the quiet annotation is rendered to one decimal, so anything
#                   below 1.05 would print "1.0x", which is the number that means
#                   "fine". Don't annotate what rounds to nothing. This also
#                   keeps us off the exact-1.0 boundary, where float error makes
#                   used == elapsed land on either side at random.
MIN_ELAPSED = 0.25
PACE_WARN = 1.05
PACE_ALARM = 1.15

LOG_PATH = os.path.expanduser("~/.claude/usage-log.jsonl")
STAMP_PATH = os.path.expanduser("~/.claude/.usage-log-stamp")
LOG_THROTTLE_SECONDS = 300


# --- presentation -----------------------------------------------------------

RESET = "\x1b[0m"


def paint(code, text):
    return f"\x1b[{code}m{text}{RESET}"


DIM, BOLD = "2", "1"
RED, YELLOW, GREEN, CYAN = "31", "33", "32", "36"
# Basic ANSI throughout, so the terminal theme picks the hue.
#
# Verified is magenta, and was bright blue until `94` turned out to render
# indistinguishably from DIM in this theme — so the state meaning "checked, and
# correct" looked exactly like "nothing to say". A signal that cannot be seen is
# not a signal. The evidence, the rejected candidates and the general lesson are
# in docs/adr/0014; run seat-colour-swatch.sh after any theme change.
MAGENTA = "95"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def visible_len(s):
    """Printed width of a line, ignoring its colour-escape codes."""
    return len(ANSI_RE.sub("", s))


def severity(pct):
    """Colour by how much of a budget is gone."""
    if pct is None:
        return DIM
    if pct >= 90:
        return RED
    if pct >= 70:
        return YELLOW
    return GREEN


def bar(pct, width=10):
    if pct is None:
        return "─" * width
    filled = int(round(pct / 100 * width))
    filled = max(0, min(width, filled))
    return "█" * filled + "░" * (width - filled)


def clock(epoch):
    return time.strftime("%a %H:%M", time.localtime(epoch))


def reset_label(epoch, now):
    """When a usage window resets: bare `HH:MM` if it's today, else `Day HH:MM`."""
    lt = time.localtime(epoch)
    nt = time.localtime(now)
    if (lt.tm_year, lt.tm_yday) == (nt.tm_year, nt.tm_yday):
        return time.strftime("%H:%M", lt)
    return time.strftime("%a %H:%M", lt)


# --- the one formula --------------------------------------------------------


def pace(used_pct, resets_at, window_seconds, now):
    """How fast are we burning, relative to the clock?

        pace = (fraction of budget spent) / (fraction of window elapsed)

    Returns (pace, exhaust_epoch). `exhaust_epoch` is populated only when the
    projection is worth acting on: enough of the window has elapsed to trust
    the rate, and the pace is high enough that running dry actually costs you
    time. Returns (None, None) when the inputs cannot support any claim.

    The projection collapses to one line. Substituting
    used/100 = pace × elapsed_fraction into

        exhaust_fraction = elapsed_fraction × (100 / used)

    gives exhaust_fraction = 1 / pace. Where you land is a function of pace
    alone -- the elapsed time cancels out entirely.
    """
    if used_pct is None or not resets_at:
        return None, None

    window_start = resets_at - window_seconds
    elapsed = now - window_start
    if elapsed <= 0 or elapsed > window_seconds:
        return None, None

    elapsed_fraction = elapsed / window_seconds
    if used_pct <= 0:
        return 0.0, None

    ratio = (used_pct / 100) / elapsed_fraction

    if elapsed_fraction < MIN_ELAPSED:
        return None, None  # too early for the rate to mean anything at all

    exhaust_at = None
    if ratio >= PACE_ALARM:
        exhaust_at = window_start + window_seconds / ratio

    return ratio, exhaust_at


def render_window(label, window, window_seconds, now):
    """One rate-limit window as a coloured segment, with projection."""
    if not window:
        return paint(DIM, f"{label} --")

    used = window.get("used_percentage")
    resets_at = window.get("resets_at")
    if used is None:
        return paint(DIM, f"{label} --")

    segment = paint(severity(used), f"{label} {used:.0f}%")
    if resets_at:
        segment += paint(DIM, f" · resets {reset_label(resets_at, now)}")

    ratio, exhaust_at = pace(used, resets_at, window_seconds, now)
    if ratio is None:
        return segment

    if exhaust_at:
        # Loud, and only when acting on it saves you something.
        segment += paint(RED, f" ▸{ratio:.1f}× dry {clock(exhaust_at)}")
    elif ratio >= PACE_WARN:
        # Over pace, but not yet enough to run dry meaningfully early.
        # Shown quietly, and never before MIN_ELAPSED has passed.
        segment += paint(YELLOW, f" ▸{ratio:.1f}×")

    return segment


# --- host CPU/RAM (shared with the Starship prompt and the SwiftBar menu bar) --


SYSUSAGE = os.path.expanduser("~/.local/bin/sysusage")


def render_sys():
    """A `cpu N% ram N%` segment from the shared sysusage script, or None.

    The prompt can't show host stats (fish/Starship isn't rendering here), so we
    ask the same script Starship and SwiftBar use. Shelling out keeps the two
    scripts decoupled; the timeout guarantees a hung read never stalls the line.
    """
    try:
        out = subprocess.run(
            [SYSUSAGE, "--json"], capture_output=True, text=True, timeout=1.0
        ).stdout
        stats = json.loads(out)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None

    cpu, gpu, ram = stats.get("cpu"), stats.get("gpu"), stats.get("ram")

    def seg(label, v):
        return paint(severity(v), f"{label} {v}%") if v is not None else None

    parts = [p for p in (seg("CPU", cpu), seg("GPU", gpu), seg("RAM", ram)) if p]
    return "  ".join(parts) if parts else None


# --- claude seat ------------------------------------------------------------
#
# Which account is answering? Claude Code picks it with CLAUDE_CONFIG_DIR, an
# environment variable — invisible, sticky across a `cd`, and wrong exactly where
# being wrong is expensive: company work billed to a personal subscription, or
# personal work filed into an employer's transcripts.
#
# The check mirrors the git identity one directly below it. A folder covered by an
# `includeIf gitdir:` rule is a company folder BY GIT'S OWN RULES, so the seat's
# account is expected to match that folder's commit email. No identity, folder or
# employer is named here; a second employer works the day it is added (ADR 0001).

SEAT_GLYPH = "◈"

# Every verdict the seat segment can reach, and how each one renders.
#
# One row per verdict, so a new verdict is a row here plus the branch that
# returns it. It used to be five edits in three files — the colour map, the label
# append, the swatch's special case, and a list in the test — and four of those
# were places you could forget.
#
#   colour  the escape code
#   badge   a word appended to the label, or None
#   asserts what the colour is CLAIMING, as one of the constants below. Two
#           states may share a colour exactly when they assert the same claim,
#           and must not otherwise.
#
# The claims are NAMES, not the sentences they hold. Grouping on the prose would
# mean that rewording one of two matching strings silently splits the group, and
# from then on divergent colours pass green — the failure ADR 0014 exists to
# prevent, reached through the key instead of the code. A typo in a name is a
# NameError; a typo in a sentence is a bug that waits.
CLAIM_INTENDED = "the seat answering is the intended one"
CLAIM_WRONG = "I know this is wrong"
CLAIM_UNCHECKABLE = "I cannot check, and the seat is not the default"
CLAIM_NOTHING = "nothing to say"

SEAT_STATES = {
    # `verified` and `overridden` make the same claim about who ACTS — the seat
    # is the folder's in both — so they share a colour, and the badge says the
    # one thing the second adds: whose subscription the session was deliberately
    # put on. The slug is the marker's; "personal" is the only one there is.
    "verified":     {"colour": MAGENTA, "badge": None, "asserts": CLAIM_INTENDED},
    "overridden":   {"colour": MAGENTA, "badge": "PERSONAL PAYS", "asserts": CLAIM_INTENDED},
    "mismatch":     {"colour": RED, "badge": None, "asserts": CLAIM_WRONG},
    "unverifiable": {"colour": YELLOW, "badge": None, "asserts": CLAIM_UNCHECKABLE},
    "neutral":      {"colour": DIM, "badge": None, "asserts": CLAIM_NOTHING},
}


def default_seat_dir():
    """Where Claude keeps its credentials when nothing is routed.

    Named once: it is both what makes a seat "the default" and what a work
    folder's assignment is compared against to see whether it displaces
    anything, and those two had drifted into separate literals.
    """
    return os.path.expanduser("~/.claude")


def seat_dir():
    """(config dir, is_default, config file) for the seat this session is on.

    Proven empirically: Claude Code spawns the status line with the launching
    shell's environment intact — SHELL, TMUX and the shell-set PATH all arrive —
    so CLAUDE_CONFIG_DIR set in fish reaches us here.

    The config FILE is not simply `<config dir>/.claude.json`, and assuming it is
    reads the wrong file for the machine owner. Verified against Claude Code
    2.1.221 by pointing CLAUDE_CONFIG_DIR at an empty directory and watching what
    landed:

        CLAUDE_CONFIG_DIR set    ->  $CLAUDE_CONFIG_DIR/.claude.json
        CLAUDE_CONFIG_DIR unset  ->  ~/.claude.json   (a SIBLING of ~/.claude)

    So the file is keyed to whether the variable is set, while `is_default` is
    keyed to where it points — a directory explicitly set to ~/.claude is still
    the owner's seat, but its config lives at ~/.claude/.claude.json.
    """
    default = default_seat_dir()
    raw = os.environ.get("CLAUDE_CONFIG_DIR")
    if not raw:
        return default, True, os.path.expanduser("~/.claude.json")

    path = os.path.abspath(os.path.expanduser(raw))
    is_default = os.path.realpath(path) == os.path.realpath(default)
    return path, is_default, os.path.join(path, ".claude.json")


def seat_account(config_file):
    """(email, tier) the seat last logged in as, or (None, None).

    This is `oauthAccount` from the seat's own config file — 0.7 ms, and it
    tracks a re-login. It is NOT Keychain truth; `claude auth status` is, and
    that costs a Node cold start, which a line redrawn this often cannot pay.
    """
    try:
        with open(config_file, encoding="utf-8") as fh:
            account = json.load(fh).get("oauthAccount") or {}
    except (OSError, ValueError):
        return None, None

    tier = account.get("organizationType") or None
    if tier and tier.startswith("claude_"):
        tier = tier[len("claude_"):]
    return account.get("emailAddress") or None, tier


# The identity tool's generated routing map. Overridable so the test can stand
# up a synthetic machine; unset it resolves to the real one. Absent is normal —
# on a machine with no identity tool the seat falls back to the git comparison
# below, and everything here degrades to what it did before the map existed.
IDENTITY_MAP = os.environ.get("STATUSLINE_IDENTITY_MAP") or \
    os.path.expanduser("~/.config/identity/map.json")

# Set by `identity override <tool>` on the process it execs. It carries INTENT
# and nothing else — which seat is live is observed below, never taken from here.
OVERRIDE_MARKER = "IDENTITY_SEAT_OVERRIDE"

# What the override sets BESIDE the marker, since identity's ADR-0013: the seat
# stays the folder's, and this variable — Claude Code's own, ranking above the
# seat's stored login — carries the personal subscription's token. It is the
# observation that pairs with the marker: the token cannot say whose it is, so a
# marker alone is a claim, a token alone is someone's exported variable, and only
# the two together are an override. The name is the identity registry's (field
# 14); it is not in the routing map yet, so the one tool this segment reports
# carries the one name here.
PAYER_VAR = "CLAUDE_CODE_OAUTH_TOKEN"


def routing_map():
    """What `identity apply` generated, or None if there is no identity tool."""
    try:
        with open(IDENTITY_MAP, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def owning_identity(cwd, mapping):
    """The map entry whose work folder CONTAINS cwd — longest match — or None.

    Containment, not a git rule. A work folder is a directory, and its own root
    holds no repository: anything deciding by `includeIf gitdir:` calls that root
    unrouted while the folder plainly owns it, which is where the machine owner
    actually launches Claude for one of these clients.
    """
    if not mapping or not cwd:
        return None
    try:
        here = os.path.realpath(cwd)
    except OSError:
        return None
    best = None
    for ident in mapping.get("identities", []):
        folder = ident.get("work_folder")
        if not folder:
            continue
        folder = os.path.realpath(os.path.expanduser(folder))
        if here == folder or here.startswith(folder + os.sep):
            if best is None or len(folder) > len(best[0]):
                best = (folder, ident)
    return best[1] if best else None


def assigned_seat(ident):
    """The store this identity routes Claude to, or None if it routes none.

    Walked one key at a time rather than chained: the map is another tool's
    output, so any level may be absent on an older or partial one, and a walk
    that checks as it goes says "routes no seat" where a chain would raise.
    """
    node = ident or {}
    for key in ("tools", "claude", "env", "CLAUDE_CONFIG_DIR"):
        if not isinstance(node, dict):
            return None
        node = node.get(key)
    return node


def personal_slug(mapping):
    """The slug of the identity that is the complement of every work folder."""
    for ident in (mapping or {}).get("identities", []):
        if not ident.get("work_folder"):
            return ident.get("slug")
    return None


def folder_seat_state(config_dir, is_default, seat_email, ident, mapping):
    """The verdict inside a work folder, decided by the map rather than by git.

    Three cases the git comparison cannot reach, all of them real on this
    machine: a folder that routes NO seat (the personal one is correct there, by
    data); a declared override (correct by declaration); and the folder's own
    root, where there is no repo to compare against at all.
    """
    assigned = assigned_seat(ident)

    if assigned is None:
        # The identity routes git but no seat, so the default seat is the only
        # one there is. Reporting that as a mismatch was a false alarm, and a red
        # that cries wolf is a red that stops being read.
        return "verified" if is_default else "mismatch"

    assigned_dir = os.path.realpath(os.path.expanduser(assigned))
    # Does this folder route a seat OTHER than the default store? A folder that
    # assigns the default store displaces nothing, so there is nothing there to
    # override, and a marker must not be allowed to claim otherwise.
    displaces = assigned_dir != os.path.realpath(default_seat_dir())

    if is_default:
        if not displaces:
            return "verified"
        # The personal seat inside a folder that routes its own. Until identity's
        # ADR-0013 an override looked exactly like this and the marker was what
        # separated the two; now an override keeps the folder's seat, so this is
        # a routing fault whatever the marker says, and a marker that still
        # claims otherwise has outlived the mechanism it described.
        return "mismatch"

    if assigned_dir != os.path.realpath(config_dir):
        return "mismatch"

    # The right STORE is selected. That is not the same as it being logged into
    # the right account, and the difference is the whole point of the segment: a
    # routed directory signed into someone else's account is the failure this is
    # meant to catch, and comparing paths alone would call it verified.
    expected = (ident or {}).get("email")
    if not seat_email or not expected:
        return "unverifiable"
    if seat_email.casefold() != expected.casefold():
        return "mismatch"

    # The right seat, signed into the right account. Whether it is also the one
    # PAYING is the one thing the seat cannot say: an override keeps this seat
    # and sets the payer variable beside the marker. Both, and only both — the
    # marker without the variable has outlived its process, and the variable
    # without the marker is someone's exported token, which identity's own
    # `check` reports as the hazard it is.
    declared = os.environ.get(OVERRIDE_MARKER)
    if declared and declared == personal_slug(mapping) and os.environ.get(PAYER_VAR):
        return "overridden"
    return "verified"


def seat_state(is_default, seat_email, git):
    """The verdict OUTSIDE every declared work folder, and the fallback when
    there is no routing map at all. See SEAT_STATES; `overridden` is not
    reachable from here, since nothing outside a work folder displaces a seat."""
    in_repo = bool(git and git.get("branch"))

    if not in_repo:
        # Routing is defined on git directories, so there is nothing to compare
        # against — but a named seat out here is still worth marking.
        return "neutral" if is_default else "unverifiable"

    if not git.get("identity_routed"):
        # A personal folder. The machine owner belongs here; anyone else is
        # burning an employer's tokens on work that isn't theirs.
        return "neutral" if is_default else "mismatch"

    git_email = git.get("identity_email")
    if not seat_email or not git_email:
        return "unverifiable"
    return "verified" if seat_email.casefold() == git_email.casefold() else "mismatch"


def seat_label(config_dir, is_default, email, tier):
    """What the segment reads. The account, or the directory when it can't be read."""
    if email:
        return f"{email} · {tier}" if tier else email

    # No readable account: name the seat by its directory instead, so a broken
    # read looks like a broken read rather than like an absent feature.
    if is_default:
        return "personal"
    return os.path.basename(config_dir).removeprefix(".claude-")


def render_seat(git, cwd):
    """(painted segment, colour) for the head of line two.

    Inside a work folder the map decides, because it knows two things git cannot:
    which folders route a seat at all, and where the folder's own root begins.
    Everywhere else — and on any machine with no identity tool, where the map is
    simply absent — the git comparison is still the answer.
    """
    config_dir, is_default, config_file = seat_dir()
    email, tier = seat_account(config_file)

    mapping = routing_map()
    ident = owning_identity(cwd, mapping)
    state = (folder_seat_state(config_dir, is_default, email, ident, mapping)
             if ident is not None else seat_state(is_default, email, git))

    label = seat_label(config_dir, is_default, email, tier)
    badge = SEAT_STATES[state]["badge"]
    if badge:
        # The colour says the seat is the intended one; the badge says how that
        # was established. Appended after the account and its tier, which are one
        # fact about one account and should not be split by a word about routing.
        label += f" · {badge}"
    color = SEAT_STATES[state]["colour"]
    return paint(color, f"{SEAT_GLYPH} {label}"), color


# --- git context (shared with the CLI `whereami` command) -------------------


WHEREAMI = os.path.expanduser("~/.local/bin/whereami")


def whereami(cwd):
    """The current dir's git context via the shared `whereami` script, or None.

    Run IN the session's cwd (not the statusline process's), with a timeout so a
    slow git call in a giant repo drops the git segment for one render rather
    than stalling the prompt. Same shell-out contract as render_sys()/sysusage.
    """
    try:
        out = subprocess.run(
            [WHEREAMI, "--json"],
            cwd=cwd or None,
            capture_output=True,
            text=True,
            timeout=1.0,
        ).stdout
        return json.loads(out)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def render_path(path, repo):
    """The display path, dim, with the repo's own segment left at normal weight.

    A path anchored on the owning repo is long — `projects/webapp/.worktrees/
    feature` — and uniformly dim it reads as one grey run in which the repo is
    exactly as findable as the scaffolding around it. Undimming that one segment
    gives the eye somewhere to land.

    Deliberately no colour: every hue in this file already carries a meaning
    (see SEAT_STATES), and a second meaning for any of them would cost more than
    this is worth. Normal-vs-dim is the one axis still free.
    """
    if not repo:
        return paint(DIM, path)

    segments = path.split("/")
    if repo not in segments:
        return paint(DIM, path)

    i = segments.index(repo)
    before, after = "/".join(segments[:i]), "/".join(segments[i + 1:])

    out = paint(DIM, before + "/") if before else ""
    out += repo
    if after:
        out += paint(DIM, "/" + after)
    return out


def render_git(info, seat_color):
    """`branch* ☉ identity` for the tail of line two, or None outside a repo.

    Branch, tree state and committing identity all answer one question — what
    am I about to write, and as whom? — so they trail the path on a single
    line. The `*` marks a dirty tree; the identity turns red on a mismatch,
    meaning you're about to commit as an identity the folder's includeIf
    routing says is wrong (whereami computes this).

    The identity carries the SEAT's colour, so the two ends of the line either
    agree or both shout. Two independent faults share this one colour slot — a
    git mismatch (includeIf didn't fire) and a seat mismatch (wrong account) —
    so the git one wins. Both are red, so nothing is ever lost: the older alarm
    keeps working and the seat signal layers underneath it.
    """
    branch = info.get("branch")
    if not branch:
        return None

    seg = paint(CYAN, branch)
    if info.get("dirty"):
        seg += paint(YELLOW, "*")
    if info.get("worktree"):
        # Only shown inside a linked `git worktree` checkout, not the main tree.
        seg += paint(DIM, " ⎇ worktree")

    identity = info.get("identity")
    if identity:
        color = RED if info.get("identity_mismatch") else seat_color
        seg += "  " + paint(color, f"☉ {identity}")
    return seg


# --- logging ----------------------------------------------------------------


def should_log(now):
    try:
        return now - os.path.getmtime(STAMP_PATH) >= LOG_THROTTLE_SECONDS
    except OSError:
        return True


def log_sample(data, now):
    """Append a throttled sample. Never let logging break the status line."""
    if not should_log(now):
        return
    try:
        rate = data.get("rate_limits") or {}
        ctx = data.get("context_window") or {}
        sample = {
            "ts": int(now),
            "session_id": data.get("session_id"),
            "model": (data.get("model") or {}).get("id"),
            "context_used_pct": ctx.get("used_percentage"),
            "five_hour": rate.get("five_hour"),
            "seven_day": rate.get("seven_day"),
        }
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(sample) + "\n")
        with open(STAMP_PATH, "w") as fh:
            fh.write(str(int(now)))
    except OSError:
        pass


# --- main -------------------------------------------------------------------


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    now = time.time()
    log_sample(data, now)

    model = (data.get("model") or {}).get("display_name", "?")
    effort = (data.get("effort") or {}).get("level")
    ctx = data.get("context_window") or {}
    rate = data.get("rate_limits") or {}

    cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd")
    git = whereami(cwd)

    # Line two: which account is answering, who am I talking to, how hard is it
    # thinking, and where does it stand — path, branch, tree state, identity.
    # The seat leads because it is the fact you cannot otherwise see.
    seat_seg, seat_color = render_seat(git, cwd)
    head = seat_seg + "  " + paint(BOLD, model)
    if effort:
        head += paint(DIM, f" · {effort}")

    # Prefer whereami's richer location (repo/within-path); fall back to the bare
    # leaf name if the shell-out failed or we're outside any repo.
    path = (git or {}).get("path")
    if not path and cwd:
        path = os.path.basename(cwd)
    if path:
        head += "  " + render_path(path, (git or {}).get("repo"))

    # …then the branch, tree state and identity, completing the "where and whom".
    if git:
        git_seg = render_git(git, seat_color)
        if git_seg:
            head += "  " + git_seg

    # Line one: the meters, side by side.
    ctx_pct = ctx.get("used_percentage")
    if ctx_pct is None:
        ctx_seg = paint(DIM, f"context {bar(None)} --")
    else:
        ctx_seg = paint(severity(ctx_pct), f"context {bar(ctx_pct)} {ctx_pct:.0f}%")
        if data.get("exceeds_200k_tokens"):
            ctx_seg += paint(YELLOW, " ⚠")

    five = render_window("5-hour", rate.get("five_hour"), FIVE_HOURS, now)
    week = render_window("7-day", rate.get("seven_day"), SEVEN_DAYS, now)

    # Wider gap between groups so the within-window " · resets …" reads as detail
    # belonging to its window, not as another top-level meter.
    sep = paint(DIM, "  ·  ")
    meters = [ctx_seg, five, week]
    sys_seg = render_sys()
    if sys_seg:
        meters.append(sys_seg)

    lines = [sep.join(meters), head]

    # A dim horizontal rule between rows, sized to the widest line. Claude Code's
    # TUI trims blank/whitespace-only rows, so a visible rule — not empty space —
    # is what actually renders as separation: a light border between the lines. A
    # closing rule after the last line gives the head line a divider beneath it too.
    width = max((visible_len(line) for line in lines), default=0)
    rule = paint(DIM, "─" * width)
    print(("\n" + rule + "\n").join(lines) + "\n" + rule)


if __name__ == "__main__":
    main()
