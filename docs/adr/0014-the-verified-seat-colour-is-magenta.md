# The verified seat colour is magenta, because bright blue could not be seen

ADR 0007 gave the seat segment four states and one colour each, and fixed the
meaning of the fourth: `mismatch` is red, `unverifiable` is yellow, `neutral` is
dim, **which leaves blue meaning one thing only — a comparison ran and passed.**

The reasoning held. The colour did not.

**The problem.** Bright blue (`94`) and dim (`2`) render close enough to each
other in this machine's terminal theme that they are not distinguishable at a
glance. So the state meaning "checked, and correct" looked identical to the state
meaning "nothing to say", and the segment's most informative verdict was the one
nobody could read.

This went unnoticed for as long as the segment has existed. It surfaced only
because the machine owner reported never having seen blue at all, which was
investigated as a suspected logic fault.

**The evidence.** A temporary file-gated probe logged one line per state change
for five days: 564 renders, of which **467 were `verified`** — every one of them
correctly computed, correctly painted, and read as grey. Four competing
hypotheses died on that data: the routing variable was present on all 467, the
git context never failed once and never approached its timeout, the folder rules
matched every time, and both addresses agreed in every case. The surviving
hypothesis was the only one no log could test, and it was settled by putting the
four states side by side and asking a human which was which.

**Decision: `verified` is bright magenta (`95`).**

Chosen by eye from a rendered swatch of candidates, against this file's existing
meanings. Every alternative collided with something already spoken for:

| Candidate | Why not |
|---|---|
| `94` bright blue | indistinguishable from `DIM` — the fault being fixed |
| `92`, `96` | read as green, which is the branch |
| `97`, `1;94`, `1;36` | read as bright white, which is the model name |
| `34` | separates from `DIM`, but weakly enough that it would need re-checking on any theme change |
| `35` magenta | works; `95` was preferred for a wider separation |

The *meaning* of the colour is unchanged from ADR 0007: a comparison ran and
passed. Only the hue moves.

**Consequence — the suite protects one half, and only one.** The states live in a
table (`SEAT_STATES`) where each row carries its colour, its badge, and what that
colour *asserts*. The rule is expressible from that: two states may share a colour
exactly when they assert the same thing, and when they do, a badge must tell them
apart. `verified` and `overridden` are the standing case — both say the seat
answering is the one meant to answer, one by routing and one by declaration.
`test-statusline-seat.py` derives the check from the table rather than restating
it, so a state added later is checked without anyone remembering to.

That is still the weak half. The failure this record exists to describe was two
*different* codes rendering as the *same* colour, and no assertion can see a
rendered pixel. `seat-colour-swatch.sh` prints every state together for a human,
and it is the real test. Run it after any theme change.

**Consequence — a colour is a claim about a person's eyes, not about a file.**
The palette in `statusline-pace.py` is written as though picking hues were a
matter of avoiding collisions between codes. It is not: it is a matter of
avoiding collisions between *rendered* colours, which depend on a theme this repo
does not control and cannot read. Any future palette change is a change to be
looked at, not merely reviewed.
