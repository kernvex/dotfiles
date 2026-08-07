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

-- Every browser identity whose signature the window carries. Normally zero or
-- one. Two means two profiles share a name, and the caller must not pick between
-- them: `pairs` has no defined order, so "the first match" is a coin toss that
-- would be written to disk as if it were a decision.
local function identities_of(window, profiles)
  local found = {}
  for dir, profile in pairs(profiles) do
    if owns(window, profile) then found[#found + 1] = dir end
  end
  return found
end

local function pin(request, world)
  local focused
  for _, w in ipairs(world.windows) do
    if w.id == world.focused then focused = w end
  end
  if focused == nil then
    return { kind = "none", reason = "nothing_focused" }
  end

  local dirs = identities_of(focused, world.profiles)
  if #dirs > 1 then
    return { kind = "none", reason = "ambiguous_signature" }
  end
  if #dirs == 1 then
    return { kind = "pin", slot = request.slot, target = { kind = "profile", dir = dirs[1] } }
  end

  -- A browser window we could not attribute must not become an application
  -- target: "Google Chrome" reaches every account equally, which is the exact
  -- ambiguity slots exist to remove. Refusing is the only honest answer.
  if focused.app == BROWSER then
    return { kind = "none", reason = "unidentified_browser_window" }
  end

  return {
    kind = "pin",
    slot = request.slot,
    target = { kind = "app", name = focused.app },
  }
end

local function jump(request, world)
  local target = world.slots[request.slot]
  if target == nil then
    return { kind = "none", reason = "unbound" }
  end

  if target.kind == "app" then
    return { kind = "activate_app", name = target.name }
  end

  -- No already_there for a pair: re-activating also re-tiles, so pressing the
  -- slot again is how a drifted layout gets healed rather than a case to skip.
  if target.kind == "pair" then
    return { kind = "activate_pair", left = target.left, right = target.right }
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

-- Solo = the jump, plus instructions to clear the backdrop so the wallpaper
-- shows through a translucent window. Only these outcomes have a window to be
-- alone with; every other action passes through undecorated and unclears nothing.
local BACKDROP_SAFE = { focus = true, activate_app = true, activate_pair = true, launch = true }

-- Which applications must stay visible, and — when the target is one specific
-- window — that window's id, so its same-app siblings can be minimized.
local function keep_of(action, world)
  if action.kind == "activate_app" then return { [action.name] = true } end
  if action.kind == "activate_pair" then return { [action.left] = true, [action.right] = true } end
  if action.kind == "launch" then return { [BROWSER] = true } end
  local id = action.kind == "focus" and action.id or world.focused
  for _, w in ipairs(world.windows) do
    if w.id == id then return { [w.app] = true }, id end
  end
end

local function solo(request, world)
  local action = jump(request, world)
  if not (BACKDROP_SAFE[action.kind] or action.reason == "already_there") then
    return action
  end
  -- Clearing the backdrop hides the target's own app to flip sibling state
  -- off-screen, so "already there" must become a real focus: raising the
  -- target back out is the step that makes the press visible.
  if action.reason == "already_there" then
    action = { kind = "focus", id = world.focused }
  end
  local keep, focus_id = keep_of(action, world)
  if keep == nil then return action end

  -- Hiding is per-application, so the kept app's other windows can only leave
  -- the backdrop by being minimized. For a focused window that is its same-app
  -- siblings; for a launch, every current browser window — the window being
  -- launched is the one the slot wants.
  local minimize = {}
  for _, w in ipairs(world.windows) do
    if keep[w.app] and w.id ~= focus_id and (focus_id or action.kind == "launch") then
      minimize[#minimize + 1] = w.id
    end
  end
  return { kind = "solo", action = action, keep = keep, minimize = minimize }
end

-- Chrome sometimes restores a parked window by itself — a page that redirects
-- or re-authenticates while minimized (Teams, Outlook) un-minimizes its own
-- window — and when that happens while Chrome is hidden, the window server
-- loses it: the window leaves the Accessibility tree entirely, so both
-- snapshots go blind and the slot that owns it opens a duplicate. Chrome's
-- scripting interface still lists the window, so the disagreement between the
-- two lists is exactly the set to rescue.
--
-- Joining the lists is a title exercise. Scripting reports the bare tab
-- title; AX stamps "<tab title>[ - <decorations>] - Google Chrome -
-- <signature>". So an AX browser title accounts for a scripted window when it
-- equals the tab title or extends it at a " - " boundary. Longest tab title
-- claims first and each AX title is spent once, so one tab title prefixing
-- another ("Inbox" / "Inbox - Zimbra") cannot double-book a window. Minimized
-- scripted windows claim their AX title but are never reported: the deep
-- sweep already sees them, and consuming their title is what keeps a lost
-- twin with the same tab title detectable. A blank tab title attributes to
-- nothing and is skipped: consigning on a blank match would gamble a visible
-- window on it.
-- Chrome's scripting interface also middle-truncates a long tab title:
-- "Billing exports time out in… · Northwind/Fern.Backend" for a window whose
-- AX title carries the full text. A join blind to that reads every
-- long-titled visible window as lost — and consigns it in plain sight.
local ELLIPSIS = "…"

local function accounts_for(title, tab)
  if title == tab then return true end
  if title:sub(1, #tab) == tab and title:sub(#tab + 1, #tab + 3) == " - " then
    return true
  end
  local cut = tab:find(ELLIPSIS, 1, true)
  if cut == nil then return false end
  local head = tab:sub(1, cut - 1)
  local tail = tab:sub(cut + #ELLIPSIS)
  if title:sub(1, #head) ~= head then return false end
  if tail == "" then return true end
  -- The tail must reappear later, again at a boundary: mid-word echoes of it
  -- do not count, so keep looking past them.
  local from = #head + 1
  while true do
    local at = title:find(tail, from, true)
    if at == nil then return false end
    local rest = title:sub(at + #tail, at + #tail + 2)
    if rest == "" or rest == " - " then return true end
    from = at + 1
  end
end

function M.unaccounted(scripted, windows)
  local pool = {}
  for _, w in ipairs(windows) do
    if w.app == BROWSER then pool[#pool + 1] = w.title end
  end
  local order = {}
  for i, sw in ipairs(scripted) do order[i] = sw end
  table.sort(order, function(a, b)
    if #a.title ~= #b.title then return #a.title > #b.title end
    return a.id < b.id
  end)
  local lost = {}
  for _, sw in ipairs(order) do
    if sw.title ~= "" then
      local claimed
      for i, title in ipairs(pool) do
        if accounts_for(title, sw.title) then
          claimed = i
          break
        end
      end
      if claimed then
        table.remove(pool, claimed)
      elseif not sw.minimized then
        lost[#lost + 1] = sw.id
      end
    end
  end
  table.sort(lost)
  return lost
end

function M.resolve(request, world)
  if request.kind == "pin" then
    return pin(request, world)
  end
  if request.kind == "solo" then
    return solo(request, world)
  end
  return jump(request, world)
end

return setmetatable(M, { __call = function(_, ...) return M.resolve(...) end })
