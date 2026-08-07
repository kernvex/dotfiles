local wezterm = require("wezterm")

return {
  font = wezterm.font_with_fallback({
    { family = "JetBrains Mono", weight = "Light" },
    { family = "JetBrainsMono Nerd Font", weight = "Light" },
    -- Persian/RTL fallback (bidi_enabled below); installed via brew `font-dejavu`.
    --
    -- The pick here is decided by advance width, not by looks. A terminal gives every
    -- character exactly one cell, so a proportional Arabic face leaves the difference
    -- between its advance and the cell as dead space -- and in a cursive script that
    -- dead space lands between letters that are supposed to join. Vazirmatn is
    -- proportional: its advances run 3..11.25 against a 9px cell, so alef alone left a
    -- 6px hole and words came apart. DejaVu Sans Mono is 8.44/9.0 across all of Persian,
    -- close enough to the cell that the joins hold.
    --
    -- Must also sit above Cascadia Code, which covers Arabic too and would otherwise
    -- claim these glyphs first -- its final alef has a zero advance.
    "DejaVu Sans Mono",
    "Cascadia Code",
    "MesloLGS NF",
    -- Backstop for anything DejaVu misses; proportional, so kept last.
    "Vazirmatn",
  }),
  font_size = 15,

  -- ﻦﺗ ﯽﺑﻮﺧ ﻡﻼ﻿ﺳ

  -- Bidi support.
  --
  -- LeftToRight, not AutoLeftToRight. WezTerm resolves a base direction per
  -- *terminal row*, so a TUI that wraps a Persian run mid-line leaves a row whose
  -- first strong character is Persian. Auto-detection then reads that row as an RTL
  -- paragraph and reorders the whole thing -- box borders included -- which is how
  -- wrapped text ends up outside the frame it belongs to. Pinning the base direction
  -- keeps every row LTR; Persian runs still shape and reverse within themselves.
  bidi_enabled = true,
  bidi_direction = "LeftToRight",

  -- color_scheme = "Batman",
  line_height = 1.0,
  harfbuzz_features = { "ss13" },

  -- some custom styled
  allow_square_glyphs_to_overflow_width = "Always",
  color_scheme = "Gruvbox Dark Hard",
  color_schemes = {
    ["Gruvbox Dark Hard"] = {
      -- The default text color
      foreground = "#ebdbb2",
      -- The default background color. Darker than Gruvbox's own #1d2021 on
      -- purpose: with opacity below 1.0 the effective backdrop is this color
      -- plus the wallpaper bleeding through, so a darker floor buys back the
      -- contrast the translucency spends — without recoloring any text.
      background = "#101213",
      -- Overrides the cell background color when the current cell is occupied by the
      -- cursor and the cursor style is set to Block
      cursor_bg = "#ebdbb2",
      -- Overrides the text color when the current cell is occupied by the cursor
      cursor_fg = "#333333",
      -- Specifies the border color of the cursor when the cursor style is set to Block,
      -- of the color of the vertical or horizontal bar when the cursor style is set to
      -- Bar or Underline.
      cursor_border = "#ebdbb2",
      -- the foreground color of selected text
      selection_fg = "#333333",
      -- the background color of selected text
      selection_bg = "#ebdbb2",
      -- The color of the scrollbar "thumb"; the portion that represents the current viewport
      scrollbar_thumb = "#333333",
      -- The color of the split lines between panes
      split = "#333333",
      ansi = {
        "#282828",
        "#cc241d",
        "#98971a",
        "#d79921",
        "#458588",
        "#b16286",
        "#689d6a",
        "#a89984",
      },
      brights = {
        "#928374",
        "#fb4934",
        "#b8bb26",
        "#fabd2f",
        "#83a598",
        "#d3769b",
        "#8ec07c",
        "#ebdbb2",
      },
    },
  },

  -- Translucency. Opacity below 1.0 is what activates the blur; blur is the
  -- radius macOS composites behind the window, not a percentage. 0.9/32 is the
  -- common readable pairing — lower opacity trades text contrast for see-through.
  window_background_opacity = 0.90,
  macos_window_background_blur = 32,

  -- Every glyph's color is multiplied by this before drawing — the knob made
  -- for translucent backgrounds. It lifts the whole palette uniformly, so TUI
  -- color semantics survive where a hand-retuned scheme would drift.
  foreground_text_hsb = { hue = 1.0, saturation = 1.02, brightness = 1.10 },

  native_macos_fullscreen_mode = true,

  -- No tab bar. tmux is the multiplexer here, and the bar's titles were actively
  -- misleading: tmux does not forward a title change outward, so each tab kept the
  -- path its shell started in while the sessionizer moved you somewhere else.
  --
  -- Nothing is lost but the strip itself. Tab switching is unaffected — WezTerm's
  -- macOS defaults already mirror Chrome (CMD+t new, CMD+w close, CMD+1..8 by
  -- index, CMD+9 last), and CMD+SHIFT+T below lists the tabs when you want to see
  -- them. The session name still reaches the macOS window title, via `set-titles`
  -- in .tmux.conf.
  enable_tab_bar = false,

  initial_cols = 150,
  initial_rows = 50,

  keys = {
    -- This will create a new split and run your default program inside it
    {
      key = "/",
      mods = "CMD",
      action = wezterm.action({ SplitVertical = { domain = "CurrentPaneDomain" } }),
    },
    { key = "'", mods = "CMD", action = wezterm.action({ SplitHorizontal = { domain = "CurrentPaneDomain" } }) },
    { key = "z", mods = "CMD", action = "TogglePaneZoomState" },
    { key = "x", mods = "CMD", action = wezterm.action({ CloseCurrentPane = { confirm = true } }) },

    -- Pane Sections
    -- Pane Navigates
    { key = "h", mods = "CMD|CTRL", action = wezterm.action({ ActivatePaneDirection = "Left" }) },
    { key = "l", mods = "CMD|CTRL", action = wezterm.action({ ActivatePaneDirection = "Right" }) },
    { key = "k", mods = "CMD|CTRL", action = wezterm.action({ ActivatePaneDirection = "Up" }) },
    { key = "j", mods = "CMD|CTRL", action = wezterm.action({ ActivatePaneDirection = "Down" }) },
    -- Pane Cycles
    { key = "[", mods = "CMD", action = wezterm.action({ ActivatePaneDirection = "Next" }) },
    { key = "]", mods = "CMD", action = wezterm.action({ ActivatePaneDirection = "Prev" }) },
    -- Pane Resize
    { key = "H", mods = "CMD|SHIFT", action = wezterm.action({ AdjustPaneSize = { "Left", 2 } }) },
    { key = "J", mods = "CMD|SHIFT", action = wezterm.action({ AdjustPaneSize = { "Down", 2 } }) },
    { key = "K", mods = "CMD|SHIFT", action = wezterm.action({ AdjustPaneSize = { "Up", 2 } }) },
    { key = "L", mods = "CMD|SHIFT", action = wezterm.action({ AdjustPaneSize = { "Right", 2 } }) },

    -- TAB section
    { key = ",", mods = "CMD", action = wezterm.action({ ActivateTabRelativeNoWrap = 1 }) },
    { key = "m", mods = "CMD", action = wezterm.action({ ActivateTabRelativeNoWrap = -1 }) },

    -- search for the string "hash" matching regardless of case
    { key = "F", mods = "CMD|SHIFT", action = wezterm.action({ Search = { CaseInSensitiveString = "hash" } }) },

    { key = "T", mods = "CMD|SHIFT", action = "ShowTabNavigator" },

    -- Moved off CMD|SHIFT+L (which is pane-resize-right above) so both work; was a dead dup.
    { key = "P", mods = "CMD|SHIFT", action = "ShowLauncher" },

    { key = "f", mods = "CMD|CTRL", action = "ToggleFullScreen" },

    { key = "N", mods = "CMD|SHIFT", action = "SpawnWindow" },

    { key = " ", mods = "CMD|SHIFT", action = "QuickSelect" },

    -- Copy Mode: keyboard-driven selection over the terminal scrollback (no mouse).
    -- Uses WezTerm's built-in copy_mode key table: hjkl move, v selects, y/Enter
    -- copies and exits, q/Esc cancels. Handy for copying a TUI response like Claude Code
    -- without holding Shift and dragging.
    { key = "x", mods = "CMD|SHIFT", action = "ActivateCopyMode" },
  },
}
