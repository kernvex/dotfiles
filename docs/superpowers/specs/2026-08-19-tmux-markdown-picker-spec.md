# Markdown picker: open a doc in a new window, in nvim

Status: ready-for-agent

## Problem Statement

Opening a markdown file means leaving what you are doing to type a path. The
files worth opening are rarely where you are standing: a handoff written by an
agent lives in the temp directory under a name nobody memorises, and a project's
docs live at the repo root while you are three directories down inside `src`.

`prefix + u` already solved the same shape of problem for links — scrape what is
in front of you, pick one, act on it in the right context. There is no equivalent
for the files, so the markdown you actually read is the markdown whose path you
can remember.

Reopening makes it worse. Coming back to a doc you had open ten minutes ago
starts a second editor on the same file, so the window you already had drifts out
of date and you keep two of them.

## Solution

`prefix + m` opens a picker of markdown files, fuzzy-searchable by any part of the
name, most recently modified first. Enter opens the chosen file in nvim in a new
tmux window — unless that file is already open in one, in which case it switches
to it.

The default list is the two places that matter and cost nothing to search: the
repo you are standing in (or the pane's directory, outside a repo), and the temp
directories where handoffs land. `ctrl-a` widens to the declared document roots
when the file is somewhere else.

## User Stories

1. As someone reading a handoff an agent just wrote, I want it at the top of the list without typing its path, so that I can read it while it is still the thing I care about.
2. As someone standing deep inside a repo, I want the repo's docs listed, so that being in `src/` does not hide `docs/`.
3. As someone standing in a directory that is not a repo, I want that directory's markdown listed, so that the feature still works outside version control.
4. As someone who remembers a fragment of a filename, I want to type it and narrow the list, so that I never have to recall a full path.
5. As someone with forty `README.md` files, I want to see where each one lives, so that I can tell them apart before pressing Enter.
6. As someone with forty `README.md` files, I want a preview of the file's contents, so that I can tell them apart even when the path does not settle it.
7. As someone returning to a doc I had open, I want the window I already have, so that I am not editing the same file in two places.
8. As someone opening a doc for the first time, I want a new window rather than losing the pane I was in, so that my current work stays where it was.
9. As someone opening a doc, I want nvim's working directory to be the file's directory, so that `:Ex`, `gf` and LSP root detection behave.
10. As someone who names windows by what is in them, I want the window named after the file, so that the window list stays readable.
11. As someone whose file is outside the default roots, I want a key that widens the search, so that "not here" is a keystroke rather than a dead end.
12. As someone who widened the search, I want to see that I did, so that an empty result reads as "not found anywhere" rather than "not found here".
13. As someone who pressed the key by accident, I want Escape to close the picker without opening anything, so that the mistake costs nothing.
14. As someone in a pane with no markdown anywhere near it, I want to be told that, so that the popup does not open and shut in silence.
15. As someone whose machine lacks fzf, I want to be told that, so that a missing dependency does not look like a broken key.
16. As someone who has just modified a file, I want it to have moved to the top of the list next time, so that the ordering tracks what I am working on.
17. As someone opening a file whose name contains spaces, I want it to open correctly, so that the picker is not quietly restricted to tidy filenames.
18. As someone using this on a machine with several tmux sessions open, I want the window created in the session I am looking at, so that it does not appear somewhere I am not.
19. As someone with several clients attached, I want the popup on the terminal I pressed the key on, so that it does not draw on a screen I am not watching.
20. As a maintainer, I want the pane the key was pressed in to be identified explicitly, so that this feature does not reintroduce the bug that made `prefix + u` do nothing.
21. As a maintainer, I want the candidate list testable without tmux, so that the sorting and de-duplication rules can be checked cheaply.
22. As a maintainer, I want the window reuse testable without a picker, so that the behaviour is asserted rather than eyeballed.
23. As someone who does not have the private identity repo, I want this to work anyway, so that the feature is not coupled to routing it does not need.
24. As someone reading the file list, I want paths shown relative to the root they were found under, so that I am reading names rather than seventy characters of prefix.
25. As someone with the same file reachable by two paths, I want it listed once, so that symlinks do not produce duplicates.

## Implementation Decisions

**A new script, `tmux-open-md`, mirroring `tmux-open-url`'s shape.** Same
repo location, same header-comment conventions, same split between a pure seam
and the tmux-facing parts. It does not share code with `tmux-open-url`: the two
have different inputs (a pane's text versus the filesystem) and the only common
ground is that both end in fzf.

**The binding routes through `run-shell`, not `display-popup` directly.**
`display-popup` does not expand `#{...}` in its shell-command, so a binding that
passes `'#{pane_id}'` to the popup delivers eleven literal characters and the
popup opens and shuts. This is the defect fixed for `prefix + u` in
`fix(tmux): prefix+u blinked because display-popup never expanded the pane id`,
and the same mistake is available here. The binding takes the same form:
`run-shell -b` performs the expansion, `-c '#{client_tty}'` puts the popup on
the terminal that pressed the key, and the pane id arrives as an argument.

**`prefix + m` overrides tmux's built-in `select-pane -m`.** Nothing in the conf
uses marked panes — no `join-pane -s '{marked}'`, no mark-based `swap-pane` — so
the default being replaced is one that is not in use here. `M`
(`select-pane -M`) is left alone.

**The search uses `find`, per ADR 0003, and the measurement says so too.** The
ADR's split is rust tools at the interactive layer, coreutils in the scripts, and
it asks to be reversed only against a measurement of the actual workload. That
measurement was taken, and it supports `find` twice over. On a large repo tree,
`fd` at its defaults is roughly four times faster — but its defaults honour
`.gitignore` and skip hidden entries, and in this repo alone that silently drops
`CLAUDE.md`, the nvim submodule's `README.md` and its `.github` templates. Brought
to parity with `--hidden --no-ignore`, `fd` measured about 1.5x *slower* than
`find` on the same tree (854ms against 571ms). The lossy version is wrong and the
correct version is slower, so there is nothing to reverse.

`bat` is used for the preview and is not an exception to that ADR: the ADR places
rust tools at the interactive layer and names fzf integration as an example. The
preview renders colour to a pane rather than piping identical bytes into fzf,
which was the case the ADR declined. It falls back to `head` where `bat` is
absent.

**Two root sets, because their costs differ by an order of magnitude.**

| set | contents | measured |
| --- | --- | --- |
| default | the pane's git repo root, or the pane's directory outside a repo; plus the temp directories | 0.31s, ~780 files |
| widened | the declared document roots | 2.2s, ~10,300 files |

The default set is what the key does. `ctrl-a` reloads the picker against the
widened set and changes the prompt so the two are distinguishable. All of `$HOME`
was measured and rejected: 32 seconds and 15,234 files, which is neither
responsive nor a list anyone can use.

The document roots are a **machine-local declaration** — true of this machine, not
of the repo — so they are read from an untracked file rather than committed, in
the same spirit as the identity repo's browser profile map. Absent that file, the
widened set falls back to the user's home directory minus the same prunes.

**Ordering is by modification time, newest first**, matching `tmux-open-url`'s
rule that the thing you want is nearly always the thing that just happened. fzf's
fuzzy matching sits on top unchanged. *This is the decision most worth a second
look before implementation: it was inferred from "sorted" and never confirmed.*

**Display is the path relative to the root it was found under**, with the
absolute path retained for opening. De-duplication is by resolved physical path,
so a file reachable through a symlink is listed once.

**Window reuse is tracked by a window option, not by window name.** The window
opened for a file carries `@md_file` set to that file's absolute physical path;
reuse is a search across windows for a matching value. Names collide — `README.md`
is not a unique key — and two different files would fight over one window.

**On Enter:** if a window with a matching `@md_file` exists, select it; otherwise
create a window with `neww -c <file's directory>` running nvim on the file, named
after the file, and set `@md_file` on it. The window is created in the session
the pane belongs to.

**Failure is never silent.** Every path that cannot proceed prints a reason and
holds the popup open: no markdown found, fzf absent, an unreadable pane, an
editor that cannot start. A popup that exits without drawing is indistinguishable
from a broken key, which is precisely how the `prefix + u` defect presented.

## Testing Decisions

A good test here asserts what the user would observe — the candidate list, the
window that exists afterwards, the message on screen — and never how the script
computes it. The two existing markdown-adjacent suites are the prior art and the
structure is copied from them deliberately.

**Two seams, both on the script, chosen to be the fewest that make the behaviour
reachable without a human at a picker:**

- `--list <root>...` — prints the candidate list for the given roots. Covers
  searching, ordering, de-duplication and display formatting. Driven against a
  fixture tree in a temp directory with controlled mtimes, so it is hermetic and
  needs no tmux, no fzf and no editor. This is the analogue of
  `tmux-open-url --extract`, and the prior art is `test-tmux-open-url`.
- `--open <file>` — performs the open-or-reuse without a picker. This is the only
  way to assert reuse as behaviour rather than by reading the code, and it keeps
  fzf out of the test entirely.

The binding itself is the third thing under test and has no new seam: it is
driven exactly as `test-tmux-open-url-binding` drives `prefix + u` — a scratch
tmux server on its own socket sourcing this checkout's conf, a client attached
through a pty because a popup needs one, and the bound command read back out with
`list-keys` and sourced so that the conf is what is exercised rather than a copy
retyped in the test.

**`test-tmux-open-md`** (no tmux) covers: newest-first ordering; de-duplication by
physical path; display paths relative to their root; a root containing no markdown;
filenames containing spaces; a root that does not exist; that hidden and
gitignored markdown is present, which is the regression guarding the `find`
decision above.

**`test-tmux-open-md-binding`** (real tmux) covers: the binding delivers a real
pane id rather than an unexpanded format, and that id is one tmux can address;
opening a file creates a window carrying `@md_file`; opening the same file again
selects that window instead of creating a second; opening a different file with
the same basename creates its own window; the new window's working directory is
the file's directory; a pane with no markdown says so rather than closing silently.

Every case is to be watched fail before it passes. The `prefix + u` defect shipped
under a green suite of seventeen tests, because the tests covered the extraction
and the failure was in the step before it — so a test that has never been red is
treated here as a test that has not been written.

## Out of Scope

- Any file type other than markdown. The extension set is fixed at `.md`; `.markdown`, `.mdx` and `README` without an extension are not included.
- Creating a new markdown file from the picker.
- Searching file *contents*. This picks by name and path; `ripgrep` already covers content.
- Opening in anything other than nvim, and any editor configuration.
- Opening in a split, a pane, or the current window. New window or existing window, nothing else.
- Closing or cleaning up windows the picker opened.
- Identity or browser routing. Nothing here needs the private repo, and the feature must work without it.
- Indexing or caching results between invocations. Both root sets were measured fast enough to walk on demand, and a cache would be a second source of truth about what exists.
- Any change to `prefix + u` or `tmux-open-url`.

## Further Notes

The one decision carrying an unconfirmed assumption is the ordering: "sorted" was
the requirement and modification time is an interpretation of it. Alphabetical is
the other reading and would be a small change, but it changes which file is under
the cursor when the picker opens, which is most of the value.

The `prefix + m` override is worth a moment's thought by whoever implements it. It
is safe against the current conf, but it is a tmux default rather than a free key,
and someone who later starts using marked panes will find the mark key gone with
no note explaining why. The binding's comment should say what it displaced.

The widened root set deliberately does not include everything. "I do not want to
restrict the path" was the requirement, and the honest answer is that the
restriction is not a policy but a budget: all of `$HOME` costs 32 seconds. The
machine-local roots file is the adjustable version of that budget, and it is the
place to put a directory the picker keeps failing to find.
