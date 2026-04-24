local util = require("src.util")

local Projectiles = {}
Projectiles.__index = Projectiles

function Projectiles.new(game)
  local self = setmetatable({}, Projectiles)
  self.game = game
  return self
end

function Projectiles:getDeflectRadius()
  local g = self.game
  local bonus = (g and g.meta and g.meta.deflectRadiusBonus) or 0
  return 58 + bonus
end

function Projectiles:spawn(fromX, fromY, speed, radius, shooterId)
  local g = self.game
  local dx, dy = g.centerX - fromX, g.centerY - fromY
  local dist = math.sqrt(dx * dx + dy * dy)
  local nx, ny = dx / (dist + 1e-6), dy / (dist + 1e-6)
  local sp = speed or 280
  g.projectiles[#g.projectiles + 1] = {
    x = fromX,
    y = fromY,
    vx = nx * sp,
    vy = ny * sp,
    r = radius or 7,
    deflected = false,
    shooterId = shooterId
  }
end

function Projectiles:update(dt)
  local g = self.game
  local out = {}
  for _, p in ipairs(g.projectiles or {}) do
    if p then
      if not p.deflected then
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        local dx, dy = p.x - g.centerX, p.y - g.centerY
        local d = math.sqrt(dx * dx + dy * dy)
        -- Treat <=18px to player center as a hit (matches player collision radius).
        if d <= 18 then
          g:playerTakeHit()
        else
          out[#out + 1] = p
        end
      else
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        local target = g:findEnemyById(p.targetId or p.shooterId)
        if target then
          local dx, dy = p.x - target.x, p.y - target.y
          if (dx * dx + dy * dy) <= ((target.r or 18) + (p.r or 7) + 6)^2 then
            g:killEnemy(target)
            g:spawnParticles(target.x, target.y, { 0.55, 0.90, 1.00 }, 14, 70, 320, 0.18, 0.50, 2, 6)
            g.flash = math.max(g.flash, 0.08)
            g.shake = math.max(g.shake, 0.10)
          else
            out[#out + 1] = p
          end
        else
          -- no target; fade out
          p.life = (p.life or 0.25) - dt
          if (p.life or 0) > 0 then out[#out + 1] = p end
        end
      end
    end
  end
  g.projectiles = out
end

function Projectiles:draw()
  local g = self.game
  if not (g.projectiles and #g.projectiles > 0) then return end

  local deflectR = self:getDeflectRadius()
  for _, p in ipairs(g.projectiles) do
    local a = p.deflected and 0.55 or 0.95
    local r0 = p.r or 7
    love.graphics.setColor(0.55, 0.85, 1.00, a)
    love.graphics.circle("fill", p.x, p.y, r0)
    love.graphics.setColor(1, 1, 1, a * 0.35)
    love.graphics.circle("line", p.x, p.y, r0 + 3)

    if (not p.deflected) then
      local dx, dy = p.x - g.centerX, p.y - g.centerY
      local d2 = dx * dx + dy * dy
      if d2 <= deflectR * deflectR then
        local d = math.sqrt(d2)
        local t = util.clamp(1.0 - (d / deflectR), 0, 1)
        local pulse = 0.5 + 0.5 * math.sin(g.t * 14)
        local ringA = (0.25 + 0.55 * t) * (0.65 + 0.35 * pulse)
        love.graphics.setColor(0.95, 0.35, 0.25, ringA)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", p.x, p.y, r0 + 10 + 4 * pulse)
        love.graphics.setLineWidth(1)

        love.graphics.setColor(0.95, 0.35, 0.25, ringA * 0.20)
        love.graphics.circle("fill", p.x, p.y, r0 + 18 + 6 * pulse)
      end
    end
  end
end

return Projectiles

