--[[ Window slots: one key, one window.

Karabiner owns the keyboard — Hyper is a Karabiner variable that emits no
modifier flags, so nothing else can observe it — and each slot arrives here as
`hs -c "slots.jump(2)"`. See ADR 0009 and CONTEXT.md's window navigation terms.

This module is wiring only. Every decision lives in `slots.resolve`, which is
pure and covered by test-resolve.lua; everything macOS-shaped lives in the
adapters. Nothing here should acquire a branch worth testing.
]]

local resolve = require("slots.resolve")
local chrome = require("slots.chrome")
local desktop = require("slots.desktop")
local store = require("slots.store")

local M = {}

-- Silence for "already_there": pressing the slot you are in is a no-op by
-- design, and an alert would make the deliberate case look like a failure.
local COMPLAINTS = {
  unbound = "slot %d: nothing bound",
  unknown_profile = "slot %d: that Chrome profile no longer exists",
  ambiguous_signature = "slot %d: two profiles share a name — rename one",
  nothing_focused = "slot %d: no focused window to pin",
  not_a_browser_identity = "slot %d: focused window is not a Chrome profile window",
}

local function survey(force_profiles)
  local windows, focused = desktop.snapshot()
  return {
    slots = store.load(),
    profiles = chrome.profiles(force_profiles),
    windows = windows,
    focused = focused,
  }
end

-- Reaching one of these means no window matched, so the profile registry we
-- matched against is the prime suspect: a rename or a sign-in since the last read
-- changes a signature, and acting on a stale one opens a duplicate window. Pay
-- for a forced re-read here and nowhere else — it costs ~50 ms, which is
-- invisible next to launching a browser and unaffordable on the focus path.
local STALE_SUSPECTS = { launch = true, unknown_profile = true }

local function resolve_freshly(request)
  local world = survey(false)
  local action = resolve(request, world)
  if not (STALE_SUSPECTS[action.kind] or STALE_SUSPECTS[action.reason]) then
    return action, world
  end
  world = survey(true)
  return resolve(request, world), world
end

local function complain(action, digit)
  if action.reason == "already_there" then return end
  local template = COMPLAINTS[action.reason]
  hs.alert.show(template and template:format(digit)
    or string.format("slot %d: %s", digit, tostring(action.reason)))
end

function M.jump(digit)
  local action = resolve_freshly({ kind = "jump", slot = digit })

  if action.kind == "focus" then
    if not desktop.focus(action.id) then
      hs.alert.show(string.format("slot %d: that window went away", digit))
    end
  elseif action.kind == "activate_app" then
    desktop.activate_app(action.name)
  elseif action.kind == "launch" then
    desktop.launch_profile(action.profile_dir)
  else
    complain(action, digit)
  end
end

function M.pin(digit)
  -- Forced: a pin writes a binding that outlives the keypress, so it must not be
  -- decided against a stale registry.
  local world = survey(true)
  local action = resolve({ kind = "pin", slot = digit }, world)

  if action.kind ~= "pin" then
    complain(action, digit)
    return
  end

  world.slots[action.slot] = { kind = "profile", dir = action.profile_dir }
  local saved, err = store.save(world.slots, world.profiles)
  if not saved then
    hs.alert.show("could not write the slot table: " .. tostring(err))
    return
  end

  local profile = world.profiles[action.profile_dir]
  hs.alert.show(string.format("slot %d → %s", digit,
    profile and profile.name ~= "" and profile.name or action.profile_dir))
end

-- Diagnostics. `hs -c "print(slots.explain())"` answers "why did that key do
-- that?" by showing the same world the resolver saw, plus what every slot
-- currently resolves to. Read-only: it performs nothing.
function M.explain()
  local world = survey(true)
  local lines = { string.format("reachable windows: %d   focused: %s",
    #world.windows, tostring(world.focused)) }
  for _, w in ipairs(world.windows) do
    lines[#lines + 1] = string.format("  %-16s %-8s %s", w.app, tostring(w.id), w.title)
  end
  lines[#lines + 1] = ""
  for digit = 0, 9 do
    local action = resolve({ kind = "jump", slot = digit }, world)
    lines[#lines + 1] = string.format("  slot %d -> %s %s", digit, action.kind,
      tostring(action.id or action.profile_dir or action.name or action.reason or ""))
  end
  return table.concat(lines, "\n")
end

return M
