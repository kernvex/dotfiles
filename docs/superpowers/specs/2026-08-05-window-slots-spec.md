# Window slots: one key, one window

Date: 2026-08-05
Status: ready-for-agent

> **Placeholders only.** This repo is public and `CONTEXT.md` keeps employer and
> coworker identity out of it entirely. Browser identities are written here as
> `<profile name>` or with invented names (`Sam Weber`, `Northwind`); profile
> directories (`Default`, `Profile 70`) are Chrome's own opaque identifiers and
> name nobody, so they appear as-is.

See `docs/adr/0009-window-slots-resolve-by-profile-signature.md` for the decision
and the measurements behind it. Vocabulary is in `CONTEXT.md` under **Window
navigation terms** — *slot*, *slot table*, *target*, *browser identity*, *profile
directory*, *profile name*, *profile signature*, *reachable window*, *pinning*,
*adoption*.

## Problem Statement

Navigation everywhere else on this machine costs one key. Harpoon reaches a file,
`cmd+<digit>` reaches a WezTerm tab, `prefix+<digit>` reaches a tmux window. Each
digit means one place and keeps meaning it. macOS windows are the hole in that
map, and `Hyper+<digit>` firing `open -a` only looks like it fills the hole.

It fails on the one case that matters most. Three or four Chrome windows are open,
each signed into a different Google account, and they cannot be merged into one
window because the accounts are the whole point of keeping them apart. `open -a
'Google Chrome.app'` names all of them equally, so the digit stops meaning a place
and starts meaning "some browser, whichever macOS feels like". The digit that was
supposed to be muscle memory becomes a coin flip, and the only reliable way to
reach a specific account is to look at the screen and click.

Three of the existing app slots are dead besides — they point at applications that
are no longer installed and fail silently — so the keyboard already lies about
what it can reach.

## Solution

`Hyper+<digit>` reaches a **slot**, and a slot names one destination permanently.
A slot's **target** is either an application, where any window will do, or a
**browser identity**, where exactly one Chrome profile's window is the right
answer and nothing else is.

Pressing a slot puts you in that window. If several windows belong to that browser
identity, you get the one you used most recently. If the engine did not open the
window itself, it recognises the window anyway by its **profile signature** and
claims it — **adoption**. If no such window exists at all, the slot opens the
profile and remembers what it opened. If you are already in the slot's window,
nothing happens.

The **slot table** is never edited by hand. **Pinning** binds a slot to the browser
identity of the window in front of you, so setting the whole thing up on a new
machine means opening your windows and pressing a key per window.

Because only **reachable windows** — those on the active Desktop — can be found or
focused at all, every window a slot can reach lives on a single Desktop, with
native full-screen given up system-wide, terminal included.

## User Stories

1. As someone navigating by muscle memory, I want `Hyper+<digit>` to reach the same
   destination every time, so that I never have to look at the screen to find out
   where a key went.
2. As someone with four Chrome windows on four Google accounts, I want a distinct
   digit per account, so that reaching a specific account is one keystroke rather
   than a hunt.
3. As someone whose accounts cannot be merged, I want the browser slots to be keyed
   on the account rather than on the application, so that "go to Chrome" is never
   the ambiguous answer.
4. As someone who reaches for the terminal constantly, I want it fixed at slot 1,
   so that the most frequent jump is the most predictable one.
5. As someone returning after a restart, I want every slot to mean what it meant
   yesterday, so that the mapping is worth memorising.
6. As someone who just closed a browser window, I want its slot to reopen that
   profile, so that closing a window is not a way to lose a key.
7. As someone who opened a window from Chrome's own profile menu, I want its slot
   to adopt that window, so that the key does not open a redundant second window
   for the same account.
8. As someone with two windows on the same account, I want the slot to reach the one
   I used most recently, so that the key stays deterministic instead of cycling.
9. As someone already in a slot's window, I want pressing that slot to do nothing,
   so that a stray repeat never moves me somewhere unexpected.
10. As someone setting up a new machine, I want to pin slots by pressing a key in the
    window I want, so that I never look up which profile directory holds which
    account.
11. As someone pinning a slot, I want visible confirmation naming what was bound, so
    that a silent keystroke is not the only evidence.
12. As someone repinning a slot that is already bound, I want the new binding to
    replace the old one, so that correcting a mistake is the same gesture as making
    the original.
13. As someone who renames a profile in Chrome, I want every slot to keep working, so
    that a cosmetic edit in the browser is never a config change.
14. As someone who signs a previously signed-out profile into an account, I want its
    slot to keep working, so that a change in the signature's *shape* is absorbed
    rather than fatal.
15. As someone with a profile whose name contains parentheses, I want it matched
    correctly, so that punctuation in a name is not a source of silent misrouting.
16. As someone with a signed-out profile, I want it matched correctly, so that having
    no Google account attached does not make a slot unreachable.
17. As someone who might rename two profiles into the same name, I want a warning
    rather than silent misrouting, so that an ambiguous slot table announces itself.
18. As someone pressing a slot with no target bound, I want nothing to happen and to
    be told, so that an unbound digit is distinguishable from a broken one.
19. As someone who values speed, I want a slot press to feel instantaneous, so that
    the keyboard keeps pace with the intent behind it.
20. As someone who cares about the machine being reproducible, I want the engine
    stowed and versioned with the rest of my configuration, so that a clone restores
    it.
21. As someone whose repository is public, I want the slot table to stay off the
    remote, so that account names and addresses are never committed.
22. As someone provisioning a new Mac, I want the setup script to install both the
    engine's runtime and the test interpreter, so that no dependency is discovered by
    failure.
23. As someone provisioning a new Mac, I want to be told plainly about the one step
    that cannot be scripted, so that a manual Accessibility grant is expected rather
    than mysterious.
24. As someone who edits keybindings, I want to change them in the generator source
    rather than in the generated file, so that the next build does not erase my work.
25. As someone changing keybindings, I want to see what a build would do before it
    touches the live configuration, so that a regeneration is never a leap.
26. As someone with slots free, I want unassigned digits to remain available, so that
    the table has room to grow without rework.
27. As someone with applications on slots, I want them to keep behaving as they do
    today, so that adding browser identities does not disturb what already works.
28. As someone maintaining this in a year, I want the reasoning recorded where the
    code is, so that the single-Desktop constraint is not mistaken for a preference
    and quietly reverted.
29. As someone debugging a slot that misfires, I want to inspect what the engine
    believes about windows and profiles, so that diagnosis does not mean guesswork.
30. As someone who moves a window to another Desktop by accident, I want the failure
    to be legible, so that "the key stopped working" leads to the cause.

## Implementation Decisions

**Karabiner keeps the keyboard.** Hyper is a Karabiner variable that emits no
modifier flags, so no other program can observe it; anything else would have to be
a callee. Each slot fires a `shell_command` invoking the Hammerspoon command-line
interface against the engine. Measured, that hop is 4.5 ms and a window focus is
14 ms — together under one frame at 60 Hz — so the mapping stays visible in one
place instead of being split across two programs for an imperceptible saving.

**The generator is the source of truth.** Slot bindings are edited in the
TypeScript rules of the `karabiner-manager` submodule of `esetup`, never in the
generated JSON. The build writes both the submodule's copy and the live
configuration directly, so hand-edits to the live file are erased by the next
build. The generator honours an environment variable overriding its output path,
which should be used to build to a temporary location and diff before any build
touches the live configuration. A shell helper for arbitrary commands already
exists in the generator's utilities; no new plumbing is required.

**The engine is a new stowed package in this repo**, added to the package list in
`install`, deploying an `init.lua` and its modules into the home directory. The
engine loads the inter-process module so the command-line interface works; this is
what makes the hop available and it must be present in the committed config, not
granted by hand.

**One seam.** A single pure function is the entire testable surface:

```
resolve(request, world) → action

request  { kind = "jump" | "pin", slot = <digit> }
world    { slots, profiles, windows, focused }
           slots    — the slot table
           profiles — per profile directory: profile name, account given name
           windows  — reachable windows as { id, title, app, mru_rank }
           focused  — id of the focused window, or nil
action   { kind = "focus",        id }
         | { kind = "launch",       profile_dir }
         | { kind = "activate_app", name }
         | { kind = "pin",          slot, profile_dir }
         | { kind = "none",         reason }
```

Everything that touches macOS — enumerating reachable windows, focusing, launching
a profile, reading Chrome's `Local State`, persisting the slot table — sits outside
as adapters with no branching of their own.

**A profile signature is constructed, never parsed.** For each profile the engine
builds the expected trailing string from `Local State` and tests the window title
against it. Where an account given name exists the signature is the given name
followed by the profile name in parentheses; where it does not, the signature is
the profile name alone. Matching is an exact suffix test after the literal
` - Google Chrome - ` separator. Parsing is forbidden: a name containing
parentheses and a signed-in account produce the same visible shape and decompose
differently, so any rule keyed on the parentheses is wrong for one of them.

**`Local State` is read live, never cached at load.** A profile rename restamps its
open windows immediately, and signing a profile in changes the signature's shape.
Either re-read on a match miss or watch the file; a load-time snapshot makes a
rename break a slot until the engine is reloaded.

**The slot table stores profile directories.** Directories are durable and name
nobody; profile names are editable and are resolved at the moment of use. The table
lives as an untracked real file in the home directory beside the stowed engine, and
is never committed — it carries account labels, and its directories denote different
people on different machines. A committed example with invented names documents the
format.

**Uniqueness is checked at the moment of use, not at load.** Matching depends on no
two profile names being equal. Nothing in Chrome enforces this, so a collision must
produce a warning rather than a silently mis-targeted slot. Originally specified as a
load-time check; that cannot work, because the registry is deliberately re-read
rather than held, so "load" is not a moment when anything is known. The check
therefore runs on the jump, where the answer is current, and refuses the slot with a
warning rather than picking one of the two profiles arbitrarily.

**Resolution order for a jump.** No target bound gives `none` with a reason. A target
that is an application activates it. A target that is a browser identity focuses the
most recently used reachable window whose signature matches; failing that, launches
the profile; a slot whose window is already focused gives `none`.

The launch **records nothing**, contrary to the first draft of this spec. Recording
the created window's identifier was going to be how a slot found its window again —
but adoption already finds it, by signature, on the very next press, and does so for
windows the engine never opened. Keeping a recorded identifier alongside that would
mean two answers to one question and a second thing to invalidate when a window
closes. The identifier is dropped and adoption is the only path.

**Pinning** binds a slot to the browser identity of the focused window, replacing any
existing binding, and persists the table. It is reached through a dedicated sublayer
rather than a modifier variant, because Hyper is itself a modifier combination. The
key is confirmed on screen naming what was bound.

**The slot table shipped by this work:** 0 Spotify, 1 WezTerm, 2 through 5 browser
identities, 6 and 7 free, 8 Slack, 9 Telegram. `Hyper+<return>` continues to reach
the terminal alongside slot 1. Slot 0 is a new binding — the generator currently
defines 1 through 9 only.

**Provisioning.** `esetup` gains the Lua interpreter in its formula list and
Hammerspoon as a cask; **Hammerspoon is currently referenced nowhere in `esetup`**
despite being installed on this machine, so a new Mac would not have it. The
automatic rearranging of Desktops must be turned off, asserted idempotently in this
repo's macOS defaults script alongside the Dock restart that applies it. Granting
Accessibility to Hammerspoon cannot be scripted and is documented as the one manual
step.

## Testing Decisions

**A good test here asserts external behaviour only** — that a given world and request
produce a given action. It never reaches into how the signature was built or which
helper was called. `resolve` is pure, so a test needs no Hammerspoon, no Chrome, no
windows and no Accessibility grant: every case is a table row of fixtures.

**Prior art** is `claude/.claude/test-whereami-path.py` and
`claude/.claude/test-statusline-seat.py` — standalone executable scripts with no test
framework, run directly, exit 0 meaning every row passed, with a module docstring
listing the branches and what each guards against. `test-whereami-path.py` makes a
point of touching nothing on the real machine; that hermetic property is preserved
here and is the reason the seam sits where it does.

**The engine's pure module is the only unit under test**, run on Lua 5.4 to match the
interpreter Hammerspoon ships. The interpreter present on this machine is LuaJIT,
which is 5.1-compatible and therefore a different language for anything nontrivial;
the Lua formula is added to `esetup` for this reason.

**Cases that must be rows**, each earned by something observed during design:

- an account given name plus a profile name containing parentheses
- a signed-out profile whose name contains parentheses — the same visible shape as
  the row above, decomposing differently
- a signed-out profile with a plain name
- a profile name containing an apostrophe
- a title whose tab portion itself contains the separator string
- a rename between two resolutions, proving the name is not cached
- a sign-in between two resolutions, proving the signature's shape is not cached
- two profiles sharing a name, expecting a warning rather than a match
- no matching window, expecting a launch
- several matching windows, expecting the most recently used
- the slot's window already focused, expecting no action
- a slot with no target bound
- a pin over an empty slot, and a pin replacing an existing binding
- an application target with no window open, and with several

**The adapters are not unit-tested.** Focusing, launching and enumerating are thin,
untestable without a live desktop, and were verified by measurement during design. A
short manual smoke checklist covers them: press each slot from cold, close a window
and press its slot, open a window from Chrome's profile menu and press its slot, pin
a slot and restart Hammerspoon.

## Out of Scope

- **Cycling** through several windows of one browser identity on repeated presses.
  Determinism was chosen deliberately. Adding it later needs no stored state: the
  resolver already sees every matching window and picks by rank, so cycling is a
  change of which rank it picks, not a change of what it knows.
- **A toggle-back binding** returning to the previous window. Wanted eventually, but
  it belongs on its own key rather than overloading a slot.
- **Removing the dead bindings** for uninstalled applications, and the existing
  sublayers. Explicitly deferred — this work touches only what the slots need.
- **Multi-display behaviour.** Unverified; only one screen was attached during design.
  Reasoning says each display carries its own active Desktop and should be fine, and
  reasoning is not evidence.
- **Cross-Desktop support.** Reaching a window on another Desktop is possible but
  reintroduces the Desktop transition the design exists to avoid.
- **Browsers other than Chrome**, and Chrome's incognito windows.
- **Migrating the Karabiner configuration into this repo.** It stays generated from
  the `karabiner-manager` submodule.

## Further Notes

The feature deliberately spans three places — engine here, keybindings in the
`karabiner-manager` submodule of `esetup`, slot table untracked in the home
directory. ADR 0009 records why, since the split is the least obvious thing about
the design and the most likely to be "tidied" by someone who does not know the
reasons.

Three claims cost real time to establish during design and are the ones most likely
to be re-broken. First, the Accessibility interface does not hide *other* Desktops,
it exposes only the *active* one — with the terminal full-screen, the entire machine
enumerated as a single window. Second, the profile appears in window titles only in
the Accessibility layer; AppleScript returns the tab title alone, which rules out an
osascript implementation. Third, a signature cannot be parsed, only predicted.

Full-screen windows were never a special case. They are Desktops wearing different
clothes, which is why the constraint is stated in terms of Desktops and applies to
ordinary maximised windows just as forcefully.
