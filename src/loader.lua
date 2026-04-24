local util = require("src.util")
local Assets = require("src.game.assets")
local Menu = require("src.menu")
local UI = require("src.game.ui")

local Loader = {}
Loader.__index = Loader

local function isImage(path)
  return path:lower():match("%.png$") or path:lower():match("%.jpg$") or path:lower():match("%.jpeg$")
end

local function isAudio(path)
  return path:lower():match("%.wav$") or path:lower():match("%.mp3$") or path:lower():match("%.ogg$")
end

local function walkFiles(dir, out)
  out = out or {}
  if not love.filesystem.getInfo(dir) then return out end
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
    local p = (dir == "" or dir == ".") and name or (dir .. "/" .. name)
    local info = love.filesystem.getInfo(p)
    if info and info.type == "directory" then
      walkFiles(p, out)
    elseif info and info.type == "file" then
      out[#out + 1] = p
    end
  end
  return out
end

local LOADING_LINES = {
  "Sharpening the edge…",
  "Polishing the timing ring…",
  "Teaching goblins to stop running…",
  "Counting beats. Miscounts will be punished.",
  "Filling Heat. Venting patience.",
  "Calibrating parry windows to human reflexes…",
  "Warming up the arena lights…",
  "Loading perks you will definitely blame later…",
  "Indexing the Compendium (knowledge is damage)…",
  "Preparing the next mistake.",
}

function Loader.new(vw, vh, onDone)
  local self = setmetatable({}, Loader)
  self.vw, self.vh = vw, vh
  self.onDone = onDone
  self.t = 0
  self.done = false
  self.progress = 0
  self.loaded = 0
  self.total = 1
  self.status = "Starting…"
  self.witty = LOADING_LINES[1]
  self.wittyTimer = 0

  self.logo = nil
  if love.filesystem.getInfo("assets/LOGO.png") then
    self.logo = love.graphics.newImage("assets/LOGO.png", { mipmaps = true })
    self.logo:setFilter("linear", "linear")
    self.logo:setMipmapFilter("linear", 1)
    self.logo:setWrap("clamp", "clamp")
  end

  -- Build preload list (everything under assets/images, assets/sounds, assets/music).
  local files = {}
  walkFiles("assets/images", files)
  walkFiles("assets/sounds", files)
  walkFiles("assets/music", files)
  walkFiles("assets/fonts", files)

  -- Keep only loadable file types.
  local filtered = {}
  for _, p in ipairs(files) do
    if isImage(p) or isAudio(p) or p:lower():match("%.ttf$") or p:lower():match("%.otf$") then
      filtered[#filtered + 1] = p
    end
  end
  self.files = filtered
  self.total = math.max(1, #filtered + 3) -- + a few explicit caches
  self.total = self.total + 2 -- menu + compendium skin warm-up

  -- Cache tables (optional; primary goal is warm disk/decoder caches).
  self.cache = { images = {}, audio = {}, fonts = {} }

  -- Coroutine that yields after each asset.
  self.co = coroutine.create(function()
    -- Explicit caches used by the game.
    self.status = "Loading gameplay assets…"
    self.cache.icons = Assets.loadIcons()
    self.loaded = self.loaded + 1
    coroutine.yield()

    self.status = "Loading SFX…"
    self.cache.sfx = Assets.loadSfx()
    self.loaded = self.loaded + 1
    coroutine.yield()

    self.status = "Loading music…"
    self.cache.music = Assets.loadMusic(nil)
    self.loaded = self.loaded + 1
    coroutine.yield()

    self.status = "Caching menus…"
    if Menu and Menu.preloadAssets then
      Menu.preloadAssets()
    end
    self.loaded = self.loaded + 1
    coroutine.yield()

    self.status = "Indexing compendium…"
    if UI and UI.preloadCompendiumSkin then
      UI.preloadCompendiumSkin()
    else
      local tmpUi = UI and UI.new and UI.new({})
      if tmpUi and tmpUi._ensureCompendiumSkin then
        tmpUi:_ensureCompendiumSkin()
      end
    end
    self.loaded = self.loaded + 1
    coroutine.yield()

    for i, p in ipairs(self.files) do
      self.status = p
      if isImage(p) then
        local img = love.graphics.newImage(p, { mipmaps = true })
        img:setFilter("linear", "linear")
        img:setMipmapFilter("linear", 1)
        img:setWrap("clamp", "clamp")
        self.cache.images[p] = img
      elseif isAudio(p) then
        local isMusic = p:lower():find("^assets/music/") ~= nil
        local mode = isMusic and "stream" or "static"
        local src = love.audio.newSource(p, mode)
        self.cache.audio[p] = src
      elseif p:lower():match("%.ttf$") or p:lower():match("%.otf$") then
        -- Just touch the file so it's warm; font creation happens later at dynamic sizes.
        self.cache.fonts[p] = true
      end

      self.loaded = self.loaded + 1
      if i % 2 == 0 then coroutine.yield() end
    end
  end)

  return self
end

function Loader:update(dt)
  self.t = self.t + dt
  self.wittyTimer = self.wittyTimer - dt
  if self.wittyTimer <= 0 then
    self.wittyTimer = 0.55 + love.math.random() * 0.55
    local idx = util.clamp(1 + math.floor((self.loaded / math.max(1, self.total)) * (#LOADING_LINES - 1)), 1, #LOADING_LINES)
    -- Jitter a bit so it doesn't feel robotic.
    idx = util.clamp(idx + love.math.random(-1, 1), 1, #LOADING_LINES)
    self.witty = LOADING_LINES[idx]
  end

  if self.done then return end
  if self.co and coroutine.status(self.co) ~= "dead" then
    local ok, err = coroutine.resume(self.co)
    if not ok then
      self.status = "Load error: " .. tostring(err)
      self.done = true
      return
    end
  end

  self.progress = util.clamp(self.loaded / math.max(1, self.total), 0, 1)
  if self.co and coroutine.status(self.co) == "dead" then
    -- Do a full collection while the loading screen is still up,
    -- to avoid a GC pause on the first menu transitions.
    collectgarbage("collect")
    self.done = true
    if self.onDone then
      self.onDone(self.cache)
    end
  end
end

function Loader:draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  -- Background vignette-ish
  love.graphics.setColor(0.06, 0.07, 0.09, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  local cx, cy = w * 0.5, h * 0.42
  if self.logo then
    local iw, ih = self.logo:getWidth(), self.logo:getHeight()
    local maxW = w * 0.56
    local maxH = h * 0.30
    local s = math.min(maxW / math.max(1, iw), maxH / math.max(1, ih))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.logo, cx, cy, 0, s, s, iw * 0.5, ih * 0.5)
  else
    love.graphics.setColor(0.92, 0.93, 0.96, 0.95)
    local f = love.graphics.getFont()
    local title = "ONE-BUTTON PARRY"
    love.graphics.print(title, cx - f:getWidth(title) * 0.5, h * 0.20)
  end

  -- Loading bar
  local barW = math.min(520, w * 0.62)
  local barH = 18
  local bx = math.floor((w - barW) * 0.5 + 0.5)
  local by = math.floor(h * 0.70 + 0.5)
  love.graphics.setColor(0.10, 0.12, 0.18, 0.95)
  love.graphics.rectangle("fill", bx, by, barW, barH, 10, 10)
  love.graphics.setColor(0.55, 0.85, 1.00, 0.22)
  love.graphics.rectangle("line", bx, by, barW, barH, 10, 10)
  love.graphics.setColor(0.55, 0.85, 1.00, 0.85)
  love.graphics.rectangle("fill", bx, by, math.floor(barW * self.progress + 0.5), barH, 10, 10)

  -- Text
  local f = love.graphics.getFont()
  local pct = ("%d%%"):format(math.floor(self.progress * 100 + 0.5))
  love.graphics.setColor(0.86, 0.90, 0.96, 0.85)
  love.graphics.print(pct, bx + barW - f:getWidth(pct), by - 26)

  love.graphics.setColor(0.72, 0.76, 0.86, 0.90)
  local line = self.witty or "Loading…"
  love.graphics.print(line, math.floor((w - f:getWidth(line)) * 0.5 + 0.5), by + barH + 18)
end

return Loader

