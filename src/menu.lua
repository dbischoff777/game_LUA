local util = require("src.util")

local Menu = {}
Menu.__index = Menu

-- Shared cache for trimmed sprites so we never re-scan ImageData
-- (prevents one-time hitches when first visiting a menu).
Menu._trimmedSpriteCache = Menu._trimmedSpriteCache or {}

local function loadTrimmedSprite(path)
  if Menu._trimmedSpriteCache[path] ~= nil then
    return Menu._trimmedSpriteCache[path]
  end
  if not love.filesystem.getInfo(path) then return nil end
  local data = love.image.newImageData(path)
  local w, h = data:getWidth(), data:getHeight()
  local minx, miny, maxx, maxy = w, h, -1, -1
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _r, _g, _b, a = data:getPixel(x, y)
      if a > 0.02 then
        if x < minx then minx = x end
        if y < miny then miny = y end
        if x > maxx then maxx = x end
        if y > maxy then maxy = y end
      end
    end
  end

  local img = love.graphics.newImage(data, { mipmaps = true })
  img:setFilter("linear", "linear")
  img:setMipmapFilter("linear", 1)

  if maxx >= minx and maxy >= miny then
    local qw = (maxx - minx + 1)
    local qh = (maxy - miny + 1)
    local quad = love.graphics.newQuad(minx, miny, qw, qh, w, h)
    local spr = { img = img, quad = quad, w = qw, h = qh }
    Menu._trimmedSpriteCache[path] = spr
    return spr
  end
  local spr = { img = img, quad = nil, w = w, h = h }
  Menu._trimmedSpriteCache[path] = spr
  return spr
end

local function ensureModeSelectButtons()
  if Menu._modeBtn ~= nil then return end
  local base = "assets/images/menu/"
  local function load(name)
    local path = base .. name .. ".png"
    return loadTrimmedSprite(path)
  end

  Menu._modeBtn = {
    standard = load("standard"),
    endless = load("endless"),
    hardcore = load("hardcore"),
    seeded = load("seeded"),
    back = load("back"),
    diff_normal = load("diff_normal"),
    diff_hard = load("diff_hard"),
    diff_easy = load("diff_easy")
  }
end

local function ensureMainMenuButtons()
  if Menu._mainBtn ~= nil then return end
  local base = "assets/images/menu/main/"
  local function load(name)
    local path = base .. name .. ".png"
    return loadTrimmedSprite(path)
  end

  Menu._mainBtn = {
    play = load("play"),
    compendium = load("compendium"),
    options = load("options"),
    quit = load("quit"),
    back = load("back"),
    yes = load("yes"),
    no = load("no")
  }
end

local function ensureSettingsMenuButtons()
  if Menu._settingsBtn ~= nil then return end
  local base = "assets/images/menu/settings/"
  local function load(name)
    local path = base .. name .. ".png"
    return loadTrimmedSprite(path)
  end
  Menu._settingsBtn = {
    sound = load("sound"),
    visuals = load("visuals"),
    keybinds = load("keybinds"),
    back = load("back")
  }
end

local function ensureMenuBackground()
  if Menu._menuBg ~= nil then return end
  local path = "assets/images/menu/main/background.png"
  if not love.filesystem.getInfo(path) then
    Menu._menuBg = false
    return
  end
  local img = love.graphics.newImage(path, { mipmaps = true })
  img:setFilter("linear", "linear")
  img:setMipmapFilter("linear", 1)
  Menu._menuBg = img
end

local function ensureMenuLogo()
  if Menu._menuLogo ~= nil then return end
  local path = "assets/LOGO.png"
  if not love.filesystem.getInfo(path) then
    Menu._menuLogo = false
    return
  end
  local img = love.graphics.newImage(path, { mipmaps = true })
  img:setFilter("linear", "linear")
  img:setMipmapFilter("linear", 1)
  img:setWrap("clamp", "clamp")
  Menu._menuLogo = img
end

function Menu.preloadAssets()
  -- Pre-warm image decoding + expensive trimming so menu navigation is hitch-free.
  ensureModeSelectButtons()
  ensureMainMenuButtons()
  ensureSettingsMenuButtons()
  ensureMenuBackground()
  ensureMenuLogo()
end

local function drawLogoContain(img, cx, cy, maxW, maxH, a)
  if not img then return end
  local iw, ih = img:getWidth(), img:getHeight()
  if iw <= 0 or ih <= 0 then return end
  local s = math.min(maxW / iw, maxH / ih)
  love.graphics.setColor(1, 1, 1, a or 1)
  love.graphics.draw(img, cx, cy, 0, s, s, iw * 0.5, ih * 0.5)
end

local function drawBgCover(img, w, h, a)
  if not img then return end
  local iw, ih = img:getWidth(), img:getHeight()
  if iw <= 0 or ih <= 0 then return end
  local s = math.max(w / iw, h / ih)
  local dw = iw * s
  local dh = ih * s
  local x = math.floor((w - dw) * 0.5 + 0.5)
  local y = math.floor((h - dh) * 0.5 + 0.5)
  love.graphics.setColor(1, 1, 1, a or 1)
  love.graphics.draw(img, x, y, 0, s, s)
end

local function mainMenuImageForButton(b)
  ensureMainMenuButtons()
  if not (Menu._mainBtn and b and b.id) then return nil end
  if b.id == "yes" then return Menu._mainBtn.yes end
  if b.id == "no" then return Menu._mainBtn.no end
  return Menu._mainBtn[b.id]
end

local function settingsMenuImageForButton(b)
  ensureSettingsMenuButtons()
  if not (Menu._settingsBtn and b and b.id) then return nil end
  return Menu._settingsBtn[b.id]
end

local function drawImageFill(sprite, x, y, w, h, a, scaleMul)
  if not sprite then return false end
  local img = sprite.img or sprite
  local iw = sprite.w or img:getWidth()
  local ih = sprite.h or img:getHeight()
  local sx = (w / math.max(1, iw)) * (scaleMul or 1)
  local sy = (h / math.max(1, ih)) * (scaleMul or 1)
  local dx = math.floor(x + 0.5)
  local dy = math.floor(y + 0.5)
  love.graphics.setColor(1, 1, 1, a or 1)
  if sprite.quad then
    love.graphics.draw(img, sprite.quad, dx, dy, 0, sx, sy)
  else
    love.graphics.draw(img, dx, dy, 0, sx, sy)
  end
  return true
end

local function modeSelectQuadIndexForButton(b)
  if not b or b.kind == "slider" or b.kind == "toggle" then return nil end
  if b.id == "standard" then return "standard" end
  if b.id == "endless" then return "endless" end
  if b.id == "hardcore" then return "hardcore" end
  if b.id == "seeded" then return "seeded" end
  if b.id == "back" then return "back" end
  if b.id == "difficulty" and b.getValue then
    local v = tostring(b.getValue() or ""):upper()
    if v == "HARD" then return "diff_hard" end
    if v == "EASY" then return "diff_easy" end
    return "diff_normal"
  end
  return nil
end

local function modeSelectImageForButton(b)
  ensureModeSelectButtons()
  if not Menu._modeBtn then return nil end
  local key = modeSelectQuadIndexForButton(b)
  return key and Menu._modeBtn[key] or nil
end

local function btn(id, label, hint)
  return { id = id, label = label, hint = hint or "", kind = "action" }
end

local function toggle(id, label, getValue, setValue, hint)
  return { id = id, label = label, getValue = getValue, setValue = setValue, hint = hint or "", kind = "toggle" }
end

local function bind(id, label, getValue)
  return { id = id, label = label, getValue = getValue, hint = "", kind = "bind" }
end

local function slider(id, label, getValue, setValue, step)
  return { id = id, label = label, getValue = getValue, setValue = setValue, step = step or 0.05, hint = "", kind = "slider" }
end

local function truncateToWidth(font, text, maxW)
  if not text or text == "" then return "" end
  if maxW <= 0 then return "" end
  if font:getWidth(text) <= maxW then return text end
  local ell = "…"
  local ellW = font:getWidth(ell)
  local t = text
  while #t > 0 and (font:getWidth(t) + ellW) > maxW do
    t = t:sub(1, #t - 1)
  end
  if #t == 0 then return ell end
  return t .. ell
end

function Menu.new(kind)
  local m = setmetatable({}, Menu)
  m.kind = kind or "title" -- title | pause | dead
  m.selected = 1
  m.buttons = {}
  m.fade = 0
  m.pressedIdx = nil
  m.pressedTimer = 0
  return m
end

function Menu:setButtons(buttons)
  self.buttons = buttons or {}
  self.selected = util.clamp(self.selected, 1, math.max(1, #self.buttons))
  self.drag = nil -- { idx = number }
end

function Menu:update(dt)
  self.fade = util.clamp(self.fade + dt * 1.6, 0, 1)
  if (self.pressedTimer or 0) > 0 then
    self.pressedTimer = math.max(0, self.pressedTimer - dt)
    if self.pressedTimer <= 0 then
      self.pressedIdx = nil
    end
  end
end

function Menu:move(delta)
  if #self.buttons == 0 then return end
  self.selected = ((self.selected - 1 + delta) % #self.buttons) + 1
end

function Menu:activateSelected()
  local b = self.buttons[self.selected]
  if not b then return nil end
  if b.kind == "toggle" and b.setValue and b.getValue then
    b.setValue(not b.getValue())
    return nil
  end
  if b.kind == "slider" then
    return nil
  end
  return b.id
end

function Menu:toggleSelected(delta)
  local b = self.buttons[self.selected]
  if not b or not b.setValue or not b.getValue then return end
  local cur = b.getValue()
  if b.kind == "toggle" and type(cur) == "boolean" then
    if delta ~= 0 then b.setValue(not cur) end
  elseif b.kind == "slider" then
    local step = b.step or 0.05
    local n = tonumber(cur) or 0
    b.setValue(util.clamp(n + delta * step, 0, 1))
  end
end

function Menu:hitTest(x, y, w, h)
  for i = 1, #self.buttons do
    local rx, ry, rw, rh = self:itemRect(i, w, h)
    if x >= rx and x <= rx + rw and y >= ry and y <= ry + rh then
      return i
    end
  end
  return nil
end

function Menu:mouseMoved(x, y, w, h)
  local idx = self:hitTest(x, y, w, h)
  if idx then
    self.selected = idx
  end
end

function Menu:sliderBarRect(idx, w, h)
  local bx, yy, bw, bh = self:itemRect(idx, w, h)
  local barW = 150
  local barH = 10
  local barX = bx + bw - 18 - barW
  local barY = yy + bh - 16
  return barX, barY, barW, barH, bx, yy, bw, bh
end

function Menu:mousePressed(x, y, w, h)
  local idx = self:hitTest(x, y, w, h)
  if not idx then return nil end
  self.selected = idx
  local b = self.buttons[idx]
  if b and b.kind == "slider" and b.getValue and b.setValue then
    local barX, barY, barW, barH = self:sliderBarRect(idx, w, h)
    if x >= barX and x <= barX + barW and y >= barY - 6 and y <= barY + barH + 6 then
      self.drag = { idx = idx }
      local t = util.clamp((x - barX) / barW, 0, 1)
      b.setValue(t)
      return nil
    end
  end
  local act = self:activateSelected()
  if self.kind == "mode_select" and act then
    self.pressedIdx = idx
    self.pressedTimer = 0.10
  end
  return act
end

function Menu:mouseReleased()
  self.drag = nil
end

function Menu:mouseDragged(x, _y, w, h)
  if not self.drag then return end
  local idx = self.drag.idx
  local b = self.buttons[idx]
  if not b or b.kind ~= "slider" or not b.getValue or not b.setValue then return end
  local barX, _barY, barW = self:sliderBarRect(idx, w, h)
  local t = util.clamp((x - barX) / barW, 0, 1)
  b.setValue(t)
end

function Menu:wheelAdjust(x, y, dy, w, h)
  local idx = self:hitTest(x, y, w, h)
  if not idx then return end
  local b = self.buttons[idx]
  if not b or b.kind ~= "slider" then return end
  self.selected = idx
  if dy == 0 then return end
  self:toggleSelected(dy > 0 and 1 or -1)
end

function Menu:layout(w, h)
  local n = #self.buttons

  -- Image-button menus use the same tile size as mode_select so the supplied PNGs fit 1:1.
  local bw, bh, gap
  if self.kind == "title" or self.kind == "confirm_quit" then
    local cols = 3
    gap = 18
    local totalW = math.min(w * 0.86, 860)
    bw = math.floor((totalW - gap * (cols - 1)) / cols) -- same as mode_select tileW
    bh = 112
  else
    bw = 420
    bh = 54
    gap = 14
    -- When there are many items (Options), tighten spacing.
    if n >= 8 then
      bh = 48
      gap = 10
    end
    if n >= 10 then
      bh = 44
      gap = 8
    end
  end
  local bx = (w - bw) * 0.5
  local totalH = n > 0 and (n * bh + (n - 1) * gap) or 0
  local by = math.floor((h - totalH) * ((self.kind == "title") and 0.55 or 0.58))
  -- Title uses a large logo; push buttons down to avoid overlap.
  if self.kind == "title" then
    by = math.max(by, math.floor(h * 0.40))
  end
  if by < h * 0.30 then by = math.floor(h * 0.30) end
  return bx, by, bw, bh, gap
end

function Menu:itemRect(i, w, h)
  if self.kind == "howto" and #self.buttons == 1 then
    local f = love.graphics.getFont()
    local label = (self.buttons[1] and self.buttons[1].label) or "Back"
    local bw = math.floor(f:getWidth(label) + 18 * 2 + 0.5)
    local bh = 54
    local bx = math.floor((w - bw) * 0.5 + 0.5)
    local by = math.floor(h * 0.78)
    return bx, by, bw, bh
  end

  if self.kind == "mode_select" then
    local cols = 3
    local gap = 18
    local totalW = math.min(w * 0.86, 860)
    local tileW = math.floor((totalW - gap * (cols - 1)) / cols)
    local tileH = 112
    local rows = math.ceil(math.max(1, #self.buttons) / cols)
    local totalH = rows * tileH + (rows - 1) * gap
    local bx = math.floor((w - (tileW * cols + gap * (cols - 1))) * 0.5 + 0.5)
    local by = math.floor(h * 0.40)
    if by + totalH > h * 0.92 then
      by = math.floor(h * 0.92 - totalH)
    end
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = bx + col * (tileW + gap)
    local y = by + row * (tileH + gap)
    return x, y, tileW, tileH
  end

  if self.kind == "options" then
    -- Settings menu uses image buttons; keep the same tile size rules as the other image menus.
    local gap = 18
    local refTotalW = math.min(w * 0.86, 860)
    local refCols = 3
    local tileW = math.floor((refTotalW - gap * (refCols - 1)) / refCols)
    local tileH = 112

    local n = #self.buttons
    local cols = (n == 4) and 2 or math.min(3, math.max(1, n))
    local rows = math.ceil(math.max(1, n) / cols)
    local totalH = rows * tileH + (rows - 1) * gap
    local rowW = tileW * cols + gap * (cols - 1)
    local bx = math.floor((w - rowW) * 0.5 + 0.5)
    local by = math.floor(h * 0.44)
    if by + totalH > h * 0.92 then
      by = math.floor(h * 0.92 - totalH)
    end
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = bx + col * (tileW + gap)
    local y = by + row * (tileH + gap)
    return x, y, tileW, tileH
  end

  if self.kind == "confirm_quit" then
    -- Match the same tile size as image-based menus, but center the row.
    -- We intentionally keep the same tileW as the 3-col image grids so the supplied PNGs fit identically.
    local gap = 18
    local refTotalW = math.min(w * 0.86, 860)
    local refCols = 3
    local tileW = math.floor((refTotalW - gap * (refCols - 1)) / refCols)
    local tileH = 112
    local cols = math.min(3, math.max(1, #self.buttons))
    local rows = math.ceil(math.max(1, #self.buttons) / cols)
    local totalH = rows * tileH + (rows - 1) * gap
    local rowW = tileW * cols + gap * (cols - 1)
    local bx = math.floor((w - rowW) * 0.5 + 0.5)
    local by = math.floor(h * 0.48)
    if by + totalH > h * 0.92 then
      by = math.floor(h * 0.92 - totalH)
    end
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x = bx + col * (tileW + gap)
    local y = by + row * (tileH + gap)
    return x, y, tileW, tileH
  end

  local bx, by, bw, bh, gap = self:layout(w, h)
  local yy = by + (i - 1) * (bh + (gap or 14))
  return bx, yy, bw, bh
end

function Menu:draw(w, h, title, subtitle)
  local a = self.fade
  local slide = (1 - a) * 18
  ensureMenuBackground()
  if Menu._menuBg and Menu._menuBg ~= false then
    -- Draw below buttons; keep a light dim so UI stays readable.
    drawBgCover(Menu._menuBg, w, h, 0.95 * a)
    love.graphics.setColor(0, 0, 0, 0.28 * a)
    love.graphics.rectangle("fill", 0, 0, w, h)
  else
    love.graphics.setColor(0, 0, 0, 0.62 * a)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end

  if self.kind == "title" or title == "ONE-BUTTON PARRY" then
    ensureMenuLogo()
    if Menu._menuLogo and Menu._menuLogo ~= false then
      drawLogoContain(Menu._menuLogo, w * 0.5, h * 0.22 + slide, w * 0.62, h * 0.26, a)
    else
      love.graphics.setColor(0.92, 0.93, 0.96, a)
      local scale = 2.2
      local f = love.graphics.getFont()
      local tw = f:getWidth(title) * scale
      love.graphics.print(title, (w - tw) * 0.5, h * 0.18 + slide, 0, scale, scale)
    end
  else
    love.graphics.setColor(0.92, 0.93, 0.96, a)
    local scale = 2.2
    local f = love.graphics.getFont()
    local tw = f:getWidth(title) * scale
    love.graphics.print(title, (w - tw) * 0.5, h * 0.18 + slide, 0, scale, scale)
  end

  local f = love.graphics.getFont()
  if subtitle and subtitle ~= "" then
    love.graphics.setColor(0.72, 0.76, 0.86, a)
    local sw = f:getWidth(subtitle) * 1.0
    love.graphics.print(subtitle, (w - sw) * 0.5, h * 0.27 + slide)
  end

  -- Reserve right-side space so labels don’t overlap value widgets (slider/toggle/bind).
  for i, b in ipairs(self.buttons) do
    local bx, yy, bw, bh = self:itemRect(i, w, h)
    yy = yy + slide
    local sel = (i == self.selected)
    local textY = yy + math.floor((bh - 20) * 0.5)

    if sel then
      love.graphics.setColor(0.25, 0.28, 0.40, 0.95 * a)
      love.graphics.rectangle("fill", bx - 6, yy - 6, bw + 12, bh + 12, 14, 14)
      love.graphics.setColor(0.55, 0.80, 1.00, 0.75 * a)
      love.graphics.rectangle("line", bx - 6, yy - 6, bw + 12, bh + 12, 14, 14)
    end

    local drewSheet = false
    if self.kind == "mode_select" then
      local img = modeSelectImageForButton(b)
      if img then
        local pressed = (self.pressedIdx == i) and ((self.pressedTimer or 0) > 0)
        local pop = pressed and 0.98 or 1.0
        -- Some button PNGs have a transparent interior; paint a plate behind for readability.
        love.graphics.setColor(0.10, 0.12, 0.18, 0.88 * a)
        love.graphics.rectangle("fill", bx, yy, bw, bh, 14, 14)
        drawImageFill(img, bx, yy, bw, bh, a, pop)
        drewSheet = true
      end
    end
    if (not drewSheet) and (self.kind == "title" or self.kind == "confirm_quit") then
      local img = mainMenuImageForButton(b)
      if img then
        local pressed = (self.pressedIdx == i) and ((self.pressedTimer or 0) > 0)
        local pop = pressed and 0.98 or 1.0
        love.graphics.setColor(0.10, 0.12, 0.18, 0.88 * a)
        love.graphics.rectangle("fill", bx, yy, bw, bh, 14, 14)
        drawImageFill(img, bx, yy, bw, bh, a, pop)
        drewSheet = true
      end
    end
    if (not drewSheet) and self.kind == "options" then
      local img = settingsMenuImageForButton(b)
      if img then
        local pressed = (self.pressedIdx == i) and ((self.pressedTimer or 0) > 0)
        local pop = pressed and 0.98 or 1.0
        love.graphics.setColor(0.10, 0.12, 0.18, 0.88 * a)
        love.graphics.rectangle("fill", bx, yy, bw, bh, 14, 14)
        drawImageFill(img, bx, yy, bw, bh, a, pop)
        drewSheet = true
      end
    end
    if not drewSheet then
      love.graphics.setColor(0.14, 0.16, 0.22, 0.92 * a)
      love.graphics.rectangle("fill", bx, yy, bw, bh, 14, 14)
      love.graphics.setColor(0.18, 0.20, 0.28, 0.55 * a)
      love.graphics.rectangle("line", bx, yy, bw, bh, 14, 14)
    end

    -- Title and mode_select can use baked-in text in images.
    if not (((self.kind == "mode_select") or (self.kind == "title") or (self.kind == "confirm_quit") or (self.kind == "options")) and drewSheet) then
      love.graphics.setColor(0.92, 0.93, 0.96, a)
      local leftPad = 18
      local rightPad = 18
      local reservedRight = 0
      if b.kind == "slider" then
        reservedRight = 150 + 14 + 56 -- bar + padding + % text space
      elseif (b.kind == "toggle" or b.kind == "bind") then
        reservedRight = 84 -- ON/OFF or key name space
      end
      local maxLabelW = bw - leftPad - rightPad - reservedRight
      local label = truncateToWidth(f, b.label or "", maxLabelW)
      if self.kind == "howto" and #self.buttons == 1 then
        local lw = f:getWidth(label)
        love.graphics.print(label, bx + (bw - lw) * 0.5, textY)
      else
        love.graphics.print(label, bx + leftPad, textY)
      end
    end

    if (not (((self.kind == "mode_select") or (self.kind == "title")) and drewSheet)) and (b.kind == "toggle" or b.kind == "bind" or b.kind == "slider") and b.getValue then
      local v = b.getValue()
      local txt = ""
      local nv = nil
      if b.kind == "toggle" then
        txt = (v and "ON" or "OFF")
      elseif b.kind == "slider" then
        nv = util.clamp(tonumber(v) or 0, 0, 1)
        txt = ("%d%%"):format(math.floor(nv * 100 + 0.5))
      else
        txt = tostring(v or "")
      end
      love.graphics.setColor(0.72, 0.76, 0.86, 0.92 * a)
      love.graphics.print(txt, bx + bw - f:getWidth(txt) - 18, textY)

      if b.kind == "slider" and nv then
        local barW = 150
        local barH = 10
        local barX = bx + bw - 18 - barW
        local barY = yy + bh - 16
        love.graphics.setColor(0.10, 0.12, 0.18, 0.85 * a)
        love.graphics.rectangle("fill", barX, barY, barW, barH, 6, 6)
        love.graphics.setColor(0.55, 0.80, 1.00, 0.55 * a)
        love.graphics.rectangle("fill", barX, barY, math.floor(barW * nv + 0.5), barH, 6, 6)
        love.graphics.setColor(0.25, 0.30, 0.42, 0.65 * a)
        love.graphics.rectangle("line", barX, barY, barW, barH, 6, 6)
      end
    end

  end

end

Menu.btn = btn
Menu.toggle = toggle
Menu.bind = bind
Menu.slider = slider

return Menu
