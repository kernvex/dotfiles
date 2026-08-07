--[[ Example slot table — documentation, not configuration.

The real one is `slot-table.lua` beside this file. It is untracked and stays that
way: it names real accounts, and the profile directories in it denote different
people on different machines, so a committed copy would be both a leak and wrong
on arrival. Every name below is invented.

The name matters: `~/.hammerspoon` is on Lua's module path, so a file called
`slots.lua` would be found by `require("slots")` ahead of `slots/init.lua` and
shadow the engine itself. Do not rename it back.

You should not need to write one by hand. Open the window you want, press
Hyper+p then a digit, and the pin is recorded here for you — including the
trailing comment, regenerated from Chrome so it always matches what Chrome
currently calls that profile.

  kind = "app"      any window of the application will do
  kind = "profile"  only this Chrome profile's window counts. `dir` is Chrome's
                    own directory name, durable and meaningless; the profile
                    name is resolved live and may be renamed freely.
  kind = "pair"     two applications tiled left/right under Rectangle's gap
                    policy. The one kind written by hand — a pin can only
                    capture the single focused window — but pins on other
                    slots preserve it.
]]

return {
  [0] = { kind = "app", name = "Spotify" },
  [1] = { kind = "app", name = "WezTerm" },
  [2] = { kind = "profile", dir = "Profile 70" }, -- Sam Weber (Northwind)
  [3] = { kind = "profile", dir = "Profile 72" }, -- Alex Rivera (Acme Group)
  [4] = { kind = "profile", dir = "Default" }, -- Personal
  [5] = { kind = "profile", dir = "Profile 14" }, -- Jo Marsh - Fernwood
  -- 6 deliberately free
  [7] = { kind = "pair", left = "Calendar", right = "Reminders" },
  [8] = { kind = "app", name = "Slack" },
  [9] = { kind = "app", name = "Telegram" },
}
