#!/usr/bin/env bash
# macOS system defaults. NOT a stow package: these values live in cfprefsd-managed
# plists, which macOS rewrites in place and caches in a running daemon. A symlinked
# plist is replaced by a real file on the first write and silently detaches from the
# repo — the same failure mode already documented for claude/settings.json and the
# Obsidian vault configs. So the repo asserts them imperatively instead.
#
# Idempotent: only writes when the current value differs, so re-running ./install is
# cheap and reports nothing when the machine already matches.
set -euo pipefail

[ "$(uname)" = "Darwin" ] || { echo "skip: macos/defaults.sh is macOS-only"; exit 0; }

changed=0

# Write only if the value actually differs, so repeat runs stay quiet.
set_default() { # $1=domain  $2=key  $3=type  $4=value
  local current want="$4"
  # `defaults read` renders booleans as 0/1, never true/false, so normalise the
  # expected value before comparing — otherwise every -bool key rewrites on every run
  # and reports a change that did not happen.
  if [ "$3" = "-bool" ]; then
    case "$want" in true | yes | YES | 1) want=1 ;; *) want=0 ;; esac
  fi
  current="$(defaults read "$1" "$2" 2>/dev/null || true)"
  [ "$current" = "$want" ] && return 0
  defaults write "$1" "$2" "$3" "$4"
  echo "set: $2 = $4 (was ${current:-unset})"
  changed=1
}

# ---------------------------------------------------------------------------
# Key repeat
#
# Units are 1/60 s, so 15 = 250 ms and 25 = 417 ms.
#
# InitialKeyRepeat is the one value here that is load-bearing for correctness, not
# taste. macOS's "Delay Until Repeat" slider bottoms out at 15 (250 ms), and at that
# setting an ordinary finger-rest crosses the repeat threshold: any key held ~300-650 ms
# — well within normal typing, especially mid-thought — starts auto-repeating. Combined
# with KeyRepeat=2 below that is 30 chars/sec, so every extra 100 ms of hold costs three
# characters and a half-second rest yields bursts like "loccccccccccccal". Burst length
# varies with hold time, which is why it reads as random.
#
# 25 (417 ms) sits above normal keystroke duration but still well under the macOS
# default of 68 (1133 ms), so hold-to-repeat stays usable for cursor movement.
# Do not lower this back to 15.
set_default NSGlobalDomain InitialKeyRepeat -int 25

# Repeat *rate* once repeating has started. 2 (33 ms, 30 chars/sec) is the fastest
# macOS allows and is deliberate — it makes held-key navigation fast. It is safe only
# because InitialKeyRepeat above gates when repeating may begin at all.
set_default NSGlobalDomain KeyRepeat -int 2

# Press-and-hold shows the accent picker (é, ç, ñ …) instead of repeating. Disabled
# deliberately so held keys repeat everywhere, which VSCodeVim/Vim motions rely on for
# j/k — see the VSCodeVim README, which is where this setting originally came from.
#
# Worth knowing: this is what lets the repeat bug reach accent-capable keys. With the
# picker enabled, a, c, e, i, o, n, s, u, y and friends never repeat, so they are immune.
# Turning it off removes that safety net from exactly those keys, which is why the vowels
# were the loudest offenders. Keeping it off is a deliberate trade, paid for by the
# InitialKeyRepeat floor above.
set_default NSGlobalDomain ApplePressAndHoldEnabled -bool false

# ---------------------------------------------------------------------------
# Desktops
#
# Window slots address a window by asking the Accessibility interface for it, and
# that interface reports only the Desktop that is active right now — a window one
# Desktop away is absent, not merely slower to reach (ADR 0009). So the slots
# assume a single Desktop, and a Desktop order that reshuffles itself underneath
# that assumption is exactly the positional instability the slots exist to escape.
#
# Off by default here, on by default in macOS, so this line is load-bearing.
mru_before="$(defaults read com.apple.dock mru-spaces 2>/dev/null || true)"
set_default com.apple.dock mru-spaces -bool false
if [ "$mru_before" != "0" ]; then
  killall Dock 2>/dev/null || true
  echo "restarted Dock to apply mru-spaces"
fi

# ---------------------------------------------------------------------------
# Rectangle window gaps
#
# 30 is not taste: it is this display's menu bar height (measured via System
# Events at the 1920x1080 looks-like scaling), so a snapped window keeps the same
# breathing room on every edge that the menu bar imposes on top. Re-measure
# before changing displays/scaling: osascript -e 'tell application "System
# Events" to get size of menu bar 1 of application process "Finder"'.
#
# gapSize is Rectangle's "Gaps between windows" and by default it also applies
# to Maximize (Rectangle's TerminalCommands.md) — that behaviour is the point
# here, so never set applyGapsToMaximize. Rectangle reads gapSize at launch,
# hence the restart when the value moves.
gap_before="$(defaults read com.knollsoft.Rectangle gapSize 2>/dev/null || true)"
set_default com.knollsoft.Rectangle gapSize -float 30
if [ "$gap_before" != "30" ]; then
  killall Rectangle 2>/dev/null || true
  sleep 1
  open -a Rectangle 2>/dev/null || true
  echo "restarted Rectangle to apply gapSize"
fi

if [ "$changed" -eq 1 ]; then
  echo "NOTE: key repeat changes apply to newly launched apps; log out and back in for a full effect."
fi
