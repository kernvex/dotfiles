# Copy mode numbers absolutely, and `:` moves the cursor rather than the view

tmux 3.7 can draw a line-number gutter in copy mode, and `:` has always been bound to
`goto-line`, so "jump to line 20" looks like it needs no decision at all. Both defaults are
wrong for the job in ways that only surface under measurement, and the two corrections are
coupled to each other — which is the reason this is written down rather than left to the
comment beside it.

**Numbering is absolute, not the default mode.** The name suggests a neutral choice and it is
not one. Default numbering labels each row with its distance from the current scroll offset,
measured off the pane bottom, so every line the pane prints renumbers the whole buffer
underneath the reader; a number noted during one turn of a Claude transcript means a different
line by the next. This is the same drift the scroll-resume binding already refuses to rest on,
for the same reason. Absolute numbering is anchored to the top of the history and holds still,
which is the only property that makes a number worth writing down. `relative` and `hybrid` are
rejected on a harder ground than taste: both label rows relative to the cursor while
`goto-line` goes on consuming absolute numbers, so the number on screen is not the number to
type and the gutter would actively mislead.

**`:` is rebound because tmux's own binding moves the view and not the cursor.** `goto-line`
sets the scroll offset alone and never touches the cursor row. Measured in an 80x20 pane
against a 200-line buffer, `:30` left the cursor nineteen rows below the target — and that is
not a constant to learn around, it is wherever the cursor happened to be sitting when the key
was pressed. The cost lands on selection rather than on reading: `:30` then `v` then `jj` then
`y` produced three lines starting nineteen low and mid-word. Sending `top-line` after the jump
puts the cursor on row 0, which under absolute numbering is the requested line. A reader who
finds `:` rebound will reasonably assume the stock binding was fine and revert it. It is not,
and this paragraph is the answer.

**The two halves are one decision.** `top-line` lands on line N *because* the numbering is
absolute — row 0 is line N in that mode and in no other. Switch the numbering back to the
default and the binding keeps working, keeps looking correct, and silently arrives somewhere
else. Nothing in tmux couples the option to the binding, so the coupling lives here and in the
config comment; anyone changing one must change the other.

**Consequences.** The gutter is `digits(history) + 1` columns wide and grows as a pane's
history grows — seven columns against the 200k limit in use here. Content is shifted right by
that width and clipped at the right edge rather than rewrapped. Both are paid only while copy
mode renders, and a live pane is untouched, which is precisely why the feature needs no toggle
and has none. All of it is 3.7 or newer, and an unrecognised option is a load-time
error, so an older tmux on another machine must lose this one feature rather than its whole
config. The guard probes for the option rather than comparing versions: `#{>=:}` compares
numerically, so `#{>=:3.10,3.7}` is false and a version test would silently drop the block on
tmux 3.10. "Does this tmux have the option" is both the real question and immune to how
releases are numbered.

Two things deliberately were *not* done, recorded so they are not done later. The position
indicator needed no change: with the cursor at the view top, the number it reports describes
the cursor and the view at once, so the two cannot disagree — a whole branch of the design
dissolved on that measurement. And no sub-state toggle was built; showing the gutter only
during a search would change its width mid-session and shift the text sideways while it is
being read.

The keystroke itself is verified, which it nearly was not. Whether `command-prompt` carries a
two-command template cannot be established on a headless server — driving that prompt needs an
attached client, and sending keys while it is open blocks tmux's command queue rather than
typing into it. The way through is a second tmux server whose pane attaches to the first, which
gives the server under test a client that genuinely exists; typing `:42` that way lands the
cursor on line 42 at row 0. The same outer capture is the only place the gutter can be READ,
since it is painted over the mode's screen and never reaches the inner pane's grid. The
`run-shell` fallback that the scroll-resume binding uses turned out not to be needed.

Finally, tmux keeps line numbers off when copy mode is entered with the mouse. That carve-out
is inert here — ADR 0004 records the mouse as off — but it goes live the moment the mouse
returns, and wheel-entered copy mode would then draw no gutter.
