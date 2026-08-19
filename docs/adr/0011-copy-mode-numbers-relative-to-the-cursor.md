# Copy mode numbers relative to the cursor, and `:` is a motion rather than a jump

tmux 3.7 can draw a line-number gutter in copy mode, and `:` has always been bound to
`goto-line`, so "read a number and jump to it" looks like it needs no decision at all. It took
three attempts, because tmux's three numbering modes answer three different questions and only
one of them is the question a person reading back through a transcript is asking.

**Numbering is `relative`: 0 is the cursor, and the count grows upward into history.** That is
the direction you travel when reading back, and it keeps the numbers small no matter how deep
the buffer is. The two rejected modes both failed on the same axis, and are recorded so they
are not tried again:

- `absolute` counts from the OLDEST line. Perfectly stable, and unusable here: against the
  200k history this config sets, every line worth reading was six digits, so reaching recent
  output meant typing `:198420`.
- `default` counts from the scroll anchor, which sounds bottom-relative and is not. Parked at
  the end of the buffer it renders 0 at the TOP of the screen and grows downward — exactly
  backwards — and within the last screenful it descends to 0 and climbs again, so two lines
  can wear the same number.

The cost of `relative` is that the numbers are anchored to something that moves: they renumber
as the cursor does. A number is good for the jump you are about to make, not one to note down.
That is the right trade for this use, where the number is read and used in the same breath.

**`:` does not call `goto-line`, because `goto-line` cannot agree with this gutter.** tmux keeps
the jump on absolute coordinates whatever the display says — `relative` and `hybrid` change only
what is drawn — so typing the number you just read would land in the oldest lines. `:` therefore
sends a counted `cursor-up`, which is the only jump that means the same thing the gutter does.

That choice pays for itself in the edges, all measured: a count that runs past the top scrolls
the view rather than stopping at the screen edge; a count past the oldest line clamps there
instead of erroring; a bare Enter is a silent no-op; and a typo'd word moves nothing and says
"Repeat count invalid" on the status line. You stay in copy mode throughout.

**The option and the binding are one decision.** The binding is a *relative* motion and is
correct only while the gutter is *relative* too. Change the mode alone and it still runs, still
looks right, and quietly means something else. Nothing in tmux couples them, and the history
above is the evidence: each numbering change forced a matching change to the binding or to the
test's arithmetic, and tmux caught none of it.

**Consequences.** The gutter costs a few columns and clips the right edge of full-width lines,
paid only while copy mode renders — a live pane never draws it, which is why this needs no
toggle and has none. After a counted motion the cursor sits on the top row, so the numbers
visible below it count downward away from the cursor; relative numbering is symmetric, as in
vim, and the useful direction is the one going back.

All of it is 3.7 or newer, and an unrecognised option is a load-time error, so an older tmux
must lose this one feature rather than its whole config. The guard probes for the option rather
than comparing versions: `#{>=:}` compares numerically, so `#{>=:3.10,3.7}` is false and a
version test would silently drop the block on tmux 3.10. "Does this tmux have the option" is
both the real question and immune to how releases are numbered.

The keystroke itself is verified, which it nearly was not. A command-prompt cannot be driven on
a headless server — sending keys while the prompt is open blocks tmux's command queue rather
than typing into it. The way through is a second tmux server whose pane attaches to the first,
giving the server under test a client that genuinely exists. The same outer capture is the only
place the gutter can be READ, since it is painted over the mode's screen and never reaches the
inner pane's grid.
