# Yank a candidate path from the sessionizer picker

Date: 2026-08-05
Status: ready-for-agent

> **Placeholders only.** This repo is public and `CONTEXT.md` keeps employer and
> coworker identity out of it entirely. Search paths that name an employer are
> written here as `<routed folder>`; live session names in examples are personal
> ones (`dotfiles`) or `<session>`.

## Problem Statement

The sessionizer picker (`ctrl-f`, or prefix-`f`) already knows where every
project on this machine lives. It walks the **search paths**, offers each
directory as a **session candidate**, and jumps to a session for whichever one
you choose. Jumping is the only thing it can do.

But the picker is also the fastest way to *find* a path, and finding one is
frequently not why you want to go there. You want to paste it: into a `cd` in
another pane, into a `--add-dir` argument, into a prompt for an agent that needs
to read a sibling repo, into a note. Today that means either jumping to the
session, running `pwd`, and jumping back — which disturbs two sessions to answer
a question — or abandoning the picker and retyping the path from memory, which
is exactly the thing the picker exists to spare you.

The cost is small each time and constant, and it falls hardest on the deepest
paths, which are the ones the picker helps with most and memory helps with
least.

## Solution

`ctrl-y` in the picker copies the highlighted candidate's absolute path to the
clipboard and closes the popup, leaving you back in the pane you started from
with the path ready to paste. A header row in the picker names the key, and a
brief status-line toast names the path that was copied.

Every line in the picker yields an absolute path, including live sessions. A
`[TMUX] <session>` entry is not a path, so it resolves to that session's working
directory — `[TMUX] dotfiles` copies `~/kernvex/dotfiles`, expanded. There is no
line where the key does nothing.

The same behaviour is reachable outside the picker as `tmux-sessionizer --yank
<candidate>`, which is what the key binding calls and what makes the feature
testable without a keypress.

## User Stories

1. As someone hunting for a path, I want to copy the highlighted directory from
   the picker with one key, so that I do not have to jump to a session and run
   `pwd` just to read a path back.
2. As someone who found the directory but did not want to go there, I want the
   popup to close on yank, so that I land back in the pane where the paste has
   to happen.
3. As someone yanking a live session, I want `[TMUX] <session>` to copy that
   session's directory rather than its name, so that every line in the picker
   means the same kind of thing.
4. As someone pasting into a command line, I want no trailing newline on the
   copied path, so that the paste does not execute the half-typed command it
   landed in.
5. As someone typing a query, I want the yank key not to be a printable
   character, so that searching for a directory whose name contains that letter
   still works.
6. As someone who searched before yanking, I want the key to act on the
   highlighted line rather than on my query text, so that the behaviour is the
   same as pressing Enter.
7. As someone who just pressed the key, I want a status-line toast naming the
   path, so that I know the copy happened and know which candidate it took.
8. As someone who pressed the key by accident, I want the toast to be brief and
   non-modal, so that it does not interrupt what I return to.
9. As someone discovering the picker afresh, I want a footer row naming the key,
   so that the feature is visible without reading the source.
9a. As someone reading the list, I want that row at the bottom rather than
   between the prompt and the first result, so that nothing sits between the
   cursor and the line it starts on.
10. As someone who yanked a session that has since been killed, I want to be told
    no such session exists, so that I do not paste a stale path that has been on
    the clipboard since an hour ago.
11. As someone on a machine with no clipboard mechanism at all, I want a written
    failure rather than a silent one, so that "nothing happened" is
    distinguishable from "it worked".
12. As someone running the picker over SSH or on a non-macOS machine, I want the
    yank to fall back to the tmux buffer, so that the fork is not silently
    macOS-only.
13. As someone who copied a path, I want it on the system clipboard, so that
    `Cmd-V` works in any application, not only inside tmux.
14. As someone with an established `y`-yanks-to-pbcopy reflex from copy mode, I
    want this key to mean the same thing in the same place, so that one habit
    covers both.
15. As someone scripting around the sessionizer, I want `--yank <candidate>` as a
    documented command, so that I can resolve a candidate to a path without
    opening a picker.
16. As someone reading `--help`, I want `--yank` listed there, so that a flag
    present in the source does not read like an accident.
17. As someone who uses both `ctrl-f` and prefix-`f`, I want the key available
    from both, so that I do not have to remember which entry point supports it.
18. As someone yanking a path containing spaces, I want it copied intact, so that
    directories with spaces are as usable as any other.
19. As someone who yanks and then decides to jump after all, I want a second
    `ctrl-f` to bring the picker straight back, so that closing on yank costs one
    keystroke to undo.
20. As someone running the sessionizer from a bare shell outside tmux, I want the
    yank to still copy, so that the feature does not depend on a tmux client
    being present.
21. As the maintainer of the fork, I want the key documented in the fork's
    README, so that the divergence from upstream is visible to a future clone.
22. As the maintainer of this dotfiles repo, I want a recorded decision about
    where sessionizer behaviour lives, so that the next picker change does not
    reopen the wrapper-versus-fork question.
23. As the maintainer, I want the footer row to double as a signal, so that a
    submodule bump that silently dropped the feature is visible before I press
    the key and find nothing.
24. As someone reading the glossary later, I want the thing being copied to have
    a name, so that "the path of a candidate" is not re-invented in prose each
    time it comes up.

## Implementation Decisions

### Where the change lives

The picker is a fork of the upstream sessionizer, vendored as a git submodule
and symlinked into the stowed `bin` package. Nothing in this repo can be edited
to change picker behaviour.

The feature is therefore implemented **in the fork**, on its default branch,
followed by a submodule pointer bump in this repo. Two commits in two repos.
This matches the fork's existing local commits, and the fork has no `upstream`
remote configured — it has already been de-facto adopted rather than tracked, so
one more local patch does not change the rebase story.

Rejected: a wrapper script in the `bin` package that injects fzf options and
execs the real script (splits one feature across two repos, and the `[TMUX]`
resolution has nowhere natural to sit); injecting the binding into the global
`FZF_DEFAULT_OPTS` (the tmux server does export it to the popup, but it would
bind the key in *every* fzf, where the placeholder is a filename, not a
directory).

This decision is recorded as an ADR at `docs/adr/0008-…`, because it recurs on
every future picker change.

### The key

`ctrl-y`. Bare `y` is not available: fzf's main window has no normal mode, so
every printable keystroke goes into the query field. Binding `y` would make any
directory with a `y` in its name unsearchable and would fire the yank against
whatever happened to be highlighted mid-query. `alt-y` was rejected as
depending on the terminal's Meta handling inside a popup.

The reasoning belongs in a comment beside the binding, in the fork's existing
commented style — it is a one-off, not an ADR.

The key is hardcoded. No configuration variable: the conf file exists for search
paths, and a key-remap knob on a single-user fork is a setting nobody sets.

### The seam

A `--yank <candidate>` mode of the script itself. The fzf binding is an
`execute-silent` of the script re-invoking itself with that flag, followed by an
abort. fzf quotes the placeholder itself, so candidates containing spaces
survive.

`--yank` is listed in `--help`. Argument handling runs early and exits without
falling through to picker logic; an empty argument is a usage error and exits
non-zero, matching how the existing session-index option treats an empty value.

Rejected: inlining the logic in the binding string (nested quoting inside a bash
string inside an fzf option, testable only by pressing the key); a second script
in the fork (the `bin` package holds exactly one symlink into that submodule
today, and a second would be a second thing to keep in sync).

### Resolving a candidate

The picker offers two kinds of line, and `--yank` normalises both to a
**candidate path**:

- a walked directory — already absolute, since the search paths are
  tilde-expanded when the conf is sourced. Copied as-is, not shortened back to
  `~`.
- `[TMUX] <session>` — resolved to that session's working directory via the tmux
  session-path format. For sessions the picker itself created this is the
  directory it was created with, so the two kinds agree.

If the session no longer exists, nothing is copied: the failure is reported and
the clipboard is left alone rather than being filled with the literal
`[TMUX] <session>` string.

### Clipboard destination

`pbcopy` when present; otherwise the tmux buffer, loaded with the flag that also
forwards it to the outer terminal over OSC 52. On this machine that means the
behaviour is byte-for-byte the existing copy-mode convention, where `y` pipes to
`pbcopy`; the fallback exists only so the fork is not macOS-only.

Written without a trailing newline.

Rejected: writing both destinations always (two things that can disagree);
tmux-buffer-only (a second mechanism nothing else in this config uses).

### Feedback

On success, a tmux status-line toast naming the copied path. The popup has
already closed by then, and the picker acts on the highlighted line rather than
on the query, so the toast is what confirms *which* candidate was taken. Toast
duration is the tmux default already in effect.

Outside tmux there is no client to display on and the toast is skipped; the copy
still happens.

On failure — dead session, or no clipboard mechanism available — the reason is
reported and the exit status is non-zero. Where the failure is the absence of
tmux itself, the report goes to stderr, since no toast is possible.

### Discoverability

The picker gains a fixed row naming the key, as a **footer**, not a header.
fzf's header sits between the prompt and the first result — precisely where the
cursor starts — so it separates you from the line you are about to act on. The
footer is out of the way at the bottom.

It costs one row of a popup sized at 70% height, and it is also the signal that
the feature survived a submodule bump.

### Scope of the binding

Both existing entry points — the root-table key and the prefix-table key — run
the same script, so both inherit the yank with no tmux config change at all.
This repo's tmux configuration is not modified by this work.

### Domain documentation

`CONTEXT.md` gains **candidate path** under the existing session terms, directly
below "Session candidate": the absolute directory a session candidate stands
for — the walked directory itself, or, for a `[TMUX]` entry, the live session's
working directory. The spec, the ADR and the fork's README all use that term.

## Testing Decisions

A good test here exercises the behaviour a user can observe — what lands on the
clipboard, what is reported when it cannot — and never the shape of the script's
internals. The seam is chosen so that this is possible at all.

**The seam is `--yank <candidate>`.** It carries the entire feature: prefix
stripping, session resolution, clipboard write, toast, and every failure path.
It is reachable from a plain shell with no fzf, no popup and no keypress, which
is the whole reason the binding re-invokes the script rather than inlining the
logic. One seam, and no others are introduced.

**Prior art: there is none, and none is being invented.** The fork contains two
files — the script and a README — and no test framework; this repo has no test
runner either. Adding one for a single bash function would be infrastructure
built for one caller. Verification is therefore a fixed list of command-line
checks, recorded here so they can be re-run by hand after any future submodule
bump.

Checks through the seam, each run directly and confirmed by reading the
clipboard back:

1. A walked directory copies itself, unchanged and absolute.
2. `[TMUX] <session>` for a live session copies that session's working
   directory, with the marker stripped.
3. A candidate containing spaces survives intact.
4. The copied value has no trailing newline.
5. `[TMUX] <session>` for a session that does not exist reports the failure,
   exits non-zero, and leaves the clipboard untouched.
6. An empty argument is a usage error and exits non-zero.
7. `--help` lists `--yank`.

Above the seam, and only verifiable by hand: pressing `ctrl-y` in a real popup
copies the highlighted candidate, closes the popup without switching sessions,
and shows the toast; and the header row is visible. This is a single manual
confirmation by the maintainer, called out as such rather than claimed as
covered.

## Out of Scope

- **Other pickers.** The cheat-sheet picker also runs fzf, but it selects
  topics, not directories; there is no candidate path to yank. No other fzf
  caller is touched.
- **The extra-session and sidecar bindings.** Both take a directory from the
  current pane through a command prompt, with no picker and no candidate list.
- **Making the key configurable.** Hardcoded, per the decision above.
- **Yanking anything other than a path** — a session name, a repo URL, a display
  path.
- **Copying to multiple destinations at once**, or syncing the tmux buffer and
  the system clipboard.
- **Changes to this repo's tmux configuration.** Both entry points inherit the
  feature for free.
- **Rebasing the fork onto upstream**, or introducing a test framework in it.
- **Preview panes, icons or any other picker restyling.** The footer row is the
  only visual change.

## Further Notes

The fork's README gains a short section covering `ctrl-y` and `--yank`. It is
the only place the divergence from upstream is visible to a future clone, and
the fork's history is otherwise a run of unhelpful automated commit messages.

The session lookup scans `list-sessions` and compares names in the shell. The
obvious call, `display-message -p -t <session> '#{session_path}'`, is wrong in a
way that reads as right: `-t` takes a *pane* target, a bare session name is not
one, and the call then prints an empty line and exits **0** for a session that is
alive. Any implementation that treats a non-zero exit as the failure signal will
report every session as missing. The scan also sidesteps a `-f` filter, in which
a session name containing a comma or a brace would be read as format syntax.

The session-path resolution reads the session's working directory, not the
current directory of any pane inside it. For sessions the picker created these
are the same, since the session was created with that directory; a session
whose panes have since `cd`'d elsewhere will still yank the directory it was
created in. This is the intended reading of "the path of that session".

Neither commit is pushed as part of this work. The fork's remote is outward-
facing and the push is the maintainer's call.
