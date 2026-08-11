# Claude session revival: exact per-pane resume + window↔session naming

**Date:** 2026-08-11
**Status:** Approved
**Amends:** `2026-08-09-tmux-session-persistence-design.md` — supersedes its
"no claude relaunch; `claude --continue` is the deliberate way back" decision.

## Problem Statement

When the tmux server dies (crash, reboot, deliberate kill), resurrect +
continuum bring every session back — layout, working directories, and each
pane's last screen as static text. But the Claude Code conversations
themselves are gone, and getting them back is the painful part: each window
shows a squashed noise of whatever was last printed, and identifying *which*
conversation a window held means reading that noise and then scanning the
resume picker's log summaries — two to three minutes per window, multiplied
by a metropolis of windows.

`claude --continue` does not help: it resumes only the *most recent* session
in the current directory, and most windows share the same project root
(`~/work/<client-project>` style), with several concurrent conversations
per project. Worktree windows happen to be unambiguous; root-dir windows — the
majority — are not.

## Solution

Every Claude session stamps its own identity onto the tmux pane it runs in,
automatically, the moment it starts or resumes — no wrapper, no habit. At
every continuum autosave, a manifest joins those identities to window
coordinates, so the manifest always describes exactly the layout resurrect
will rebuild. After a restore, `prefix+r` in any pane types
`claude --resume <uuid>` at the prompt: the exact conversation that pane
held, back in one keypress, lazily, window by window as you revisit them.

Names bind the two worlds together. Deliberately naming a tmux window
(`prefix+,`) pushes that name into the Claude session as its title
(uniqueness-checked per project, suffixing `-2`, `-3` in the
`tmux-session-here` tradition). Windows never manually named display their
Claude's live self-description in the status bar instead, pulled from the
title stream Claude already emits.

## User Stories

1. As a multi-project Claude Code user, I want every Claude session to record which tmux pane it lives in automatically, so that resume never depends on a habit I might forget.
2. As a returning user after a server crash, I want one keypress in a restored pane to resume the exact conversation that pane held, so that I never read squashed scrollback to identify a window again.
3. As a returning user, I want revival to be lazy and per-pane, so that only the projects I actually revisit relaunch their Claudes, with no thundering herd at restore time.
4. As a user pressing the revive key in a pane whose Claude is already running, I want a status message and no action, so that a stray keypress cannot damage a live session.
5. As a user whose session started after the last autosave, I want revival to fall back to matching by the pane's working directory with a notice, so that even unmanifested sessions come back with a best effort.
6. As a user in a pane with no recorded session at all, I want a message pointing me at the resume picker, so that revival never dead-ends silently.
7. As a user reviving a pane, I want the resume command *typed* at my prompt rather than executed invisibly, so that I can cancel it, see it in shell history, and keep the pre-crash text in scrollback above it.
8. As a user who names a tmux window, I want that name pushed into the window's Claude session as its title, so that the window name and the session title are the same handle.
9. As a user pushing a name that already exists in the same project (as a session title or a live window name), I want the name auto-suffixed to the next free `-2`, `-3` and the window renamed to match, so that names stay unique without prompting me.
10. As a user who names a window before launching Claude in it, I want the title pushed automatically when the session starts, so that "name first, launch whenever" just works.
11. As a user who renames a window mid-conversation, I want the running session retitled, so that the link holds at any point in the window's life.
12. As a user who never names a window, I want it to display its Claude's live title (cleaned and truncated) in the status bar, so that unnamed windows still tell me what they are doing.
13. As a user running sidecar sessions and worktree Claudes, I want those tracked identically to root-dir ones, so that no launch path is invisible to revival.
14. As a user who deliberately exits a Claude, I want the pane's mapping kept, so that the revive key can still bring that conversation back if the exit was premature.
15. As a user whose conversation is resumed (same UUID) many times, I want the mapping refreshed on every start and resume, so that the map self-heals and never goes stale.
16. As a Claude Code user, I want the tracking hook to be silent and non-fatal, so that a broken hook can never pollute a session's context or block Claude from starting.
17. As a user watching the rename push, I want delivery verified against the pane title with a retry and a visible failure message, so that a swallowed `/rename` is caught rather than assumed.
18. As the owner of this config, I want revival to sit on the existing resurrect/continuum machinery rather than replace it, so that one persistence system remains, not two.

## Implementation Decisions

- Four small commands, one purpose each, following the repo's
  one-script-one-job convention:
  - **track** — the SessionStart hook target. Reads the hook JSON from
    stdin (`session_id`, `cwd` — fields verified against official hook
    docs), stamps the UUID and cwd as pane options on `$TMUX_PANE`, appends
    one line to an on-disk log. If the pane's window was deliberately named
    (detected via tmux's `automatic-rename` having been switched off by a
    manual rename) and the title differs, it kicks the naming harness.
    Prints nothing on success — SessionStart stdout is injected into the
    session's context. Always exits 0; no-ops outside tmux.
  - **name** — the push harness. Sanitizes the window name under the same
    rules as `tmux-session-here` (target-safe characters, dash collapsing),
    checks uniqueness against BOTH existing session titles in the project's
    Claude store AND live tmux window names rooted at the same directory,
    suffixes to the next free `-2`/`-3` on collision, renames the window to
    the final result, then delivers `/rename <name>` into the window's
    Claude pane via send-keys and verifies the pane title actually changed
    within a timeout; one retry, then a `display-message` failure. In
    multi-pane windows it targets the lowest-index Claude pane.
  - **revive** — the `prefix+r` target. Resolution ladder: manifest row for
    this pane's coordinates → newest log entry for the pane's cwd (with a
    "matched by cwd" notice) → a message pointing at the resume picker.
    Types the resume command at the prompt; guards against a live Claude.
  - **manifest** — runs from resurrect's post-save hook at every continuum
    autosave: joins pane options to coordinates (session, window index,
    pane index, window name, cwd, title) and rewrites the manifest
    atomically. Running at save time is the correctness argument: the
    manifest always matches the layout resurrect will restore.
- State is two files in a dedicated state directory: an append-only log
  (trimmed opportunistically to ~1000 lines) and the manifest, both written
  atomically (temp + rename).
- Identity is per-pane (pane options), not per-window; naming is per-window.
- `claude --resume <uuid>` reuses the original session ID (verified in the
  official sessions docs), so a pane's UUID is stable across any number of
  resumes; the hook re-stamping on each resume makes the map self-healing.
  Cross-directory resume works as of Claude Code v2.1.223+, covering
  worktrees.
- The tmux side: revive binds to `prefix+r`; the existing config-reload
  binding moves from `r` to `R`. A tmux `after-rename-window` hook drives
  the naming harness, with a re-entry guard (the harness itself renames
  windows in the suffix case and must not re-trigger itself). The
  `automatic-rename-format` Claude branch changes from the static label to
  the pane title cleaned of its spinner glyph and truncated to ~24
  characters — pure tmux format expansion, no polling.
- The SessionStart hook is registered in the user-level Claude settings
  (the copy-managed claude package), alongside — not replacing — the
  superpowers plugin's SessionStart hook.
- To verify empirically at implementation time (documentation gaps, all
  with graceful fallbacks): whether hook layers stack, whether `/rename`
  exists in the installed version and queues while Claude is busy, whether
  a `source` field distinguishes resume from startup in the hook input, and
  the exact resurrect post-save hook option name (against the pinned
  v4.0.0 source).

## Testing Decisions

- Tests assert external behavior at production entry points; nothing
  internal is mocked or inspected.
- **Primary seam:** one test script driving all four commands against a
  real scratch tmux server on a private socket with a scratch `$HOME`, and
  a mock `claude` first on `PATH` that answers `/rename X` by emitting the
  OSC title escape — so the deliver-and-verify loop runs for real without
  an API call. `track` is fed hook JSON on stdin with `$TMUX_PANE` set,
  exactly as Claude invokes hooks; `name` is invoked as the tmux hook
  invokes it; `revive` is asserted via capture-pane on what it actually
  typed; `manifest` against panes with options pre-set.
- **Secondary pure seam:** name sanitization and collision-suffix
  resolution behind a text-in/text-out flag, no tmux required — the
  edge-case table (dots, colons, dash collapsing, suffix walking) lives
  here.
- **Prior art:** the existing url-extraction test script (pure seam, exit
  status asserted — its header documents the bug that output-only
  assertions shipped); scratch-`$HOME` and isolated-socket conventions from
  the catppuccin bootstrap proof and the persistence spec's verification
  tier.
- The real Claude binary is not a test dependency: one manual live smoke
  (real session, real rename, watch the title land) as a checklist step.

## Out of Scope

- Auto-reviving all panes at restore time (thundering herd; deliberately
  lazy instead).
- A picker UI over revivable panes — can be layered on later by looping
  the per-pane revive.
- Pushing names in the reverse direction as state (Claude title → window
  *name*); the title only *displays* via the status-bar fallback.
- nvim session restore, cross-machine session sync, changing the continuum
  autosave interval.

## Further Notes

- Verified facts this design leans on, with sources: SessionStart hook
  input includes `session_id` and `cwd` (hooks reference); plain resume
  reuses the session ID (sessions reference); cross-directory resume since
  v2.1.223 (sessions reference). Uncertain points are isolated behind
  fallbacks and listed above as implementation-time verifications.
- Degradation ladder is deliberate: exact (manifest) → probable (cwd match,
  with notice) → manual (picker, with notice). No silent failure at any
  rung.
- The 2026-08-09 persistence spec's out-of-scope list included custom
  `@resurrect-processes` for `claude`; this design keeps that exclusion
  (revival types into restored panes; resurrect still relaunches nothing),
  but retires its "`--continue` is the way back" rationale.
