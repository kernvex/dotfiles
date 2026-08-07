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

-- The deep sweep: every standard window, including minimized ones and those of
-- hidden applications — the two states solo puts windows into, and the two
-- states orderedWindows cannot see. Costs a full Accessibility enumeration per
-- running app, so it backs the miss path only, never a routine keypress.
-- Hidden and minimized windows carry no recency, so they rank after every
-- visible window, in discovery order.
function M.snapshot_deep()
  local windows, handles = {}, {}
  local rank = 0
  -- minimized rides along because the caller already knows it — ordered
  -- windows are on screen, the sweep tests it anyway — and the resolver needs
  -- it to leave already-parked windows out of a solo's minimize list: each
  -- redundant AX minimize costs ~15ms of flip time and re-pokes the exact
  -- state churn the ghost-tile desync grew from.
  local function add(w, minimized)
    local id = w:id()
    if id == nil or handles[id] then return end
    rank = rank + 1
    handles[id] = w
    local app = w:application()
    windows[#windows + 1] = {
      id = id,
      app = app and app:name() or "",
      title = w:title() or "",
      mru_rank = rank,
      minimized = minimized,
    }
  end
  for _, w in ipairs(hs.window.orderedWindows()) do add(w, false) end
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 then
      for _, w in ipairs(app:allWindows()) do
        local minimized = w:isMinimized()
        if w:isStandard() or minimized then add(w, minimized) end
      end
    end
  end
  local focused = hs.window.focusedWindow()
  return windows, focused and focused:id() or nil, handles
end

function M.focus(id, handles)
  local w = handles and handles[id] or hs.window.get(id)
  if w == nil then return false end
  local app = w:application()
  -- A window solo minimized must come back out of the Dock: focus alone raises
  -- and activates but never unminimizes. Unminimizing a visible app animates
  -- out of the Dock and macOS offers no off switch — but a hidden app renders
  -- nothing, so the state flips invisibly.
  if w:isMinimized() then
    if app and not app:isHidden() then
      -- hide() can be rejected mid-transition — usually because the sibling
      -- flip a moment ago hid this very app and the transition has not
      -- committed yet. Unminimizing after a failed hide animates in full
      -- view, so wait for the in-flight hide to land (a few ms) and only
      -- re-issue if it never does.
      if not app:hide() then
        local deadline = hs.timer.absoluteTime() + 150 * 1e6
        while not app:isHidden() and hs.timer.absoluteTime() < deadline do
          hs.timer.usleep(5000)
        end
        if not app:isHidden() then app:hide() end
      end
    end
    w:unminimize()
    -- The restore is asynchronous, and no-animation holds only while the app
    -- stays hidden: an unhide issued mid-restore puts the tail of the Dock
    -- animation on screen. Wait it out — it lands in 30-90ms — but bounded,
    -- so a wedged window degrades to the old animated behaviour, not a dead
    -- key. Every millisecond here is wallpaper on screen: the sibling flip
    -- already hid this app, so the poll is tight and there is no settle.
    if w:isMinimized() then
      local deadline = hs.timer.absoluteTime() + 400 * 1e6
      while w:isMinimized() and hs.timer.absoluteTime() < deadline do
        hs.timer.usleep(10000)
      end
    end
  end
  if app and app:isHidden() then app:unhide() end
  w:focus()
  -- A solo hides the frontmost app just before this runs, and macOS promotes
  -- Finder in the same beat — an activation raced against that promotion
  -- loses, leaving the window correct but behind. Don't race it: re-assert
  -- once, after the promotion has settled.
  hs.timer.doAfter(0.15, function()
    local focused = hs.window.focusedWindow()
    if focused == nil or focused:id() ~= id then w:focus() end
  end)
  return true
end

-- Minimizing a visible window animates into the Dock and macOS offers no off
-- switch. A hidden app renders nothing, so the same state change made while
-- its app is hidden shows no animation at all. Nothing here unhides — the
-- caller raises the target after this, and focus() un-hides what it raises;
-- an activation performed before this juggling gets un-fronted by it.
function M.flip_minimized(minimize, handles)
  local hidden = {}
  for _, id in ipairs(minimize) do
    local w = handles and handles[id]
    local app = w and w:application()
    if app then
      if not app:isHidden() then
        app:hide()
        hidden[#hidden + 1] = app
      end
      w:minimize()
    end
  end
  -- hide() on the frontmost app can be rejected or land late, and the next
  -- step (focus) minimizes-and-unminimizes under the assumption this app is
  -- already hidden — paying ~70ms for a second hide on a mid-transition app
  -- when it is not. Committing the hide here is the same wallpaper beat, and
  -- far cheaper than discovering it later.
  for _, app in ipairs(hidden) do
    local deadline = hs.timer.absoluteTime() + 100 * 1e6
    while not app:isHidden() and hs.timer.absoluteTime() < deadline do
      hs.timer.usleep(5000)
    end
    if not app:isHidden() then app:hide() end
  end
end

-- kind() == 1 keeps this to ordinary Dock applications: hiding an accessory or
-- background process is at best a no-op and at worst pulls a menu-bar app's
-- panel out from under it. Hidden apps un-hide themselves on activation, so a
-- later jump to any of them needs no undo step here.
--
-- Runs AFTER the target is raised, never before: hiding a background app
-- steals nothing from the frontmost one, so the backdrop vanishes behind the
-- already-front target — no beat of bare desktop, no activation to race. Only
-- hiding the frontmost app promotes Finder, and by now the frontmost app is
-- the one in the keep set.
-- hide() can return false: an app entangled in the same beat's activation
-- transition (the one just un-fronted, or the one being raised) rejects the
-- AX call. A missed hide is not cosmetic — it inherits frontmost the next
-- time the kept app gets hidden for a sibling flip, which reads as a dead
-- keypress. So misses are retried once, deferred past the transition.
function M.hide_others(keep)
  local missed = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 and not keep[app:name()] and not app:isHidden() then
      if not app:hide() then missed[#missed + 1] = app end
    end
  end
  if #missed > 0 then
    hs.timer.doAfter(0.25, function()
      for _, app in ipairs(missed) do app:hide() end
    end)
  end
end

function M.activate_app(name)
  return hs.application.launchOrFocus(name)
end

-- Rectangle owns the gap policy and macos/defaults.sh sets it; read the same
-- defaults instead of repeating the numbers, so a policy change lands here
-- without an edit. Read per call, not cached: pair jumps are rare and launching
-- an app dwarfs four `defaults read`s.
local function rectangle_default(key)
  local out = hs.execute("/usr/bin/defaults read com.knollsoft.Rectangle " .. key .. " 2>/dev/null")
  return tonumber(out) or 0
end

-- Left/right halves under Rectangle's composed gaps: screenEdgeGap* shrink the
-- screen on three sides, gapSize insets each window with half of it at the
-- shared edge, and skipGapTopEdge means no inset at the top — `frame()` already
-- starts below the menu bar, which is the whole of the top spacing.
local function pair_frames()
  local vf = hs.screen.mainScreen():frame()
  local g = rectangle_default("gapSize")
  local x = vf.x + rectangle_default("screenEdgeGapLeft")
  local w = vf.w - rectangle_default("screenEdgeGapLeft") - rectangle_default("screenEdgeGapRight")
  local h = vf.h - rectangle_default("screenEdgeGapBottom") - g
  local half = (w - 3 * g) / 2
  return { x = x + g,            y = vf.y, w = half, h = h },
         { x = x + w - g - half, y = vf.y, w = half, h = h }
end

-- `open` blocks until the app has a window (bounded), because a frame can only
-- be set on a window that exists — launchOrFocus returns before that.
local function place(name, frame)
  local app = hs.application.open(name, 2, true)
  local win = app and (app:mainWindow() or app:focusedWindow())
  if win then win:setFrame(frame) end
end

-- Left is placed first, so focus ends on the right window.
function M.activate_pair(left, right)
  local left_frame, right_frame = pair_frames()
  place(left, left_frame)
  place(right, right_frame)
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
