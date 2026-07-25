# tmux is tuned for full-screen TUIs, not just shells

The tmux config was written for a workflow of shells and Neovim, where every keystroke
either belongs to tmux (behind the prefix) or to a program that reads line-oriented
input. Claude Code broke three of its assumptions at once, and each symptom looked
cosmetic while actually pointing at a real gap.

**Colour.** Claude rendered its mascot and welcome box in pink instead of Claude orange.
The cause is not the terminal pipeline: WezTerm reports `COLORTERM=truecolor`, tmux
carries 24-bit colour through correctly (starship's prompt in the same pane emits
`38;2;…`), and `capture-pane -e` confirms tmux stores RGB. Claude Code clamps *itself*
to the 256-colour palette whenever `$TMUX` is set — a defensive heuristic from before
`COLORTERM` was standard — and `#d97757` quantises to colour 174, `#d787af`, which is
pink. `env -u TMUX claude` restores truecolor, which is how the cause was isolated;
`CLAUDE_CODE_TMUX_TRUECOLOR=1` opts out of the clamp without lying about the
environment. Set via `set-environment -g` so it reaches every pane, tmux-launched or not.

**Mouse.** Lesson 2 of the tmux course argues mouse mode off is deliberate: clicking
panes and dragging borders is a habit that does not survive a keyboard-only remote
session. That argument holds for *navigation* and does not extend to *scrollback*.
Neovim and other alternate-screen programs are scrolled by their own keys; a program
that renders inline on the normal screen — Claude Code, a plain shell — has no scroll
of its own, so with `mouse off` the wheel does nothing at all and reading back over a
long transcript means entering copy mode for every glance. `mouse on` is therefore
adopted for the wheel, and the navigation discipline is kept by habit rather than by
removing the capability. The cost is that a drag now selects into a tmux buffer instead
of the terminal's, so `MouseDragEnd1Pane` is bound to `copy-pipe-and-cancel pbcopy` to
make selections reach the macOS clipboard anyway (holding Option in WezTerm still gets
a native selection).

**Ctrl-f.** The sessionizer was bound in two places, and both had a hole. The fish
binding only fires at a fish prompt, so inside any full-screen TUI the keystroke goes to
that program instead — the jump reflex silently stopped working exactly where the
sessions matter most. And `bind f run-shell tmux-sessionizer` could never have worked:
`run-shell` gives the command no tty, and fzf needs one.

**Decision:** bind `C-f` in the **root** key table, so tmux intercepts it ahead of any
program in the pane, and run the picker in a `display-popup -E` rather than `run-shell`.
Programs that legitimately own Ctrl-f (vim/view page-forward, `less`, `more`, `man`,
`fzf`) get it passed through via `if-shell -F` on `pane_current_command`, which is a
format evaluation and costs no subprocess. Keep the fish binding: it is what serves the
case of *not being in tmux yet*.

**Consequence:** `pane_current_command` reports the pane's foreground process, and tmux
resolves that imprecisely for a pipeline — `seq 1 500 | less` reports `fish`, so Ctrl-f
there opens the picker instead of paging. Programs launched directly, including every
editor invocation, resolve correctly. Root-table bindings are also global: any future
key added there is taken away from every program in every pane, so this table stays
deliberately small.

## A directory maps to one session, and sometimes you want two

`tmux-sessionizer` names a session after the directory's basename and reuses it, which
is the guarantee the whole workflow rests on: you never ask whether a project is already
running. It is also the reason a second terminal opened on a repo lands in the session
the first one is already in — which, when that session is running Claude Code, looks
like Claude resumed a previous conversation when in fact tmux handed back the same pane.

**Decision:** do not touch the sessionizer's one-directory-one-session rule; add
`bin/.local/bin/tmux-session-here` beside it for the explicit case. It creates sibling
sessions named `<project>-<label>` (`dotfiles-review`, `dotfiles-refactor`), rooted at
the same directory, auto-numbering to `<project>-2`, `-3`, … when no label is given.
Bound to prefix-`F`, which prompts for the label. Because the sessionizer already lists
live sessions as `[TMUX] …` entries in its picker, the siblings are reachable through
the same Ctrl-f afterwards with no further machinery.

**Consequence:** labels are sanitised to `[A-Za-z0-9_-]` — `.` and `:` are tmux target
separators and cannot survive into a session name. Sibling sessions are independent
workspaces, not clones: nothing is copied from the original session, and killing one
leaves the others alone.

The dominant case for a second session is narrower than "two agents building in
parallel": it is *one agent is mid-edit and I have a question*. Interrupting the working
agent costs its momentum and drags a detour through its context, and a second unrestricted
Claude on the same working tree is a genuine hazard — tmux isolates screens, not files, so
two writers clobber each other silently. Both problems disappear if the second session
cannot write.

**Decision:** `bind A` for a `<project>-ask` sibling running
`claude --permission-mode plan`. Plan mode is enforced by the tool rather than by
remembering not to ask for edits, so the sidecar is safe alongside an active writer by
construction. One per project, and re-pressing returns to it, mirroring the
one-session-per-project reflex. `git worktree` remains the answer for the rarer case where
the second agent genuinely must write; it is deliberately not automated here, because
reaching for it should be a decision.

**Consequence:** the sidecar shares the tmux server with the agent it is asking about, so
it can read that agent's screen directly (`tmux capture-pane -p -t <session> -S -200`) and
answer from evidence rather than from a summary. It does not share context or conversation
history with it.
