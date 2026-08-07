--[[ Adapter: what Chrome knows about its profiles.

Reads `Local State`, the file Chrome keeps its profile registry in, and returns
the shape the resolver expects: profile directory -> { name, given_name }.

Read live, never snapshotted at load. Renaming a profile restamps its open
windows immediately, and signing one in changes the *shape* of its signature —
so a load-time cache turns either into a slot that stays broken until reload.

But the file is ~187 KB and read-plus-decode measures ~50 ms, which would be
three times the cost of the keypress it serves. So: cached against mtime for the
fast path, and `force` for the slow one. The caller forces a re-read only when a
slot found no window, where being wrong means opening a duplicate — and where the
50 ms disappears beside the cost of launching a browser window anyway. That also
covers mtime's one-second granularity, which could otherwise hide a rename made
in the same second as the previous read.
]]

local M = {}

local LOCAL_STATE = os.getenv("HOME")
  .. "/Library/Application Support/Google/Chrome/Local State"

local cache = { mtime = nil, profiles = {} }

function M.profiles(force)
  local mtime = hs.fs.attributes(LOCAL_STATE, "modification")
  if mtime == nil then return {} end
  if mtime == cache.mtime and not force then return cache.profiles end

  local file = io.open(LOCAL_STATE, "r")
  if file == nil then return {} end
  local raw = file:read("a")
  file:close()

  local ok, decoded = pcall(hs.json.decode, raw)
  if not ok or type(decoded) ~= "table" then return cache.profiles end

  local info = decoded.profile and decoded.profile.info_cache or {}
  local profiles = {}
  for dir, entry in pairs(info) do
    profiles[dir] = {
      name = entry.name or "",
      given_name = entry.gaia_given_name or "",
    }
  end

  cache = { mtime = mtime, profiles = profiles }
  return profiles
end

-- The scripting interface is the one voice that lists every window Chrome
-- believes it has — including a window the Accessibility tree has lost (see
-- resolve.unaccounted). Titles here are bare tab titles: the
-- " - Google Chrome - <signature>" stamp exists only on the AX side. Guarded
-- on the app actually running, because AppleScript would launch Chrome to
-- answer, and asking about windows must never start a browser.
function M.windows()
  if hs.application.get("Google Chrome") == nil then return {} end
  local ok, out = hs.osascript.applescript([[
    set acc to {}
    tell application "Google Chrome"
      repeat with w in windows
        set end of acc to {id of w, title of w, minimized of w}
      end repeat
    end tell
    return acc
  ]])
  if not ok or type(out) ~= "table" then return {} end
  local list = {}
  for _, row in ipairs(out) do
    list[#list + 1] = { id = row[1], title = row[2], minimized = row[3] }
  end
  return list
end

-- Park these windows (Chrome window ids) as minimized, through Chrome itself:
-- a window AX has lost cannot be reached by any hs.window call, but Chrome
-- still owns it, and minimizing re-registers it with the window server —
-- after which the deep sweep sees it and a slot can raise it normally.
-- `try` per window: an id can go stale between the survey and this call.
function M.consign(ids)
  if #ids == 0 then return end
  local lines = { 'tell application "Google Chrome"' }
  for _, id in ipairs(ids) do
    lines[#lines + 1] = string.format(
      "  try\n    set minimized of window id %d to true\n  end try", id)
  end
  lines[#lines + 1] = "end tell"
  hs.osascript.applescript(table.concat(lines, "\n"))
end

return M
