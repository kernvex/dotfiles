# The status line reads the routing map, and a seat can be correct by declaration

> **Supersedes ADR 0007 in part** — specifically its refusal to read a seat map. It does not
> touch 0007's other decisions, and ADR 0014's hue is unaffected.

ADR 0007 rejected "a declarative seat map committed to this repo" in the
strongest terms available: *a claim rather than an observation… A stale green
light is worse than no light.* The seat segment has compared observations ever
since — the account in the seat's own config file against the identity git
resolves in that directory.

That comparison cannot answer three questions, and all three are live on this
machine.

**A work folder's own root is not a repository.** Routing was decided by whether
git matched an `includeIf gitdir:` rule, which is false at the root — so a
correctly routed seat rendered yellow there. That root is where Claude is
actually launched for one of these clients, which is how the fault went
unnoticed: it looked like a quirk of one directory rather than a wrong answer.

**Some folders route git but no seat.** One client's identity has no Claude seat
at all, so the default seat is the only seat there is. The segment called that a
mismatch and painted it red — a false alarm, and a red that cries wolf is a red
that stops being read.

**A deliberate seat override is indistinguishable from a fault.** Both are the
default seat answering inside a work folder. No observation separates them,
because the difference is intent.

**Decision: read `~/.config/identity/map.json` when the directory falls inside a
work folder it declares, and treat a declared override as verified.**

## Why this is not what 0007 refused

0007 refused a map *committed to this repo* and maintained by hand — a claim
that could drift arbitrarily far from reality while still looking authoritative.
This is a different artifact. It is generated output, emitted by the run that
generates the routing itself, from the same data. It cannot be confidently ahead
of the behaviour it describes: edit a declaration without applying, and the map
still reports what was actually generated. Its own repo makes staleness the
point, and forbids the word "cache" for it on the grounds that a cache may be
refreshed independently of what it describes.

The observation 0007 protected is also still here. Inside a work folder the map
supplies the *assignment*; what is actually in force is still read from the
environment and the seat's own config, and the two are compared. Nothing is
believed because a file said so.

## The marker, and why three conditions

`IDENTITY_SEAT_OVERRIDE` carries intent only. The word `OVERRIDDEN` appears only
when the marker is set **and** the seat in use is the default one **and** the
folder routes a different seat. Any one of those failing removes the word rather
than making it false — so a marker that outlives what it describes goes quiet
instead of lying. A claim believed on its own would eventually assert an override
that is not in force, which is 0007's stale green light by another route.

## Consequences

**Magenta now means one sentence, slightly wider than before:** the seat
answering is the intended one — established by routing, by data, or by
declaration. The word on the segment says which, so the colour stays unambiguous.
ADR 0014, which moved the hue, is unaffected.

**A machine with no identity tool is unchanged.** An absent or unreadable map
falls straight back to the git comparison, which is asserted deliberately in
`test-statusline-seat.py` rather than left to whether a map happens to exist.

**The map's location is overridable** (`STATUSLINE_IDENTITY_MAP`) so the tests can
stand up a synthetic machine — fake folders, fake seats, fake map — and name no
employer in a public repo, the same bargain ADR 0001 struck for git rules.
