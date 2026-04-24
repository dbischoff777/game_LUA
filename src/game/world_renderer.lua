local util = require("src.util")
local enemy = require("src.enemy")

local WorldRenderer = {}
WorldRenderer.__index = WorldRenderer

function WorldRenderer.new(game)
  local self = setmetatable({}, WorldRenderer)
  self.game = game
  self:_ensureRingFx()
  return self
end

function WorldRenderer:_ensureRingFx()
  if self.ringCanvas and self.ringShader then return end

  local size = 192
  self.ringSize = size
  self.ringCanvas = love.graphics.newCanvas(size, size)

  self.ringShader = love.graphics.newShader([[
    extern number u_time;
    extern number u_amount; // 0..1

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      // Subtle heat-haze distortion using a few sin layers.
      float a = clamp(u_amount, 0.0, 1.0);
      vec2 uv = tc;

      float w1 = sin((uv.y * 18.0 + u_time * 4.2) * 6.2831);
      float w2 = sin((uv.x * 12.0 - u_time * 2.6) * 6.2831);
      float w3 = sin(((uv.x + uv.y) * 10.0 + u_time * 3.1) * 6.2831);

      vec2 off = vec2(w1 * 0.0035 + w3 * 0.0020, w2 * 0.0030 - w3 * 0.0015) * a;
      vec4 px = Texel(tex, uv + off);
      return px * color;
    }
  ]])
end

function WorldRenderer:draw()
  local g = self.game

  local sx, sy = 0, 0
  if g.shake > 0 then
    local a = g.shake / 0.25
    local mult = g.shakeMult or 1.0
    sx = (love.math.random() - 0.5) * 14 * a * mult
    sy = (love.math.random() - 0.5) * 14 * a * mult
  end

  love.graphics.push()
  love.graphics.translate(sx, sy)

  -- Arena background image (drawn below the rest of the scene).
  if g.assets and g.assets.arena then
    local img = g.assets.arena
    local iw, ih = img:getWidth(), img:getHeight()
    if iw > 0 and ih > 0 then
      local s = math.max(g.w / iw, g.h / ih)
      local dw, dh = iw * s, ih * s
      local x = math.floor((g.w - dw) * 0.5 + 0.5)
      local y = math.floor((g.h - dh) * 0.5 + 0.5)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, x, y, 0, s, s)
    end
  end

  -- The arena background image replaces the old grey backing plates.

  if g.assets and g.assets.hero then
    local img = g.assets.hero
    local iw, ih = img:getWidth(), img:getHeight()
    local size = 44
    local s = size / math.max(1, math.max(iw, ih))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, g.centerX, g.centerY, 0, s, s, iw * 0.5, ih * 0.5)
  else
    love.graphics.setColor(0.88, 0.90, 0.96)
    love.graphics.circle("fill", g.centerX, g.centerY, 16)
  end

  -- "pulse" is a unified readiness cue: it turns on when either
  -- (a) a projectile is in deflect range or (b) an impact is within the parry window.
  if g.state == "playing" then
    local pulse = 0
    local deflectR = g:getDeflectRadius()
    for _, p in ipairs(g.projectiles or {}) do
      if p and (not p.deflected) then
        local dx, dy = p.x - g.centerX, p.y - g.centerY
        if (dx * dx + dy * dy) <= deflectR * deflectR then
          pulse = 1
          break
        end
      end
    end
    if pulse == 0 then
      local e, imp = enemy.findNearestImpact(g, g.enemies)
      if e and imp then
        local dt = g.t - imp.t
        local win = g:currentParryWindowForEnemy(e)
        if math.abs(dt) <= win then
          pulse = 1
        end
      end
    end

    -- Dual-meter ring: Heat (top) + Focus (bottom)
    self:_ensureRingFx()
    local heat = util.clamp(g.player.heat or 0, 0, 1)
    local focus = util.clamp(g.player.focus or 0, 0, 1)
    local overheated = (g.isOverheated and g:isOverheated()) or (g.player.overheatActive == true)
    local cx, cy = g.centerX, g.centerY

    local function lerp(a, b, t) return a + (b - a) * t end
    local function lerp3(c1, c2, t) return { lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t), lerp(c1[3], c2[3], t) } end
    local function heatColor(t)
      -- blue -> yellow -> orange/red, with stronger urgency at 80%+
      t = util.clamp(t, 0, 1)
      local c0 = { 0.45, 0.85, 1.00 } -- cool
      local c1 = { 1.00, 0.95, 0.35 } -- warm
      local c2 = { 1.00, 0.35, 0.15 } -- critical
      if t < 0.65 then
        return lerp3(c0, c1, t / 0.65)
      end
      return lerp3(c1, c2, (t - 0.65) / 0.35)
    end
    local function focusColor(active)
      -- Slight hue/sat shift when actively focusing.
      local base = { 0.55, 0.80, 1.00 }
      local hot = { 0.70, 0.55, 1.00 }
      return active and lerp3(base, hot, 0.45) or base
    end

    -- Micro "shake" when Heat is pinned at full / overheat just triggered.
    local rox, roy = 0, 0
    if overheated and heat >= 0.995 then
      rox = (love.math.random() - 0.5) * 2.0
      roy = (love.math.random() - 0.5) * 2.0
    end
    local drawX, drawY = cx + rox, cy + roy

    local size = self.ringSize or 192
    local half = size * 0.5
    local r = 34
    local rcx, rcy = half, half

    local function arc(a0, a1, col, a, w)
      love.graphics.setColor(col[1], col[2], col[3], a)
      love.graphics.setLineWidth(w)
      love.graphics.arc("line", "open", rcx, rcy, r, a0, a1)
    end

    local function glowArc(a0, a1, col, a, w)
      arc(a0, a1, col, a, w)
      arc(a0, a1, col, a * 0.22, w + 5)
      arc(a0, a1, col, a * 0.10, w + 10)
    end

    love.graphics.push("all")
    love.graphics.setCanvas({ self.ringCanvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)

    local ringTex = g.assets and g.assets.heatFocus or nil

    local function drawRingTexArc(a0, a1, alpha, tint)
      if not ringTex then return end
      local iw, ih = ringTex:getWidth(), ringTex:getHeight()
      local outerR = r + 10
      local innerR = r - 6
      local sc = (outerR * 2) / math.max(1, math.max(iw, ih))

      local function outerSector()
        love.graphics.arc("fill", "pie", rcx, rcy, outerR, a0, a1)
      end
      local function innerSector()
        love.graphics.arc("fill", "pie", rcx, rcy, innerR, a0, a1)
      end

      love.graphics.stencil(outerSector, "replace", 1)
      love.graphics.stencil(innerSector, "replace", 0, true)
      love.graphics.setStencilTest("greater", 0)
      love.graphics.setColor(tint[1], tint[2], tint[3], alpha or 1)
      love.graphics.draw(ringTex, rcx, rcy, 0, sc, sc, iw * 0.5, ih * 0.5)
      love.graphics.setStencilTest()
    end

    if not ringTex then
      arc(0, math.pi * 2, { 0.25, 0.30, 0.42 }, 0.30, 4)
    end

    local hw = 5
    local heatFizz = (heat > 0.70) and ((heat - 0.70) / 0.30) or 0
    local fizz = heatFizz > 0 and (0.5 + 0.5 * math.sin(g.t * (22 + 10 * heatFizz))) or 0
    local overPulse = overheated and (0.55 + 0.45 * math.sin(g.t * 10.5)) or 0
    local ha = (0.28 + 0.55 * heat) * (1.0 + 0.20 * heatFizz * fizz)
    if overheated then
      ha = math.max(ha, 0.80) * (0.92 + 0.14 * overPulse)
    end
    if heat >= 0.90 then
      local crit = util.clamp((heat - 0.90) / 0.10, 0, 1)
      ha = ha * (1.0 + 0.18 * crit * (0.5 + 0.5 * math.sin(g.t * 14)))
    end
    local hStart = math.pi
    local hEnd = math.pi + math.pi * heat
    if heat > 0.001 then
      local hCol = overheated and { 1.00, 0.25, 0.10 } or heatColor(heat)
      if ringTex then
        drawRingTexArc(hStart, hEnd, ha, hCol)
      else
        glowArc(hStart, hEnd, hCol, ha, hw)
      end
    end

    local fw = 5
    local breath = 0
    if focus >= 0.995 and (not g.player.focusActive) then
      breath = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(g.t * 2.2))
    end
    local focusPress = g.player.focusActive and (0.55 + 0.45 * (0.5 + 0.5 * math.sin(g.t * 18))) or 0
    local fa = (g.player.focusActive and (0.92 + 0.06 * focusPress)) or (focus >= 0.995 and (0.40 + 0.25 * breath) or 0.75)
    local fStart = 0
    local fEnd = math.pi * focus
    if focus > 0.001 then
      local fCol = focusColor(g.player.focusActive)
      if ringTex then
        drawRingTexArc(fStart, fEnd, fa, fCol)
      else
        glowArc(fStart, fEnd, fCol, fa, fw)
      end
    end

    local pulseA = 0.14 + 0.22 * pulse * (0.6 + 0.4 * math.sin(g.t * 16))
    arc(0, math.pi * 2, { 0.55, 0.90, 1.00 }, pulseA, 3)

    do
      local sparkN = overheated and 10 or (g.player.focusActive and 7 or 4)
      local sparkA = (overheated and 0.22 or 0.12) + 0.12 * pulse
      local spin = g.t * (overheated and 3.1 or 2.2)
      local col = overheated and { 1.00, 0.45, 0.20 } or { 0.55, 0.90, 1.00 }
      love.graphics.setColor(col[1], col[2], col[3], sparkA)
      love.graphics.setPointSize(2)
      for i = 1, sparkN do
        local a = spin + i * (math.pi * 2 / sparkN) + 0.35 * math.sin(g.t * 2.0 + i)
        local rr = r + 2 + 3 * (0.5 + 0.5 * math.sin(g.t * 6.0 + i * 1.7))
        local x = rcx + math.cos(a) * rr
        local y = rcy + math.sin(a) * rr
        love.graphics.points(x, y)
      end
      love.graphics.setPointSize(1)
    end

    if overheated then
      local a = 0.10 + 0.10 * (0.5 + 0.5 * math.sin(g.t * 7.5))
      arc(0, math.pi * 2, { 1.00, 0.35, 0.15 }, a, 10)
    end

    local hf = util.clamp(g.player.heatFlash or 0, 0, 0.10) / 0.10
    local ff = util.clamp(g.player.focusFlash or 0, 0, 0.10) / 0.10
    local of = util.clamp(g.player.overheatFlash or 0, 0, 0.20) / 0.20
    if (hf > 0) or (ff > 0) or (of > 0) then
      love.graphics.setBlendMode("add")
      if hf > 0 then arc(math.pi, math.pi * 2, { 1, 1, 1 }, 0.16 * hf, 10) end
      if ff > 0 then arc(0, math.pi, { 1, 1, 1 }, 0.14 * ff, 10) end
      if of > 0 then arc(0, math.pi * 2, { 1, 1, 1 }, 0.22 * of, 14) end
      love.graphics.setBlendMode("alpha")
    end

    love.graphics.setCanvas()
    love.graphics.pop()

    local haze = util.clamp((heat * heat) * (overheated and 1.0 or 0.65), 0, 1)
    self.ringShader:send("u_time", g.t or 0)
    self.ringShader:send("u_amount", haze)

    local px = drawX - half
    local py = drawY - half
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(self.ringShader)

    -- Base distorted ring
    love.graphics.draw(self.ringCanvas, px, py)

    -- Cheap bloom: slightly larger additive copies
    love.graphics.setBlendMode("add")
    local bA = 0.22 + 0.18 * haze
    love.graphics.setColor(1, 1, 1, bA)
    love.graphics.draw(self.ringCanvas, px - 1, py - 1, 0, 1.03, 1.03)
    love.graphics.setColor(1, 1, 1, bA * 0.60)
    love.graphics.draw(self.ringCanvas, px - 2, py - 2, 0, 1.06, 1.06)
    love.graphics.setBlendMode("alpha")

    love.graphics.setShader()
  end

  if g.fxSys and g.fxSys.drawDeathJuice then
    g.fxSys:drawDeathJuice()
  end

  -- enemies
  if g.state == "playing" or g.state == "perk" then
    for _, e in ipairs(g.enemies) do
      enemy.draw(g, e)
    end
  end

  if g.projectilesSys and g.projectilesSys.draw then
    g.projectilesSys:draw()
  end

  -- FX: rings behind particles for readability
  for _, r in ipairs(g.fx.rings) do
    local t = util.clamp(r.t / math.max(0.001, r.life), 0, 1)
    local rr = util.lerp(r.r0, r.r1, t)
    local a = (1 - t) * 0.75
    love.graphics.setColor(r.col[1], r.col[2], r.col[3], a)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", r.x, r.y, rr)
  end
  love.graphics.setLineWidth(1)

  -- Parry burst (arc + slash + additive glow)
  if g.fx.bursts and #g.fx.bursts > 0 then
    love.graphics.setBlendMode("add")
    for _, b in ipairs(g.fx.bursts) do
      local t = util.clamp(b.t / math.max(0.001, b.life), 0, 1)
      local a = (1 - t)
      local col = b.perfect and { 0.95, 0.55, 1.0 } or { 0.45, 1.0, 0.80 }
      local glow = b.perfect and 1.0 or 0.8

      -- Arc shock ring
      local r0 = 18
      local r1 = b.perfect and 110 or 90
      local rr = util.lerp(r0, r1, t)
      local arcSpan = b.perfect and (math.pi * 1.35) or (math.pi * 1.10)
      local arcStart = b.angle - arcSpan * 0.5
      local arcEnd = b.angle + arcSpan * 0.5
      love.graphics.setColor(col[1], col[2], col[3], 0.55 * a * glow)
      love.graphics.setLineWidth(b.perfect and 6 or 5)
      love.graphics.arc("line", "open", b.x, b.y, rr, arcStart, arcEnd)
      love.graphics.setColor(col[1], col[2], col[3], 0.25 * a * glow)
      love.graphics.setLineWidth(b.perfect and 10 or 8)
      love.graphics.arc("line", "open", b.x, b.y, rr, arcStart, arcEnd)

      -- Slash streak (stacked lines for faux gradient)
      local len = b.perfect and 170 or 140
      local dx = math.cos(b.angle) * len * 0.5
      local dy = math.sin(b.angle) * len * 0.5
      love.graphics.setLineWidth(b.perfect and 10 or 8)
      love.graphics.setColor(1, 1, 1, 0.18 * a)
      love.graphics.line(b.x - dx, b.y - dy, b.x + dx, b.y + dy)
      love.graphics.setLineWidth(b.perfect and 5 or 4)
      love.graphics.setColor(col[1], col[2], col[3], 0.55 * a * glow)
      love.graphics.line(b.x - dx, b.y - dy, b.x + dx, b.y + dy)
      love.graphics.setLineWidth(1)

      -- Center bloom
      love.graphics.setColor(col[1], col[2], col[3], 0.35 * a * glow)
      love.graphics.circle("fill", b.x, b.y, (b.perfect and 22 or 18) * (1 + 0.15 * (1 - t)))
      love.graphics.setColor(1, 1, 1, 0.18 * a)
      love.graphics.circle("fill", b.x, b.y, (b.perfect and 12 or 10))
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setLineWidth(1)
  end

  for _, p in ipairs(g.fx.particles) do
    local t = util.clamp(p.t / math.max(0.001, p.life), 0, 1)
    local a = (1 - t) * 0.9
    love.graphics.setColor(p.col[1], p.col[2], p.col[3], a)
    if p.shape == "shard" then
      local ww = p.w or 3
      local hh = p.size or 8
      love.graphics.push()
      love.graphics.translate(p.x, p.y)
      love.graphics.rotate(p.rot or 0)
      love.graphics.rectangle("fill", -hh * 0.5, -ww * 0.5, hh, ww, 1, 1)
      love.graphics.pop()
    else
      love.graphics.circle("fill", p.x, p.y, p.size * (1 - 0.35 * t))
    end
  end

  if g.flash > 0 then
    local a = util.clamp(g.flash / 0.25, 0, 1) * 0.35
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.rectangle("fill", 0, 0, g.w, g.h)
  end

  love.graphics.pop()
end

return WorldRenderer

