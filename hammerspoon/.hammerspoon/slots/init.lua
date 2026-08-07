--[[ Window slots: one key, one window.

Karabiner owns the keyboard — Hyper is a Karabiner variable that emits no
modifier flags, so nothing else can observe it — and each slot arrives as a
`hammerspoon://slots?act=jump&n=2` URL event, bound in the root init.lua.
See ADR 0009 and CONTEXT.md's window navigation terms.

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
  action = resolve(request, world)
  inner = action.action or action
  if inner.kind ~= "launch" then return action, world, handles end
  -- Even the deep sweep has one blind spot: a parked window Chrome restored
  -- by itself while hidden leaves the Accessibility tree entirely (see
  -- resolve.unaccounted). Launching against that blindness opens a duplicate
  -- window, so before trusting a launch, rescue whatever Chrome still admits
  -- to and look once more.
  --
  -- Sampled twice, because the two window lists cannot be read atomically: a
  -- tab retitling between the reads looks exactly like a lost window, and
  -- consigning that false positive minimizes a window the user can see — with
  -- the full genie animation the solo machinery exists to avoid. A window is
  -- only lost if both looks, a beat apart, agree it is. The sleeps are
  -- blocking beats on Hammerspoon's main thread, affordable only because this
  -- path already ends in either a rescue or a browser launch — both of which
  -- dwarf them.
  local lost = resolve.unaccounted(chrome.windows(), world.windows)
  if #lost == 0 then return action, world, handles end
  hs.timer.usleep(150000)
  world, handles = survey(true, true)
  local suspect = {}
  for _, id in ipairs(lost) do suspect[id] = true end
  local confirmed = {}
  for _, id in ipairs(resolve.unaccounted(chrome.windows(), world.windows)) do
    if suspect[id] then confirmed[#confirmed + 1] = id end
  end
  if #confirmed == 0 then return resolve(request, world), world, handles end
  chrome.consign(confirmed)
  hs.timer.usleep(300000)
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

-- Ordered so the screen never shows bare desktop: flip the sibling windows'
-- minimize state off-screen (this may hide the target's own app, so it must
-- precede the raise), raise the target, and only then hide everything else —
-- background apps vanish behind an already-front window, and hiding them
-- steals nothing from it.
--
-- The resolver only decorates a solo when the wallpaper would be seen behind
-- the target (resolve's TRANSLUCENT set; pairs by construction). An opaque
-- target arrives as the plain jump action and is performed as one — covering
-- the backdrop instead of clearing it, so nothing hides, flips, or flashes.
function M.solo(digit)
  local action, _, handles = resolve_freshly({ kind = "solo", slot = digit })
  if action.kind ~= "solo" then
    perform(action, handles, digit)
    return
  end
  desktop.flip_minimized(action.minimize, handles)
  perform(action.action, handles, digit)
  desktop.hide_others(action.keep)
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
