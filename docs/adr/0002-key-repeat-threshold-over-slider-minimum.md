# InitialKeyRepeat is pinned above the macOS slider minimum, not at it

This machine ran `InitialKeyRepeat=15` with `KeyRepeat=2` — both ends of the macOS
Keyboard sliders pushed to their fastest positions. That combination produces runaway
repeats in ordinary prose: `local` typed as `loccccccccccccal`, `machines` as
`maaaaaaaaaachines`. It reads as a hardware fault and was initially assumed to be one,
but it reproduced identically on the built-in keyboard and the external MX MCHNCL,
because the values live in `NSGlobalDomain`, above the HID layer.

The mechanism is arithmetic, not a defect. 15 units is 250 ms until repeat begins, and
2 units is 33 ms between repeats (30 chars/sec). A key held 300-650 ms — normal when
pausing mid-word — therefore emits 2 to 12 extra characters. Burst length tracks hold
duration linearly, which is exactly why the symptom looks random: `cccan` is a 317 ms
hold, `maaaaaaaaaachines` a 550 ms one. At the macOS default of 68 (1133 ms) every one
of those same keystrokes emits nothing at all.

`ApplePressAndHoldEnabled=false` (adopted from the VSCodeVim setup instructions, so
held `j`/`k` repeat) widens the blast radius: the accent picker normally makes
a, c, e, i, o, n, s, u, y immune to repeating, and disabling it removes that protection
from precisely the letters most common in English prose.

**Decision:** pin `InitialKeyRepeat=25` (417 ms) — above the slider's minimum of 15,
comfortably above normal keystroke duration, still far below the 1133 ms default so
hold-to-repeat stays useful. Keep `KeyRepeat=2` and the disabled press-and-hold, both
of which are deliberate ergonomics; the threshold is what makes them safe. Assert all
three from `macos/defaults.sh` rather than leaving them to the System Settings UI,
whose slider cannot express 25 and would silently snap back to 15.

**Consequence:** these values are no longer reachable through the Keyboard pane —
dragging either slider will overwrite them with a UI-expressible value and can
reintroduce the bug. `./install` reasserts the correct state, so the fix is to re-run
it rather than to re-drag the slider. Key repeat changes only affect newly launched
apps; a full logout is needed to apply them everywhere.
