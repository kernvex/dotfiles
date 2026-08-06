#!/usr/bin/env lua
--[[ Every branch of the window-slot resolver, asserted against fixtures.

`resolve(request, world)` is the single pure seam of the engine (see
docs/adr/0009-window-slots-resolve-by-profile-signature.md). It takes a snapshot
of the world and returns an action; it touches no window, no browser and no
file, so this file needs neither Hammerspoon nor Chrome nor an Accessibility
grant, and passes anywhere.

Run:  lua test-resolve.lua          (exit 0 = every case passed)
      Hammerspoon ships Lua 5.4, so run this on 5.4 — `brew install lua@5.4`,
      binary at /opt/homebrew/opt/lua@5.4/bin/lua.
]]

package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
local resolve = require("slots.resolve")

-- ---------------------------------------------------------------------------
-- harness

local failures = {}
local passed = 0

local function render(v, seen)
  if type(v) ~= "table" then return tostring(v) end
  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = k .. "=" .. render(v[k] ~= nil and v[k] or v[tonumber(k)], seen)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function check(name, actual, expected)
  if same(actual, expected) then
    passed = passed + 1
  else
    failures[#failures + 1] = string.format(
      "%s\n     expected: %s\n     actual:   %s", name, render(expected), render(actual))
  end
end

-- ---------------------------------------------------------------------------
-- cases

check("unbound slot does nothing, and says why",
  resolve({ kind = "jump", slot = 6 },
          { slots = {}, profiles = {}, windows = {}, focused = nil }),
  { kind = "none", reason = "unbound" })

check("an application target is activated by name",
  resolve({ kind = "jump", slot = 8 },
          { slots = { [8] = { kind = "app", name = "Slack" } },
            profiles = {}, windows = {}, focused = nil }),
  { kind = "activate_app", name = "Slack" })

-- A signed-in profile signs its windows "<given name> (<profile name>)". This
-- profile name also contains parentheses, so the signature nests them — the
-- shape that defeats any rule keyed on "the last parenthesised group".
check("a browser identity focuses its window, signature nesting parentheses",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 13719, app = "Google Chrome", mru_rank = 1,
        title = "New chat - Pinned - Google Chrome - Sam (Sam Weber (Northwind))" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 13719 })

check("a browser identity with no window open launches its profile",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {},
    focused = nil,
  }),
  { kind = "launch", profile_dir = "Profile 70" })

-- Deliberately listed out of order: list position must not decide this.
check("several windows on one identity resolve to the most recently used",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 100, app = "Google Chrome", mru_rank = 3,
        title = "Older - Google Chrome - Sam (Sam Weber (Northwind))" },
      { id = 200, app = "Google Chrome", mru_rank = 1,
        title = "Newer - Google Chrome - Sam (Sam Weber (Northwind))" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 200 })

check("pressing the slot you are already in does nothing",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 13719, app = "Google Chrome", mru_rank = 1,
        title = "Anything - Google Chrome - Sam (Sam Weber (Northwind))" },
    },
    focused = 13719,
  }),
  { kind = "none", reason = "already_there" })

check("pinning binds a slot to the identity of the focused window",
  resolve({ kind = "pin", slot = 4 }, {
    slots = {},
    profiles = {
      ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" },
      ["Profile 72"] = { name = "Alex Rivera (Acme Group)", given_name = "" },
    },
    windows = {
      { id = 13719, app = "Google Chrome", mru_rank = 1,
        title = "Anything - Google Chrome - Sam (Sam Weber (Northwind))" },
      { id = 13802, app = "Google Chrome", mru_rank = 2,
        title = "Other - Google Chrome - Alex Rivera (Acme Group)" },
    },
    focused = 13802,
  }),
  { kind = "pin", slot = 4, target = { kind = "profile", dir = "Profile 72" } })

-- A profile deleted in Chrome leaves its slot pointing at nothing. Must report,
-- not raise: this runs inside a hotkey, where an error is a dead key.
check("a slot pointing at a profile Chrome no longer has reports it",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 999" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {},
    focused = nil,
  }),
  { kind = "none", reason = "unknown_profile" })

-- A terminal displaying this very test file has a title ending in a signature.
check("only a browser window can satisfy a browser identity",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 5, app = "WezTerm", mru_rank = 1,
        title = "test-resolve.lua - Google Chrome - Sam (Sam Weber (Northwind))" },
    },
    focused = nil,
  }),
  { kind = "launch", profile_dir = "Profile 70" })

-- Nothing in Chrome stops you renaming two profiles the same. Their signatures
-- then collide and no window can be attributed. Refuse rather than guess.
check("colliding profile names refuse the jump instead of guessing",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = {
      ["Profile 70"] = { name = "Shared Name", given_name = "" },
      ["Profile 99"] = { name = "Shared Name", given_name = "" },
    },
    windows = {
      { id = 7, app = "Google Chrome", mru_rank = 1,
        title = "Whose window? - Google Chrome - Shared Name" },
    },
    focused = nil,
  }),
  { kind = "none", reason = "ambiguous_signature" })

-- ---------------------------------------------------------------------------
-- Guards. These passed the moment they were written; they exist to stop a future
-- "simplification" of the matcher, not to have driven it. Each is a shape seen on
-- a real machine during design (names invented, structure untouched).

-- THE case the whole matcher exists for. Both signatures have the shape "X (Y)"
-- and decompose differently: the first is account + name where the name itself
-- contains parentheses; the second is a signed-out profile whose name contains
-- parentheses and has no account at all. A parser cannot separate them — only
-- constructing each expected signature and comparing can.
local twins = {
  slots = {
    [2] = { kind = "profile", dir = "Profile 70" },
    [3] = { kind = "profile", dir = "Profile 72" },
  },
  profiles = {
    ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" },
    ["Profile 72"] = { name = "Alex Rivera (Acme Group)", given_name = "" },
  },
  windows = {
    { id = 13719, app = "Google Chrome", mru_rank = 1,
      title = "Inbox - Pinned - Google Chrome - Sam (Sam Weber (Northwind))" },
    { id = 13802, app = "Google Chrome", mru_rank = 2,
      title = "Teams - Pinned - Google Chrome - Alex Rivera (Acme Group)" },
  },
  focused = nil,
}
check("ambiguous twin: signed-in profile whose name has parentheses",
  resolve({ kind = "jump", slot = 2 }, twins), { kind = "focus", id = 13719 })
check("ambiguous twin: signed-out profile whose name has parentheses",
  resolve({ kind = "jump", slot = 3 }, twins), { kind = "focus", id = 13802 })

check("a signed-out profile with a plain name signs without parentheses",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 64" } },
    profiles = { ["Profile 64"] = { name = "Reception", given_name = "" } },
    windows = {
      { id = 42, app = "Google Chrome", mru_rank = 1,
        title = "Docs - Google Chrome - Reception" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 42 })

check("an apostrophe in a profile name is just a character",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 72" } },
    profiles = { ["Profile 72"] = { name = "Alex O'Rivera - Acme", given_name = "" } },
    windows = {
      { id = 43, app = "Google Chrome", mru_rank = 1,
        title = "Mail - Google Chrome - Alex O'Rivera - Acme" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 43 })

-- Anchoring on the END of the title is what makes this safe; a "find the
-- separator" rule would take the first one and attribute the window to Sam.
check("a tab title containing the separator does not confuse attribution",
  resolve({ kind = "jump", slot = 3 }, {
    slots = { [3] = { kind = "profile", dir = "Profile 72" } },
    profiles = {
      ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" },
      ["Profile 72"] = { name = "Alex Rivera (Acme Group)", given_name = "" },
    },
    windows = {
      { id = 44, app = "Google Chrome", mru_rank = 1,
        title = "Notes on - Google Chrome - Sam (Sam Weber (Northwind))"
             .. " - Google Chrome - Alex Rivera (Acme Group)" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 44 })

check("pinning over a bound slot replaces the binding",
  resolve({ kind = "pin", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 72"] = { name = "Alex Rivera (Acme Group)", given_name = "" } },
    windows = {
      { id = 13802, app = "Google Chrome", mru_rank = 1,
        title = "Teams - Google Chrome - Alex Rivera (Acme Group)" },
    },
    focused = 13802,
  }),
  { kind = "pin", slot = 2, target = { kind = "profile", dir = "Profile 72" } })

-- Any window that is not a browser identity pins as its application: a slot
-- reaching "Reminders" wants any Reminders window, so the app is the honest unit.
check("pinning a non-browser window binds its application",
  resolve({ kind = "pin", slot = 7 }, {
    slots = {},
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = { { id = 9, app = "Reminders", mru_rank = 1, title = "Reminders" } },
    focused = 9,
  }),
  { kind = "pin", slot = 7, target = { kind = "app", name = "Reminders" } })

-- A browser window we cannot attribute must NOT fall through to pinning the
-- application: "Google Chrome" as a target reaches all four accounts equally,
-- which is the precise ambiguity this whole feature exists to remove. Happens
-- for real when a window's title has not been stamped yet, and under screen
-- lock, where macOS degrades every title to the bare app name.
check("an unidentifiable browser window refuses rather than pinning the app",
  resolve({ kind = "pin", slot = 2 }, {
    slots = {},
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = { { id = 9, app = "Google Chrome", mru_rank = 1, title = "Chrome" } },
    focused = 9,
  }),
  { kind = "none", reason = "unidentified_browser_window" })

-- `jump` already refuses a colliding signature. `pin` must too, and for a worse
-- reason: it resolves by scanning the profile table, whose order is undefined, so
-- it would bind one of the two arbitrarily and write that guess to disk.
check("pinning a window whose signature two profiles share refuses",
  resolve({ kind = "pin", slot = 2 }, {
    slots = {},
    profiles = {
      ["Profile 70"] = { name = "Shared Name", given_name = "" },
      ["Profile 99"] = { name = "Shared Name", given_name = "" },
    },
    windows = {
      { id = 9, app = "Google Chrome", mru_rank = 1,
        title = "Whose window? - Google Chrome - Shared Name" },
    },
    focused = 9,
  }),
  { kind = "none", reason = "ambiguous_signature" })

check("pinning with nothing focused reports rather than binds",
  resolve({ kind = "pin", slot = 2 },
          { slots = {}, profiles = {}, windows = {}, focused = nil }),
  { kind = "none", reason = "nothing_focused" })

-- Resolution takes the registry as an argument rather than remembering one, so a
-- rename between two calls simply lands. These two cases pin that property down:
-- they are what stops anyone "optimising" the registry into module state.
local window_after_rename = {
  { id = 300, app = "Google Chrome", mru_rank = 1,
    title = "Inbox - Google Chrome - Sam (Sam Weber (Northwind))" },
}
check("before a rename, the old signature matches",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = window_after_rename,
    focused = nil,
  }),
  { kind = "focus", id = 300 })
check("after a rename, the same slot follows the new name",
  resolve({ kind = "jump", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    -- renamed in Chrome; the window's title was restamped to match
    profiles = { ["Profile 70"] = { name = "Sam Weber (Fernwood)", given_name = "Sam" } },
    windows = {
      { id = 300, app = "Google Chrome", mru_rank = 1,
        title = "Inbox - Google Chrome - Sam (Sam Weber (Fernwood))" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 300 })

-- Signing in does not edit the name, it changes the signature's SHAPE: the same
-- profile goes from bare name to "<given name> (<name>)".
check("signing a profile in changes the shape of its signature, and still matches",
  resolve({ kind = "jump", slot = 3 }, {
    slots = { [3] = { kind = "profile", dir = "Profile 72" } },
    profiles = { ["Profile 72"] = { name = "Reception", given_name = "Robin" } },
    windows = {
      { id = 301, app = "Google Chrome", mru_rank = 1,
        title = "Docs - Google Chrome - Robin (Reception)" },
    },
    focused = nil,
  }),
  { kind = "focus", id = 301 })

-- An application target says nothing about windows: any window of that app will
-- do, so the count is irrelevant and the action is the same either way.
check("an application target ignores how many windows it has",
  resolve({ kind = "jump", slot = 8 }, {
    slots = { [8] = { kind = "app", name = "Slack" } },
    profiles = {},
    windows = {
      { id = 400, app = "Slack", mru_rank = 1, title = "Slack - one" },
      { id = 401, app = "Slack", mru_rank = 2, title = "Slack - two" },
    },
    focused = 400,
  }),
  { kind = "activate_app", name = "Slack" })

-- ---------------------------------------------------------------------------

if #failures > 0 then
  io.stderr:write(string.format("\n%d passed, %d FAILED\n\n", passed, #failures))
  for _, f in ipairs(failures) do io.stderr:write("  ✗ " .. f .. "\n\n") end
  os.exit(1)
end
print(string.format("%d passed", passed))
