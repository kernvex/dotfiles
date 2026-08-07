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
  unidentified_browser_window = "slot %d: cannot tell which profile that Chrome window is",
}

-- What to call a target on screen. A profile is named by whatever Chrome calls it
-- right now, which is the only name you would recognise.
local function describe(target, profiles)
  if target.kind == "app" then return target.name end
  local profile = profiles[target.dir]
  if profile and profile.name ~= "" then return profile.name end
  return target.dir
end

-- Returns the world the resolver reasons about, and separately the live window
-- objects it must not see: the resolver stays pure, and the caller keeps the
-- handles it needs to act without paying to look them up again.
local function survey(force_profiles, deep)
  local snapshot = deep and desktop.snapshot_deep or desktop.snapshot
  local windows, focused, handles = snapshot()
  return {
    slots = store.load(),
    profiles = chrome.profiles(force_profiles),
    windows = windows,
    focused = focused,
  }, handles
end

-- Reaching one of these means no window matched, and two suspects explain
-- that: the profile registry is stale (a rename or sign-in changed a
-- signature), or the window exists but is minimized or hidden — the states
-- solo leaves the backdrop in, which the ordinary snapshot cannot see. The
-- retry re-reads the registry AND sweeps deep, because acting on either
-- mistake opens a duplicate window. Both costs stay off the focus path, where
-- they would be unaffordable on every keypress.
local STALE_SUSPECTS = { launch = true, unknown_profile = true }

local function resolve_freshly(request)
  local world, handles = survey(false, false)
  local action = resolve(request, world)
  local inner = action.action or action
  if not (STALE_SUSPECTS[inner.kind] or STALE_SUSPECTS[inner.reason]) then
    return action, world, handles
  end
  world, handles = survey(true, true)
  return resolve(request, world), world, handles
end

local function complain(action, digit)
  if action.reason == "already_there" then return end
  local template = COMPLAINTS[action.reason]
  hs.alert.show(template and template:format(digit)
    or string.format("slot %d: %s", digit, tostring(action.reason)))
end

local function perform(action, handles, digit)
  if action.kind == "focus" then
    if not desktop.focus(action.id, handles) then
      hs.alert.show(string.format("slot %d: that window went away", digit))
    end
  elseif action.kind == "activate_app" then
    desktop.activate_app(action.name)
  elseif action.kind == "activate_pair" then
    desktop.activate_pair(action.left, action.right)
  elseif action.kind == "launch" then
    desktop.launch_profile(action.profile_dir)
  else
    complain(action, digit)
  end
end

function M.jump(digit)
  local action, _, handles = resolve_freshly({ kind = "jump", slot = digit })
  perform(action, handles, digit)
end

-- The jump, then the backdrop clears so the wallpaper shows through the
-- translucent window. A solo that cannot reach a window degrades to exactly
-- what jump would have said, complaint included, and hides nothing.
function M.solo(digit)
  local action, _, handles = resolve_freshly({ kind = "solo", slot = digit })
  if action.kind ~= "solo" then
    complain(action, digit)
    return
  end
  perform(action.action, handles, digit)
  desktop.clear_backdrop(action.keep, action.minimize, handles)
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

  -- The resolver decided what the target is; this only records it.
  world.slots[action.slot] = action.target
  local saved, err = store.save(world.slots, world.profiles)
  if not saved then
    hs.alert.show("could not write the slot table: " .. tostring(err))
    return
  end

  hs.alert.show(string.format("slot %d → %s", digit, describe(action.target, world.profiles)))
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
