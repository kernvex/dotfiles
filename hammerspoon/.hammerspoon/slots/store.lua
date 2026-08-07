--[[ Adapter: the slot table on disk.

Machine-local and never committed. It carries account labels, and the profile
directories in it denote different people on different machines, so a shared
copy would be both a leak and wrong on arrival. `slot-table.example.lua` beside
it documents the format with invented names.

Named `slot-table.lua` rather than `slots.lua` because `~/.hammerspoon` is on
Lua's module path: a file called `slots.lua` is found by `require("slots")`
*before* `slots/init.lua`, so the data would silently shadow the engine and every
key would fail with a nil call.

Written by pinning rather than by hand, so saving regenerates the file. The
profile name is re-emitted as a trailing comment on each save: the file stays
readable to a human, while the durable identifier remains the directory.
]]

local M = {}

local PATH = os.getenv("HOME") .. "/.hammerspoon/slot-table.lua"

function M.path() return PATH end

function M.load()
  local chunk = loadfile(PATH)
  if chunk == nil then return {} end
  local ok, table_ = pcall(chunk)
  if not ok or type(table_) ~= "table" then return {} end
  return table_
end

-- A trailing comment sits after the comma, so the comma is unconditional and the
-- comment is the only thing that varies.
local function entry_source(target, profiles)
  if target.kind == "app" then
    return string.format("{ kind = \"app\", name = %q },", target.name)
  end
  -- Pairs are written by hand (a pin captures one window), but a save must
  -- still re-emit them: it regenerates the whole file, and dropping the entry
  -- here would mean any pin on any slot silently unbinds every pair.
  if target.kind == "pair" then
    return string.format("{ kind = \"pair\", left = %q, right = %q },", target.left, target.right)
  end
  local source = string.format("{ kind = \"profile\", dir = %q },", target.dir)
  local profile = profiles and profiles[target.dir]
  if profile and profile.name ~= "" then
    return source .. " -- " .. profile.name
  end
  return source
end

function M.save(slots, profiles)
  local digits = {}
  for digit in pairs(slots) do digits[#digits + 1] = digit end
  table.sort(digits)

  local lines = {
    "-- Slot table. Machine-local, never committed: see slot-table.example.lua.",
    "-- Written by pinning (Hyper+p then a digit). This file is regenerated on",
    "-- every pin, so hand-written comments do not survive one.",
    "return {",
  }
  for _, digit in ipairs(digits) do
    lines[#lines + 1] = string.format("  [%d] = %s", digit, entry_source(slots[digit], profiles))
  end
  lines[#lines + 1] = "}"

  local file, err = io.open(PATH, "w")
  if file == nil then return false, err end
  file:write(table.concat(lines, "\n") .. "\n")
  file:close()
  return true
end

return M
