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

-- Karabiner reaches the slots through this one-way URL event, not the `hs`
-- CLI. The CLI blocks on a CFMessagePort reply, and that port corrupts across
-- Hammerspoon reloads — the command may still execute, but the spawned `hs`
-- wedges forever and the next keypress hits a poisoned port and executes
-- nothing. A URL event has no reply channel, so there is nothing to corrupt.
-- hs.ipc above stays for diagnostics (`hs -c "print(slots.explain())"`) only;
-- no keypress depends on it.
hs.urlevent.bind("slots", function(_, params)
  local verb, digit = params.act, tonumber(params.n)
  if digit and (verb == "jump" or verb == "pin" or verb == "solo") then
    slots[verb](digit)
  end
end)
