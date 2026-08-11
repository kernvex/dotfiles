# Claude Session Revival Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a tmux server death, one keypress in any restored pane resumes the exact Claude Code conversation that pane held; window names and Claude session titles become one handle.

**Architecture:** A Claude Code SessionStart hook stamps each session's UUID onto its tmux pane and into an append-only log; a resurrect post-save hook joins pane UUIDs to window coordinates in a manifest at every continuum autosave; `prefix+r` resolves the current pane through manifest → cwd-match → picker-hint and types `claude --resume <uuid>` at the prompt. A tmux `after-rename-window` hook pushes deliberate window names into Claude via `/rename` with per-project uniqueness suffixing; never-named windows display Claude's live title via `automatic-rename-format`.

**Tech Stack:** bash, tmux 3.7c (local jemalloc build), tmux-resurrect v4.0.0 (pinned), python3 (stdlib json only), Claude Code ≥ 2.1.223.

**Spec:** `docs/superpowers/specs/2026-08-11-claude-session-revival-design.md` (GitHub issue #1).

## Global Constraints

- Scripts live in `bin/.local/bin/`, self-contained, bash, executable, lowercase-dash names — repo convention.
- State dir: `$HOME/.local/state/claude-tmux/` containing `sessions.log` (append-only TSV) and `manifest.tsv` (rewritten atomically). All writes tmp+`mv`.
- `sessions.log` columns (tab-separated): `epoch  pane_id  uuid  cwd  session:win.pane  window_name`.
- `manifest.tsv` columns (tab-separated): `session_name  window_index  pane_index  window_name  uuid  cwd  pane_title`.
- Claude-pane detector everywhere: `is_claude_cmd() { case "$1" in [0-9]*|claude) return 0;; *) return 1;; esac }` — the native binary is installed under its version number (see `.tmux.conf` automatic-rename comment); plain `claude` accepted for future-proofing.
- The SessionStart hook target must print NOTHING to stdout on success (stdout is injected into the session's context) and must ALWAYS exit 0 (a broken hook must never block a Claude launch).
- Tests: one script `bin/.local/bin/test-claude-tmux`, exit 0 = pass, exit status of the SUT asserted (prior art: `test-tmux-open-url` — its header documents the bug that output-only assertions shipped). Scratch tmux server on a private socket, scratch `$HOME`, mock claude named `2.1.999` so the digit detector matches it. **Fixture names must be generic** — the identity pre-commit hook rejects client names, and this repo is public.
- The live tmux server is never killed by any task. Live-server changes are additive commands, verified non-destructively.
- Commit style: `type(scope): lowercase summary`, body explains why, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File Structure

| File | Responsibility |
|---|---|
| `bin/.local/bin/claude-tmux-track` (create) | SessionStart hook target: stamp pane options, append log line, kick the naming push for deliberately-named windows |
| `bin/.local/bin/claude-tmux-name` (create) | Sanitize + uniqueness-resolve a name (pure seam behind `--resolve-name`), rename the window, deliver `/rename` with verification |
| `bin/.local/bin/claude-tmux-manifest` (create) | Join `@claude_session` pane options to coordinates, write `manifest.tsv` atomically |
| `bin/.local/bin/claude-tmux-revive` (create) | `prefix+r` target: manifest → cwd → hint ladder, type the resume command |
| `bin/.local/bin/test-claude-tmux` (create) | All tests, both seams |
| `tmux/.tmux.conf` (modify) | `r`/`R` flip, `after-rename-window` hook, `automatic-rename-format` title fallback, `@resurrect-hook-post-save-all` |
| `claude/.claude/settings.json` (modify, via `claude-settings-sync`) | Register the SessionStart hook |
| `README.md` (modify) | Binding table row for `prefix r`/`R` |

---

### Task 1: `claude-tmux-track` + test harness scaffolding

**Files:**
- Create: `bin/.local/bin/claude-tmux-track`
- Create: `bin/.local/bin/test-claude-tmux`

**Interfaces:**
- Consumes: SessionStart hook JSON on stdin (`{"session_id": "...", "cwd": "...", ...}`), `$TMUX`, `$TMUX_PANE`.
- Produces: pane options `@claude_session` (UUID) and `@claude_cwd` (absolute path) on `$TMUX_PANE`; one appended `sessions.log` line per invocation (columns per Global Constraints). Later tasks read exactly these.

- [ ] **Step 1: Write the failing tests**

Create `bin/.local/bin/test-claude-tmux`:

```bash
#!/usr/bin/env bash
# Tests for the claude-tmux-* quartet.
#
#   ./test-claude-tmux     exit 0 = pass
#
# Two seams, per the spec:
#   1. A real scratch tmux server on a private socket with a scratch $HOME —
#      every script driven through its production entry point (hook JSON on
#      stdin, tmux-hook invocation, keybinding invocation). Claude is mocked
#      at the process boundary only: a shim named "2.1.999" (the digit
#      detector matches it, same as the real version-numbered binary) that
#      answers /rename by emitting the OSC 2 title escape.
#   2. The pure --resolve-name seam: text in, text out, no tmux (Task 2).
#
# EXIT STATUS IS ASSERTED, not just output — same lesson test-tmux-open-url's
# header records.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCK="claude-tmux-test-$$"
PASS=0; FAIL=0

T() { command tmux -L "$SOCK" "$@"; }

ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then ok; else
    fail "$1"; printf '        want: %s\n        got:  %s\n' "$2" "$3"
  fi
}

assert_exit() { # <desc> <want-code> <got-code>
  if [ "$2" -eq "$3" ]; then ok; else
    fail "$1 (exit)"; printf '        want exit %s, got %s\n' "$2" "$3"
  fi
}

setup() {
  SCRATCH="$(mktemp -d /tmp/claude-tmux-test.XXXXXX)"
  SHIM="$SCRATCH/bin"; mkdir -p "$SHIM"
  # Mock claude. Named 2.1.999 so #{pane_current_command} starts with a digit,
  # exactly like the real native binary.
  cat > "$SHIM/2.1.999" <<'MOCK'
#!/usr/bin/env bash
while IFS= read -r line; do
  case "$line" in
    "/rename "*) printf '\033]2;%s\033\\' "${line#/rename }";;
    quit) exit 0;;
  esac
done
MOCK
  chmod +x "$SHIM/2.1.999"
  T kill-server 2>/dev/null; sleep 0.2
  T -f /dev/null new-session -d -s main -x 120 -y 30 bash || {
    echo "cannot start scratch server"; exit 1; }
  SOCKPATH="$(T display -p '#{socket_path}')"
  sleep 0.3
}

teardown() {
  T kill-server 2>/dev/null
  rm -rf "$SCRATCH"
}

# Run a SUT the way production runs it: scratch HOME, scratch server.
sut() { # <script> [args...] — reads stdin
  HOME="$SCRATCH" TMUX="$SOCKPATH,0,0" TMUX_PANE="${SUT_PANE:-}" \
    PATH="$SHIM:$PATH" "$HERE/$@"
}

hook_json() { # <uuid> <cwd>
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart"}' "$1" "$2"
}

# ---------------------------------------------------------------------------
# claude-tmux-track
# ---------------------------------------------------------------------------
t_track_stamps_pane_and_log() {
  local pane out code uuid="11111111-2222-3333-4444-555555555555"
  pane="$(T display -p -t main '#{pane_id}')"
  out="$(hook_json "$uuid" /tmp/projA | SUT_PANE="$pane" sut claude-tmux-track)"; code=$?
  assert_exit "track exits 0" 0 "$code"
  assert_eq "track is silent on success" "" "$out"
  assert_eq "track stamps @claude_session" "$uuid" \
    "$(T show -pv -t "$pane" @claude_session 2>/dev/null)"
  assert_eq "track stamps @claude_cwd" "/tmp/projA" \
    "$(T show -pv -t "$pane" @claude_cwd 2>/dev/null)"
  local line
  line="$(tail -1 "$SCRATCH/.local/state/claude-tmux/sessions.log")"
  assert_eq "log line carries uuid" "$uuid" "$(printf '%s' "$line" | cut -f3)"
  assert_eq "log line carries cwd" "/tmp/projA" "$(printf '%s' "$line" | cut -f4)"
}

t_track_no_tmux_is_noop() {
  local code
  hook_json aaaa /tmp/x | HOME="$SCRATCH" TMUX= TMUX_PANE= \
    "$HERE/claude-tmux-track" >/dev/null; code=$?
  assert_exit "track outside tmux exits 0" 0 "$code"
}

t_track_bad_json_is_noop() {
  local pane code
  pane="$(T display -p -t main '#{pane_id}')"
  T set -pu -t "$pane" @claude_session 2>/dev/null
  printf 'not json at all' | SUT_PANE="$pane" sut claude-tmux-track >/dev/null; code=$?
  assert_exit "track with bad json exits 0" 0 "$code"
  assert_eq "bad json stamps nothing" "" \
    "$(T show -pv -t "$pane" @claude_session 2>/dev/null)"
}

main() {
  setup
  trap teardown EXIT
  t_track_stamps_pane_and_log
  t_track_no_tmux_is_noop
  t_track_bad_json_is_noop
  printf '%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
main
```

Make it executable: `chmod +x bin/.local/bin/test-claude-tmux`

- [ ] **Step 2: Run tests, verify they fail**

Run: `bin/.local/bin/test-claude-tmux`
Expected: FAIL — `claude-tmux-track` does not exist (sut invocation errors, exit assertions fail).

- [ ] **Step 3: Implement `claude-tmux-track`**

Create `bin/.local/bin/claude-tmux-track`:

```bash
#!/usr/bin/env bash
# claude-tmux-track — SessionStart hook target: stamp the session's identity
# onto the tmux pane it runs in, and append it to the on-disk map.
#
# Registered in ~/.claude/settings.json (copy-managed; see claude/README.md).
# Claude pipes the hook input JSON to stdin; session_id and cwd are the two
# fields used. Resume reuses the original session id, so re-stamping on every
# start/resume is what keeps the map self-healing.
#
# Contract (spec): print NOTHING to stdout on success — SessionStart stdout is
# injected into the session's context. ALWAYS exit 0 — a broken hook must
# never block a claude launch. No-op outside tmux. Errors land in hook.err.
set -u

STATE="$HOME/.local/state/claude-tmux"
LOG="$STATE/sessions.log"
mkdir -p "$STATE" 2>/dev/null || exit 0

main() {
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  command -v tmux >/dev/null 2>&1 || return 0

  local json sid cwd
  json="$(cat 2>/dev/null)" || return 0
  # python3, not jq: jq is not a dependency anywhere else in this repo.
  IFS="$(printf '\t')" read -r sid cwd < <(printf '%s' "$json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("session_id", ""), d.get("cwd", ""), sep="\t")' 2>/dev/null) || true
  [ -n "${sid:-}" ] || return 0

  tmux set -p -t "$TMUX_PANE" @claude_session "$sid" 2>/dev/null || return 0
  tmux set -p -t "$TMUX_PANE" @claude_cwd "${cwd:-}" 2>/dev/null

  local meta
  meta="$(tmux display -p -t "$TMUX_PANE" \
    "#{session_name}:#{window_index}.#{pane_index}$(printf '\t')#{window_name}" \
    2>/dev/null)" || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$TMUX_PANE" "$sid" "${cwd:-}" "$meta" \
    >> "$LOG" 2>/dev/null

  # Opportunistic trim: let the log double its budget, then keep the tail.
  local n
  n="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -gt 2000 ]; then
    tail -1000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
  return 0
}

main >/dev/null 2>>"$STATE/hook.err" || true
exit 0
```

Make it executable: `chmod +x bin/.local/bin/claude-tmux-track`

- [ ] **Step 4: Run tests, verify they pass**

Run: `bin/.local/bin/test-claude-tmux`
Expected: `3 tests: … 0 failed`, exit 0. (PASS count is per-assertion; expect ~9 passed.)

- [ ] **Step 5: Commit**

```bash
git add bin/.local/bin/claude-tmux-track bin/.local/bin/test-claude-tmux
git commit -m "feat(bin): claude-tmux-track stamps session identity onto its pane"
```

---

### Task 2: `claude-tmux-name` — the pure `--resolve-name` seam

**Files:**
- Create: `bin/.local/bin/claude-tmux-name` (resolve mode only; delivery added in Task 3)
- Modify: `bin/.local/bin/test-claude-tmux` (add pure-seam cases)

**Interfaces:**
- Consumes: `--resolve-name <raw-name>` argument; taken names one-per-line on stdin.
- Produces: the sanitized, collision-free name on stdout, exit 0; exit 1 with empty output when the name sanitizes to nothing. Task 3 calls exactly `claude-tmux-name --resolve-name "$raw" <<< "$taken"`.

- [ ] **Step 1: Add failing pure-seam tests**

Add to `test-claude-tmux` before `main` (and call them from `main` after the track cases — they need no server, but run within the same harness):

```bash
# ---------------------------------------------------------------------------
# claude-tmux-name --resolve-name (pure seam: text in, text out, no tmux)
# ---------------------------------------------------------------------------
resolve() { # <raw> <taken newline-list>
  printf '%s' "$2" | "$HERE/claude-tmux-name" --resolve-name "$1"
}

t_resolve_sanitizes() {
  assert_eq "spaces and punctuation collapse to dashes" "auth-fix" \
    "$(resolve 'auth fix!' '')"
  assert_eq "dots and colons cannot survive into a tmux target" "v1_2-api" \
    "$(resolve 'v1.2:api' '')"
  assert_eq "runs of dashes collapse" "a-b" "$(resolve 'a---b' '')"
  assert_eq "edge dashes trim" "x" "$(resolve '--x--' '')"
}

t_resolve_walks_suffixes() {
  assert_eq "free name passes through" "auth" "$(resolve auth 'other')"
  assert_eq "taken name gets -2" "auth-2" "$(resolve auth 'auth')"
  assert_eq "suffix walks past taken suffixes" "auth-3" \
    "$(resolve auth "$(printf 'auth\nauth-2')")"
}

t_resolve_empty_fails() {
  local out code
  out="$(resolve '!!!' '')"; code=$?
  assert_exit "unsalvageable name exits 1" 1 "$code"
  assert_eq "unsalvageable name prints nothing" "" "$out"
}
```

- [ ] **Step 2: Run tests, verify the new cases fail**

Run: `bin/.local/bin/test-claude-tmux`
Expected: track cases pass; resolve cases FAIL (`claude-tmux-name` not found).

- [ ] **Step 3: Implement resolve mode**

Create `bin/.local/bin/claude-tmux-name`:

```bash
#!/usr/bin/env bash
# claude-tmux-name — one handle for a tmux window and the Claude session in it.
#
# Modes:
#   --resolve-name <raw>   pure seam: sanitize <raw>, read taken names (one
#                          per line) from stdin, print the first free name.
#                          Exit 1 if nothing sanitizes out. No tmux touched.
#   (delivery modes are added by the naming-harness task)
#
# Sanitising follows tmux-session-here exactly: tmux treats `.` and `:` as
# target-spec separators, so they become underscores; anything else outside
# [A-Za-z0-9_-] collapses to a dash; dash runs collapse; edge dashes trim.
# Collisions walk -2, -3, … — same convention as tmux-session-here's
# auto-numbered sibling sessions, never a prompt.
set -uo pipefail

sanitize() {
  local name="$1"
  name="$(printf '%s' "$name" | tr '.:' '__')"
  name="${name//[^A-Za-z0-9_-]/-}"
  while [[ $name == *--* ]]; do name="${name//--/-}"; done
  while [[ $name == -* ]]; do name="${name#-}"; done
  while [[ $name == *- ]]; do name="${name%-}"; done
  printf '%s' "$name"
}

resolve_name() { # <raw>; taken list on stdin
  local base taken candidate n
  base="$(sanitize "$1")"
  [ -n "$base" ] || return 1
  taken="$(cat)"
  candidate="$base"
  n=2
  while printf '%s\n' "$taken" | grep -qxF "$candidate"; do
    candidate="$base-$n"
    n=$((n + 1))
  done
  printf '%s\n' "$candidate"
}

case "${1:-}" in
  --resolve-name)
    [ $# -ge 2 ] || { echo "usage: claude-tmux-name --resolve-name <raw>" >&2; exit 2; }
    resolve_name "$2"
    ;;
  *)
    echo "usage: claude-tmux-name --resolve-name <raw>" >&2
    exit 2
    ;;
esac
```

Make it executable: `chmod +x bin/.local/bin/claude-tmux-name`

- [ ] **Step 4: Run tests, verify they pass**

Run: `bin/.local/bin/test-claude-tmux`
Expected: all assertions pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add bin/.local/bin/claude-tmux-name bin/.local/bin/test-claude-tmux
git commit -m "feat(bin): claude-tmux-name pure seam — sanitize + collision suffixes"
```

---

### Task 3: `claude-tmux-name` delivery + track's named-window kick

**Files:**
- Modify: `bin/.local/bin/claude-tmux-name` (add `--from-hook` / `--from-track` delivery)
- Modify: `bin/.local/bin/claude-tmux-track` (kick the push when the window was deliberately named)
- Modify: `bin/.local/bin/test-claude-tmux`

**Interfaces:**
- Consumes: Task 2's `resolve_name`; pane options from Task 1.
- Produces: `claude-tmux-name --from-hook '<session>:<window_index>'` (called by the tmux `after-rename-window` hook, Task 6) and `claude-tmux-name --from-track <pane_id>` (called by track). Both: resolve → rename window if needed → deliver `/rename <name>` → verify `#{pane_title}` ends with the name within 10s → one retry → exit 1 + `display-message` on failure. Window option `@claude_naming` is the re-entry guard Task 6's hook must respect implicitly (the harness checks it itself).

- [ ] **Step 1: Add failing delivery tests**

Add to `test-claude-tmux` (server-seam section), and register in `main`:

```bash
# ---------------------------------------------------------------------------
# claude-tmux-name delivery (mock claude answers /rename with an OSC title)
# ---------------------------------------------------------------------------
new_claude_window() { # <win-name> — window running the mock, returns pane id
  T new-window -t main -n "$1" -c "$SCRATCH" "PATH=$SHIM:$PATH 2.1.999"
  sleep 0.4
  T display -p -t "main:$1" '#{pane_id}'
}

t_name_pushes_window_name_as_title() {
  local pane code
  pane="$(new_claude_window pushme)"
  T rename-window -t main:pushme workname   # manual rename: automatic-rename off
  SUT_PANE="$pane" sut claude-tmux-name --from-hook "main:workname"; code=$?
  assert_exit "delivery exits 0" 0 "$code"
  # allow the title escape a moment to round-trip
  sleep 1
  assert_eq "session title became the window name" "workname" \
    "$(T display -p -t "$pane" '#{pane_title}')"
}

t_name_suffixes_and_renames_on_collision() {
  local pane code
  # another live window with the target name, rooted at the same cwd
  T new-window -t main -n depwork -c "$SCRATCH" bash
  pane="$(new_claude_window second)"
  T rename-window -t "main:second" depwork
  SUT_PANE="$pane" sut claude-tmux-name --from-hook "main:depwork"; code=$?
  assert_exit "collision delivery exits 0" 0 "$code"
  sleep 1
  assert_eq "window renamed to the suffixed result" "depwork-2" \
    "$(T display -p -t "$pane" '#{window_name}')"
  assert_eq "title matches the suffixed name" "depwork-2" \
    "$(T display -p -t "$pane" '#{pane_title}')"
}

t_name_no_claude_pane_is_noop() {
  local code
  T new-window -t main -n plain -c "$SCRATCH" bash
  sut claude-tmux-name --from-hook "main:plain"; code=$?
  assert_exit "window without claude exits 0 (nothing to push)" 0 "$code"
}

t_name_unconfirmed_rename_fails() {
  local pane code
  # a mock that ignores /rename: delivery must retry, then fail loudly
  cp "$SHIM/2.1.999" "$SHIM/2.1.998"
  sed -i '' 's|printf .*\\\\.*;;|:;;|' "$SHIM/2.1.998" 2>/dev/null || \
    sed -i 's|printf .*\\\\.*;;|:;;|' "$SHIM/2.1.998"
  T new-window -t main -n deaf -c "$SCRATCH" "PATH=$SHIM:$PATH 2.1.998"
  sleep 0.4
  pane="$(T display -p -t main:deaf '#{pane_id}')"
  T rename-window -t main:deaf silent
  CLAUDE_TMUX_NAME_TIMEOUT=2 SUT_PANE="$pane" \
    sut claude-tmux-name --from-hook "main:silent"; code=$?
  assert_exit "unconfirmed rename exits 1" 1 "$code"
}

t_track_kicks_push_for_named_window() {
  local pane uuid="99999999-8888-7777-6666-555555555555"
  pane="$(new_claude_window kicked)"
  T rename-window -t main:kicked myproj
  hook_json "$uuid" "$SCRATCH" | SUT_PANE="$pane" sut claude-tmux-track >/dev/null
  sleep 2
  assert_eq "track pushed the deliberate window name" "myproj" \
    "$(T display -p -t "$pane" '#{pane_title}')"
}
```

- [ ] **Step 2: Run tests, verify the new cases fail**

Run: `bin/.local/bin/test-claude-tmux`
Expected: earlier cases pass; delivery cases FAIL (`--from-hook` prints usage, exit 2).

- [ ] **Step 3: Implement delivery**

In `claude-tmux-name`, replace the `case` block at the bottom with:

```bash
STATE="$HOME/.local/state/claude-tmux"
# Verification budget in seconds; the test shrinks it to keep the suite fast.
TIMEOUT="${CLAUDE_TMUX_NAME_TIMEOUT:-10}"

is_claude_cmd() { case "$1" in [0-9]*|claude) return 0;; *) return 1;; esac }

claude_pane_of() { # <window-target> — lowest-index claude pane, empty if none
  local idx cmd
  while IFS="$(printf '\t')" read -r idx cmd; do
    if is_claude_cmd "$cmd"; then
      tmux display -p -t "${1}.${idx}" '#{pane_id}'
      return 0
    fi
  done < <(tmux list-panes -t "$1" \
      -F "#{pane_index}$(printf '\t')#{pane_current_command}" | sort -n)
  return 1
}

taken_names() { # <cwd> <own-window-id> — live windows on this cwd + our records
  # Live windows rooted at the same directory, excluding the window being
  # named (its own current name must not count as a collision with itself).
  local wid path name
  while IFS="$(printf '\t')" read -r wid path name; do
    [ "$wid" = "$2" ] && continue
    [ "$path" = "$1" ] && printf '%s\n' "$name"
  done < <(tmux list-panes -a \
      -F "#{window_id}$(printf '\t')#{pane_current_path}$(printf '\t')#{window_name}" | sort -u)
  # Names we previously pushed for this cwd (titles have no greppable store —
  # spec fallback: our own records are the source of truth for pushed names).
  awk -F'\t' -v c="$1" '$4 == c { print $6 }' "$STATE/sessions.log" 2>/dev/null | sort -u
}

deliver() { # <window-target>
  local win="$1" pane raw cwd wid final title deadline try
  # Re-entry guard: our own rename-window below re-fires after-rename-window.
  if [ "$(tmux show -wv -t "$win" @claude_naming 2>/dev/null)" = "1" ]; then
    return 0
  fi
  pane="$(claude_pane_of "$win")" || return 0   # no claude here: nothing to push
  raw="$(tmux display -p -t "$win" '#{window_name}')"
  cwd="$(tmux display -p -t "$pane" '#{pane_current_path}')"
  wid="$(tmux display -p -t "$win" '#{window_id}')"
  final="$(taken_names "$cwd" "$wid" | resolve_name "$raw")" || return 0
  if [ "$final" != "$raw" ]; then
    tmux set -w -t "$win" @claude_naming 1
    tmux rename-window -t "$win" "$final"
    # rename-window re-disables automatic-rename itself; drop the guard after
    # the hook it triggered has had its moment to see it.
    { sleep 1; tmux set -wu -t "$win" @claude_naming 2>/dev/null; } &
  fi
  for try in 1 2; do
    tmux send-keys -t "$pane" -l "/rename $final"
    tmux send-keys -t "$pane" Enter
    deadline=$(( $(date +%s) + TIMEOUT ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
      title="$(tmux display -p -t "$pane" '#{pane_title}')"
      case "$title" in *"$final") return 0;; esac
      sleep 0.5
    done
  done
  tmux display-message "claude-tmux-name: /rename \"$final\" not confirmed in $win"
  return 1
}

case "${1:-}" in
  --resolve-name)
    [ $# -ge 2 ] || { echo "usage: claude-tmux-name --resolve-name <raw>" >&2; exit 2; }
    resolve_name "$2"
    ;;
  --from-hook)
    [ $# -ge 2 ] || { echo "usage: claude-tmux-name --from-hook <session:window>" >&2; exit 2; }
    deliver "$2"
    ;;
  --from-track)
    [ $# -ge 2 ] || { echo "usage: claude-tmux-name --from-track <pane_id>" >&2; exit 2; }
    deliver "$(tmux display -p -t "$2" '#{session_name}:#{window_index}')"
    ;;
  *)
    echo "usage: claude-tmux-name --resolve-name|--from-hook|--from-track <arg>" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Add the kick to `claude-tmux-track`**

In `claude-tmux-track`, insert before the final `return 0` of `main`:

```bash
  # A deliberately named window (manual rename switched automatic-rename off)
  # pushes its name into the brand-new session: "name first, launch whenever".
  local auto
  auto="$(tmux show -wv -t "$TMUX_PANE" automatic-rename 2>/dev/null)"
  if [ "$auto" = "off" ] && [ -x "$HOME/.local/bin/claude-tmux-name" ]; then
    "$HOME/.local/bin/claude-tmux-name" --from-track "$TMUX_PANE" \
      >/dev/null 2>&1 &
  fi
```

- [ ] **Step 5: Run tests, verify all pass**

Run: `bin/.local/bin/test-claude-tmux`
Expected: all assertions pass, exit 0. The `t_track_kicks_push_for_named_window` case proves the kick end-to-end against the mock.

- [ ] **Step 6: Commit**

```bash
git add bin/.local/bin/claude-tmux-name bin/.local/bin/claude-tmux-track bin/.local/bin/test-claude-tmux
git commit -m "feat(bin): claude-tmux-name delivers verified /rename pushes"
```

---

### Task 4: `claude-tmux-manifest`

**Files:**
- Create: `bin/.local/bin/claude-tmux-manifest`
- Modify: `bin/.local/bin/test-claude-tmux`

**Interfaces:**
- Consumes: pane options `@claude_session`/`@claude_cwd` (Task 1).
- Produces: `manifest.tsv` (columns per Global Constraints), rewritten atomically on every run. Task 5 reads it by columns 1–3 → column 5.

- [ ] **Step 1: Add failing tests**

```bash
# ---------------------------------------------------------------------------
# claude-tmux-manifest
# ---------------------------------------------------------------------------
t_manifest_joins_stamped_panes() {
  local pane uuid="aaaabbbb-cccc-dddd-eeee-ffff00001111" mf row code
  pane="$(T display -p -t main:0 '#{pane_id}')"
  hook_json "$uuid" /tmp/projB | SUT_PANE="$pane" sut claude-tmux-track >/dev/null
  T new-window -t main -n unstamped -c "$SCRATCH" bash   # must NOT appear
  sut claude-tmux-manifest; code=$?
  assert_exit "manifest exits 0" 0 "$code"
  mf="$SCRATCH/.local/state/claude-tmux/manifest.tsv"
  row="$(awk -F'\t' -v u="$uuid" '$5 == u' "$mf")"
  assert_eq "stamped pane appears once" 1 "$(printf '%s' "$row" | grep -c .)"
  assert_eq "unstamped panes are excluded" 0 \
    "$(awk -F'\t' '$5 == ""' "$mf" | grep -c . || true)"
  assert_eq "manifest row carries session name" "main" \
    "$(printf '%s' "$row" | cut -f1)"
  assert_eq "manifest row carries cwd" "/tmp/projB" \
    "$(printf '%s' "$row" | cut -f6)"
  assert_eq "no temp file left behind" "" \
    "$(ls "$SCRATCH/.local/state/claude-tmux/" | grep tmp || true)"
}
```

- [ ] **Step 2: Run tests, verify the new case fails**

Run: `bin/.local/bin/test-claude-tmux` — manifest case FAILS (script missing).

- [ ] **Step 3: Implement**

Create `bin/.local/bin/claude-tmux-manifest`:

```bash
#!/usr/bin/env bash
# claude-tmux-manifest — join every @claude_session pane option to its window
# coordinates and rewrite manifest.tsv atomically.
#
# Runs from resurrect's post-save hook (@resurrect-hook-post-save-all), i.e.
# at every continuum autosave — which is the correctness argument: written at
# the same instant as the resurrect save, the manifest always describes
# exactly the layout resurrect will rebuild. Columns:
#   session_name  window_index  pane_index  window_name  uuid  cwd  pane_title
set -uo pipefail

STATE="$HOME/.local/state/claude-tmux"
OUT="$STATE/manifest.tsv"
mkdir -p "$STATE"

TAB="$(printf '\t')"
tmp="$OUT.tmp.$$"
tmux list-panes -a -F \
  "#{session_name}${TAB}#{window_index}${TAB}#{pane_index}${TAB}#{window_name}${TAB}#{@claude_session}${TAB}#{@claude_cwd}${TAB}#{pane_title}" \
  | awk -F'\t' '$5 != ""' > "$tmp"
mv "$tmp" "$OUT"
```

Make it executable: `chmod +x bin/.local/bin/claude-tmux-manifest`

- [ ] **Step 4: Run tests, verify they pass**

Run: `bin/.local/bin/test-claude-tmux` — all pass, exit 0.

- [ ] **Step 5: Verify the hook seam against pinned resurrect source (no code)**

Run: `sed -n '300,315p' ~/.tmux/plugins/tmux-resurrect/scripts/save.sh` and `grep -n "execute_hook" ~/.tmux/plugins/tmux-resurrect/scripts/helpers.sh`
Confirm: `execute_hook "post-save-all"` exists and executes the option's value as a shell command. Record the confirmation in the commit body.

- [ ] **Step 6: Commit**

```bash
git add bin/.local/bin/claude-tmux-manifest bin/.local/bin/test-claude-tmux
git commit -m "feat(bin): claude-tmux-manifest joins pane identities to coordinates"
```

---

### Task 5: `claude-tmux-revive`

**Files:**
- Create: `bin/.local/bin/claude-tmux-revive`
- Modify: `bin/.local/bin/test-claude-tmux`

**Interfaces:**
- Consumes: `manifest.tsv` (Task 4), `sessions.log` (Task 1), one argument: the pane id (`#{pane_id}`, passed explicitly by the binding — same lesson as `tmux-open-url`: never trust a popup's inherited environment).
- Produces: the literal string `claude --resume <uuid>` typed (no Enter — the user reviews and submits; Ctrl-C cancels) at the pane's prompt. Exit 0 on typed-or-guarded, 1 on nothing-found, 2 on usage error.

- [ ] **Step 1: Add failing tests**

```bash
# ---------------------------------------------------------------------------
# claude-tmux-revive
# ---------------------------------------------------------------------------
typed_line() { # <pane> — last non-empty line of the pane's visible content
  T capture-pane -p -t "$1" | grep -v '^$' | tail -1
}

t_revive_types_manifest_uuid() {
  local pane uuid="12121212-3434-5656-7878-909090909090" code
  T new-window -t main -n revme -c /tmp bash
  sleep 0.3
  pane="$(T display -p -t main:revme '#{pane_id}')"
  hook_json "$uuid" /tmp | SUT_PANE="$pane" sut claude-tmux-track >/dev/null
  sut claude-tmux-manifest
  sut claude-tmux-revive "$pane"; code=$?
  assert_exit "revive exits 0 on manifest hit" 0 "$code"
  sleep 0.3
  case "$(typed_line "$pane")" in
    *"claude --resume $uuid") ok;;
    *) fail "revive typed the exact resume command"; \
       printf '        got: %s\n' "$(typed_line "$pane")";;
  esac
}

t_revive_guards_live_claude() {
  local pane code
  pane="$(new_claude_window alive)"
  sut claude-tmux-revive "$pane"; code=$?
  assert_exit "revive against live claude exits 0" 0 "$code"
  assert_eq "revive typed nothing into a live claude" "" \
    "$(T display -p -t "$pane" '#{pane_title}')"
}

t_revive_falls_back_to_cwd() {
  local pane uuid="fefefefe-0000-1111-2222-333333333333" code
  # log entry exists, manifest does NOT (session started after last autosave)
  T new-window -t main -n cwdfall -c /tmp/projC bash
  mkdir -p /tmp/projC; sleep 0.3
  pane="$(T display -p -t main:cwdfall '#{pane_id}')"
  hook_json "$uuid" /tmp/projC | SUT_PANE="$pane" sut claude-tmux-track >/dev/null
  rm -f "$SCRATCH/.local/state/claude-tmux/manifest.tsv"
  sut claude-tmux-revive "$pane"; code=$?
  assert_exit "cwd fallback exits 0" 0 "$code"
  sleep 0.3
  case "$(typed_line "$pane")" in
    *"claude --resume $uuid") ok;;
    *) fail "cwd fallback typed the resume command";;
  esac
}

t_revive_nothing_recorded() {
  local pane code
  T new-window -t main -n empty -c "$SCRATCH" bash
  sleep 0.3
  pane="$(T display -p -t main:empty '#{pane_id}')"
  rm -f "$SCRATCH/.local/state/claude-tmux/manifest.tsv" \
        "$SCRATCH/.local/state/claude-tmux/sessions.log"
  sut claude-tmux-revive "$pane"; code=$?
  assert_exit "nothing recorded exits 1" 1 "$code"
  assert_eq "nothing typed when nothing recorded" "" \
    "$(typed_line "$pane" | grep 'claude --resume' || true)"
}
```

- [ ] **Step 2: Run tests, verify the new cases fail**

Run: `bin/.local/bin/test-claude-tmux` — revive cases FAIL (script missing).

- [ ] **Step 3: Implement**

Create `bin/.local/bin/claude-tmux-revive`:

```bash
#!/usr/bin/env bash
# claude-tmux-revive <pane_id> — bring back the exact Claude conversation this
# pane held. Bound to prefix+r.
#
# Resolution ladder (spec: no silent failure at any rung):
#   1. manifest.tsv row for this pane's coordinates — exact: written at the
#      same autosave the restored layout came from.
#   2. newest sessions.log entry for this pane's cwd — the session started
#      after the last autosave; probably right, says so out loud.
#   3. a hint at claude --resume's own picker.
#
# The command is TYPED at the prompt, not executed: visible, cancellable with
# Ctrl-C, in shell history once run. The user presses Enter to launch.
set -uo pipefail

STATE="$HOME/.local/state/claude-tmux"
MF="$STATE/manifest.tsv"
LOG="$STATE/sessions.log"

pane="${1:-}"
[ -n "$pane" ] || { echo "usage: claude-tmux-revive <pane_id>" >&2; exit 2; }

msg() { tmux display-message -t "$pane" "claude-tmux-revive: $1"; }
is_claude_cmd() { case "$1" in [0-9]*|claude) return 0;; *) return 1;; esac }

cmd="$(tmux display -p -t "$pane" '#{pane_current_command}')"
if is_claude_cmd "$cmd"; then
  msg "claude already running here — nothing to do"
  exit 0
fi

TAB="$(printf '\t')"
IFS="$TAB" read -r sess win pidx cwd < <(tmux display -p -t "$pane" \
  "#{session_name}${TAB}#{window_index}${TAB}#{pane_index}${TAB}#{pane_current_path}")

uuid="$(awk -F'\t' -v s="$sess" -v w="$win" -v p="$pidx" \
  '$1==s && $2==w && $3==p { print $5; exit }' "$MF" 2>/dev/null || true)"

if [ -z "$uuid" ]; then
  # Last matching line wins: the log is append-only, so last = newest.
  uuid="$(awk -F'\t' -v c="$cwd" '$4==c { u=$3 } END { if (u) print u }' \
    "$LOG" 2>/dev/null || true)"
  [ -n "$uuid" ] && msg "no manifest row — matched by cwd (session newer than last autosave)"
fi

if [ -z "$uuid" ]; then
  msg "no session recorded for this pane — try: claude --resume"
  exit 1
fi

tmux send-keys -t "$pane" -l "claude --resume $uuid"
exit 0
```

Make it executable: `chmod +x bin/.local/bin/claude-tmux-revive`

- [ ] **Step 4: Run tests, verify they pass**

Run: `bin/.local/bin/test-claude-tmux` — all assertions pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add bin/.local/bin/claude-tmux-revive bin/.local/bin/test-claude-tmux
git commit -m "feat(bin): claude-tmux-revive types the exact resume command"
```

---

### Task 6: tmux wiring — bindings, hooks, title fallback

**Files:**
- Modify: `tmux/.tmux.conf`
- Modify: `README.md`

**Interfaces:**
- Consumes: all four scripts by their absolute `~/.local/bin/` paths.
- Produces: `prefix+r` → revive, `prefix+R` → config reload, `after-rename-window` → naming harness, `@resurrect-hook-post-save-all` → manifest, `automatic-rename-format` title fallback.

- [ ] **Step 1: Apply the config edits**

In `tmux/.tmux.conf`, replace the line `bind r source-file ~/.tmux.conf` with:

```tmux
# r revives, R reloads — flipped deliberately: after a server death, reviving
# the pane's Claude is the frequent motion and reload is the rare one.
# The pane id is passed as an argument for the same reason tmux-open-url's
# binding passes it: never trust an inherited environment to name the pane.
bind r run-shell "~/.local/bin/claude-tmux-revive '#{pane_id}'"
bind R source-file ~/.tmux.conf
```

Replace the `set -g automatic-rename-format …` line (keeping its existing comment block above it) with:

```tmux
set -g automatic-rename-format '#{?#{m:[0-9]*,#{pane_current_command}},#{?#{==:#{pane_title},#{host}},Claude,#{=24:#{s/^[^a-zA-Z0-9]+ ?//:pane_title}}},#{pane_current_command}}'
```

and append to that comment block:

```tmux
# The Claude branch no longer prints a static "Claude": it renders the pane
# title — the live conversation summary Claude streams into #T — stripped of
# its spinner glyph and truncated to 24 columns so the pill stays a pill.
# Until Claude's first title write, #T still holds the default (the hostname),
# which would make every fresh Claude window wear the machine's name; the
# equality test papers over exactly that gap with the old static label.
# Manually named windows never get here: a manual rename turns
# automatic-rename off, and the deliberate name is pushed INTO Claude instead
# (claude-tmux-name, below).
```

Add after the `bind A` block (sessionizer section):

```tmux
# ---------------------------------------------------------------------------
# Claude session <-> window naming
# ---------------------------------------------------------------------------
# A deliberate window rename (prefix+,) becomes the Claude session's title:
# claude-tmux-name uniqueness-checks the name per project (suffixing -2, -3
# in the tmux-session-here tradition), renames the window to the final
# result, types /rename into the window's Claude pane and VERIFIES the title
# actually changed — one retry, then a status-line complaint. The harness
# guards its own re-entry (its rename-window re-fires this hook) via the
# @claude_naming window option, so no guard is needed here.
set-hook -g after-rename-window 'run-shell -b "~/.local/bin/claude-tmux-name --from-hook \"#{session_name}:#{window_index}\""'
```

Add with the resurrect/continuum options (before the `@plugin` lines):

```tmux
# At every autosave, snapshot which Claude conversation lives in which pane
# (claude-tmux-manifest). Written at the save instant, so the manifest always
# matches the layout resurrect will rebuild; prefix+r consumes it after a
# restore to type the exact `claude --resume <uuid>` back into each pane.
set -g @resurrect-hook-post-save-all "$HOME/.local/bin/claude-tmux-manifest"
```

- [ ] **Step 2: Parse-test on a scratch server**

Run: `tmux -L parsewire -f ~/.tmux.conf new-session -d && tmux -L parsewire list-keys | grep -cE 'claude-tmux' && tmux -L parsewire show-hooks -g | grep claude-tmux-name && tmux -L parsewire kill-server`
Expected: no config errors; `bind r` and the hook both present.

- [ ] **Step 3: Test the rename hook end-to-end on the scratch test server**

Add to `test-claude-tmux` (and to `main`):

```bash
t_rename_hook_fires_harness() {
  # The production wiring: after-rename-window → claude-tmux-name. Set the
  # hook on the scratch server exactly as .tmux.conf sets it, but pointing at
  # the repo copy under test with the scratch environment.
  T set-hook -g after-rename-window \
    "run-shell -b \"HOME='$SCRATCH' PATH='$SHIM:$PATH' '$HERE/claude-tmux-name' --from-hook '#{session_name}:#{window_index}'\""
  local pane
  pane="$(new_claude_window hookwin)"
  T rename-window -t main:hookwin hooked
  sleep 3
  assert_eq "prefix+, alone pushes the title" "hooked" \
    "$(T display -p -t "$pane" '#{pane_title}')"
  T set-hook -gu after-rename-window
}
```

Run: `bin/.local/bin/test-claude-tmux` — all pass. This proves the hook's format context names the renamed window.

- [ ] **Step 4: Apply to the live server, verify non-destructively**

```bash
tmux bind r run-shell "~/.local/bin/claude-tmux-revive '#{pane_id}'"
tmux bind R source-file ~/.tmux.conf
tmux set-hook -g after-rename-window 'run-shell -b "~/.local/bin/claude-tmux-name --from-hook \"#{session_name}:#{window_index}\""'
tmux set -g @resurrect-hook-post-save-all "$HOME/.local/bin/claude-tmux-manifest"
tmux set -g automatic-rename-format '#{?#{m:[0-9]*,#{pane_current_command}},#{?#{==:#{pane_title},#{host}},Claude,#{=24:#{s/^[^a-zA-Z0-9]+ ?//:pane_title}}},#{pane_current_command}}'
```

Verify: `tmux show -gv status-right | grep -c continuum_save` still returns ≥1 (autosave stays armed — ordering constraint from the persistence spec); `tmux list-keys -T prefix | grep -E '^bind-key.*(claude-tmux-revive|source-file)'` shows both. Then run `~/.local/bin/claude-tmux-manifest` once by hand and confirm `~/.local/state/claude-tmux/manifest.tsv` lists this session's pane (this very Claude was stamped only if the settings hook of Task 7 already ran — if Task 7 hasn't run yet, confirm instead that the file is created and empty, which is correct at this point).

- [ ] **Step 5: README row**

In `README.md`'s "tmux + Claude Code" table, add:

```markdown
| `prefix r` → revive / `prefix R` → reload | After a restore, `r` types `claude --resume <exact-uuid>` for the conversation this pane held (manifest → cwd-match → picker hint). Reload moved to `R`. |
```

- [ ] **Step 6: Commit**

```bash
git add tmux/.tmux.conf README.md bin/.local/bin/test-claude-tmux
git commit -m "feat(tmux): wire claude session revival — prefix+r, rename hook, title pills"
```

---

### Task 7: SessionStart hook registration + live smoke

**Files:**
- Modify: `~/.claude/settings.json` (live, python-merged, atomic) then `claude/.claude/settings.json` via `claude-settings-sync`

**Interfaces:**
- Consumes: `claude-tmux-track` (Task 1/3).
- Produces: every future Claude session in tmux self-registers. This task also discharges the spec's empirical verifications.

- [ ] **Step 1: Register the hook in the live settings (atomic merge, not overwrite)**

```bash
python3 - <<'EOF'
import json, os, tempfile
p = os.path.expanduser('~/.claude/settings.json')
with open(p) as f:
    d = json.load(f)
d.setdefault('hooks', {})['SessionStart'] = [
    {"hooks": [{"type": "command",
                "command": "\"$HOME/.local/bin/claude-tmux-track\""}]}
]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p))
with os.fdopen(fd, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
os.replace(tmp, p)
print('hook registered')
EOF
```

- [ ] **Step 2: Sync back into the repo**

Run: `claude-settings-sync`
Expected: `synced: … -> …/claude/.claude/settings.json` and a diff showing only the added `hooks` key.

- [ ] **Step 3: Empirical verifications (spec-mandated), in one throwaway tmux window**

Create a test window on the live server (`tmux new-window -n hooktest -c /tmp`), run `claude` in it interactively, then verify from another pane:

1. **Hook fires + stacking:** `tmux show -pv -t hooktest @claude_session` prints a UUID, and the running Claude still shows the superpowers skill banner in its context (ask it: "did you receive superpowers instructions?"). Records: hooks stack.
2. **`/rename` exists and queues:** type `/rename hooktest-title` into it (while idle, then again mid-response). Verify `tmux display -p -t hooktest '#{pane_title}'` ends with the name. Records: `/rename` semantics. If `/rename` does NOT exist in this build, the naming push degrades to window-rename-only — file a follow-up issue and note it in the commit body; identity/revive are unaffected.
3. **Exact resume:** `/exit` the test Claude, press `prefix+r` in its pane, confirm the typed command carries the same UUID `@claude_session` showed, press Enter, confirm the conversation resumes with context intact.
4. **Manifest path:** run `~/.local/bin/claude-tmux-manifest`; confirm the hooktest row. (Continuum's next 15-minute autosave exercises the same call via the resurrect hook; check `~/.local/state/claude-tmux/manifest.tsv`'s mtime after one interval.)
5. Kill the test window.

The `source` field question from the spec is deliberately NOT load-bearing: start and resume are treated identically (re-stamp), so no verification is needed for v1.

- [ ] **Step 4: Commit (settings + findings)**

```bash
git add claude/.claude/settings.json
git commit -m "feat(claude): SessionStart hook registers every session with its tmux pane"
```

Body records the verification results from Step 3 (hook stacking, `/rename` behavior, resume round-trip).

---

## Self-Review Notes

- Spec coverage: stories 1–18 map to Tasks 1 (1, 15, 16), 2 (9), 3 (8, 10, 11, 17), 4 (18), 5 (2–7, 14), 6 (12, 13), 7 (registration + verifications). Story 13 (sidecars/worktrees) needs no dedicated code: the hook fires wherever claude runs; cross-directory resume is a verified platform fact.
- Type consistency: log column 3 = uuid (track's `printf` argument 3; revive's cwd-fallback awk reads `$3`), manifest column 5 = uuid (manifest's awk filter and revive's coordinate awk both use `$5`). Coordinates are `session_name`/`window_index`/`pane_index` = manifest columns 1–3 everywhere.
- The live server is touched only additively (Task 6 Step 4, Task 7 Step 3); no task kills or restarts it.
