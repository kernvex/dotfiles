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
    127)   echo "fzf is not installed, so there is nothing to pick with"; picker_hold; exit 1 ;;
    *)     printf 'the picker failed (exit %s)\n' "$1"; picker_hold; exit 1 ;;
  esac
}
