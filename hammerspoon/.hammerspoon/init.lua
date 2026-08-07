--[[ Hammerspoon entry point.

Loads the inter-process module so the `hs` command-line tool can reach this
config: Karabiner drives every window slot through `hs -c`, so without this the
keys do nothing and fail silently. It belongs in the committed config rather
than being enabled by hand — that is the difference between a machine that works
after `./install` and one that works after somebody remembers.

`slots` is deliberately global. `hs -c "slots.jump(2)"` evaluates in the global
environment, so a local would be unreachable from the very caller it exists for.
]]

require("hs.ipc")

-- Window moves are teleports, not tweens: solo minimizes sibling windows and
-- the pair slot setFrames two of them, and the default 0.2 s animation on each
-- reads as lag in a keypress-driven flow.
hs.window.animationDuration = 0

slots = require("slots")
