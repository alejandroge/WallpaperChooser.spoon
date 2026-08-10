local obj = {}
obj.__index = obj

obj.name = "WallpaperChooser"
obj.version = "0.1.0"
obj.author = "Alejandro Guevara <alejandro.guevara.esc@gmail.com>"
obj.homepage = "https://www.hammerspoon.org/Spoons/"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local parser = dofile(spoonPath .. "parser.lua")
local wallpaper = dofile(spoonPath .. "wallpaper.lua")

obj.logger = hs.logger.new("WallpaperChooser")

obj.sourceURL = nil        -- Smashing Magazine wallpaper article URL
obj.preferredResolutions = {}
obj.variantPreference = { "nocal", "cal" }
obj.cacheDir = hs.fs.temporaryDirectory() .. "/WallpaperChooser"
obj.cycleEnabled = false
obj.cycleInterval = 60 * 60
obj._cycleTimer = nil
obj._cycleChoices = nil
obj._cycleIndex = 1

local function downloadToFile(url, destPath, callback)
  hs.http.asyncGet(url, nil, function(status, body)
    if status < 200 or status >= 300 then
      callback(false, "HTTP " .. tostring(status))
      return
    end
    local file, err = io.open(destPath, "wb")
    if not file then
      callback(false, err or "failed to open file")
      return
    end
    file:write(body)
    file:close()
    callback(true)
  end)
end

function obj:configure(options)
  options = options or {}
  self.sourceURL = options.sourceURL or self.sourceURL
  self.preferredResolutions = options.preferredResolutions or self.preferredResolutions
  self.variantPreference = options.variantPreference or self.variantPreference
  self.cacheDir = options.cacheDir or self.cacheDir
  if options.cycleEnabled ~= nil then self.cycleEnabled = options.cycleEnabled end
  self.cycleInterval = options.cycleInterval or self.cycleInterval
  return self
end

function obj:initChooser()
  if self.chooser then
    return
  end
  self.chooser = hs.chooser.new(function(choice)
    if choice then
      self:applyChoice(choice)
    end
  end)
  self.chooser:rows(10)
  self.chooser:width(30)
  self.chooser:placeholderText("Fetching wallpapers...")
end

function obj:bindHotkeys(mapping)
  local spec = {
    choose = function() self:choose() end,
    cycleOnce = function() self:cycleOnce() end,
  }
  hs.spoons.bindHotkeysToSpec(spec, mapping or {})
  return self
end

function obj:choose()
  if not self.sourceURL then
    hs.alert.show("WallpaperChooser: sourceURL not configured")
    return
  end
  self:initChooser()
  self.chooser:placeholderText("Loading wallpapers...")
  self.chooser:choices({})
  self.chooser:show()
  self:fetchChoices(function(choices, err)
    if not choices then
      hs.alert.show("WallpaperChooser error: " .. (err or "unknown"))
      self.chooser:hide()
      return
    end
    self.chooser:placeholderText("Select wallpaper")
    self.chooser:choices(choices)
  end)
end

function obj:fetchChoices(callback)
  parser.fetch(self.sourceURL, function(decoded, err)
    if not decoded then
      callback(nil, err)
      return
    end
    self:choicesFromDecoded(decoded, callback, true)
  end)
end

function obj:choicesFromDecoded(decoded, callback, includeImages)
  local choices, err = wallpaper.choicesFromDecoded(decoded, self.variantPreference, includeImages)
  if not choices then
    callback(nil, err)
    return
  end
  callback(choices)
end

function obj:loadCycleChoices(callback)
  parser.fetch(self.sourceURL, function(decoded, err)
    if not decoded then
      callback(nil, err)
      return
    end

    self:choicesFromDecoded(decoded, function(choices, choicesErr)
      if not choices then
        callback(nil, choicesErr)
        return
      end

      self._cycleChoices = choices
      self._cycleIndex = 1
      callback(choices)
    end, false)
  end)
end

function obj:cycleOnce()
  if not self.sourceURL then
    self.logger.e("WallpaperChooser: sourceURL not configured")
    return
  end

  local function applyNext(choices)
    if not choices or #choices == 0 then
      self.logger.e("WallpaperChooser: no wallpapers available for cycling")
      return
    end

    if self._cycleIndex > #choices then
      self._cycleIndex = 1
    end

    local choice = choices[self._cycleIndex]
    self._cycleIndex = self._cycleIndex + 1
    self:applyChoice(choice)
  end

  if self._cycleChoices then
    applyNext(self._cycleChoices)
    return
  end

  self:loadCycleChoices(function(choices, err)
    if not choices then
      self.logger.e("WallpaperChooser cycle error: " .. tostring(err or "unknown"))
      return
    end
    applyNext(choices)
  end)
end

function obj:startCycling()
  if self._cycleTimer then
    self._cycleTimer:stop()
    self._cycleTimer = nil
  end

  self._cycleChoices = nil
  self._cycleIndex = 1

  if not self.cycleEnabled then return self end
  if not self.cycleInterval or self.cycleInterval <= 0 then return self end

  self:loadCycleChoices(function(_, err)
    if err then
      self.logger.e("WallpaperChooser cycle preload error: " .. tostring(err))
    end
  end)

  self._cycleTimer = hs.timer.new(self.cycleInterval, function()
    self:cycleOnce()
  end)
  self._cycleTimer:start()

  return self
end

function obj:stopCycling()
  if self._cycleTimer then
    self._cycleTimer:stop()
    self._cycleTimer = nil
  end
  return self
end

function obj:start()
  self:startCycling()
  return self
end

function obj:applyChoice(choice)
  local ok, err = wallpaper.ensureDir(self.cacheDir)
  if not ok then
    hs.alert.show("WallpaperChooser cache error: " .. tostring(err))
    return
  end
  local screens = hs.screen.allScreens()
  if #screens == 0 then
    hs.alert.show("WallpaperChooser: no screens found")
    return
  end
  for idx, screen in ipairs(screens) do
    local resKey, url = wallpaper.bestResolutionForScreen(choice.resolutions, screen, self.preferredResolutions)
    if not url then
      self.logger.wf("No resolution match for screen %d", idx)
    else
      self:applyWallpaperForScreen(screen, choice, resKey, url)
    end
  end
end

function obj:applyWallpaperForScreen(screen, choice, resKey, url)
  local slug = wallpaper.sanitizeFilenamePart(choice.wallpaper.slug or choice.wallpaper.name or "wallpaper")
  local variant = wallpaper.sanitizeFilenamePart(choice.variantKey or "variant")
  local ext = wallpaper.fileExtensionFromURL(url)
  local filename = string.format("%s/%s-%s-%s.%s", self.cacheDir, slug, variant, wallpaper.sanitizeFilenamePart(resKey or ""), ext)
  if hs.fs.attributes(filename, "mode") == "file" then
    local setOk = screen:desktopImageURL("file://" .. filename)
    if not setOk then
      hs.alert.show("Failed to set wallpaper for " .. tostring(screen:id()))
    end
    return
  end

  downloadToFile(url, filename, function(success, err)
    if not success then
      hs.alert.show("Download failed: " .. tostring(err))
      return
    end
    local setOk = screen:desktopImageURL("file://" .. filename)
    if not setOk then
      hs.alert.show("Failed to set wallpaper for " .. tostring(screen:id()))
    end
  end)
end

return obj
