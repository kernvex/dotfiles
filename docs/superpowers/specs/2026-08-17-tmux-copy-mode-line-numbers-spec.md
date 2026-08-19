# Line numbers in copy mode, and a `:` that lands on the line

Date: 2026-08-17
Status: ready-for-agent

## Problem Statement

Reading back over a long transcript in copy mode, there is no way to say "take me
to that line." You can search for text you remember, or scroll until the thing
reappears, but you cannot name a position and go to it. Every reference to a
place in the scrollback has to be re-derived by eye.

tmux can already do both halves of the obvious fix, and both are unusable as
shipped. The line-number gutter exists from 3.7 onward but defaults to `off`.
`:` is already bound to `goto-line` in `copy-mode-vi`, but it does not do what a
vim reflex expects: it scrolls the requested line to the top row and leaves the
cursor wherever it already was. Measured in an 80x20 pane against a 200-line
buffer, `:30` left the cursor 19 rows below the target — and the miss is not a
constant to learn around, it is wherever the cursor happened to be sitting when
the key was pressed.

The consequence is not cosmetic. Typing `:30`, then `v`, then `jj`, then `y`
yields a selection that begins nineteen lines low and mid-word:

```
vanilla  ->   ne-44                wanted  ->   content-line-25
              content-line-45                   content-line-26
              content-lin                       c
```

## Solution

Draw the gutter with absolute, history-anchored numbering, and rebind `:` so
that the number read out of the gutter is the number typed at the prompt and the
cursor lands on that line.

The gutter costs nothing outside copy mode — the option is only consulted while
copy mode renders — so there is no toggle to remember and no state to manage.
Inside copy mode it costs a 4-to-7 column gutter and clips the right edge of
full-width lines, which is the accepted price.

## User Stories

1. As someone reading a long transcript, I want each line in copy mode to carry a number, so that I can refer to a position instead of describing it.
2. As someone reading a long transcript, I want those numbers anchored to the top of the history, so that a number I noted a moment ago still means the same line after the pane prints more output.
3. As someone who has scrolled far back, I want to type `:` followed by a number, so that I can jump to a line directly rather than scrolling to it.
4. As someone jumping to a line, I want the cursor to end up on that line, so that the jump is a real move and not just a scroll.
5. As someone jumping to a line, I want the number I type to be the number I can see in the gutter, so that I never have to translate between two coordinate systems.
6. As someone jumping to a line, I want the position indicator to agree with where the cursor is, so that two numbers on screen never contradict each other.
7. As someone selecting text, I want to jump to a line and immediately press `v`, so that a selection starts exactly where I aimed.
8. As someone copying a block, I want the yanked text to begin at the line I jumped to, so that I do not have to inspect and fix the clipboard afterwards.
9. As someone copying a block, I want the selection to start at the beginning of the target line rather than mid-word, so that the paste is usable as-is.
10. As someone mid-selection, I want `:N` to extend the selection to the target, so that the jump composes with `v` the way it does in vim.
11. As someone who mistypes a line number far beyond the buffer, I want to land at the end of the buffer rather than see an error, so that a typo is a harmless over-scroll.
12. As someone searching with `/`, I want the gutter present during the search, so that I can note the line a match landed on.
13. As someone who has found a match, I want to be able to leave copy mode and come back to that line by number, so that the position survives the round trip.
14. As someone working in a plain pane, I want no gutter and no lost columns, so that normal output is never narrowed by a copy-mode feature.
15. As someone who never enters copy mode in a given pane, I want to pay no cost at all for this feature, so that it is invisible until asked for.
16. As someone reading in a themed terminal, I want the gutter to use the catppuccin palette, so that it recedes instead of competing with the content.
17. As someone reading in a themed terminal, I want the current line's number highlighted distinctly, so that I can see where the cursor is without hunting.
18. As someone reading in a themed terminal, I want the current-line colour not to collide with a colour that already means something else in the status bar, so that colour keeps carrying one meaning each.
19. As someone who installs these dotfiles on another machine, I want an older tmux to load the config without error, so that a version difference degrades quietly instead of breaking the whole config.
20. As someone who installs these dotfiles on another machine, I want the feature simply absent on an older tmux rather than half-applied, so that there is no partially-working state to debug.
21. As someone who already relies on `'` to resume a scroll position, I want that binding to keep working unchanged, so that a new feature does not cost me an old one.
22. As someone who relies on `q` and `Escape` recording scroll position on the way out, I want that behaviour untouched, so that the existing copy-mode contract holds.
23. As a maintainer, I want the shipped config string itself asserted by the tests rather than a hand-copied duplicate, so that a test cannot pass against a config that no longer says that.
24. As a maintainer, I want the stranded-cursor behaviour captured as explicit regression evidence, so that a future change that reintroduces it fails loudly.
25. As a maintainer, I want the parts that cannot be tested headlessly named as such in the test file, so that the gap is a documented decision rather than an oversight.
26. As a maintainer, I want the tests to run on their own tmux socket, so that running them never disturbs the live server or its sessions.
27. As a maintainer, I want the theme to be resolved before colour assertions run, so that the tests are not flaky on TPM's load timing.
28. As a maintainer, I want the reasoning recorded next to the config, so that a future reader knows why absolute was chosen over the default numbering.

## Implementation Decisions

**Numbering is `absolute`, not `default`.** The default mode numbers each row by
its distance from the current scroll offset, measured off the pane bottom, so
every line the pane prints renumbers the buffer underneath the reader. This is
the same instability the existing scroll-resume binding already refuses to rely
on, and its comment already argues the case: an offset measured from the bottom
is wrong the moment the bottom moves. Absolute numbering is anchored to the top
of the history and holds still.

`relative` and `hybrid` are rejected outright on a correctness ground rather than
a taste one: both display numbers relative to the cursor while `goto-line`
continues to consume absolute ones, so the number on screen is not the number to
type. That defeats the entire purpose.

**`:` is rebound to jump and then land.** `goto-line` sets only the scroll
offset; it never touches the cursor row. Following it with `top-line` moves the
cursor to screen row 0, which under absolute numbering is exactly the requested
line. Verified against a live server: cursor on the target, screen row 0,
indicator reading the requested number.

This also resolves what looked like a separate problem. Because the cursor ends
at the view top, the position indicator — which reports the top of the view —
describes the cursor and the view at once. No rewrite of the position format is
needed, and the two numbers cannot disagree.

The binding is two commands in one block, from a prototype run against a live
server:

```tmux
bind -T copy-mode-vi : command-prompt -p "(goto line)" {
  send -X goto-line -- "%%"
  send -X top-line
}
```

**The target line lands at the top row.** Centring it is possible but would move
the cursor off the view top, which is precisely what keeps the indicator honest.
Landing at the top also suits the common motive for jumping, which is to read
forward from a point.

**A jump extends an active selection.** `goto-line` updates the selection, so
`v` followed by `:N` stretches to the target. This matches vim and is left as-is.

**An out-of-range number clamps to the end of the buffer.** With the rebind this
makes a wild number behave as a second `G`. Rejecting it instead would mean
parsing and validating the count in the binding, which is not worth it for a
harmless outcome.

**There is no toggle, because none is needed.** The option is only consulted
while copy mode renders. Outside copy mode there is no gutter and no column
cost, so "only while in copy mode" is the plain behaviour of setting the option.
Conditioning the gutter on a sub-state of copy mode — showing it during a search
but not while merely scrolling — was considered and rejected: changing the gutter
width mid-session shifts the pane's text sideways by several columns while it is
being read.

**Everything is wrapped in a version guard.** The option and both style options
arrived in tmux 3.7; an unrecognised option is a load-time error, which on an
older machine would break the whole config rather than this one feature. The
guard is a format comparison on `#{version}`, verified to answer correctly on
the 3.7c build in use here.

**Styles are set with theme references and expand at draw time.** A style option
stores its format unexpanded and resolves it against a format tree when the
gutter is painted, so a `@thm_*` reference resolves long after TPM has loaded.
This was checked rather than assumed, and it means the block has no ordering
constraint relative to the plugin loader — unlike the status-bar spacer, which
does. The gutter takes a recessive overlay colour and the current line takes the
peach accent in bold.

**Accepted costs, to be recorded in the config comment.** The gutter is
`digits(history) + 1` columns wide, which against the 200k history limit in use
here is seven columns, and it grows as a pane's history grows. Content is shifted
right by that width and clipped at the right edge rather than rewrapped. Both are
paid only inside copy mode.

**One link is unverified.** Whether `command-prompt` carries a two-command
template could not be established headlessly: driving the prompt requires an
attached client, and sending keys while the prompt is open blocks tmux's command
queue. Every step downstream of it is verified. If it misbehaves in practice, the
fallback is the `run-shell` with an explicit pane id that the `'` binding in this
config already uses for exactly this reason.

**A carve-out that does not currently apply.** tmux keeps line numbers off when
copy mode is entered with the mouse. The live config sets `mouse off`, so copy
mode is never entered that way here and the carve-out never fires. It becomes
relevant only if mouse mode is restored, at which point wheel-entered copy mode
would silently have no gutter.

## Testing Decisions

A good test here asserts observable behaviour — where the cursor ended up, what
the indicator reads, what colour actually resolved — and never the internal shape
of the config. It also asserts the *shipped* string: the established practice in
this repo is to read the value out of the running server or out of the checked-in
config rather than restating it in the test, so that a test cannot pass against a
config that no longer says that.

**A new test script**, a sibling of the existing tmux test scripts, on its own
tmux socket, sourcing this checkout's real tmux config. Its own socket so that
running it never disturbs the live server or its sessions. Exit status is
asserted, not merely output, consistent with the other test scripts here.

**Prior art to follow closely.** The mode-indicator test script is the template
for the harness: private socket, real config sourced, copy mode driven with
`send-keys -X`, a wait loop for the theme before any colour assertion, and a
frank header note about what a headless server cannot exercise. The claude-tmux
test script is the template for the shipped-string-not-a-duplicate principle.

**Asserted behaviourally**, by issuing the same commands the binding issues:

- Under absolute numbering, jumping to line N and then moving to the top line
  puts the cursor on absolute line N — checked both as the reported position and
  as a cursor row of zero.
- After such a jump the indicator agrees with the cursor. This is the property
  that removed the need to touch the position format, so it is the one most worth
  locking down.
- Jumping alone, without the follow-up, leaves the cursor stranded away from the
  target. Captured deliberately as regression evidence, in the same spirit as the
  existing test that first proves an earlier guard really did over-match.
- A number far beyond the end of the buffer clamps to the end rather than
  erroring.

**Asserted statically**, because a headless server cannot type at a prompt:

- The `:` binding in the copy-mode-vi table carries both the jump and the
  land-on-line commands.
- The numbering option is absolute, and both style options resolve through
  format expansion to non-empty theme colours.

**Declared untestable, with the reason in the header:** the round trip through
the interactive prompt. This is the same class as the prefix pill in the
mode-indicator tests, which that file already documents as static-only and
eyeballed live; carry that wording over rather than invent a new excuse for it.

## Out of Scope

- Conditioning the gutter on a sub-state of copy mode.
- Centring the target line, or any minimal-scroll placement.
- The relative and hybrid numbering modes.
- Rewriting the copy-mode position format, which this design makes unnecessary.
- Restoring mouse mode, and the gutter carve-out that would come with it.
- Changing the history limit, which is load-bearing for AI transcripts.
- Any backport or emulation for tmux older than 3.7; those machines get the
  feature absent, by design.
- Numbering anywhere outside copy mode.

## Further Notes

**An ADR is stale in this area.** ADR 0004 records mouse mode as adopted for the
wheel, while the live config has set it off since the copy-mode crash of
2026-08-11 and explains why at length. This spec does not change that state
either way, but the contradiction is worth resolving separately, and the mouse
carve-out above is the reason it surfaced here.

**A version-comparison caveat.** The guard compares version strings, which orders
3.10 below 3.7. It answers correctly for every version that exists today and for
the 3.7-or-newer question being asked, but it is not a general version
comparator and should not be copied as one.

**Glossary candidates, deliberately not added.** This feature introduces
vocabulary — the gutter, an absolute line, the position indicator — that is tmux's
rather than this repo's. The glossary is for terms this repo coins, so these were
left out; revisit if they start appearing in commit messages and issue titles.

**No ADR proposed.** The decision is cheap to reverse (three options and one
binding), unsurprising to a reader who finds the config comment, and the genuine
trade-offs are recorded above and in that comment. It fails all three of the
tests for wanting an ADR.

## Amendment, 2026-08-17 (during implementation)

Two things this spec asserts were found to be wrong while building it. Recorded here rather
than edited into the text above, so that what was believed at design time stays legible.

**The version guard became a capability probe.** The spec specified a comparison on
`#{version}` and noted in Further Notes that it "orders 3.10 below 3.7" but answers correctly
today. Measured during review, `#{>=:3.10,3.7}` is `0`: the comparison is numeric, so a future
tmux 3.10 would not merely mis-sort, it would silently drop the whole block. The guard now asks
whether the option exists instead, which is the real question and cannot be broken by a
renumbering.

**The command-prompt round trip is no longer untestable.** The spec declared it so, with the
reason, and asked the test file to say the same. That was true only of a *single* headless
server. A second tmux server whose pane attaches to the first gives the server under test a
real client, and the keystroke can then be driven and asserted end to end — and the outer
capture is also the only place the rendered gutter can be read, since it is drawn over the
mode's screen and never reaches the inner pane's grid. Both are now covered, so the test file
declares nothing untestable.

**The current line is rosewater, not peach.** Implementation Decisions above named peach, and
that contradicted user story 18 in this same spec: peach is already the Claude window pill, so
it would have been a second meaning for a colour that has one. Review caught the contradiction
and the choice was reversed. Rosewater is spent nowhere else in the config, and it is the
strongest contrast in the palette at 12.9:1 on base — against the gutter's own 4.4:1, which is
what makes the current line unmistakable among the dim numbers around it. Teal read better on
paper at 11:1 but sits close to sky, the copy-mode pill that is on screen at the same moment.

One deliberate addition beyond the enumerated testing list: a case that moves the cursor off
the top row and checks the line under it against independently fetched content. It replaced an
assertion that compared `copy_position + copy_cursor_y` to the target while `copy_cursor_y` was
known to be zero, which could not fail.

## Amendment, 2026-08-18 (after using it) — superseded by the entry below

**Numbering reversed to bottom-anchored.** This spec chose `absolute` and argued the case at
length, and the argument held on its own terms — those numbers do not drift. What it never
weighed was the interaction with the `history-limit 200000` set a few lines above it in the same
config: absolute counts from the OLDEST line, so in practice every line worth reading was six
digits and reaching recent output meant typing `:198420`. Stable and unusable.

`default` numbering is bottom-anchored: the newest end is 0 and the count grows backwards into
history, putting the lines actually revisited under `:100`. Its cost is the drift this spec
originally rejected it for, now accepted deliberately — a number is good while you read and
stale after the next turn of output, which is how the jump is used.

Two consequences worth recording. Within the last screenful the numbers descend to 0 and climb
back, so two lines there can share a number; harmless, because that region is on screen anyway.
And an out-of-range number clamps to the OLDEST line rather than the newest, since counting
backwards makes a large number a request for deep history — the opposite end from before.

The rebind, the guard, the styles and every test but the coordinate arithmetic were untouched by
this. That is the coupling ADR 0011 warned about, arriving on schedule: one option changed, and
the test's coordinates inverted and the out-of-range case flipped direction, with nothing in
tmux to catch either.

## Amendment, 2026-08-18 (second pass, after seeing it on screen)

`default` was wrong too, and the screenshot settled it in a way none of my measurements had:
parked at the end of the buffer it renders 0 at the TOP of the screen with the count growing
downward. I had measured that case, called it "the degenerate bottom screenful", and failed to
notice it is the case you are in every single time you enter copy mode.

The requirement, stated plainly, is 0 at the cursor with the count growing upward into history.
Only `relative` renders that, and it forces a second change: `goto-line` consumes absolute
coordinates no matter what the gutter displays, so `:` cannot be a jump at all. It now sends a
counted `cursor-up`, the only motion that means what a relative gutter says.

What that buys, all measured through a real attached client: past the top it scrolls rather
than stopping; past the oldest line it clamps; a bare Enter is a silent no-op; a typo'd word
moves nothing and reports "Repeat count invalid". The tests assert each one, including the
rendered gutter reading 0 at the cursor and 1, 2, 3 going back.

The lesson worth keeping is about the evidence, not the option. Every mode was measured before
being chosen, and twice the measurement was of the wrong situation — a scrolled buffer when the
common case is an unscrolled one. Rendering the thing and looking at it caught in one screenshot
what three rounds of format probes had not.

