local util = require("src.util")

local FX = {}
FX.__index = FX

function FX.new(game)
  local self = setmetatable({}, FX)
  self.game = game
  return self
end

function FX:spawnParticles(x, y, col, count, speedMin, speedMax, lifeMin, lifeMax, sizeMin, sizeMax)
  local g = self.game
  local p = g.fx.particles
  count = count or 10
  speedMin, speedMax = speedMin or 40, speedMax or 220
  lifeMin, lifeMax = lifeMin or 0.25, lifeMax or 0.55
  sizeMin, sizeMax = sizeMin or 2, sizeMax or 5
  for _ = 1, count do
    local a = love.math.random() * math.pi * 2
    local sp = util.lerp(speedMin, speedMax, love.math.random())
    local life = util.lerp(lifeMin, lifeMax, love.math.random())
    local size = util.lerp(sizeMin, sizeMax, love.math.random())
    p[#p + 1] = {
      x = x,
      y = y,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp,
      life = life,
      t = 0,
      size = size,
      col = { col[1], col[2], col[3] }
    }
  end
end

function FX:spawnRing(x, y, col, r0, r1, life)
  local g = self.game
  local rings = g.fx.rings
  rings[#rings + 1] = {
    x = x, y = y,
    r0 = r0 or 10,
    r1 = r1 or 110,
    life = life or 0.25,
    t = 0,
    col = { col[1], col[2], col[3] }
  }
end

function FX:spawnEnemyDeathJuice(e)
  local g = self.game
  if not e then return end
  local x, y = e.x or 0, e.y or 0
  local kind = e.kind or "basic"

  -- radial shards + pop ring
  local col = (kind == "boss") and { 0.95, 0.85, 0.35 } or { 0.95, 0.35, 0.20 }
  self:spawnParticles(x, y, col, 10, 120, 420, 0.10, 0.22, 2, 6)
  self:spawnRing(x, y, col, (e.r or 18) * 0.7, (e.r or 18) * 3.2, 0.16)

  -- afterimage smear (2–3 faded sprites trailing)
  local img = (kind == "boss") and (g.assets and g.assets.boss) or (g.assets and g.assets.enemy)
  local n = 3
  for i = 1, n do
    g.fx.afterimages[#g.fx.afterimages + 1] = {
      x = x,
      y = y,
      img = img,
      r = e.r or 18,
      t = -(i - 1) * 0.02,
      life = 0.12,
      a0 = 0.42 - (i - 1) * 0.10
    }
  end

  -- squash+stretch pop (drawn as a very short-lived FX sprite)
  g.fx.deaths[#g.fx.deaths + 1] = {
    x = x,
    y = y,
    img = img,
    r = e.r or 18,
    t = 0,
    life = 0.16,
    col = col
  }
end

function FX:spawnParryBurst(x, y, perfect)
  local g = self.game
  local bursts = g.fx.bursts
  local angle = love.math.random() * math.pi * 2
  local dur = perfect and 0.32 or 0.24
  bursts[#bursts + 1] = {
    x = x, y = y,
    t = 0,
    life = dur,
    angle = angle,
    perfect = perfect and true or false
  }

  -- shard particles (rotated rectangles)
  local baseCol = perfect and { 0.95, 0.55, 1.0 } or { 0.45, 1.0, 0.80 }
  local count = perfect and 18 or 12
  for _ = 1, count do
    local a = angle + (love.math.random() - 0.5) * 1.2
    local sp = util.lerp(perfect and 260 or 190, perfect and 520 or 380, love.math.random())
    local life = util.lerp(0.18, perfect and 0.45 or 0.35, love.math.random())
    local size = util.lerp(4, perfect and 10 or 8, love.math.random())
    local w = util.lerp(2, 4, love.math.random())
    g.fx.particles[#g.fx.particles + 1] = {
      x = x,
      y = y,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp,
      life = life,
      t = 0,
      size = size,
      col = { baseCol[1], baseCol[2], baseCol[3] },
      shape = "shard",
      rot = a,
      vr = (love.math.random() - 0.5) * 10,
      w = w
    }
  end
end

function FX:update(dt)
  local g = self.game

  local np = {}
  for _, p in ipairs(g.fx.particles) do
    p.t = p.t + dt
    if p.t < p.life then
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.vx = p.vx * (1 - 1.8 * dt)
      p.vy = p.vy * (1 - 1.8 * dt)
      if p.vr then
        p.rot = (p.rot or 0) + p.vr * dt
      end
      np[#np + 1] = p
    end
  end
  g.fx.particles = np

  local nr = {}
  for _, r in ipairs(g.fx.rings) do
    r.t = r.t + dt
    if r.t < r.life then
      nr[#nr + 1] = r
    end
  end
  g.fx.rings = nr

  local nb = {}
  for _, b in ipairs(g.fx.bursts or {}) do
    b.t = b.t + dt
    if b.t < b.life then
      nb[#nb + 1] = b
    end
  end
  g.fx.bursts = nb

  local na = {}
  for _, a in ipairs(g.fx.afterimages or {}) do
    a.t = a.t + dt
    if a.t < a.life then
      na[#na + 1] = a
    end
  end
  g.fx.afterimages = na

  local nd = {}
  for _, d in ipairs(g.fx.deaths or {}) do
    d.t = d.t + dt
    if d.t < d.life then
      nd[#nd + 1] = d
    end
  end
  g.fx.deaths = nd
end

function FX:drawDeathJuice()
  local g = self.game
  -- Death juice (afterimage smear + squash/stretch pop)
  if g.fx.afterimages and #g.fx.afterimages > 0 then
    for _, a in ipairs(g.fx.afterimages) do
      if (a.t or 0) >= 0 then
        local t = util.clamp((a.t or 0) / math.max(0.001, a.life or 0.12), 0, 1)
        local alpha = (a.a0 or 0.35) * (1 - t)
        if a.img then
          local iw, ih = a.img:getWidth(), a.img:getHeight()
          local s = (math.max(36, (a.r or 18) * 2.1)) / math.max(1, math.max(iw, ih))
          local ox = util.lerp(-8, 8, t)
          local oy = util.lerp(6, -4, t)
          love.graphics.setColor(1, 1, 1, alpha)
          love.graphics.draw(a.img, (a.x or 0) + ox, (a.y or 0) + oy, 0, s, s, iw * 0.5, ih * 0.5)
        else
          love.graphics.setColor(1, 1, 1, alpha)
          love.graphics.circle("fill", a.x or 0, a.y or 0, (a.r or 18) * (1.0 + 0.2 * (1 - t)))
        end
      end
    end
  end

  if g.fx.deaths and #g.fx.deaths > 0 then
    for _, d in ipairs(g.fx.deaths) do
      local t = util.clamp((d.t or 0) / math.max(0.001, d.life or 0.16), 0, 1)
      local a = (1 - t)
      local sx = 1.0 + 0.40 * (1 - t)
      local sy = 1.0 - 0.28 * (1 - t)
      if d.img then
        local iw, ih = d.img:getWidth(), d.img:getHeight()
        local s = (math.max(36, (d.r or 18) * 2.2)) / math.max(1, math.max(iw, ih))
        love.graphics.setColor(1, 1, 1, 0.75 * a)
        love.graphics.draw(d.img, d.x or 0, d.y or 0, 0, s * sx, s * sy, iw * 0.5, ih * 0.5)
      else
        local col = d.col or { 1, 1, 1 }
        love.graphics.setColor(col[1], col[2], col[3], 0.75 * a)
        love.graphics.circle("fill", d.x or 0, d.y or 0, (d.r or 18) * (1.3 + 0.9 * (1 - t)))
      end
    end
  end
end

return FX

