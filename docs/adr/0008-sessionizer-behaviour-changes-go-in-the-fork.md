# Sessionizer behaviour changes go in the fork, not in a wrapper

The session picker is not a script in this repo. It is a fork of the upstream
sessionizer, vendored as a git submodule and symlinked into the stowed `bin`
package — so `bin/.local/bin/tmux-sessionizer` is a pointer, and there is nothing
there to edit. Every change to how the picker behaves has to be put somewhere,
and the choice recurs each time.

**Decision:** put it in the fork, on its default branch, and follow it with a
submodule pointer bump here. Two commits in two repos, which is the price the
existing local commits (the TCC-denial fix, the search-path dedupe) already pay.

The fork has no `upstream` remote configured — only `origin`, pointing at an
account-owned copy. It was adopted rather than tracked, so the usual argument for
keeping a vendored dependency pristine does not apply: there is no upstream
rebase to protect, and there has not been one.

**Considered: a wrapper script in `bin`** that sets fzf options and execs the
real script. It keeps the submodule untouched, which is why it is the obvious
suggestion, and it is what the rest of `bin` looks like. It was rejected because
picker behaviour is not only flags. The yank added in this ADR's originating work
has to turn a `[TMUX] <name>` line into a **candidate path**, which is logic that
belongs beside the code that produced the line; a wrapper would either duplicate
that or shell back into the script anyway. One feature would then live in two
repos with the seam in the wrong place.

**Considered: injecting fzf bindings through the global `FZF_DEFAULT_OPTS`** set
in the fish config. The tmux server does export that variable to the popup, so it
genuinely reaches the picker — which makes this the trap rather than the
non-starter. It was rejected because it would bind the key in *every* fzf on the
machine, including the file widgets where the placeholder is a filename rather
than a directory, and where the same keystroke would then mean something subtly
different.

**Consequence — the fork diverges further from upstream.** Each such change makes
a future rebase onto the original project more work. That is accepted, not
overlooked: the fork's own history is a run of unhelpful automated commit
messages, and no rebase was realistically going to happen.

**Consequence — a submodule bump can silently undo a feature.** Anything shipped
this way needs a tell that survives into the UI. The yank's footer row in the
picker is one: if it stops being drawn, the feature left with it, and that is
visible before a keypress finds out the hard way.
