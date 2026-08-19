# tmux-picker-lib.sh — the plumbing shared by the popup pickers.
#
# Sourced, not executed. tmux-open-md and tmux-open-path both open a popup, both
# resolve a pane's directory, both hold the box open to say something, and both
# have to tell "the user pressed Escape" apart from "the picker broke". Those
# four things were written out twice, in the same change that extracted tmux-edit
# so that the two keys could not drift — which is the argument for extracting
# these too.
#
# tmux-open-url deliberately does NOT source this. Its clipboard path has no test
# and it was repaired recently; converging it is worth doing once that path is
# covered, and not before.

# ---------------------------------------------------------------------------
# THE LOG.
#
# A popup is a bad place to read a diagnosis from: it is gone by the time anyone
# thinks to look, and asking the person at the keyboard to reproduce a failure
# with tracing turned on is asking them to do the debugging. So every run leaves
# a record, and the record is what gets read afterwards.
#
# NOTHING HERE MAY EVER BREAK A PICKER. Under `set -e` a failed write is
# indistinguishable from a real error, so every step is guarded and the function
# always returns success. A picker that dies because its logging failed would be
# a fourth entry in the list of silent deaths this exists to end.
PICKER_LOG_FILE="${TMUX_PICKER_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-pickers/picker.log}"
PICKER_LOG_MAX_BYTES="${TMUX_PICKER_LOG_MAX_BYTES:-262144}"

picker_log() { # <event> [detail...]
  local event="${1:-}" file="$PICKER_LOG_FILE" size
  shift 2>/dev/null || true
  [ -n "$event" ] || return 0

  mkdir -p "${file%/*}" 2>/dev/null || return 0

  # One generation kept. An unbounded file in a directory nobody prunes is a
  # slow leak, and nobody reads further back than the last run anyway.
  size="$(wc -c < "$file" 2>/dev/null || echo 0)"
  size="${size// /}"
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -ge "$PICKER_LOG_MAX_BYTES" ]; then
    mv -f "$file" "$file.1" 2>/dev/null || true
  fi

  printf '%s %s[%s] %s %s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo unknown-time)" \
    "${0##*/}" "$$" "$event" "$*" >> "$file" 2>/dev/null || true
  return 0
}

# Hold the popup open long enough for a message to be read. Without it the popup
# closes the instant it opens and nothing is ever seen, which is indistinguishable
# from the key doing nothing at all.
#
# `|| true` because a `read` that reaches EOF — no tty, stdin closed, a test
# harness — returns non-zero, and under `set -e` that would kill the script on the
# line whose entire job is to keep it alive.
picker_hold() { read -r -n 1 -s -p "press any key" || true; }

# The directory of the pane the key was pressed in.
#
# EMPTY IS THE FAILURE MODE HERE, not a non-zero exit. `display-message` asked
# about a pane that does not exist answers with exit 0 and an empty string, so a
# guard testing only the status lets an empty directory through — and an empty
# directory is not inert: `git -C "" rev-parse` falls back to the CURRENT one, so
# a picker quietly lists a different repo than the one you pressed the key in.
# Measured, against the literal `#{pane_id}` an unexpanded binding delivers.
picker_pane_dir() { # <pane-id>  ->  prints the directory, or fails with a message
  local dir
  dir="$(tmux display-message -p -t "$1" '#{pane_current_path}' 2>/dev/null || true)"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    printf 'cannot read pane %s\n' "$1"
    return 1
  fi
  printf '%s' "$dir"
}

# `bat` where it exists, `head` otherwise. This is fzf integration — the
# interactive layer ADR 0003 puts the rust tools at — rather than a script piping
# identical bytes through a second process, which is the case that ADR declined.
picker_preview_command() { # <field>  ->  a command string for --preview
  if command -v bat >/dev/null 2>&1; then
    printf 'bat --color=always --style=numbers --line-range=:200 -- %s' "$1"
  else
    printf 'head -200 -- %s' "$1"
  fi
}

# ---------------------------------------------------------------------------
# SAYING SOMETHING, ALWAYS.
#
# A picker runs inside a popup, so a script that dies without printing takes the
# box down with it and the key simply looks broken. That has happened three times
# in this feature, for three unrelated reasons — `grep` matching nothing,
# `display-message` returning empty, `find` refusing a directory — and each was
# found by a person pressing a key rather than by a test.
#
# The specific guards for those three are all in place. This is the different
# kind of defence: whatever the FOURTH reason turns out to be, it will announce
# itself instead of vanishing. It cannot prevent the bug; it converts it from
# invisible into reported, which is the difference between "the key is broken"
# and a line naming the script and its exit status.
_PICKER_EXPLAINED=0

# Fail with a reason the user can read. Everything that knows why it is stopping
# should come through here, so the last-resort trap below stays silent for it.
#
# NO HOLD, deliberately. The bindings use `display-popup -EE`, which keeps the
# popup open precisely when the command exits non-zero — so the message is
# already going to stay on screen, and holding as well would cost a second
# keypress to dismiss. The division is: a message with a ZERO exit has to hold
# (success closes the popup), a message with a non-zero exit must not.
picker_fail() { # <message...>
  _PICKER_EXPLAINED=1
  picker_log failed "$*"
  printf '%s\n' "$*"
  exit 1
}

_picker_on_exit() { # <status>
  picker_log exit "status=$1 explained=${_PICKER_EXPLAINED:-0}"
  [ "$1" -eq 0 ] && return 0
  [ "${_PICKER_EXPLAINED:-0}" -eq 1 ] && return 0
  printf '%s exited %s with nothing to show for it — this is a bug in the picker, not in your files\n' \
    "${0##*/}" "$1"
}

picker_explain_unexpected_exit() { trap '_picker_on_exit $?' EXIT; }

# fzf's exit status, TRIAGED rather than blanket-ignored. A bare `|| exit 0`
# reads "the user pressed Escape" into every possible failure, including fzf
# being absent — and a popup that exits 0 for that is a box that opens and shuts
# with no explanation, which is the shape of the outage this repo already had
# once. 130 is Escape or C-c and 1 is an empty selection: both are the user
# declining, and both leave quietly.
picker_triage_fzf() { # <exit status>  ->  0 to continue, or exits
  case "$1" in
    0)     return 0 ;;
    1|130) exit 0 ;;
    127)   picker_fail "fzf is not installed, so there is nothing to pick with" ;;
    *)     picker_fail "the picker failed (exit $1)" ;;
  esac
}
