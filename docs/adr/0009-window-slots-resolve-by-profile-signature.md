# Window slots resolve by profile signature, and only on a single Desktop

`Hyper+<digit>` already switched applications, by way of Karabiner firing `open -a`. That
answer fails for exactly one case, and it is the case that matters most: three or four Chrome
windows, each signed into a different Google account, which cannot be merged into one window.
`open -a 'Google Chrome.app'` names all of them equally, so the digit stops meaning a place.
What is wanted is harpoon's guarantee — one key, one destination, permanently — raised to the
level of macOS windows.

**Every window a slot can reach must share one Desktop.** This is the constraint the design
turns on, and it is not about speed. The Accessibility API enumerates only the currently
active Desktop. Measured here with the terminal full-screen, `hs.window.allWindows()` returned
exactly one window for the entire machine — the terminal — while Chrome had two windows open
at that instant. Earlier, AppleScript reported four Chrome windows where the Accessibility
layer reported two. The limit is not a full-screen quirk: two ordinary maximised windows moved
one Desktop across, sitting at `0,30,1920,1080` with the menu bar showing, were equally
invisible. A window on another Desktop is not expensive to reach, it does not exist. Native
full-screen also costs a ~600 ms Desktop transition against ~48 ms for the whole keypress on
the active Desktop, but that was the smaller objection.

**A signature can be predicted, never parsed.** Chrome does put the profile in the window
title, but only in the Accessibility layer — AppleScript's `name of window` returns the tab
title alone. The shape is `<tab title> - Google Chrome - <account given name> (<profile name>)`,
except for a profile that is not signed in, which yields `<tab title> - Google Chrome -
<profile name>` with no parentheses at all. Two live profiles settled it; written here with
invented names, since this repo is public, but with their shapes intact:

    Sam (Sam Weber (Northwind))    account + name, where the name itself contains parentheses
    Alex Rivera (Acme Group)       name only, no account, name itself contains parentheses

Both have the shape `X (Y)` and decompose differently, so any rule keyed on the parentheses
gets one of them wrong. The only sound method is to build each configured profile's expected
signature from Chrome's `Local State` and test the window title against it. That also forces
`Local State` to be read live rather than cached at load: renaming a profile restamps its open
windows immediately (verified against a captured baseline), and signing a profile in changes
the signature's *shape*, not merely its text.

**Slots store profile directories, not profile names.** A directory such as `Profile 70` is
durable and meaningless to a reader; the name beside it is meaningful and was edited twice
during the design session itself, once into a form that broke the first matching rule. The
name is still needed as the join key, so it is resolved from `Local State` at the moment of
use rather than recorded.

**Decision.** Karabiner keeps ownership of the keyboard — Hyper is a Karabiner variable that
emits no modifiers, so no other program can observe it — and each slot fires a `shell_command`
calling `hs -c` into a Hammerspoon engine.

The design was chosen on a predicted ~18 ms, from timing the `hs -c` hop (4.5 ms) and a focus
on an already-held window (14 ms) separately. That prediction was wrong, and the components
were the reason: the first end-to-end measurement was **88 ms**. Half of it was one line —
`hs.window.get(id)`, which re-enumerates every window to find one by identifier and costs
~30 ms on its own, having just been handed that very window during enumeration. Passing the
handle through instead brought a keypress to **~48 ms** (32–69 ms over twelve alternating
jumps): ~6 ms to spawn `hs`, ~10 ms to enumerate windows, ~1 ms for the cached profile
registry, ~10 ms for the focus itself, and 0.01 ms for the resolver.

48 ms is roughly three frames rather than one, and the choice survives it: a synthesised-chord
bridge would have removed the 6 ms spawn and left the other 42, at the cost of splitting the
mapping across two programs. The lesson worth keeping is that summing component timings
predicted a number five times too low, because the expensive part was a lookup neither
component contained. A
slot press focuses the most recently used window of its target, adopts a matching window it did
not open, and otherwise launches the profile and records what it created. Pressing the slot you
are already in does nothing, as in tmux and WezTerm. Slots are authored by pinning the focused
window, not by editing a file.

**Consequences.** The feature spans three places: the engine is a stowed `hammerspoon` package
in this repo, the keys are generated from `rules.ts` in the `karabiner-manager` submodule of
`esetup`, and the slot table is an untracked file in `$HOME`. The split is deliberate —
`karabiner-manager` is a fork tracking upstream and should not absorb a bespoke Lua engine, and
the slot table names real accounts — but it is the reason this decision is written down at all.
Native full-screen is given up system-wide, terminal included. Granting Accessibility to
Hammerspoon cannot be scripted, so a new machine keeps one irreducible manual step.
