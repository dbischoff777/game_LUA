local UI = {}
UI.__index = UI

UI._comboShader = nil

-- Shared compendium skin cache so the loader can pre-warm it once
-- and all UI instances reuse it (prevents first-open hitch).
UI._sharedCompendiumSkin = nil

function UI.new(game)
  local self = setmetatable({}, UI)
  self.game = game
  return self
end

function UI:_ensureCompendiumSkin()
  if UI._sharedCompendiumSkin ~= nil then
    self._compendiumSkin = UI._sharedCompendiumSkin
    return
  end
  if self._compendiumSkin ~= nil then return end
  local function loadTrimmedSprite(path)
    if not love.filesystem.getInfo(path) then return nil end
    local data = love.image.newImageData(path)
    local w, h = data:getWidth(), data:getHeight()

    -- Many of these are exported on a white/checkerboard background; color-key using pixel (0,0).
    local br, bg, bb, _ = data:getPixel(0, 0)
    local tol = 0.10
    data:mapPixel(function(_x, _y, r, g, b, a)
      local dr, dg, db = r - br, g - bg, b - bb
      local d = math.sqrt(dr * dr + dg * dg + db * db)
      if d <= tol then return 0, 0, 0, 0 end
      -- Avoid linear/mipmap fringe: zero RGB when effectively transparent.
      if a <= 0.01 then return 0, 0, 0, 0 end
      return r, g, b, a
    end)

    -- Trim transparent margins.
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
    img:setWrap("clamp", "clamp")

    if maxx >= minx and maxy >= miny then
      local qw = (maxx - minx + 1)
      local qh = (maxy - miny + 1)
      local quad = love.graphics.newQuad(minx, miny, qw, qh, w, h)
      return { img = img, quad = quad, w = qw, h = qh }
    end
    return { img = img, quad = nil, w = w, h = h }
  end

  -- Prefer the dedicated frame.png for 9-slice: cleaner transparency + bigger ornaments.
  local frameImg = nil
  local frame9 = nil
  local framePath = "assets/images/menu/compendium/frame.png"
  if love.filesystem.getInfo(framePath) then
    local fdata = love.image.newImageData(framePath)
    local fW, fH = fdata:getWidth(), fdata:getHeight()
    local fbr, fbg, fbb, _ = fdata:getPixel(0, 0)
    fdata:mapPixel(function(_x, _y, r, g, b, a)
      local dr, dg, db = r - fbr, g - fbg, b - fbb
      local d = math.sqrt(dr * dr + dg * dg + db * db)
      if d <= 0.10 then return 0, 0, 0, 0 end
      if a <= 0.01 then return 0, 0, 0, 0 end
      return r, g, b, a
    end)
    frameImg = love.graphics.newImage(fdata, { mipmaps = true })
    frameImg:setFilter("linear", "linear")
    frameImg:setMipmapFilter("linear", 1)
    frameImg:setWrap("clamp", "clamp")

    local srcBorder = 180
    local sMW = fW - 2 * srcBorder
    local sMH = fH - 2 * srcBorder
    local function fq(x, y, qw, qh)
      return love.graphics.newQuad(x, y, qw, qh, fW, fH)
    end
    frame9 = {
      TL = fq(0, 0, srcBorder, srcBorder),
      TR = fq(fW - srcBorder, 0, srcBorder, srcBorder),
      BL = fq(0, fH - srcBorder, srcBorder, srcBorder),
      BR = fq(fW - srcBorder, fH - srcBorder, srcBorder, srcBorder),
      T  = fq(srcBorder, 0, sMW, srcBorder),
      B  = fq(srcBorder, fH - srcBorder, sMW, srcBorder),
      L  = fq(0, srcBorder, srcBorder, sMH),
      R  = fq(fW - srcBorder, srcBorder, srcBorder, sMH),
      srcBorder = srcBorder,
      sMW = sMW,
      sMH = sMH,
      srcW = fW,
      srcH = fH
    }
  else
    -- If frame is missing, disable the compendium skin entirely (fallback UI will render).
    self._compendiumSkin = false
    return
  end

  local tabs = {
    player = { n = {}, a = {} },
    enemies = { n = {}, a = {} },
    howto = { n = {}, a = {} },
    back = { n = {}, a = {} }
  }
  tabs.player.n = loadTrimmedSprite("assets/images/menu/compendium/player.png")
  tabs.player.a = loadTrimmedSprite("assets/images/menu/compendium/playerActive.png")
  tabs.enemies.n = loadTrimmedSprite("assets/images/menu/compendium/enemies.png")
  tabs.enemies.a = loadTrimmedSprite("assets/images/menu/compendium/enemiesActive.png")
  tabs.howto.n = loadTrimmedSprite("assets/images/menu/compendium/howtoplay.png")
  tabs.howto.a = loadTrimmedSprite("assets/images/menu/compendium/howtoplayActive.png")
  tabs.back.n = loadTrimmedSprite("assets/images/menu/compendium/back.png")
  tabs.back.a = tabs.back.n

  self._compendiumSkin = {
    frameImg = frameImg,
    frame9 = frame9,
    tabs = tabs,
    strip = nil,
    scroll = nil
  }

  UI._sharedCompendiumSkin = self._compendiumSkin
end

function UI.preloadCompendiumSkin()
  if UI._sharedCompendiumSkin ~= nil then return end
  local tmp = UI.new({})
  tmp:_ensureCompendiumSkin()
end

function UI:_drawCompendium9Slice(dstX, dstY, dstW, dstH, targetBorder)
  local skin = self._compendiumSkin
  if not (skin and skin.frame9) then return end
  local img = skin.frameImg or skin.img
  local f = skin.frame9
  local tB = targetBorder
  local cornerS = tB / f.srcBorder

  local dL = dstX
  local dR = dstX + dstW - tB
  local dT = dstY
  local dB = dstY + dstH - tB
  local dMW = math.max(1, dstW - 2 * tB)
  local dMH = math.max(1, dstH - 2 * tB)
  local edgeSX = dMW / f.sMW
  local edgeSY = dMH / f.sMH

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, f.TL, dL, dT, 0, cornerS, cornerS)
  love.graphics.draw(img, f.TR, dR, dT, 0, cornerS, cornerS)
  love.graphics.draw(img, f.BL, dL, dB, 0, cornerS, cornerS)
  love.graphics.draw(img, f.BR, dR, dB, 0, cornerS, cornerS)
  love.graphics.draw(img, f.T, dL + tB, dT, 0, edgeSX, cornerS)
  love.graphics.draw(img, f.B, dL + tB, dB, 0, edgeSX, cornerS)
  love.graphics.draw(img, f.L, dL, dT + tB, 0, cornerS, edgeSY)
  love.graphics.draw(img, f.R, dR, dT + tB, 0, cornerS, edgeSY)
end

function UI:_compendiumTabLayout(ww, wh)
  self:_ensureCompendiumSkin()
  if not self._compendiumSkin or self._compendiumSkin == false then
    return nil
  end

  local maxW = math.min(ww * 0.78, 920)
  local boxX = math.floor((ww - maxW) * 0.5 + 0.5)
  local boxY = math.floor(wh * 0.30 + 0.5)
  local boxW = maxW
  local bottomY = math.floor(wh * 0.80 + 0.5)
  local boxH = math.max(260, bottomY - boxY)

  -- Frame 9-slice screen-side border thickness (large enough to preserve corner ornaments).
  local targetBorder = 54
  -- Tab target height (readable for baked-in text).
  local targetH = 56
  local gap = 8
  -- Keep tabs clear of the corner emblems on the frame's left/right borders.
  -- Extra-safe inset: the left corner ornament extends further than the nominal border.
  local innerPad = targetBorder + 64

  -- Tabs overlap the top border so the active glow reads properly.
  local tabY = math.floor(boxY + targetBorder - targetH * 0.50 + 0.5)

  local function tabW(id)
    local t = self._compendiumSkin.tabs[id]
    if not t then return 140, targetH end
    local src = t.n
    local sc = targetH / math.max(1, src.h)
    return math.floor(src.w * sc + 0.5), targetH
  end

  local wP, hP = tabW("player")
  local wE, hE = tabW("enemies")
  local wH, hH = tabW("howto")
  local wB, hB = tabW("back")

  local xPlayer = boxX + innerPad
  local xEnemies = xPlayer + wP + gap
  local xHow = xEnemies + wE + gap
  local xBack = boxX + boxW - innerPad - wB

  return {
    player = { x = xPlayer, y = tabY, w = wP, h = hP },
    enemies = { x = xEnemies, y = tabY, w = wE, h = hE },
    howto = { x = xHow, y = tabY, w = wH, h = hH },
    back = { x = xBack, y = tabY, w = wB, h = hB },
    meta = {
      tabY = tabY,
      tabH = targetH,
      boxX = boxX,
      boxY = boxY,
      boxW = boxW,
      boxH = boxH,
      targetBorder = targetBorder,
      innerPad = innerPad
    }
  }
end

local function drawCenteredText(w, text, y, scale)
  scale = scale or 1
  local f = love.graphics.getFont()
  local tw = f:getWidth(text) * scale
  love.graphics.print(text, (w - tw) * 0.5, y, 0, scale, scale)
end

function UI:updateFonts(scale)
  local g = self.game
  -- Recreate fonts at integer pixel sizes to keep text sharp.
  local s = scale or 1
  local base = 14
  local normalSize = math.max(12, math.floor(base * s + 0.5))
  local bigSize = math.max(16, math.floor(26 * s + 0.5))
  local titleSize = math.max(18, math.floor(34 * s + 0.5))

  local f = g.uiFonts
  if f and f.normalSize == normalSize and f.bigSize == bigSize and f.titleSize == titleSize then
    return
  end

  local function pickFontFile()
    -- Put Terminus here (TTF/OTF). If missing, we fall back to the default font.
    local candidates = {
      "assets/fonts/Terminus.ttf",
      "assets/fonts/TerminusTTF.ttf",
      "assets/fonts/Terminus (TTF).ttf"
    }
    for _, p in ipairs(candidates) do
      if love.filesystem.getInfo(p) then return p end
    end
    return nil
  end

  local fontFile = pickFontFile()
  local function makeFont(size)
    if fontFile then
      return love.graphics.newFont(fontFile, size)
    end
    return love.graphics.newFont(size)
  end

  g.uiFonts = {
    normalSize = normalSize,
    bigSize = bigSize,
    titleSize = titleSize,
    file = fontFile,
    normal = makeFont(normalSize),
    big = makeFont(bigSize),
    title = makeFont(titleSize)
  }
end

function UI:draw(scale, ox, oy, ww, wh)
  local g = self.game
  local util = require("src.util")

  local s = scale or 1
  self:updateFonts(s)

  -- Combo meter subtle haze/shimmer (similar spirit to Heat/Focus ring pass).
  if UI._comboShader == nil and love.graphics and love.graphics.newShader then
    UI._comboShader = love.graphics.newShader([[
      extern number u_time;
      extern number u_amount; // 0..1

      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
        // subtle "energy flow" distortion - keep small to avoid UI blur
        float a = clamp(u_amount, 0.0, 1.0);
        float wob = sin((uv.y * 26.0) + u_time * 4.0) * 0.0025 * a;
        float wob2 = sin((uv.x * 18.0) - u_time * 3.1) * 0.0018 * a;
        vec2 u2 = uv + vec2(wob, wob2);

        vec4 c = Texel(tex, u2) * color;

        // faint moving highlight band
        float band = 0.5 + 0.5 * sin(u_time * 2.8 + uv.x * 10.0);
        float boost = smoothstep(0.65, 0.98, band) * 0.10 * a;
        c.rgb += boost;
        return c;
      }
    ]])
  end

  local fonts = g.uiFonts
  local function vx(x) return ox + x * s end
  local function vy(y) return oy + y * s end

  if g.state ~= "menu" then
    local gaW, gaH = g.vw * s, g.vh * s
    local pad = math.floor(12 * s + 0.5)
    local barH = math.floor(44 * s + 0.5)
    local bx, by = ox + pad, oy + pad
    local bw = gaW - pad * 2

    -- HUD background plate (kept transparent now that the arena has its own background).
    -- Draw only a faint outline for separation on bright scenes.
    love.graphics.setColor(0.55, 0.85, 1.00, 0.12)
    love.graphics.rectangle("line", bx, by, bw, barH, 14, 14)

    local hp = g.player.hp or 0
    local mhp = g.player.maxHp or 0
    local heart = g.assets and g.assets.heart or nil
    local heartSize = math.max(12, math.floor(18 * s + 0.5))
    local pipR = math.max(4, math.floor(5 * s + 0.5))
    local pipGap = heart and math.max(heartSize + math.floor(6 * s + 0.5), math.floor(16 * s + 0.5))
      or math.max(6, math.floor(10 * s + 0.5))
    local px = bx + pad
    local py = by + math.floor(barH * 0.5)
    for i = 1, mhp do
      local filled = (i <= hp)
      local x = px + (i - 1) * pipGap
      if heart then
        local iw, ih = heart:getWidth(), heart:getHeight()
        local sc = heartSize / math.max(1, math.max(iw, ih))
        if filled then
          love.graphics.setColor(1.00, 0.35, 0.45, 0.95)
        else
          love.graphics.setColor(1.00, 0.35, 0.45, 0.22)
        end
        love.graphics.draw(heart, x, py, 0, sc, sc, iw * 0.5, ih * 0.5)
        if filled then
          love.graphics.setBlendMode("add")
          love.graphics.setColor(1.00, 1.00, 1.00, 0.10)
          love.graphics.draw(heart, x, py, 0, sc * 1.08, sc * 1.08, iw * 0.5, ih * 0.5)
          love.graphics.setBlendMode("alpha")
        end
      else
        if filled then
          love.graphics.setColor(0.35, 1.00, 0.70, 0.95)
          love.graphics.circle("fill", x, py, pipR)
        else
          love.graphics.setColor(0.35, 1.00, 0.70, 0.25)
          love.graphics.circle("line", x, py, pipR)
        end
      end
    end

    love.graphics.setFont(fonts.normal)

    local bossHp = nil
    for _, e in ipairs(g.enemies) do
      if e.kind == "boss" and (e.hp or 0) > 0 then
        bossHp = ("%d/%d"):format(e.hp, e.maxHp or e.hp)
        break
      end
    end
    local centerTxt = bossHp and ("WAVE %d  •  BOSS %s"):format(g.wave, bossHp) or ("WAVE %d"):format(g.wave)
    love.graphics.setFont(fonts.big)
    love.graphics.setColor(0.95, 0.85, 0.35, 0.95)
    love.graphics.print(centerTxt, bx + bw * 0.5 - fonts.big:getWidth(centerTxt) * 0.5, by + math.floor(10 * s))

    love.graphics.setFont(fonts.normal)
    love.graphics.setColor(0.86, 0.90, 0.96, 0.92)
    local rightX = bx + bw - pad
    local scoreTxt = ("SCORE %d"):format(g.player.score or 0)
    local streakTxt = ("STREAK %d"):format(g.player.streak or 0)
    local bestTxt = ("BEST %d"):format(g.player.bestStreak or 0)
    local yTop = by + math.floor(7 * s)
    local yBot = by + math.floor(24 * s)
    love.graphics.print(scoreTxt, rightX - fonts.normal:getWidth(scoreTxt), yTop)
    love.graphics.setColor(0.55, 0.85, 1.00, 0.92)
    local comboLine = ("%s  •  %s"):format(streakTxt, bestTxt)
    love.graphics.print(comboLine, rightX - fonts.normal:getWidth(comboLine), yBot)

    -- Combo multiplier meter (ties streak -> score gain).
    local mult, prog, _tiers, rank = 1.0, 0.0, 0, nil
    if g.getComboMult then
      mult, prog, _tiers, rank = g:getComboMult()
    end
    local multTxt = rank and ("%s  x%.2f"):format(rank, mult) or ("x%.2f"):format(mult)
    local mw = fonts.normal:getWidth(multTxt)
    local imgEmpty = g.assets and g.assets.combometerEmpty or nil
    local imgFull = g.assets and g.assets.combometerFull or nil
    local my = yBot + math.floor(12 * s + 0.5)
    if imgEmpty and imgFull then
      local iw, ih = imgEmpty:getWidth(), imgEmpty:getHeight()
      -- Make it large and readable.
      local meterH = math.floor(82 * s + 0.5)
      local sc = meterH / math.max(1, ih)
      local meterW = math.floor(iw * sc + 0.5)
      local mx = rightX - math.max(meterW, mw)
      local cx = mx + meterW * 0.5

      -- Inner track bounds (used for emptying + filling).
      local insetX = math.floor(iw * 0.10 + 0.5)
      local insetY = math.floor(ih * 0.36 + 0.5)
      local innerW = math.max(1, iw - insetX * 2)
      local innerH = math.max(1, ih - insetY * 2)
      local p = util.clamp(prog, 0, 1)
      local sx = mx + insetX * sc
      local sy = my + insetY * sc
      local sw = innerW * sc
      local sh = innerH * sc

      -- Base: truly empty bar.
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.draw(imgEmpty, mx, my, 0, sc, sc)

      -- Fill: overlay the "full" art, clipped to progress.
      local fillW = math.max(0, math.floor(sw * p + 0.5))
      if fillW > 0 then
        love.graphics.setScissor(sx, sy, fillW, sh)
        local pulse = 0.72 + 0.28 * (0.5 + 0.5 * math.sin((g.t or 0) * 9.5))
        -- Core full bar.
        local haze = util.clamp((p * p) * (0.55 + 0.45 * pulse), 0, 1)
        if UI._comboShader then
          UI._comboShader:send("u_time", g.t or 0)
          UI._comboShader:send("u_amount", haze)
          love.graphics.setShader(UI._comboShader)
        end
        love.graphics.setColor(1, 1, 1, 0.92 + 0.08 * pulse)
        love.graphics.draw(imgFull, mx, my, 0, sc, sc)
        love.graphics.setShader()

        -- Stronger glow + pulse, similar to Heat/Focus layering.
        love.graphics.setBlendMode("add")
        local glowA = (0.22 + 0.26 * pulse) * util.clamp(p, 0.15, 1.0)
        love.graphics.setColor(0.55, 0.90, 1.00, glowA)
        love.graphics.draw(imgFull, mx - 1, my - 1, 0, sc * 1.02, sc * 1.02)
        love.graphics.setColor(0.55, 0.90, 1.00, glowA * 0.65)
        love.graphics.draw(imgFull, mx - 2, my - 2, 0, sc * 1.05, sc * 1.05)
        love.graphics.setColor(0.55, 0.90, 1.00, glowA * 0.38)
        love.graphics.draw(imgFull, mx - 3, my - 3, 0, sc * 1.08, sc * 1.08)
        love.graphics.setBlendMode("alpha")
        love.graphics.setScissor()
      end

      -- Centered label under the bar, with a nicer plate + glow.
      -- Keep it tucked close to the meter.
      local ty = my + meterH + math.floor(1 * s + 0.5)
      love.graphics.setFont(fonts.normal)
      local tw = fonts.normal:getWidth(multTxt)
      local th = fonts.normal:getHeight()
      -- Ensure the label never exceeds the meter width.
      local textScale = math.min(1.0, (meterW - 10) / math.max(1, tw))
      local tx = math.floor(cx - (tw * textScale) * 0.5 + 0.5)

      -- Animated "style" pulse that scales with fill.
      local fillAmt = util.clamp(p, 0, 1)
      local pulse = 0.5 + 0.5 * math.sin((g.t or 0) * (6.0 + 8.0 * fillAmt))
      local pop = (0.015 + 0.065 * fillAmt) * pulse
      local labelScale = textScale * (1.0 + pop)
      local glowA = (0.14 + 0.26 * fillAmt) * (0.65 + 0.35 * pulse)

      love.graphics.setColor(0.05, 0.06, 0.10, 0.48)
      love.graphics.rectangle("fill", tx - 14, ty - 8, tw * labelScale + 28, th * labelScale + 14, 12, 12)
      love.graphics.setColor(0.55, 0.85, 1.00, 0.24)
      love.graphics.rectangle("line", tx - 14, ty - 8, tw * labelScale + 28, th * labelScale + 14, 12, 12)

      love.graphics.setColor(0.90, 0.92, 1.00, 0.90 + 0.08 * fillAmt)
      love.graphics.print(multTxt, tx, ty, 0, labelScale, labelScale)
      love.graphics.setBlendMode("add")
      love.graphics.setColor(0.55, 0.90, 1.00, glowA)
      love.graphics.print(multTxt, tx, ty, 0, labelScale, labelScale)
      love.graphics.setBlendMode("alpha")
      love.graphics.setFont(fonts.normal)
    else
      local meterW = math.floor(96 * s + 0.5)
      local meterH = math.floor(8 * s + 0.5)
      local mx = rightX - math.max(meterW, mw)
      love.graphics.setColor(0.08, 0.10, 0.16, 0.62)
      love.graphics.rectangle("fill", mx, my, meterW, meterH, 6, 6)
      local fillW = math.max(0, math.floor(meterW * util.clamp(prog, 0, 1) + 0.5))
      if fillW > 0 then
        love.graphics.setColor(0.45, 1.00, 0.80, 0.85)
        love.graphics.rectangle("fill", mx, my, fillW, meterH, 6, 6)
        love.graphics.setBlendMode("add")
        love.graphics.setColor(0.55, 0.85, 1.00, 0.22)
        love.graphics.rectangle("fill", mx, my, fillW, meterH, 6, 6)
        love.graphics.setBlendMode("alpha")
      end
      love.graphics.setColor(0.86, 0.90, 0.96, 0.80)
      love.graphics.print(multTxt, rightX - mw, my + meterH + math.floor(3 * s + 0.5))
    end

    -- Parry feedback (centered in game area, native pixels)
    love.graphics.setFont(fonts.big)
    local centerX = ox + gaW * 0.5
    local msgY = oy + gaH - 110 * s
    local perkActive = (g.player.lastPerkTimer or 0) > 0 and (g.player.lastPerkText or "") ~= ""
    if perkActive then
      local t = util.clamp((g.player.lastPerkTimer or 0) / 1.35, 0, 1)
      local a0 = util.clamp(1 - (t - 0.85) / 0.15, 0, 1) * util.clamp(t / 0.12, 0, 1)
      local a = 0.95 * a0
      local msg = g.player.lastPerkText
      love.graphics.setFont(fonts.normal)
      local tw = fonts.normal:getWidth(msg)
      local th = fonts.normal:getHeight()
      local padX = 14
      local padY = 8
      local x = math.floor(centerX - tw * 0.5 + 0.5)
      local y = math.floor((msgY - 34 * s) + (1 - a0) * 6 + 0.5)

      -- Soft plate + subtle glow to make it feel like an announcement.
      love.graphics.setColor(0.05, 0.06, 0.10, 0.55 * a)
      love.graphics.rectangle("fill", x - padX, y - padY, tw + padX * 2, th + padY * 2, 12, 12)
      love.graphics.setColor(0.55, 0.85, 1.00, 0.22 * a)
      love.graphics.rectangle("line", x - padX, y - padY, tw + padX * 2, th + padY * 2, 12, 12)

      love.graphics.setColor(0.95, 0.85, 0.35, a)
      love.graphics.print(msg, x, y)
      love.graphics.setBlendMode("add")
      love.graphics.setColor(0.55, 0.85, 1.00, 0.18 * a)
      love.graphics.print(msg, x, y)
      love.graphics.setBlendMode("alpha")
      love.graphics.setFont(fonts.big)
    end
    if g.player.lastParry.timer > 0 then
      local ok = g.player.lastParry.ok
      local msg = g.player.lastParry.label
      love.graphics.setColor(ok and 0.45 or 1.0, ok and 1.0 or 0.35, ok and 0.75 or 0.55)
      local tw = fonts.big:getWidth(msg)
      love.graphics.print(msg, centerX - tw * 0.5, msgY)
    else
      if not g.player.hasParriedOnce then
        love.graphics.setColor(0.9, 0.9, 0.95, 0.85)
        local msg = "Press SPACE / Mouse to parry"
        local tw = fonts.big:getWidth(msg)
        love.graphics.print(msg, centerX - tw * 0.5, oy + gaH - 90 * s)
      end
    end
  end

  -- Perk screen (drawn in native pixels but aligned to game area)
  if g.state == "perk" then
    local gaW, gaH = g.vw * s, g.vh * s
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", ox, oy, gaW, gaH)

    love.graphics.setFont(fonts.title)
    love.graphics.setColor(1, 1, 1)
    local title = ("WAVE %d COMPLETE"):format(g.wave - 1)
    love.graphics.print(title, ox + gaW * 0.5 - fonts.title:getWidth(title) * 0.5, vy(120))

    love.graphics.setFont(fonts.normal)
    local subtitle = "Choose a perk"
    love.graphics.print(subtitle, ox + gaW * 0.5 - fonts.normal:getWidth(subtitle) * 0.5, vy(165))
    local hpLine = ("Current HP: %d/%d"):format(g.player.hp, g.player.maxHp)
    love.graphics.setColor(0.82, 0.84, 0.92)
    love.graphics.print(hpLine, ox + gaW * 0.5 - fonts.normal:getWidth(hpLine) * 0.5, vy(188))

    local c = g.perk.choices or {}
    for i = 1, 3 do
      local y = 210 + (i - 1) * 92
      local bx, by = vx(160), vy(y)
      local bw, bh = (g.w - 320) * s, 72 * s
      love.graphics.setColor(0.14, 0.16, 0.22)
      love.graphics.rectangle("fill", bx, by, bw, bh, 14, 14)

      local p = c[i]
      local rarityId = p and p.rarity or "common"
      local col = (g.rarity[rarityId] and g.rarity[rarityId].color) or { 1, 1, 1 }
      love.graphics.setColor(col[1], col[2], col[3])
      local name = p and p.name or "—"
      local desc = p and p.desc or ""
      love.graphics.print(("%s"):format(name), bx + 30 * s, by + 14 * s)
      love.graphics.setColor(0.82, 0.84, 0.92)
      love.graphics.print(desc, bx + 30 * s, by + 38 * s)
    end
  end

  -- Title/menus are still drawn from Game:draw() after this pass.
end

function UI:drawHowTo(ww, wh)
  local g = self.game
  self:updateFonts(1)
  local f = love.graphics.getFont()
  love.graphics.setColor(0.86, 0.90, 0.96, 0.92)

  local parryKey = g:prettyKey((g.settings and g.settings.keyParry) or "space")
  local focusKey = g:prettyKey((g.settings and g.settings.keyFocus) or "lshift")

  local function drawBulletIcon(kind, x, y)
    local cx, cy = x + 10, y + 10
    if kind == "ring" then
      love.graphics.setColor(0.55, 0.90, 1.00, 0.95)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", cx, cy, 8)
      love.graphics.setLineWidth(1)
    elseif kind == "shot" then
      love.graphics.setColor(0.95, 0.35, 0.25, 0.95)
      love.graphics.circle("fill", cx - 2, cy, 4)
      love.graphics.setColor(1, 1, 1, 0.35)
      love.graphics.circle("line", cx - 2, cy, 7)
      love.graphics.setColor(0.95, 0.35, 0.25, 0.55)
      love.graphics.line(cx + 3, cy, cx + 12, cy)
    elseif kind == "heat" then
      love.graphics.setColor(1.00, 0.55, 0.25, 0.95)
      love.graphics.polygon("fill", cx - 3, cy + 7, cx + 1, cy + 1, cx - 2, cy - 7, cx + 6, cy - 1, cx + 3, cy + 7)
    elseif kind == "focus" then
      love.graphics.setColor(0.55, 0.80, 1.00, 0.95)
      love.graphics.setLineWidth(2)
      love.graphics.line(cx - 7, cy, cx + 7, cy)
      love.graphics.line(cx, cy - 7, cx, cy + 7)
      love.graphics.setLineWidth(1)
    end
  end

  -- Tutorial copy lives here; keep it in sync with mechanics (heat/focus/deflect).
  local raw = {
    { txt = "Goal: survive and build streak by parrying attacks." },
    { txt = "" },
    { icon = "ring", txt = ("Parry: press %s or Left Mouse when the player ring pulses."):format(parryKey) },
    { txt = "Perfect: hit closer to the exact impact for bonus score." },
    { txt = "" },
    { icon = "shot", txt = "Projectiles: some enemies shoot. Parry when a shot enters the red danger ring." },
    { txt = "If timed right, the shot reflects back and kills the shooter." },
    { txt = "" },
    { icon = "heat", txt = "HEAT (orange): parries and perfect parries fill Heat. When full, enemies get buffed while Heat drains back to 0—then the cycle repeats." },
    { icon = "focus", txt = ("FOCUS (blue): hold %s to widen your parry window for clutch saves."):format(focusKey) },
    { txt = "" },
    { txt = "Tip: Keybinds lets you rebind controls." }
  }

  local function wrapText(text, maxW)
    if text == "" then return { "" } end
    local words = {}
    for w2 in tostring(text):gmatch("%S+") do
      words[#words + 1] = w2
    end
    local out = {}
    local line = ""
    for i2 = 1, #words do
      local w2 = words[i2]
      local cand = (line == "") and w2 or (line .. " " .. w2)
      if f:getWidth(cand) <= maxW then
        line = cand
      else
        out[#out + 1] = line
        line = w2
      end
    end
    out[#out + 1] = line
    return out
  end

  local maxW = math.min(ww * 0.78, 860)
  local startX = (ww - maxW) * 0.5
  local textX = startX + 26

  local render = {}
  for _, row in ipairs(raw) do
    local parts = wrapText(row.txt or "", maxW - 26)
    for j = 1, #parts do
      render[#render + 1] = {
        icon = (j == 1) and row.icon or nil,
        txt = parts[j]
      }
    end
  end

  local baseLineH = math.max(18, math.floor((f:getHeight() or 16) * 1.25))
  local lineH = baseLineH

  local topY = wh * 0.32
  local bottomY = wh * 0.80
  if g.menu and g.menu.itemRect then
    local _bx, btnY = g.menu:itemRect(1, ww, wh)
    bottomY = math.min(bottomY, btnY - 20)
  end
  local availH = math.max(120, bottomY - topY)

  local blockH = #render * lineH
  if blockH > availH then
    lineH = math.max(14, math.floor(availH / math.max(1, #render)))
    blockH = #render * lineH
  end

  local y = topY + (availH - blockH) * 0.5
  for _, row in ipairs(render) do
    local line = row.txt or ""
    if row.icon then
      drawBulletIcon(row.icon, textX - 28, y - 1)
    end
    love.graphics.setColor(0.86, 0.90, 0.96, 0.92)
    love.graphics.print(line, textX, y)
    y = y + lineH
  end
end

function UI:drawCompendium(ww, wh)
  local g = self.game
  local util = require("src.util")
  self:updateFonts(1)
  local fonts = g.uiFonts
  local f = fonts.normal or love.graphics.getFont()

  local tab = g.compendiumTab or "player"
  g.compendiumScroll = g.compendiumScroll or 0
  local maxW = math.min(ww * 0.78, 920)
  local x0 = math.floor((ww - maxW) * 0.5 + 0.5)
  local topY = math.floor(wh * 0.30 + 0.5)
  local bottomY = math.floor(wh * 0.80 + 0.5)

  self:_ensureCompendiumSkin()
  local skin = self._compendiumSkin
  local layout = self:_compendiumTabLayout(ww, wh)

  local pad = 16
  local boxX = x0
  local boxY = topY
  local boxW = maxW
  local boxH = (layout and layout.meta and layout.meta.boxH) or math.max(160, bottomY - topY)
  local tB = (layout and layout.meta and layout.meta.targetBorder) or 54

  -- Default content area (used when skin present; adjusted in fallback branch).
  -- No visible scrollbar; keep content aligned to the frame.
  local scrollbarReserve = 0
  local sidePad = 12
  local contentX = boxX + tB + sidePad
  local contentY = boxY + tB + (layout and layout.meta and layout.meta.tabH or 56) * 0.6
  local contentW = boxW - tB * 2 - sidePad * 2 - scrollbarReserve
  local contentH = (boxY + boxH - tB) - contentY

  if skin and skin ~= false and layout then
    -- Dark interior plate so text reads well over the arena behind the menu.
    love.graphics.setColor(0.06, 0.08, 0.14, 0.85)
    love.graphics.rectangle("fill", boxX + tB * 0.55, boxY + tB * 0.55, boxW - tB * 1.10, boxH - tB * 1.10, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    -- 9-slice frame (corners stay intact, edges stretch).
    self:_drawCompendium9Slice(boxX, boxY, boxW, boxH, tB)
  else
    -- Fallback panel
    love.graphics.setColor(0.08, 0.10, 0.16, 0.72)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 16, 16)
    love.graphics.setColor(0.55, 0.85, 1.00, 0.18)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 16, 16)
  end

  if skin and skin ~= false and layout then
    -- Tabs (preserve each tab's native aspect; draw active slightly raised).
    local function drawTab(id, isActive)
      local t = skin.tabs[id]
      local r = layout[id]
      if not (t and r) then return end
      local src = isActive and t.a or t.n
      local sc = r.h / math.max(1, src.h)
      local drawW = src.w * sc
      local drawX = math.floor(r.x + (r.w - drawW) * 0.5 + 0.5)
      local drawY = math.floor(r.y + (isActive and -4 or 0) + 0.5)
      love.graphics.setColor(1, 1, 1, 1)
      local img = src.img
      if img then
        if src.quad then
          love.graphics.draw(img, src.quad, drawX, drawY, 0, sc, sc)
        else
          love.graphics.draw(img, drawX, drawY, 0, sc, sc)
        end
      end
    end
    drawTab("player", tab == "player")
    drawTab("enemies", tab == "enemies")
    drawTab("howto", tab == "howto")
    drawTab("back", false)

    -- Content sits below the tab row, inside the frame's inner area.
    contentY = math.max(contentY, layout.player.y + layout.player.h + 10)
    contentX = boxX + tB + sidePad
    contentW = boxW - tB * 2 - sidePad * 2 - scrollbarReserve
    contentH = (boxY + boxH - tB) - contentY
  else
    local tabY = math.floor(boxY + 10 + 0.5)
    local tabW = 140
    local tabH = 34
    local function drawTab(tx, label, active)
      tx = math.floor(tx + 0.5)
      love.graphics.setColor(active and 0.25 or 0.12, active and 0.28 or 0.14, active and 0.40 or 0.20, active and 0.92 or 0.75)
      love.graphics.rectangle("fill", tx, tabY, tabW, tabH, 12, 12)
      love.graphics.setColor(0.55, 0.85, 1.00, active and 0.45 or 0.20)
      love.graphics.rectangle("line", tx, tabY, tabW, tabH, 12, 12)
      love.graphics.setColor(0.92, 0.93, 0.96, active and 0.95 or 0.65)
      love.graphics.setFont(fonts.normal)
      local tw = (fonts.normal and fonts.normal:getWidth(label)) or f:getWidth(label)
      local th = (fonts.normal and fonts.normal:getHeight()) or f:getHeight()
      local px = math.floor(tx + (tabW - tw) * 0.5 + 0.5)
      local py = math.floor(tabY + (tabH - th) * 0.5 + 0.5)
      love.graphics.print(label, px, py)
    end
    local txPlayer = boxX + pad
    local txEnemies = txPlayer + tabW + 10
    local txHowTo = txEnemies + tabW + 10
    local txBack = boxX + boxW - pad - tabW
    drawTab(txPlayer, "Player", tab == "player")
    drawTab(txEnemies, "Enemies", tab == "enemies")
    drawTab(txHowTo, "How to play", tab == "howto")
    drawTab(txBack, "Back", false)

    contentX = boxX + pad
    contentY = tabY + tabH + 18
    contentW = boxW - pad * 2
    contentH = (boxY + boxH - 10) - contentY
  end

  local function drawIcon(img, x, y, size, a)
    if not img then return end
    local iw, ih = img:getWidth(), img:getHeight()
    local sc = (size or 36) / math.max(1, math.max(iw, ih))
    love.graphics.setColor(1, 1, 1, a or 1)
    love.graphics.draw(img, x, y, 0, sc, sc, iw * 0.5, ih * 0.5)
  end

  local function wrap(text, maxWidth)
    local words, out = {}, {}
    for w2 in tostring(text or ""):gmatch("%S+") do words[#words + 1] = w2 end
    local line = ""
    for i = 1, #words do
      local w2 = words[i]
      local cand = (line == "") and w2 or (line .. " " .. w2)
      if ((fonts.normal and fonts.normal:getWidth(cand)) or f:getWidth(cand)) <= maxWidth then
        line = cand
      else
        out[#out + 1] = line
        line = w2
      end
    end
    out[#out + 1] = line
    return out
  end

  local function tierFromCount(n)
    n = tonumber(n) or 0
    if n >= 25 then return 3 end
    if n >= 10 then return 2 end
    if n >= 3 then return 1 end
    return 0
  end

  local function nextUnlockForTier(tier)
    if tier <= 0 then return 3 end
    if tier == 1 then return 10 end
    if tier == 2 then return 25 end
    return nil
  end

  love.graphics.setFont(fonts.normal)
  love.graphics.setColor(0.86, 0.90, 0.96, 0.92)

  if tab == "howto" then
    local parryKey = g:prettyKey((g.settings and g.settings.keyParry) or "space")
    local focusKey = g:prettyKey((g.settings and g.settings.keyFocus) or "lshift")

    local function drawBulletIcon(kind, x, y)
      local cx, cy = x + 10, y + 10
      if kind == "ring" then
        love.graphics.setColor(0.55, 0.90, 1.00, 0.95)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", cx, cy, 8)
        love.graphics.setLineWidth(1)
      elseif kind == "shot" then
        love.graphics.setColor(0.95, 0.35, 0.25, 0.95)
        love.graphics.circle("fill", cx - 2, cy, 4)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.circle("line", cx - 2, cy, 7)
        love.graphics.setColor(0.95, 0.35, 0.25, 0.55)
        love.graphics.line(cx + 3, cy, cx + 12, cy)
      elseif kind == "heat" then
        love.graphics.setColor(1.00, 0.55, 0.25, 0.95)
        love.graphics.polygon("fill", cx - 3, cy + 7, cx + 1, cy + 1, cx - 2, cy - 7, cx + 6, cy - 1, cx + 3, cy + 7)
      elseif kind == "focus" then
        love.graphics.setColor(0.55, 0.80, 1.00, 0.95)
        love.graphics.setLineWidth(2)
        love.graphics.line(cx - 7, cy, cx + 7, cy)
        love.graphics.line(cx, cy - 7, cx, cy + 7)
        love.graphics.setLineWidth(1)
      end
    end

    local raw = {
      { txt = "Goal: survive and build streak by parrying attacks." },
      { txt = "" },
      { icon = "ring", txt = ("Parry: press %s or Left Mouse when the player ring pulses."):format(parryKey) },
      { txt = "Perfect: hit closer to the exact impact for bonus score." },
      { txt = "" },
      { icon = "shot", txt = "Projectiles: some enemies shoot. Parry when a shot enters the red danger ring." },
      { txt = "If timed right, the shot reflects back and kills the shooter." },
      { txt = "" },
      { icon = "heat", txt = "HEAT (orange): parries and perfect parries fill Heat. When full, enemies get buffed while Heat drains back to 0—then the cycle repeats." },
      { icon = "focus", txt = ("FOCUS (blue): hold %s to widen your parry window for clutch saves."):format(focusKey) }
    }

    local render = {}
    for _, row in ipairs(raw) do
      local parts = wrap(row.txt or "", contentW - 26)
      for j = 1, #parts do
        render[#render + 1] = { icon = (j == 1) and row.icon or nil, txt = parts[j] }
      end
    end

    local lineH = math.max(18, math.floor(((fonts.normal and fonts.normal:getHeight()) or f:getHeight()) * 1.25 + 0.5))
    local maxScroll = math.max(0, (#render * lineH) - contentH)
    g.compendiumScroll = util.clamp(g.compendiumScroll or 0, 0, maxScroll)
    local y = contentY - (g.compendiumScroll or 0)
    -- Clip tightly to the content column (contentX .. contentX+contentW).
    love.graphics.setScissor(contentX - 2, contentY, math.max(1, contentW + 4), math.max(1, contentH))
    for _, row in ipairs(render) do
      if row.icon then
        drawBulletIcon(row.icon, contentX, y - 2)
      end
      love.graphics.setColor(0.86, 0.90, 0.96, 0.92)
      love.graphics.print(row.txt or "", contentX + 26, y)
      y = y + lineH
    end
    love.graphics.setScissor()
  elseif tab == "player" then
    g.compendiumScroll = 0
    local level, into, need
    if g.recalcLevelFromXp then
      level, into, need = g:recalcLevelFromXp()
    else
      level, into, need = 1, 0, 25
    end
    local head = ("Level %d  •  XP %d/%d"):format(level, into, need)
    love.graphics.setFont(fonts.big)
    love.graphics.setColor(0.95, 0.85, 0.35, 0.95)
    love.graphics.print(head, contentX, contentY)

    love.graphics.setFont(fonts.normal)
    love.graphics.setColor(0.86, 0.90, 0.96, 0.92)
    local lore = {
      { req = 1, txt = "You are the last sentinel at the edge of the abyss." },
      { req = 5, txt = "The seal is cracked. Every parry is a prayer etched into steel." },
      { req = 20, txt = "Your name was erased from the annals—only the rhythm of battle remembers it." },
      { req = 60, txt = "Beyond the gate waits the Choir of Ash. You were built to endure it." }
    }
    local locked = "??? (Unlock more lore by gaining levels.)"
    local y = contentY + 52
    for _, entry in ipairs(lore) do
      local unlocked = (tonumber(level) or 1) >= (entry.req or 1)
      local text = unlocked and entry.txt or locked
      love.graphics.setColor(0.86, 0.90, 0.96, unlocked and 0.92 or 0.45)
      local parts = wrap(text, contentW)
      for _, p in ipairs(parts) do
        love.graphics.print(p, contentX, y)
        y = y + 22
      end
      y = y + 6
    end
    love.graphics.setColor(0.55, 0.85, 1.00, 0.35)
    love.graphics.print("Lore unlocks at Lv 5, 20, 60", contentX, boxY + boxH - 34)
  else
    local entries = {
      {
        id = "basic",
        name = "Striker",
        icon = (g.assets and g.assets.basic),
        info = {
          "Approaches, then creates one timing window.",
          "Parry the bullseye ring to defeat.",
          "Lore: The smallest of the abyssal host—still enough to end a run."
        }
      },
      {
        id = "double",
        name = "Double",
        icon = (g.assets and g.assets.double),
        info = {
          "Two beats in one attack.",
          "Stay ready for the second pulse—missing any beat will hit.",
          "Lore: They learn your rhythm, then strike between breaths."
        }
      },
      {
        id = "feint",
        name = "Feint",
        icon = (g.assets and g.assets.feint),
        info = {
          "Fakes an attack, then quickly re-telegraphs.",
          "Wait for the real bullseye rings before committing.",
          "Lore: The abyss loves laughter. It sounds like a missed parry."
        }
      },
      {
        id = "heavy",
        name = "Heavy",
        icon = (g.assets and g.assets.heavy),
        info = {
          "Slower windup but tighter timing.",
          "Use Focus to stabilize, especially during overheat.",
          "Lore: Their swings are sermons—each one demands an answer."
        }
      },
      {
        id = "chain",
        name = "Chain",
        icon = (g.assets and g.assets.chain),
        info = {
          "A sequence of 2–4 beats.",
          "Parry each beat in order to defeat it.",
          "Lore: They count your mistakes. They count very well."
        }
      },
      {
        id = "ranged",
        name = "Ranged",
        icon = (g.assets and g.assets.ranged),
        info = {
          "Fires projectiles from afar.",
          "Parry when a shot enters the red danger ring to reflect it.",
          "Lore: Cowards, they call it. You call it target practice."
        }
      },
      {
        id = "shield",
        name = "Shieldbearer",
        icon = (g.assets and g.assets.shieldbearer),
        info = {
          "Guarded. Needs two parries.",
          "First parry breaks the shield and forces a second attack.",
          "Lore: The shield is not for defense—it’s a promise to return."
        }
      },
      {
        id = "goblin",
        name = "Treasure Goblin",
        icon = (g.assets and g.assets.goblin) or (g.assets and g.assets.enemy),
        info = {
          "Teleports after every successful parry.",
          "Needs several parries—defeat it before it escapes to claim a huge score bonus.",
          "Lore: It doesn't fight for victory. It fights for time."
        }
      },
      {
        id = "boss",
        name = "Boss",
        icon = (g.assets and g.assets.boss),
        info = {
          "Multi-HP. One window at a time.",
          "Stay consistent—panic is the real damage.",
          "Lore: Some doors open only to those who keep time."
        }
      }
    }

    local y = contentY
    local iconSize = 42
    local kills = (g.settings and g.settings.kills) or {}
    local lineH = math.max(18, math.floor(((fonts.normal and fonts.normal:getHeight()) or f:getHeight()) * 1.15 + 0.5))
    local rows = {}
    local totalH = 0
    for _, it in ipairs(entries) do
      local k = kills[it.id] or 0
      local tier = tierFromCount(k)
      local nextAt = nextUnlockForTier(tier)
      local shown
      if tier == 0 then
        shown = { "??? Defeat this enemy to unlock its entry." }
      elseif tier == 1 then
        shown = { it.info[1] }
      elseif tier == 2 then
        shown = { it.info[1], it.info[2] }
      else
        shown = { it.info[1], it.info[2], it.info[3] }
      end

      -- Pre-wrap text to compute a row height that prevents overlap.
      local lines = {}
      for si = 1, #shown do
        local parts = wrap(shown[si], contentW - 60)
        for li = 1, #parts do
          lines[#lines + 1] = parts[li]
          if #lines >= 3 then break end -- keep list readable and compact
        end
        if #lines >= 3 then break end
      end

      local rowPad = 10
      local rowH = math.max(iconSize + 16, 8 + lineH + lineH + (#lines * lineH) + rowPad)
      rows[#rows + 1] = { it = it, k = k, tier = tier, nextAt = nextAt, lines = lines, h = rowH }
      totalH = totalH + rowH
    end

    local maxScroll = math.max(0, totalH - contentH)
    g.compendiumScroll = util.clamp(g.compendiumScroll or 0, 0, maxScroll)

    y = contentY - (g.compendiumScroll or 0)
    -- Clip tightly to the content column (contentX .. contentX+contentW).
    love.graphics.setScissor(contentX - 2, contentY, math.max(1, contentW + 4), math.max(1, contentH))
    for _, row in ipairs(rows) do
      local it = row.it
      local k = row.k
      local tier = row.tier
      local nextAt = row.nextAt
      local lines = row.lines
      local rowH = row.h

      if y + rowH < contentY - 40 then
        y = y + rowH
      elseif y > contentY + contentH + 40 then
        break
      else
        drawIcon(it.icon, contentX + 22, y + rowH * 0.5, iconSize, (tier == 0) and 0.30 or 1.0)

        love.graphics.setFont(fonts.normal)
        love.graphics.setColor(0.92, 0.93, 0.96, (tier == 0) and 0.55 or 0.95)
        love.graphics.print(it.name, contentX + 54, y + 4)

        love.graphics.setColor(0.55, 0.85, 1.00, 0.42)
        local prog = nextAt and ("Defeated: %d  •  Next unlock at %d"):format(k, nextAt) or ("Defeated: %d  •  Fully unlocked"):format(k)
        love.graphics.print(prog, contentX + 54, y + 4 + lineH)

        love.graphics.setColor(0.86, 0.90, 0.96, (tier == 0) and 0.45 or 0.82)
        local dy = y + 4 + lineH + lineH
        for iLine = 1, #lines do
          love.graphics.print(lines[iLine], contentX + 54, dy)
          dy = dy + lineH
        end
        y = y + rowH
      end
    end
    love.graphics.setScissor()

    -- Intentionally no visible scrollbar; wheel scrolling only.
  end
end

function UI:compendiumHitTest(x, y, ww, wh)
  local g = self.game
  local layout = self:_compendiumTabLayout(ww, wh)
  if layout then
    local function hitRect(r)
      return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
    end
    if hitRect(layout.player) then return "comp_tab_player" end
    if hitRect(layout.enemies) then return "comp_tab_enemies" end
    if hitRect(layout.howto) then return "comp_tab_howto" end
    if hitRect(layout.back) then return "back" end
    return nil
  end

  -- Fallback hit test (no skin).
  local tabW, tabH = 140, 34
  local maxW = math.min(ww * 0.78, 920)
  local boxX = math.floor((ww - maxW) * 0.5 + 0.5)
  local boxY = math.floor(wh * 0.30 + 0.5)
  local boxW = maxW
  local pad = 16
  local tabY = math.floor(boxY + 10 + 0.5)

  local function hit(tx)
    return x >= tx and x <= tx + tabW and y >= tabY and y <= tabY + tabH
  end

  local txPlayer = math.floor(boxX + pad + 0.5)
  local txEnemies = math.floor(txPlayer + tabW + 10 + 0.5)
  local txHowTo = math.floor(txEnemies + tabW + 10 + 0.5)
  local txBack = math.floor(boxX + boxW - pad - tabW + 0.5)
  if hit(txPlayer) then return "comp_tab_player" end
  if hit(txEnemies) then return "comp_tab_enemies" end
  if hit(txHowTo) then return "comp_tab_howto" end
  if hit(txBack) then return "back" end
  return nil
end

UI.drawCenteredText = drawCenteredText

return UI

