--[[ Adapter: the reachable windows, and the actions that move between them.

"Reachable" is not a filter this module applies — it is the only thing the
Accessibility interface will report. Windows on any Desktop other than the
active one are absent, not merely unlisted, which is why every window a slot can
reach has to share one Desktop. See ADR 0009.

`hs.window.orderedWindows()` returns them front to back, so list position is
recency of use and becomes the resolver's `mru_rank` directly.
]]

local M = {}

-- Returns plain data for the resolver, the focused window's id, and the live
-- window objects keyed by id. That third value is not a convenience: looking a
-- window back up afterwards with `hs.window.get(id)` re-enumerates everything and
-- measures ~30 ms, which was the single largest cost in a keypress. We already
-- hold the object here, so hand it on rather than pay to find it twice.
--
-- Deliberately not cached across calls: these are handles to windows that close.
function M.snapshot()
  local windows, handles = {}, {}
  for rank, w in ipairs(hs.window.orderedWindows()) do
    local id = w:id()
    handles[id] = w
    local app = w:application()
    windows[#windows + 1] = {
      id = id,
      app = app and app:name() or "",
      title = w:title() or "",
      mru_rank = rank,
    }
  end
  local focused = hs.window.focusedWindow()
  return windows, focused and focused:id() or nil, handles
end

function M.focus(id, handles)
  local w = handles and handles[id] or hs.window.get(id)
  if w == nil then return false end
  w:focus()
  return true
end

function M.activate_app(name)
  return hs.application.launchOrFocus(name)
end

-- `-n` (folded into `-na` here) is what makes the arguments reach a new instance
-- rather than being swallowed by the running Chrome, which would otherwise
-- ignore --profile-directory entirely and just raise whatever it already had.
function M.launch_profile(dir)
  hs.task.new("/usr/bin/open", nil, {
    "-na", "Google Chrome", "--args",
    "--profile-directory=" .. dir, "--new-window",
  }):start()
end

return M
