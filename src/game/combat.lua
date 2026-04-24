local util = require("src.util")
local enemy = require("src.enemy")

local Combat = {}
Combat.__index = Combat

function Combat.new(game)
  local self = setmetatable({}, Combat)
  self.game = game
  return self
end

function Combat:currentParryWindowForEnemy(e)
  local g = self.game
  -- Shrink with streak (higher streak => narrower), but clamp to a minimum.
  -- After taking damage, give a brief recovery period so the player can re-stabilize.
  local base = g.player.parryWindowBase

  local rec = g.player.recovery or 0
  local recT = util.clamp(rec / 1.25, 0, 1) -- 0..1
  -- During recovery, temporarily boost the base window and suppress streak shrink.
  local recoveryBoost = 0.060 * recT -- up to +60ms right after hit
  local streak = math.max(1, g.player.streak)
  local shrink = (g.player.parryShrinkPerStreak or 0.985) ^ (streak - 1)
  local shrinkMix = 1 - recT -- 0 => no shrink at start of recovery, 1 => full shrink when recovered
  local effShrink = util.lerp(1.0, shrink, shrinkMix)

  local win = (base + recoveryBoost) * effShrink
  win = win * g:getParryDifficultyMult()

  -- Heavy is slightly tighter by default.
  if e and e.kind == "heavy" then
    win = win - 0.015
  end

  return util.clamp(win, g.player.parryWindowMin or 0.050, 0.250)
end

function Combat:getLateParryGrace(e)
  return self:currentParryWindowForEnemy(e)
end

function Combat:getHitCommitDelay()
  return 1 / 60
end

function Combat:getPerfectWindowForEnemy(e)
  local g = self.game
  local parry = self:currentParryWindowForEnemy(e)
  local cap = g.player.perfectWindowCap or 0
  local ratio = g.player.perfectRatio or 0.35
  return math.max(0, math.min(cap, parry * ratio))
end

function Combat:addScoreForParry(dtFromImpact, parryWindowUsed)
  local g = self.game
  g.player.streak = g.player.streak + 1
  g.player.bestStreak = math.max(g.player.bestStreak, g.player.streak)

  local base = 10
  local bonus = math.floor((g.player.streak - 1) * (1 + (g.meta.comboBonus or 0)))

  local perfect = false
  local cap = g.player.perfectWindowCap or 0
  local ratio = g.player.perfectRatio or 0.38
  local innerFromParry = (parryWindowUsed or 0) * ratio
  local inner = math.max(0, math.min(cap, innerFromParry))
  if inner > 0 and math.abs(dtFromImpact) <= inner then
    perfect = true
    bonus = bonus + (g.meta.perfectBonus or 0)
  end

  g.player.score = g.player.score + base + bonus
  return perfect
end

function Combat:playerTakeHit()
  local g = self.game
  if (g.player.invuln or 0) > 0 then
    return
  end

  if g.meta.streakShield and not g.meta.shieldUsedThisWave then
    g.meta.shieldUsedThisWave = true
    g.player.lastParry.ok = true
    g.player.lastParry.dt = 0
    g.player.lastParry.timer = 0.8
    g.player.lastParry.label = "SHIELD!"
    g.flash = 0.10
    g.shake = 0.10
    g.freeze = 0.02
    return
  end

  -- Cheat death: consume a guard if this hit would be fatal.
  if (g.player.hp or 0) <= 1 and (g.meta.fatalGuard or 0) > 0 then
    g.meta.fatalGuard = (g.meta.fatalGuard or 0) - 1
    g.player.lastParry.ok = true
    g.player.lastParry.dt = 0
    g.player.lastParry.timer = 1.0
    g.player.lastParry.label = "LAST STAND!"
    g:playSfx("parry", 0.9, 0.92)
    g.player.invuln = 0.35
    g.player.recovery = 1.5
    g.player.streak = 0
    g.flash = 0.18
    g.shake = 0.22
    g.freeze = 0.05
    return
  end

  g.player.hp = g.player.hp - 1
  g:duckMusic(util.lerp(0.70, 0.50, love.math.random()), 0.15)
  g:playSfx("hit", 1.0, 1.0)
  g.player.invuln = 0.18
  g.player.recovery = 1.25
  g.player.streak = 0
  g.flash = 0.25
  g.shake = 0.25
  g.freeze = 0.05
  if g.dda then
    g.dda.v = util.clamp((g.dda.v or 0) - 0.28, 0, 1)
    g.dda.target = util.clamp((g.dda.target or 0) - 0.35, 0, 1)
  end
  if g.player.hp <= 0 then
    g.bests.bestStreak = math.max(g.bests.bestStreak or 0, g.player.bestStreak or 0)
    g.bests.bestScore = math.max(g.bests.bestScore or 0, g.player.score or 0)
    g.state = "dead"
    g:goToMenu("dead")
  end
end

function Combat:onSuccessfulParry(e, dtFromImpact)
  local g = self.game
  local win = self:currentParryWindowForEnemy(e)
  local perfect = self:addScoreForParry(dtFromImpact, win)
  g.player.hasParriedOnce = true
  if perfect then
    g:duckMusic(util.lerp(0.70, 0.50, love.math.random()), 0.15)
  end
  g:playSfx("parry", perfect and 1.10 or 0.85, perfect and 1.08 or 1.0)
  g:spawnParryBurst(e.x, e.y, perfect)
  g.player.lastParry.ok = true
  g.player.lastParry.dt = dtFromImpact
  g.player.lastParry.timer = perfect and 0.65 or 0
  g.player.lastParry.label = perfect and "PERFECT!" or ""

  if perfect then
    g.flash = 0.16
    g.shake = 0.14
    g.freeze = 0.045
    g:spawnParticles(e.x, e.y, { 0.90, 0.60, 1.00 }, 18, 60, 320, 0.25, 0.60, 2, 6)
    g:spawnRing(e.x, e.y, { 0.95, 0.55, 1.00 }, 18, 140, 0.22)
  else
    g.flash = 0.12
    g.shake = 0.10
    g.freeze = 0.03
    g:spawnParticles(e.x, e.y, { 0.55, 1.00, 0.70 }, 12, 50, 260, 0.22, 0.50, 2, 5)
    g:spawnRing(e.x, e.y, { 0.45, 1.00, 0.70 }, 14, 110, 0.18)
  end

  g:tryShockwave(e.x, e.y)
  if g.dda then
    local bump = perfect and 0.06 or 0.03
    g.dda.target = util.clamp((g.dda.target or 0) + bump, 0, 1)
  end

  -- Heat cycle: parry/perfect both build heat until full.
  -- Once full, enemies are buffed while heat drains back to 0.
  if g.player and (not g.player.overheatActive) then
    local heat0 = g.player.heat or 0
    local heat = heat0 + (perfect and 0.14 or 0.10)
    if heat >= 1.0 then
      heat = 1.0
      g.player.overheatActive = true
      g.player.overheatFlash = math.max(g.player.overheatFlash or 0, 0.18)
    end
    g.player.heat = util.clamp(heat, 0, 1)
    if g.player.heat > heat0 + 1e-4 then
      g.player.heatFlash = math.max(g.player.heatFlash or 0, 0.08)
    end
  end
end

function Combat:onFailedParry(dtFromImpact)
  local g = self.game
  g.player.lastParry.ok = false
  g.player.lastParry.dt = dtFromImpact
  g.player.lastParry.timer = 0
  g.player.lastParry.label = ""
  g:spawnParticles(g.centerX, g.centerY, { 1.00, 0.35, 0.35 }, 14, 50, 260, 0.22, 0.55, 2, 6)
  g:spawnRing(g.centerX, g.centerY, { 1.00, 0.35, 0.35 }, 20, 150, 0.20)
  self:playerTakeHit()
  if g.dda then
    g.dda.v = util.clamp((g.dda.v or 0) - 0.18, 0, 1)
    g.dda.target = util.clamp((g.dda.target or 0) - 0.25, 0, 1)
  end
end

function Combat:attemptParry()
  local g = self.game
  if g.state ~= "playing" then return end
  if g.player.cd > 0 then return end
  g.player.cd = g.player.cooldown

  -- Projectile deflect: if a shot is close, parry deflects it.
  do
    local bestIdx, bestD = nil, nil
    local deflectR = g:getDeflectRadius()
    for i = 1, #(g.projectiles or {}) do
      local p = g.projectiles[i]
      if p and (not p.deflected) then
        local dx, dy = p.x - g.centerX, p.y - g.centerY
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= deflectR and ((not bestD) or d < bestD) then
          bestD, bestIdx = d, i
        end
      end
    end
    if bestIdx then
      local p = g.projectiles[bestIdx]
      p.deflected = true
      p.life = 0.25
      -- reflect toward the shooter (if alive)
      local target = g:findEnemyById(p.shooterId)
      if target then
        local dx, dy = target.x - p.x, target.y - p.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local nx, ny = dx / (dist + 1e-6), dy / (dist + 1e-6)
        local sp = math.max(360, math.sqrt((p.vx or 0)^2 + (p.vy or 0)^2) * 1.35)
        p.vx = nx * sp
        p.vy = ny * sp
        p.targetId = target.id
      else
        -- shooter already gone; just fling outward
        p.vx = -(p.vx or 0) * 1.25
        p.vy = -(p.vy or 0) * 1.25
      end
      g:duckMusic(util.lerp(0.76, 0.60, love.math.random()), 0.12)
      g:playSfx("parry", 0.95, 1.40)
      self:onSuccessfulParry({ x = p.x, y = p.y, kind = "projectile" }, 0)
      g.player.lastParry.timer = 0.55
      g.player.lastParry.label = "DEFLECT!"
      g.player.score = (g.player.score or 0) + 5
      return
    end
  end

  local e, imp = enemy.findNearestImpact(g, g.enemies)
  if not e or not imp then
    -- Fatigue: pressing parry with no active window is a self-hit (prevents spam-to-win),
    -- but only when there are actual threats present (enemies/projectiles).
    local hasThreat = false
    for _, ee in ipairs(g.enemies or {}) do
      if ee and ee.phase ~= "done" then
        hasThreat = true
        break
      end
    end
    if (not hasThreat) and g.projectiles and #g.projectiles > 0 then
      hasThreat = true
    end
    if hasThreat then
      g.player.lastParry.ok = false
      g.player.lastParry.dt = 999
      g.player.lastParry.timer = 0.70
      g.player.lastParry.label = "You whiff and hit yourself"
      g:spawnParticles(g.centerX, g.centerY, { 1.00, 0.25, 0.25 }, 16, 60, 320, 0.22, 0.60, 2, 7)
      g:spawnRing(g.centerX, g.centerY, { 1.00, 0.25, 0.25 }, 22, 160, 0.22)
      g.flash = math.max(g.flash, 0.18)
      g.shake = math.max(g.shake, 0.22)
      self:playerTakeHit()
    else
      g.player.lastParry.ok = false
      g.player.lastParry.dt = 999
      g.player.lastParry.timer = 0
      g.player.lastParry.label = ""
    end
    return
  end

  local dt = g.t - imp.t
  local win = self:currentParryWindowForEnemy(e)
  if math.abs(dt) <= win then
    imp.parried = true
    imp.resolved = true
    imp.pending = false
    imp.ready = false
    imp.readyAt = nil
    self:onSuccessfulParry(e, dt)

    if e.kind == "boss" then
      -- Prevent late queued impacts from dealing damage after a successful parry.
      e.hp = (e.hp or 1) - 1
      for _, i2 in ipairs(e.impacts or {}) do
        i2.parried = true
        i2.resolved = true
        i2.pending = false
        i2.ready = false
        i2.readyAt = nil
      end
      if (e.hp or 0) <= 0 then
        g.bossActive = false
        g.bossId = nil
        g:killEnemy(e)
      end
    elseif e.kind == "chain" then
      e.hp = (e.hp or 1) - 1
      if (e.hp or 0) <= 0 then
        for _, i2 in ipairs(e.impacts or {}) do
          i2.parried = true
          i2.resolved = true
          i2.pending = false
          i2.ready = false
          i2.readyAt = nil
        end
        g:killEnemy(e)
      end
    elseif e.kind == "shield" then
      e.hp = (e.hp or 1) - 1
      if (e.hp or 0) <= 0 then
        for _, i2 in ipairs(e.impacts or {}) do
          i2.parried = true
          i2.resolved = true
          i2.pending = false
          i2.ready = false
          i2.readyAt = nil
        end
        g:killEnemy(e)
      else
        e.shieldBroken = true
        for _, i2 in ipairs(e.impacts or {}) do
          i2.parried = true
          i2.resolved = true
          i2.pending = false
          i2.ready = false
          i2.readyAt = nil
        end
        e.impacts = nil
        e.nextImpactIdx = nil
        e.phase = "approach"
        e.timer = 0
        g:spawnRing(e.x, e.y, { 0.55, 0.90, 1.00 }, 18, 120, 0.18)
        g:spawnParticles(e.x, e.y, { 0.55, 0.90, 1.00 }, 10, 60, 260, 0.18, 0.45, 2, 5)
      end
    elseif e.kind == "goblin" then
      e.hp = (e.hp or 1) - 1
      for _, i2 in ipairs(e.impacts or {}) do
        i2.parried = true
        i2.resolved = true
        i2.pending = false
        i2.ready = false
        i2.readyAt = nil
      end

      if (e.hp or 0) <= 0 then
        g:killEnemy(e)
      else
        -- Teleport after each successful parry.
        local function pickSpot()
          local pad = 120
          local minX, maxX = pad, g.w - pad
          local minY, maxY = pad, g.h - pad
          for _ = 1, 12 do
            local x = love.math.random(minX, maxX)
            local y = love.math.random(minY, maxY)
            local dx, dy = x - g.centerX, y - g.centerY
            if (dx * dx + dy * dy) >= (150 * 150) then
              return x, y
            end
          end
          return love.math.random(minX, maxX), love.math.random(minY, maxY)
        end

        local nx, ny = pickSpot()
        g:spawnRing(e.x, e.y, { 0.95, 0.85, 0.35 }, 18, 120, 0.18)
        g:spawnParticles(e.x, e.y, { 0.95, 0.85, 0.35 }, 10, 70, 320, 0.16, 0.45, 2, 6)
        e.x, e.y = nx, ny
        e.phase = "telegraph"
        e.timer = 0
        e.impacts = nil
        e.nextImpactIdx = nil
        g.player.score = (g.player.score or 0) + 15
        g.player.lastParry.timer = 0.55
        g.player.lastParry.label = ("GOBLIN (%d)"):format(e.hp or 0)
      end
    else
      for _, i2 in ipairs(e.impacts or {}) do
        i2.parried = true
        i2.resolved = true
        i2.pending = false
        i2.ready = false
        i2.readyAt = nil
      end
      g:killEnemy(e)
    end
  else
    self:onFailedParry(dt)
  end
end

return Combat

