# WallpaperChooser.spoon

Fetch wallpaper options from a Smashing Magazine wallpaper article, show them in an `hs.chooser`, and set per-screen desktop images using the best matching resolution.

## Setup

1. Place `WallpaperChooser.spoon` in `~/.hammerspoon/Spoons/`.
2. In `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("WallpaperChooser")

spoon.WallpaperChooser:configure({
  sourceURL = "https://www.smashingmagazine.com/2025/12/desktop-wallpaper-calendars-january-2026/",
  preferredResolutions = { "1680x1050", "1920x1080", "2560x1440" }, -- optional
  variantPreference = { "nocal", "cal" }, -- optional
  cacheDir = os.getenv("HOME") .. "/Documents/wallpapers", -- optional; defaults to temp dir
  cycleEnabled = true, -- optional; defaults to false
  cycleInterval = 60 * 60, -- optional; seconds, defaults to one hour
})

spoon.WallpaperChooser:bindHotkeys({
  choose = { { "ctrl", "alt", "cmd" }, "w" },
  cycleOnce = { { "ctrl", "alt", "cmd" }, "b" }, -- optional; applies next wallpaper immediately
})
:start()
```

Invoke the hotkey to fetch wallpapers, select one, and it will apply per screen.

## Notes

- The spoon has a built-in Lua parser for Smashing Magazine wallpaper article pages.
- The spoon first tries the exact screen resolution, then `preferredResolutions`, then the largest available resolution.
- Cycling is sequential based on the parsed wallpaper list order and fetches/parses once per config reload.
- `cycleOnce` uses the same sequential path as the timer, so it is useful for testing cycling.
- Images are downloaded to a cache directory (default: system temporary directory). Set `cacheDir` to persist them.
