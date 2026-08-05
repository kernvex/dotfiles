--[[ The window-slot resolver: the one pure seam of the engine.

Takes a snapshot of the world and returns the action to perform. Touches no
window, no browser and no file — every macOS call lives in the adapters that
surround it. See docs/adr/0009-window-slots-resolve-by-profile-signature.md.
]]

local M = {}

local SEPARATOR = " - Google Chrome - "

-- The trailing string a Chrome window title carries to say which profile owns
-- it. Constructed from the profile, never parsed out of the title: a name that
-- itself contains parentheses and a signed-out profile produce the same visible
-- shape and decompose differently, so no parser can tell them apart.
function M.signature(profile)
  if profile.given_name and profile.given_name ~= "" then
    return profile.given_name .. " (" .. profile.name .. ")"
  end
  return profile.name
end

local BROWSER = "Google Chrome"

local function owns(window, profile)
  if window.app ~= BROWSER then return false end
  local suffix = SEPARATOR .. M.signature(profile)
  local title = window.title
  return #title >= #suffix and title:sub(-#suffix) == suffix
end

-- Which browser identity owns a window, or nil if none does.
local function identity_of(window, profiles)
  for dir, profile in pairs(profiles) do
    if owns(window, profile) then return dir end
  end
end

local function pin(request, world)
  local focused
  for _, w in ipairs(world.windows) do
    if w.id == world.focused then focused = w end
  end
  if focused == nil then
    return { kind = "none", reason = "nothing_focused" }
  end

  local dir = identity_of(focused, world.profiles)
  if dir == nil then
    return { kind = "none", reason = "not_a_browser_identity" }
  end

  return { kind = "pin", slot = request.slot, profile_dir = dir }
end

local function jump(request, world)
  local target = world.slots[request.slot]
  if target == nil then
    return { kind = "none", reason = "unbound" }
  end

  if target.kind == "app" then
    return { kind = "activate_app", name = target.name }
  end

  local profile = world.profiles[target.dir]
  if profile == nil then
    -- Launching an unknown directory would make Chrome create a fresh empty
    -- profile under that name, quietly turning a stale slot into a new account.
    return { kind = "none", reason = "unknown_profile" }
  end

  local signature = M.signature(profile)
  for dir, other in pairs(world.profiles) do
    if dir ~= target.dir and M.signature(other) == signature then
      return { kind = "none", reason = "ambiguous_signature" }
    end
  end

  local best
  for _, w in ipairs(world.windows) do
    if owns(w, profile) and (best == nil or w.mru_rank < best.mru_rank) then
      best = w
    end
  end

  if best then
    if world.focused == best.id then
      return { kind = "none", reason = "already_there" }
    end
    return { kind = "focus", id = best.id }
  end

  return { kind = "launch", profile_dir = target.dir }
end

function M.resolve(request, world)
  if request.kind == "pin" then
    return pin(request, world)
  end
  return jump(request, world)
end

return setmetatable(M, { __call = function(_, ...) return M.resolve(...) end })
