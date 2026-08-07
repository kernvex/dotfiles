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

check("a pair target activates both applications for side-by-side tiling",
  resolve({ kind = "jump", slot = 7 },
          { slots = { [7] = { kind = "pair", left = "Calendar", right = "Reminders" } },
            profiles = {}, windows = {}, focused = nil }),
  { kind = "activate_pair", left = "Calendar", right = "Reminders" })

-- Re-activating a pair also re-tiles it, so "already in it" is not a case to
-- skip: pressing the slot again is how a drifted layout gets healed.
check("a pair target re-activates even when one of its windows is focused",
  resolve({ kind = "jump", slot = 7 },
          { slots = { [7] = { kind = "pair", left = "Calendar", right = "Reminders" } },
            profiles = {},
            windows = { { id = 9, app = "Reminders", mru_rank = 1, title = "Reminders" } },
            focused = 9 }),
  { kind = "activate_pair", left = "Calendar", right = "Reminders" })

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
-- Solo: the jump plus backdrop-clearing instructions. The resolver decides who
-- stays visible and which same-app siblings leave; the adapters only obey.

check("solo on an app slot keeps that app and hides the rest",
  resolve({ kind = "solo", slot = 8 }, {
    slots = { [8] = { kind = "app", name = "Slack" } },
    profiles = {},
    windows = {
      { id = 1, app = "Slack", mru_rank = 1, title = "Slack" },
      { id = 2, app = "Mail", mru_rank = 2, title = "Inbox" },
    },
    focused = nil,
  }),
  { kind = "solo", action = { kind = "activate_app", name = "Slack" },
    keep = { Slack = true }, minimize = {} })

-- Hiding is per-application, so the browser's other identities can only leave
-- the backdrop by being minimized — and only they do; the target stays up.
check("solo on a browser identity minimizes the browser's other windows",
  resolve({ kind = "solo", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 100, app = "Google Chrome", mru_rank = 1,
        title = "Inbox - Google Chrome - Sam (Sam Weber (Northwind))" },
      { id = 200, app = "Google Chrome", mru_rank = 2,
        title = "Other - Google Chrome - Alex Rivera (Acme Group)" },
      { id = 300, app = "WezTerm", mru_rank = 3, title = "dotfiles" },
    },
    focused = nil,
  }),
  { kind = "solo", action = { kind = "focus", id = 100 },
    keep = { ["Google Chrome"] = true }, minimize = { 200 } })

-- Already being there is not a reason to skip: clearing the backdrop is the
-- half of solo that jump does not already do. And it must resolve to a real
-- focus, not already_there — the clear hides the target's own app to flip
-- sibling state off-screen, so raising the target back out is what makes the
-- press visible.
check("solo on the slot you are in still clears the backdrop",
  resolve({ kind = "solo", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 100, app = "Google Chrome", mru_rank = 1,
        title = "Inbox - Google Chrome - Sam (Sam Weber (Northwind))" },
      { id = 200, app = "Google Chrome", mru_rank = 2,
        title = "Other - Google Chrome - Alex Rivera (Acme Group)" },
    },
    focused = 100,
  }),
  { kind = "solo", action = { kind = "focus", id = 100 },
    keep = { ["Google Chrome"] = true }, minimize = { 200 } })

-- The launched window is the one the slot wants, so every current browser
-- window is backdrop.
check("solo that launches keeps the browser and minimizes its current windows",
  resolve({ kind = "solo", slot = 2 }, {
    slots = { [2] = { kind = "profile", dir = "Profile 70" } },
    profiles = { ["Profile 70"] = { name = "Sam Weber (Northwind)", given_name = "Sam" } },
    windows = {
      { id = 200, app = "Google Chrome", mru_rank = 1,
        title = "Other - Google Chrome - Alex Rivera (Acme Group)" },
    },
    focused = nil,
  }),
  { kind = "solo", action = { kind = "launch", profile_dir = "Profile 70" },
    keep = { ["Google Chrome"] = true }, minimize = { 200 } })

check("solo on a pair keeps both applications",
  resolve({ kind = "solo", slot = 7 }, {
    slots = { [7] = { kind = "pair", left = "Calendar", right = "Reminders" } },
    profiles = {}, windows = {}, focused = nil,
  }),
  { kind = "solo", action = { kind = "activate_pair", left = "Calendar", right = "Reminders" },
    keep = { Calendar = true, Reminders = true }, minimize = {} })

check("solo on an unbound slot does nothing and hides nothing",
  resolve({ kind = "solo", slot = 6 },
          { slots = {}, profiles = {}, windows = {}, focused = nil }),
  { kind = "none", reason = "unbound" })

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
-- unaccounted: the windows Chrome admits to that the Accessibility tree has
-- lost. Scripted windows carry bare tab titles; AX titles extend them with
-- decorations and the profile stamp, or the window is gone from AX entirely —
-- which is the case this function exists to catch.

check("a window Chrome lists but AX cannot see is reported for rescue",
  resolve.unaccounted(
    { { id = 5, title = "Chat | Teams", minimized = false } },
    {}),
  { 5 })

check("a decorated AX title accounts for its bare tab title",
  resolve.unaccounted(
    { { id = 5, title = "Chat | Teams", minimized = false } },
    { { id = 1, app = "Google Chrome", mru_rank = 1,
        title = "Chat | Teams - Pinned - Google Chrome - Sam (Sam Weber (Northwind))" } }),
  {})

-- The minimized window is AX-visible and claims the one AX title, which is
-- exactly what leaves its lost twin — same tab title — with nothing to claim.
check("a minimized twin does not mask a lost window with the same title",
  resolve.unaccounted(
    { { id = 3, title = "New Tab", minimized = true },
      { id = 7, title = "New Tab", minimized = false } },
    { { id = 1, app = "Google Chrome", mru_rank = 1,
        title = "New Tab - Google Chrome - Sam (Sam Weber (Northwind))" } }),
  { 7 })

-- "New" is a prefix of "New Tab" but not at a " - " boundary, so it must not
-- claim that AX title.
check("a tab title claims only at a ' - ' boundary, not any prefix",
  resolve.unaccounted(
    { { id = 3, title = "New", minimized = false } },
    { { id = 1, app = "Google Chrome", mru_rank = 1,
        title = "New Tab - Google Chrome - Sam (Sam Weber (Northwind))" } }),
  { 3 })

-- Longest first: were "Inbox" allowed to claim the only AX title, the longer
-- "Inbox - Zimbra" would be consigned while actually visible.
check("the longest tab title claims first so a shorter one cannot double-book",
  resolve.unaccounted(
    { { id = 2, title = "Inbox", minimized = false },
      { id = 4, title = "Inbox - Zimbra", minimized = false } },
    { { id = 1, app = "Google Chrome", mru_rank = 1,
        title = "Inbox - Zimbra - Google Chrome - Sam (Sam Weber (Northwind))" } }),
  { 2 })

-- A terminal displaying a Chrome-shaped title must not vouch for a browser
-- window.
check("only browser windows can account for a scripted window",
  resolve.unaccounted(
    { { id = 9, title = "Chat | Teams", minimized = false } },
    { { id = 1, app = "WezTerm", mru_rank = 1,
        title = "Chat | Teams - Google Chrome - Sam (Sam Weber (Northwind))" } }),
  { 9 })

-- A blank tab title attributes to nothing; consigning on it would gamble a
-- visible window. Skipped, never reported.
check("a blank tab title is never consigned",
  resolve.unaccounted(
    { { id = 6, title = "", minimized = false } },
    {}),
  {})

check("a consistent world rescues nothing",
  resolve.unaccounted(
    { { id = 2, title = "Docs", minimized = false },
      { id = 3, title = "Mail", minimized = true } },
    { { id = 1, app = "Google Chrome", mru_rank = 1,
        title = "Docs - Google Chrome - Reception" },
      { id = 4, app = "Google Chrome", mru_rank = 2,
        title = "Mail - Google Chrome - Reception" } }),
  {})

-- ---------------------------------------------------------------------------

if #failures > 0 then
  io.stderr:write(string.format("\n%d passed, %d FAILED\n\n", passed, #failures))
  for _, f in ipairs(failures) do io.stderr:write("  ✗ " .. f .. "\n\n") end
  os.exit(1)
end
print(string.format("%d passed", passed))
