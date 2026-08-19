# Two file pickers: markdown on disk, and paths on screen

Status: ready-for-agent

Two sibling keys, specified together because they share an editor and must not
each invent one.

| key | answers | source |
| --- | --- | --- |
| `prefix + m` | "what markdown is near me?" | the filesystem |
| `prefix + g` | "what files are on my screen?" | the pane's text |

## Problem Statement

Opening a file means leaving what you are doing to type a path, and the paths
worth opening are rarely ones you can type from memory.

Two distinct versions of that. **On disk:** a handoff written by an agent lives in
the temp directory under a name nobody memorises, and a project's docs live at
the repo root while you are three directories down inside `src`. **On screen:** a
failing test names the file and the line, a compiler error names four, `git
status` names eleven — and every one of them has to be retyped into an editor by
hand, or copied out with the mouse. The path is right there, already printed,
and it is still faster to guess at it than to use it.

`prefix + u` already solved this shape for links: take what is in front of you,
pick one, act on it in the right context. Nothing does it for files.

Reopening compounds it. Coming back to a file you had open ten minutes ago starts
a second editor on the same file, so the window you already had drifts out of
date and you keep two of them.

## Solution

**`prefix + m`** opens a picker of markdown files from the filesystem, most
recently modified first, fuzzy-searchable by any part of the name. The default
list is the two places that cost nothing to search: the repo you are standing in
(or the pane's directory, outside a repo), and the temp directories where
handoffs land. `ctrl-a` widens to the declared document roots.

**`prefix + g`** opens a picker of file paths found in the pane you are looking
at, most recently printed first. A candidate is only offered if it exists on
disk, which is what makes it possible to be aggressive about recognising paths
without drowning the list in words that merely look like one. Where the text
carried a line number — `src/thing.ts:42`, a stack frame, a compiler error — the
line is kept and used.

Both open on Enter into nvim, in a new tmux window, reusing the window if that
file is already open in one. `prefix + g` additionally copies the path with
`ctrl-y`, by the same mechanism `prefix + u` copies a link.

## User Stories

### Picking markdown from the filesystem (`prefix + m`)

1. As someone reading a handoff an agent just wrote, I want it at the top of the list without typing its path, so that I can read it while it is still the thing I care about.
2. As someone standing deep inside a repo, I want the repo's docs listed, so that being in `src/` does not hide `docs/`.
3. As someone standing in a directory that is not a repo, I want that directory's markdown listed, so that the feature still works outside version control.
4. As someone who remembers a fragment of a filename, I want to type it and narrow the list, so that I never have to recall a full path.
5. As someone with forty `README.md` files, I want to see where each one lives, so that I can tell them apart before pressing Enter.
6. As someone with forty `README.md` files, I want a preview of the contents, so that I can tell them apart even when the path does not settle it.
7. As someone whose file is outside the default roots, I want a key that widens the search, so that "not here" is a keystroke rather than a dead end.
8. As someone who widened the search, I want to see that I did, so that an empty result reads as "not found anywhere" rather than "not found here".
9. As someone who has just modified a file, I want it to have moved to the top next time, so that the ordering tracks what I am working on.
10. As someone with markdown inside a gitignored or hidden directory, I want it listed, so that the picker's idea of "my files" matches mine rather than git's.

### Picking paths off the screen (`prefix + g`)

11. As someone looking at a failing test, I want the file it names in a list, so that I can open it without retyping the path.
12. As someone looking at a failing test, I want to land on the line it named, so that I arrive where the failure is rather than at the top of the file.
13. As someone looking at compiler output naming several files, I want all of them listed, so that I can work through them without scrolling back.
14. As someone looking at `git status`, I want the changed files listed, so that I can open one directly from what I am already reading.
15. As someone looking at a stack trace, I want the frames' files listed, so that a trace becomes navigable rather than something to squint at.
16. As someone whose pane contains words that merely resemble paths, I want them left out, so that the list is short enough to read.
17. As someone whose pane names a file that has since been deleted, I want it left out, so that Enter never opens an empty buffer at a path that is gone.
18. As someone standing in the directory the output was printed from, I want relative paths resolved against it, so that `src/thing.ts` finds the file it meant.
19. As someone who wants the path rather than the file, I want to copy it, so that I can paste it into a command, a message or another tool.
20. As someone who copies a path, I want the absolute one, so that it still means the same thing wherever I paste it.
21. As someone reading a long transcript, I want the most recently printed path first, so that the one I am reacting to is under the cursor.
22. As someone whose pane printed the same path five times, I want it listed once, so that the list reflects distinct files rather than repetition.
23. As someone in a pane with no paths in it, I want to be told that, so that the popup does not open and shut in silence.

### Shared behaviour

24. As someone returning to a file I had open, I want the window I already have, so that I am not editing the same file in two places.
25. As someone opening a file for the first time, I want a new window rather than losing the pane I was in, so that my current work stays where it was.
26. As someone opening a file, I want nvim's working directory to be the file's directory, so that `:Ex`, `gf` and LSP root detection behave.
27. As someone who names windows by what is in them, I want the window named after the file, so that the window list stays readable.
28. As someone reusing a window for a file named with a line number, I want to be taken to that line, so that reuse is not worse than opening fresh.
29. As someone who pressed the key by accident, I want Escape to close the picker without opening anything, so that the mistake costs nothing.
30. As someone whose machine lacks fzf, I want to be told that, so that a missing dependency does not look like a broken key.
31. As someone opening a file whose name contains spaces, I want it to open correctly, so that the pickers are not quietly restricted to tidy filenames.
32. As someone with several tmux sessions open, I want the window created in the session I am looking at, so that it does not appear somewhere I am not.
33. As someone with several clients attached, I want the popup on the terminal I pressed the key on, so that it does not draw on a screen I am not watching.
34. As someone without the private identity repo, I want both pickers to work, so that they are not coupled to routing they do not need.
35. As a maintainer, I want the pane the key was pressed in identified explicitly, so that neither picker reintroduces the bug that made `prefix + u` do nothing.
36. As a maintainer, I want one implementation of "open this file in a window", so that the two pickers cannot drift into behaving differently.

## Implementation Decisions

### Three scripts, and why the editor is its own

`tmux-open-md` and `tmux-open-path` are two pickers with unrelated inputs — a
filesystem walk and a pane's text — and no shared logic between them. What they
do share is the ending: open this file, in nvim, in a window, unless it is
already open.

That ending becomes **`tmux-edit <file> [line]`**, a script of its own. It is the
only thing that knows how a file becomes a window, both pickers call it, and it is
testable on its own without a picker in front of it. Story 36 is the reason: two
copies of open-or-reuse would drift, and the drift would be invisible until one
key started behaving differently from the other.

Neither picker shares code with `tmux-open-url`. Their inputs differ and the only
common ground is that all three end in fzf.

### The bindings route through `run-shell`, both of them

`display-popup` does not expand `#{...}` in its shell-command, so a binding that
passes `'#{pane_id}'` to the popup delivers eleven literal characters and the
popup opens and shuts. This is the defect fixed for `prefix + u` in `fix(tmux):
prefix+u blinked because display-popup never expanded the pane id`, and the same
mistake is available twice more here.

Both bindings take the established form: `run-shell -b` performs the expansion,
`-c '#{client_tty}'` puts the popup on the terminal that pressed the key, and the
pane id arrives as an argument.

### The keys

`prefix + m` overrides tmux's built-in `select-pane -m`. Nothing in the conf uses
marked panes — no `join-pane -s '{marked}'`, no mark-based `swap-pane` — so the
default being replaced is not in use here. `M` (`select-pane -M`) is left alone.

`prefix + g` is unbound in both tmux's defaults and this conf, so it displaces
nothing. `g` for "go to file", after vim's `gf`.

Each binding's comment records what it displaced, so someone who later wants
marked panes finds out where the key went.

### `tmux-edit`: open or reuse

Reuse is tracked by a **window option**, `@edit_file`, set to the file's absolute
physical path. Reuse is a search across windows for a matching value.

Not by window name: `README.md` is not a unique key, and two different files
would fight over one window. The option is named for editing rather than for
markdown, because two callers now share it.

On invocation: if a window carrying a matching `@edit_file` exists, select it, and
send it to the requested line if one was given (story 28). Otherwise create a
window with `neww -c <file's directory>` running nvim on the file — at `+<line>`
where given — named after the file, with `@edit_file` set on it. The window is
created in the session the pane belongs to.

### `tmux-open-md`: the filesystem walk

**The search uses `find`, per ADR 0003, and the measurement agrees.** The ADR's
split is rust tools at the interactive layer, coreutils in the scripts, and it
asks to be reversed only against a measurement of the actual workload. That
measurement was taken and it supports `find` twice over. On a large repo tree,
`fd` at its defaults is roughly four times faster — but its defaults honour
`.gitignore` and skip hidden entries, and in this repo alone that silently drops
`CLAUDE.md`, the nvim submodule's `README.md` and its `.github` templates
(story 10). Brought to parity with `--hidden --no-ignore`, `fd` measured about
1.5x *slower* than `find` on the same tree (854ms against 571ms). The lossy
version is wrong and the correct version is slower, so there is nothing to
reverse.

`bat` is used for the preview and is not an exception to that ADR: the ADR places
rust tools at the interactive layer and names fzf integration as an example. The
preview renders colour to a pane rather than piping identical bytes into fzf,
which was the case the ADR declined. It falls back to `head` where `bat` is absent.

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

**Ordering is by modification time, newest first**, confirmed. It is the
filesystem's analogue of `tmux-open-url`'s rule that the thing you want is nearly
always the thing that just happened. fzf's fuzzy matching sits on top unchanged.

**Display is the path relative to the root it was found under**, with the absolute
path retained for opening. De-duplication is by resolved physical path, so a file
reachable through a symlink is listed once.

### `tmux-open-path`: reading paths off the screen

**Existence is the filter, and it is what makes the rest safe.** Almost any word
can look like a path, so a recogniser tuned to avoid false positives would miss
the real ones. Instead the recogniser is deliberately generous, and every
candidate is then resolved and tested against the filesystem; anything that is not
an existing file is dropped. This is what keeps the list short (story 16) without
narrow pattern rules, and it is also why a deleted file never appears (story 17).

Resolution is relative to **the pane's current directory** — the directory the
output was printed from — with `~` expanded and absolute paths taken as they are.

**Recognised forms**, all subject to the existence check: absolute paths; `~`
paths; relative paths containing a separator; a path followed by `:line` or
`:line:col`; paths appearing inside quotes, parentheses or angle brackets; and
paths introduced by the labels `git status` uses. Trailing sentence punctuation is
stripped, by the same rules `tmux-open-url` applies to links, for the same reason.

**Line numbers are kept** where the text carried one, passed to `tmux-edit`, and
shown in the picker so it is clear where Enter will land.

**Ordering is by position in the pane, most recent first**, de-duplicated keeping
the most recent occurrence. This is `tmux-open-url`'s rule unchanged, and it is
deliberately *not* mtime: the question this key answers is "what did I just see",
not "what did I recently change".

**Display is relative to the pane's directory** when the file is beneath it, and
`~`-shortened otherwise.

**`ctrl-y` copies the absolute path** (story 20), by the same mechanism
`tmux-open-url` uses — `pbcopy` where present, `tmux set-buffer` otherwise.

That clipboard helper is duplicated rather than shared. It is two lines, and the
alternative is either a shared library sourced by three scripts or an edit to
`tmux-open-url` — a script whose copy path has no test and which was fixed only
recently. Converging the three onto one helper is a reasonable follow-up once
that path is covered; doing it here would put a just-repaired script back in
scope for no behavioural gain.

### Failure is never silent, in either picker

Every path that cannot proceed prints a reason and holds the popup open: no
candidates found, fzf absent, an unreadable pane, an editor that cannot start. A
popup that exits without drawing is indistinguishable from a broken key, which is
exactly how the `prefix + u` defect presented, and it presented that way for
three separate underlying causes.

## Testing Decisions

A good test here asserts what the user would observe — the candidate list, the
window that exists afterwards, the message on screen — and never how a script
computes it. The structure is copied deliberately from `test-tmux-open-url` and
`test-tmux-open-url-binding`, which are the prior art.

**Three seams, one per script, each the highest point that makes the behaviour
reachable without a human at a picker:**

- **`tmux-open-md --list <root>...`** — prints the candidate list for the given
  roots. Covers searching, ordering, de-duplication, display formatting. Driven
  against a fixture tree with controlled mtimes: hermetic, no tmux, no fzf, no
  editor. The analogue of `tmux-open-url --extract`.
- **`tmux-open-path --extract <base-dir>`** — reads pane text on stdin and prints
  the candidate list. Covers recognition, the existence filter, line-number
  capture, ordering, de-duplication, display. Driven against a fixture tree, so
  "exists" is controlled by the test rather than by the machine it runs on.
- **`tmux-edit <file> [line]`** — the open-or-reuse, exercised directly. This is
  the only way to assert reuse as behaviour rather than by reading the code, and
  it keeps fzf out of the test entirely.

The bindings need no new seam: they are driven exactly as
`test-tmux-open-url-binding` drives `prefix + u` — a scratch tmux server on its
own socket sourcing this checkout's conf, a client attached through a pty because
a popup needs one, and the bound command read back out with `list-keys` and
sourced, so the conf is what is exercised rather than a copy retyped in the test.

**`test-tmux-open-md`** (no tmux): newest-first ordering; de-duplication by
physical path; display paths relative to their root; a root containing no
markdown; filenames containing spaces; a root that does not exist; and that hidden
and gitignored markdown is present — the regression guarding the `find` decision.

**`test-tmux-open-path`** (no tmux): an absolute path is found; a relative path is
resolved against the base directory; a `~` path is found; `path:42` and
`path:42:8` yield the path with the line captured; a path that does not exist is
dropped; a word that resembles a path but is not one is dropped; a directory is
dropped; the same path printed repeatedly appears once, at its most recent
position; most-recent-first ordering; trailing sentence punctuation is not part of
the path; a path containing spaces; `git status` output yields its files; a stack
trace yields its frames; text containing no paths yields nothing **and exits
zero** — the exact combination that made `prefix + u` die silently under a green
suite.

**`test-tmux-edit`** (real tmux): opening a file creates a window carrying
`@edit_file`; opening the same file again selects that window rather than creating
a second; two different files with the same basename get their own windows; the
window's working directory is the file's directory; a line number opens at that
line; reusing a window with a line number moves to that line.

**`test-tmux-open-md-binding`** and **`test-tmux-open-path-binding`** (real tmux):
each binding delivers a real pane id rather than an unexpanded format, and one
tmux can address; each survives a pane with nothing to offer by saying so rather
than closing silently.

Every case is to be watched fail before it passes. The `prefix + u` defect shipped
under a green suite of seventeen tests, because the tests covered the extraction
and the failure was in the step before it — so a test that has never been red is
treated here as a test that has not been written.

## Out of Scope

- Any file type other than markdown for `prefix + m`. The extension set is fixed at `.md`; `.markdown`, `.mdx` and extensionless `README` are excluded.
- Filesystem-wide picking of non-markdown files. `prefix + g` reads the screen, not the disk; a picker over every file on the machine is a third feature and would make `prefix + m` redundant.
- Creating a new file from either picker.
- Searching file *contents*. Both pick by name and path; ripgrep already covers content.
- Opening in anything other than nvim, and any editor configuration.
- Opening in a split, a pane, or the current window. New window or existing window, nothing else.
- Directories as targets. `prefix + g` lists files; a path that resolves to a directory is dropped.
- Closing or cleaning up windows the pickers opened.
- Identity or browser routing. Neither picker needs the private repo, and both must work without it.
- Indexing or caching between invocations. Both root sets were measured fast enough to walk on demand, and a cache would be a second source of truth about what exists.
- Any change to `prefix + u` or `tmux-open-url`, including converging its clipboard helper.
- Copying from `prefix + m`. Only `prefix + g` copies; markdown picking is for reading, and the request was specific.

## Further Notes

`prefix + g`'s value depends almost entirely on the existence filter doing its
job. If it is too permissive the list fills with noise and the key becomes
useless; if it is too strict the paths you wanted are the ones missing, silently.
The fixture-tree tests are what pin this down, and they are worth writing before
the recogniser rather than after — the temptation to tune patterns against a real
pane until it "looks right" produces something that cannot be reasoned about and
whose failures are invisible.

The `prefix + m` override is worth a moment by whoever implements it. It is safe
against the current conf, but it is a tmux default rather than a free key, and
someone who later starts using marked panes will find the mark key gone.

The widened root set deliberately does not include everything. "I do not want to
restrict the path" was the requirement, and the honest answer is that the
restriction is not a policy but a budget: all of `$HOME` costs 32 seconds. The
machine-local roots file is the adjustable version of that budget.

One ordering rule differs between the two keys, and the difference is deliberate
rather than an oversight: `prefix + m` sorts by modification time, `prefix + g` by
position in the pane. They answer different questions — what I recently changed,
against what I just saw — and giving them one rule would make one of them wrong.
