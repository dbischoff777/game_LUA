local util = require("src.util")

local enemy = {}

local function drawIcon(img, x, y, size, alpha, scaleMul)
  if not img then return end
  local iw, ih = img:getWidth(), img:getHeight()
  local s = (size or 36) / math.max(1, math.max(iw, ih))
  s = s * (scaleMul or 1)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(img, x, y, 0, s, s, iw * 0.5, ih * 0.5)
end

local function baseEnemy(x, y, side, speed)
  return {
    id = 0,
    x = x,
    y = y,
    r = 18,
    side = side,
    speed = speed,
    kind = "basic",
    hp = 1,
    maxHp = 1,
    -- Phase is the authoritative state machine; only enemy.update() advances it.
    -- "done" is a terminal state and will be culled from `g.enemies` by EnemyRuntime.
    phase = "approach", -- approach -> telegraph -> strike -> done
    timer = 0,
    telegraph = 0.75,
    windup = 0.20,
    impacts = nil, -- array of { t = number, parried = bool, resolved = bool, pending = bool, ready = bool, readyAt = number }
    nextImpactIdx = nil, -- index of earliest unresolved impact (stable per-enemy)
    bossInterval = 0.55, -- time between boss parry windows
    bossTimer = 0,
    attacked = false,
    feintDone = false
  }
end

function enemy.spawn(kind, params)
  local e = baseEnemy(params.x, params.y, params.side, params.speed)
  e.id = params.id or 0
  e.kind = kind
  e.telegraph = params.telegraph
  e.windup = params.windup
  e.hp = params.hp or 1
  e.maxHp = params.hp or 1

  if kind == "double" then
    e.r = 20
    e.windup = math.max(0.16, params.windup - 0.02)
  elseif kind == "heavy" then
    e.r = 24
    e.windup = params.windup + 0.08
  elseif kind == "feint" then
    e.r = 18
    e.windup = params.windup
  elseif kind == "shield" then
    e.r = 22
    e.windup = params.windup + 0.03
    e.hp = params.hp or 2
    e.maxHp = params.hp or 2
    e.shieldBroken = false
  elseif kind == "boss" then
    e.r = 38
    e.windup = params.windup + 0.10
    e.telegraph = params.telegraph + 0.25
    e.bossInterval = params.bossInterval or 0.55
    e.bossTimer = 0
  elseif kind == "chain" then
    e.r = 20
    e.windup = math.max(0.14, params.windup - 0.03)
  elseif kind == "ranged" then
    e.r = 18
    e.windup = math.max(0.14, params.windup - 0.02)
    e.telegraph = params.telegraph + 0.10
    e.shotEvery = 0.85
    e.shotTimer = 0
  elseif kind == "goblin" then
    e.r = 16
    e.windup = math.max(0.14, (params.windup or 0.20) - 0.04)
    e.telegraph = math.max(0.35, (params.telegraph or 0.70) * 0.75)
    e.hp = params.hp or 4
    e.maxHp = params.hp or 4
    e.teleportFx = 0
  end

  return e
end

local function setStrikeImpacts(g, e, impactTimes)
  table.sort(impactTimes)
  e.impacts = {}
  for i = 1, #impactTimes do
    e.impacts[i] = {
      t = impactTimes[i],
      parried = false,
      resolved = false,
      pending = false,
      ready = false,
      readyAt = nil
    }
  end
  e.nextImpactIdx = (#impactTimes > 0) and 1 or nil
  e.phase = "strike"
  e.timer = 0
end

local function refreshNextImpactIdx(e)
  if not e.impacts then
    e.nextImpactIdx = nil
    return
  end
  -- Recompute because impacts can be mass-resolved (boss/chain) and we need the earliest unresolved impact.
  local bestIdx, bestT = nil, nil
  for i = 1, #e.impacts do
    local imp = e.impacts[i]
    if not imp.resolved then
      if (not bestT) or imp.t < bestT then
        bestT = imp.t
        bestIdx = i
      end
    end
  end
  e.nextImpactIdx = bestIdx
end

function enemy.update(g, e, dt)
  e.timer = e.timer + dt

  local px, py = g.centerX, g.centerY
  local spMul = (g.getEnemySpeedMult and g:getEnemySpeedMult()) or 1.0

  if e.phase == "approach" then
    local dx = px - e.x
    local dy = py - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local nx, ny = dx / (dist + 1e-6), dy / (dist + 1e-6)
    e.x = e.x + nx * e.speed * dt * spMul
    e.y = e.y + ny * e.speed * dt * spMul

    if dist < 170 or e.kind == "boss" then
      e.phase = "telegraph"
      e.timer = 0
    end

  elseif e.phase == "telegraph" then
    if e.kind == "ranged" then
      -- Ranged enemy stays at distance and fires projectiles.
      e.shotTimer = (e.shotTimer or 0) + dt
      if e.shotTimer >= (e.shotEvery or 0.85) then
        e.shotTimer = 0
        if g and g.spawnProjectile then
          g:spawnProjectile(e.x, e.y, 280 + (e.speed or 0) * 0.25, 7, e.id)
        end
        -- brief recoil flash handled in draw
        e.attacked = true
      else
        e.attacked = false
      end
      return
    end
    if e.timer >= e.telegraph then
      local now = g.t
      if e.kind == "basic" then
        setStrikeImpacts(g, e, { now + e.windup })
      elseif e.kind == "double" then
        setStrikeImpacts(g, e, { now + e.windup, now + e.windup + 0.18 })
      elseif e.kind == "heavy" then
        setStrikeImpacts(g, e, { now + e.windup })
      elseif e.kind == "shield" then
        setStrikeImpacts(g, e, { now + e.windup })
      elseif e.kind == "boss" then
        -- Boss starts with exactly one window; subsequent windows are spawned
        -- only after the previous one fully resolves (see strike logic).
        setStrikeImpacts(g, e, { now + e.windup })
      elseif e.kind == "chain" then
        -- 2–4 beats; must be parried sequentially.
        local beats = love.math.random(2, 4)
        local gap = 0.16
        local times = {}
        for i = 1, beats do
          times[i] = now + e.windup + (i - 1) * gap
        end
        e.hp = beats
        e.maxHp = beats
        setStrikeImpacts(g, e, times)
      elseif e.kind == "feint" then
        -- fake impact, then a short re-telegraph, then real impact
        e.phase = "feint"
        e.timer = 0
        e.feintAt = now + math.max(0.08, e.windup - 0.06) -- no damage
        e.realTelegraph = 0.22
        e.realWindup = e.windup
      elseif e.kind == "goblin" then
        setStrikeImpacts(g, e, { now + e.windup })
      end
    end

  elseif e.phase == "feint" then
    -- nothing happens at feintAt except a visual cue; then we telegraph again
    if g.t >= (e.feintAt or 0) then
      e.phase = "telegraph2"
      e.timer = 0
    end

  elseif e.phase == "telegraph2" then
    if e.timer >= (e.realTelegraph or 0.22) then
      local now = g.t
      setStrikeImpacts(g, e, { now + (e.realWindup or e.windup) })
    end

  elseif e.phase == "strike" then
    if not e.impacts then return end

    for i = 1, #e.impacts do
      local imp = e.impacts[i]
      if not imp.resolved then
        if g.t >= imp.t then
          imp.pending = true
        end

        -- Important: never apply damage immediately when an impact becomes due.
        -- Two-phase hit commit:
        -- - At imp.t: mark pending (parryable)
        -- - At imp.t + grace: mark ready
        -- - Next frame (commit delay): resolve into damage if still not parried
        local grace = g:getLateParryGrace(e) or 0
        if imp.pending and (not imp.ready) and g.t >= imp.t + grace then
          imp.ready = true
          imp.readyAt = g.t
        end

        if imp.ready and g.t >= (imp.readyAt or g.t) + (g:getHitCommitDelay() or 0) then
          imp.resolved = true
          if not imp.parried then
            g:onEnemyImpact(e)
          end
        end
      end
    end

    refreshNextImpactIdx(e)

    -- Boss: spawn exactly ONE parry window at a time.
    -- Only create a new window after all current impacts are resolved.
    if e.kind == "boss" and (e.hp or 0) > 0 and (not e.nextImpactIdx) then
      e.bossTimer = (e.bossTimer or 0) + dt
      if e.bossTimer >= (e.bossInterval or 0.55) then
        e.bossTimer = 0
        setStrikeImpacts(g, e, { g.t + e.windup })
      end
    end

    local allDone = true
    for i = 1, #e.impacts do
      if not e.impacts[i].resolved then allDone = false break end
    end
    if allDone then
      if e.kind == "boss" and (e.hp or 0) > 0 then
        -- keep boss alive; it will spawn the next window via bossTimer
      elseif e.kind == "ranged" then
        -- keep firing until removed by other rules
        e.phase = "telegraph"
        e.timer = 0
      elseif e.kind == "goblin" and (e.hp or 0) > 0 then
        -- goblin keeps re-appearing (teleport handled by Combat on parry).
        e.impacts = nil
        e.nextImpactIdx = nil
        e.phase = "telegraph"
        e.timer = 0
      elseif e.kind == "shield" and (e.hp or 0) > 0 then
        -- Shieldbearer persists until its guard is fully broken (2 parries).
        e.impacts = nil
        e.nextImpactIdx = nil
        e.phase = "approach"
        e.timer = 0
      else
        e.phase = "done"
      end
    end
  end
end

function enemy.findNearestImpact(g, enemies)
  local bestE, bestImp, bestAbs = nil, nil, 1e9
  for _, e in ipairs(enemies) do
    if e.phase == "strike" and e.impacts then
      for _, imp in ipairs(e.impacts) do
        if not imp.resolved then
          local dt = g.t - imp.t
          local adt = math.abs(dt)
          if adt < bestAbs then
            bestAbs = adt
            bestE = e
            bestImp = imp
          end
        end
      end
    end
  end
  return bestE, bestImp
end

function enemy.draw(g, e)
  local function pickEnemyImg()
    local img = (g.assets and g.assets.enemy) or nil
    if e.kind == "basic" then img = (g.assets and g.assets.basic) or img end
    if e.kind == "double" then img = (g.assets and g.assets.double) or img end
    if e.kind == "feint" then img = (g.assets and g.assets.feint) or img end
    if e.kind == "heavy" then img = (g.assets and g.assets.heavy) or img end
    if e.kind == "chain" then img = (g.assets and g.assets.chain) or img end
    if e.kind == "ranged" then img = (g.assets and g.assets.ranged) or img end
    if e.kind == "shield" then img = (g.assets and g.assets.shieldbearer) or img end
    if e.kind == "boss" then img = (g.assets and g.assets.boss) or img end
    if e.kind == "goblin" then img = (g.assets and g.assets.goblin) or img end
    return img
  end

  if e.phase == "approach" then
    drawIcon(pickEnemyImg(), e.x, e.y, e.r * 2.6, 1)
    if e.kind == "goblin" then
      love.graphics.setBlendMode("add")
      love.graphics.setColor(0.95, 0.85, 0.35, 0.22)
      love.graphics.circle("fill", e.x, e.y, e.r * 1.65)
      love.graphics.setBlendMode("alpha")
    end
    if e.kind == "shield" and not e.shieldBroken then
      love.graphics.setColor(0.55, 0.90, 1.00, 0.55)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", e.x, e.y, e.r * 1.25)
      love.graphics.setColor(0.55, 0.90, 1.00, 0.16)
      love.graphics.circle("fill", e.x, e.y, e.r * 1.30)
      love.graphics.setLineWidth(1)
    end
    return
  end

  if e.phase == "telegraph" or e.phase == "telegraph2" then
    -- No extra telegraph ring; the strike bullseye rings are the main timing read.
    -- Keep a subtle color shift to show "about to strike".
    drawIcon(pickEnemyImg(), e.x, e.y, e.r * 2.6, 1)
    if e.kind == "shield" and not e.shieldBroken then
      local p = util.clamp(e.timer / math.max(0.001, e.telegraph), 0, 1)
      local a = 0.35 + 0.20 * (0.5 + 0.5 * math.sin((g.t + p) * 10))
      love.graphics.setColor(0.55, 0.90, 1.00, a)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", e.x, e.y, e.r * (1.18 + 0.06 * p))
      love.graphics.setLineWidth(1)
    end
    return
  end

  if e.phase == "feint" then
    -- Feint cue: "fool" scale pop (up then snap down), no extra symbols.
    local t = util.clamp(e.timer / 0.22, 0, 1)
    local pop = math.sin(t * math.pi) -- 0..1..0
    local scaleMul = 1.0 + 0.18 * pop
    local a = 0.85 + 0.15 * pop
    drawIcon(pickEnemyImg(), e.x, e.y, e.r * 2.6, a, scaleMul)
    return
  end

  if e.phase == "strike" then
    -- Best-practice timing telegraph: bullseye rings.
    -- Outer ring = parry window, inner ring = perfect window.
    local nextImp = (e.nextImpactIdx and e.impacts and e.impacts[e.nextImpactIdx]) or nil

    drawIcon(pickEnemyImg(), e.x, e.y, e.r * 2.8, 1)
    if e.kind == "shield" and not e.shieldBroken then
      love.graphics.setColor(0.55, 0.90, 1.00, 0.55)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", e.x, e.y, e.r * 1.22)
      love.graphics.setLineWidth(1)
    end

    if e.kind == "boss" then
      local hp = e.hp or 0
      local mhp = e.maxHp or math.max(1, hp)
      local frac = util.clamp(hp / math.max(1, mhp), 0, 1)
      local bw, bh = 120, 10
      local bx, by = e.x - bw / 2, e.y + e.r + 16
      love.graphics.setColor(0.08, 0.10, 0.16, 0.75)
      love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)
      love.graphics.setColor(0.20, 0.95, 0.55, 0.90)
      love.graphics.rectangle("fill", bx, by, bw * frac, bh, 6, 6)
    end

    if nextImp and (not nextImp.resolved) then
      local parryW = g:currentParryWindowForEnemy(e)
      local perfectW = g:getPerfectWindowForEnemy(e)
      local grace = g:getLateParryGrace(e) or parryW

      local dt = nextImp.t - g.t -- >0 before impact, <=0 after impact
      local a = 0.0
      local rOuter, rInner

      if dt > 0 then
        -- Countdown toward impact.
        local prog = util.clamp(1 - dt / math.max(0.001, e.windup), 0, 1)
        a = 0.15 + 0.55 * prog
        rOuter = util.lerp(92, e.r + 10, prog)
        rInner = util.lerp(70, e.r + 6, prog)
      else
        -- Impact is pending: fade rings out over grace window.
        local t = util.clamp((-dt) / math.max(0.001, grace), 0, 1)
        a = (1 - t) * 0.70
        rOuter = e.r + 10
        rInner = e.r + 6
      end

      -- Outer: parry (slightly different tint for heavy)
      love.graphics.setLineWidth(3)
      if e.kind == "boss" then
        love.graphics.setColor(0.55, 0.85, 1.00, a)
      elseif e.kind == "heavy" then
        love.graphics.setColor(1.00, 0.78, 0.35, a)
      else
        love.graphics.setColor(0.45, 1.00, 0.80, a)
      end
      love.graphics.circle("line", e.x, e.y, rOuter)

      -- Inner: perfect
      local innerA = a * 0.9
      if perfectW <= 0 then innerA = 0 end
      love.graphics.setLineWidth(2)
      love.graphics.setColor(0.95, 0.55, 1.00, innerA)
      love.graphics.circle("line", e.x, e.y, rInner)
      love.graphics.setLineWidth(1)

      -- Note: no extra warning ring here; avoid “double window” visuals.
    end

    return
  end

  if e.phase ~= "done" then
    love.graphics.setColor(0.95, 0.35, 0.20)
    love.graphics.circle("fill", e.x, e.y, e.r)
  end
end

return enemy
