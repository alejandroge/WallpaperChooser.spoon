local M = {}

function M.sanitizeFilenamePart(str)
  return tostring(str or ""):gsub("[^%w%-_.]", "_")
end

function M.ensureDir(path)
  local attrs = hs.fs.attributes(path)
  if attrs and attrs.mode == "directory" then
    return true
  end
  local ok, err = hs.fs.mkdir(path)
  if not ok then
    return false, err
  end
  return true
end

local function sortedKeys(tbl)
  local keys = {}
  for key, _ in pairs(tbl or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function bestVariantFor(wallpaper, preference)
  if not wallpaper.variants then
    return nil
  end
  for _, key in ipairs(preference or {}) do
    if wallpaper.variants[key] then
      return key
    end
  end
  for _, key in ipairs(sortedKeys(wallpaper.variants)) do
    return key
  end
  return nil
end

local function resolutionSize(resolution)
  local width, height = tostring(resolution or ""):match("^(%d+)x(%d+)$")
  return tonumber(width), tonumber(height)
end

function M.bestResolutionForScreen(resolutions, screen, preferredResolutions)
  if not resolutions then
    return nil, nil
  end

  if screen then
    local mode = screen:currentMode()
    if mode then
      local key = string.format("%dx%d", mode.w, mode.h)
      if resolutions[key] then
        return key, resolutions[key]
      end
    end
  end

  for _, key in ipairs(preferredResolutions or {}) do
    if resolutions[key] then
      return key, resolutions[key]
    end
  end

  local bestKey, bestUrl, bestPixels = nil, nil, -1
  for _, key in ipairs(sortedKeys(resolutions)) do
    local url = resolutions[key]
    local width, height = resolutionSize(key)
    local pixels = width and height and width * height or 0
    if pixels > bestPixels then
      bestKey = key
      bestUrl = url
      bestPixels = pixels
    end
  end

  return bestKey, bestUrl
end

function M.fileExtensionFromURL(url)
  if not url then
    return "img"
  end
  local path = tostring(url):match("^[^?#]+") or tostring(url)
  local ext = path:match("%.([a-zA-Z0-9]+)$")
  return ext and ext:lower() or "img"
end

function M.choicesFromDecoded(decoded, variantPreference, includeImages)
  if not decoded.wallpapers then
    return nil, "JSON missing wallpapers array"
  end

  local choices = {}
  for _, item in ipairs(decoded.wallpapers) do
    local variantKey = bestVariantFor(item, variantPreference)
    local variant = variantKey and item.variants and item.variants[variantKey] or nil
    local image = nil
    local text = item.name or item.slug or "Wallpaper"

    if variantKey then
      text = string.format("%s (%s)", text, variantKey)
    end

    if includeImages and item.preview_url then
      image = hs.image.imageFromURL(item.preview_url)
      if image then image:size({ w = 64, h = 64 }) end
    end

    table.insert(choices, {
      text = text,
      subText = item.slug or "",
      image = image,
      wallpaper = item,
      variantKey = variantKey,
      resolutions = variant and variant.resolutions or nil,
    })
  end

  return choices
end

return M
