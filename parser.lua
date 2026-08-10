local M = {}

local function normalizeURL(url)
  return tostring(url or ""):gsub("х", "x"):gsub("Х", "x"):gsub("×", "x")
end

local function htmlDecode(value)
  return tostring(value or "")
    :gsub("&amp;", "&")
    :gsub("&quot;", '"')
    :gsub("&#39;", "'")
    :gsub("&lt;", "<")
    :gsub("&gt;", ">")
end

local function slugToName(slug)
  local words = {}
  for word in tostring(slug or ""):gmatch("[^%-]+") do
    table.insert(words, word:sub(1, 1):upper() .. word:sub(2))
  end
  return table.concat(words, " ")
end

local function hasSuffix(value, suffix)
  return value:sub(-#suffix) == suffix
end

local function isImageURL(url)
  local lower = tostring(url or ""):lower()
  return hasSuffix(lower, ".png") or hasSuffix(lower, ".jpg") or hasSuffix(lower, ".jpeg")
end

local function isAbsoluteURL(url)
  return tostring(url or ""):match("^https?://") ~= nil
end

local function addURL(urls, url)
  url = htmlDecode(tostring(url or ""):match("^%s*(.-)%s*$"))
  if url == "" then return end
  if not isImageURL(url) then return end
  if not isAbsoluteURL(url) then return end

  table.insert(urls, url)
end

local function extractImageLinks(html)
  local urls = {}
  html = tostring(html or "")

  for url in html:gmatch("https://[^'\"<>%s]+%.png") do
    addURL(urls, url)
  end
  for url in html:gmatch("https://[^'\"<>%s]+%.jpg") do
    addURL(urls, url)
  end
  for url in html:gmatch("https://[^'\"<>%s]+%.jpeg") do
    addURL(urls, url)
  end

  for _, href in html:gmatch("<[aA][^>]-[hH][rR][eE][fF]%s*=%s*(['\"])(.-)%1") do
    addURL(urls, href)
  end

  for _, src in html:gmatch("<[iI][mM][gG][^>]-[sS][rR][cC]%s*=%s*(['\"])(.-)%1") do
    addURL(urls, src)
  end

  for _, srcset in html:gmatch("[sS][rR][cC][sS][eE][tT]%s*=%s*(['\"])(.-)%1") do
    for part in srcset:gmatch("[^,]+") do
      local url = part:match("^%s*(%S+)")
      addURL(urls, url)
    end
  end

  local seen = {}
  local unique = {}
  for _, url in ipairs(urls) do
    if not seen[url] then
      seen[url] = true
      table.insert(unique, url)
    end
  end
  table.sort(unique)

  return unique
end

local function matchWallpaperURL(url)
  local normalized = normalizeURL(url)
  local host, rest = normalized:match("^https://([^/]+)/files/wallpapers/(.+)$")
  if host ~= "www.smashingmagazine.com" and host ~= "smashingmagazine.com" and host ~= "files.smashing.media" then
    return nil
  end

  local _, remainder = rest:match("^([^/]+)/(.+)$")
  if not remainder then return nil end

  local parts = {}
  for part in remainder:gmatch("[^/]+") do
    table.insert(parts, part)
  end

  if #parts < 1 or #parts > 3 then return nil end

  local slugDir = nil
  local variantDir = nil
  local filename = nil

  if #parts == 3 then
    slugDir = parts[1]
    variantDir = parts[2]
    filename = parts[3]
  elseif #parts == 2 then
    if parts[1] == "cal" or parts[1] == "nocal" then
      variantDir = parts[1]
      filename = parts[2]
    else
      slugDir = parts[1]
      filename = parts[2]
    end
  else
    filename = parts[1]
  end

  if variantDir and variantDir ~= "cal" and variantDir ~= "nocal" then return nil end

  local baseName, variantFile, resolution = filename:match("^(.+)%-([cC][aA][lL])%-(%d+x%d+)%.jpg$")
  if not baseName then
    baseName, variantFile, resolution = filename:match("^(.+)%-([cC][aA][lL])%-(%d+x%d+)%.jpeg$")
  end
  if not baseName then
    baseName, variantFile, resolution = filename:match("^(.+)%-([cC][aA][lL])%-(%d+x%d+)%.png$")
  end
  if not baseName then
    baseName, variantFile, resolution = filename:match("^(.+)%-([nN][oO][cC][aA][lL])%-(%d+x%d+)%.jpg$")
  end
  if not baseName then
    baseName, variantFile, resolution = filename:match("^(.+)%-([nN][oO][cC][aA][lL])%-(%d+x%d+)%.jpeg$")
  end
  if not baseName then
    baseName, variantFile, resolution = filename:match("^(.+)%-([nN][oO][cC][aA][lL])%-(%d+x%d+)%.png$")
  end
  if not baseName then
    baseName, resolution = filename:match("^(.+)%-(%d+x%d+)%.jpg$")
  end
  if not baseName then
    baseName, resolution = filename:match("^(.+)%-(%d+x%d+)%.jpeg$")
  end
  if not baseName then
    baseName, resolution = filename:match("^(.+)%-(%d+x%d+)%.png$")
  end
  if not baseName or not resolution then return nil end

  local slug = slugDir or baseName
  local variant = variantDir or variantFile or "nocal"
  variant = variant:lower()

  return slug, variant, resolution
end

local function matchPreviewURL(url)
  local normalized = normalizeURL(url)
  local slug = normalized:match("^https://[^/]+/files/wallpapers/[^/]+/([^/]+)/[^/]+%-preview%.png$")
  if slug then return slug end

  local filename = normalized:match("/([^/]+)%.png$")
  if not filename then return nil end
  if not filename:match("%-preview") then return nil end

  slug = filename:gsub("%-preview%-opt$", ""):gsub("%-preview$", "")

  local parts = {}
  for part in slug:gmatch("[^%-]+") do
    table.insert(parts, part)
  end

  if #parts > 2 and parts[2]:match("^%d%d?$") then
    table.remove(parts, 1)
    table.remove(parts, 1)
    slug = table.concat(parts, "-")
  end

  return slug ~= "" and slug or nil
end

function M.parse(html, sourceURL)
  local wallMap = {}

  for _, url in ipairs(extractImageLinks(html)) do
    local slug, variant, resolution = matchWallpaperURL(url)
    if slug then
      local wallpaper = wallMap[slug]
      if not wallpaper then
        wallpaper = {
          slug = slug,
          name = slugToName(slug),
          variants = {},
        }
        wallMap[slug] = wallpaper
      end

      wallpaper.variants[variant] = wallpaper.variants[variant] or { resolutions = {} }
      wallpaper.variants[variant].resolutions[resolution] = url
    else
      local previewSlug = matchPreviewURL(url)
      if previewSlug then
        local wallpaper = wallMap[previewSlug]
        if not wallpaper then
          wallpaper = {
            slug = previewSlug,
            name = slugToName(previewSlug),
            variants = {},
          }
          wallMap[previewSlug] = wallpaper
        end
        wallpaper.preview_url = wallpaper.preview_url or url
      end
    end
  end

  local slugs = {}
  for slug, _ in pairs(wallMap) do
    table.insert(slugs, slug)
  end
  table.sort(slugs)

  local wallpapers = {}
  for _, slug in ipairs(slugs) do
    local wallpaper = wallMap[slug]
    if next(wallpaper.variants) then
      table.insert(wallpapers, wallpaper)
    end
  end

  local output = {
    source_url = sourceURL,
    wallpaper_count = #wallpapers,
    wallpapers = wallpapers,
  }

  if #wallpapers == 0 then
    output.errors = { "no wallpapers detected (parsing rules may need adjustment)" }
  end

  return output
end

function M.fetch(url, callback)
  local headers = {
    ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
  }

  hs.http.asyncGet(url, headers, function(status, body, responseHeaders)
    if status < 200 or status >= 300 then
      callback(nil, "HTTP " .. tostring(status) .. ": " .. tostring(body or ""))
      return
    end

    local finalURL = url
    if responseHeaders then
      finalURL = responseHeaders["Location"] or responseHeaders["location"] or finalURL
    end

    callback(M.parse(body or "", finalURL))
  end)
end

return M
