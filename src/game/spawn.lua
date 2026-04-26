local util = require("src.util")
local enemy = require("src.enemy")
local perks = require("src.perks")

local Spawn = {}
Spawn.__index = Spawn

function Spawn.new(game)
  local self = setmetatable({}, Spawn)
  self.game = game
  return self
end

local function defaultRunSeed()
  return os.time()
end

function Spawn:resetRun(seed)
  local g = self.game
  g.run = {
    seed = seed or defaultRunSeed(),
    takenPerks = {},
    fallbackCounter = 0
  }
  g.mode = g.mode or "run" -- "run" | "endless"
  g.runStartMode = g.mode

  love.math.setRandomSeed(g.run.seed)

  g.meta = {
    comboBonus = 0,
    perfectBonus = 0,
    shockwave = 0,
    streakShield = false,
    fatalGuard = 0,
    perkPopupOverride = nil,
    deflectRadiusBonus = 0,
    focusRegenBonus = 0,
    focusDrainMult = 1.0,
    overheatDrainMult = 1.0,
    lifeLeechStacks = 0,
    lifeLeechCharge = 0,
    shieldUsedThisWave = false
  }

  g.dda = { v = 0, target = 0 } -- dynamic difficulty scalar 0..1

  g.player = {
    hp = 3,
    maxHp = 3,
    streak = 0,
    bestStreak = 0,
    score = 0,
    hasParriedOnce = false,

    parryWindowBase = 0.250,
    parryWindowMin = 0.045,
    parryShrinkPerStreak = 0.987,

    perfectWindowCap = 0.050,
    perfectRatio = 0.35,
    cooldown = 0.18,
    cd = 0,
    invuln = 0,
    recovery = 0,

    lastParry = { ok = false, dt = 0, timer = 0, label = "" }
  }
  g.player.heat = 0
  g.player.overheatActive = false
  g.player.focus = 1.0
  g.player.focusActive = false
  g.projectiles = {}

  -- Standard mode uses a Diablo-style Rift progression (0..100%) instead of discrete waves.
  g.wave = 1 -- treated as Rift tier for scaling
  g.riftPoints = 0
  local function expectedDangerForTier(tier)
    tier = math.max(1, tonumber(tier) or 1)
    local danger = {
      basic = 1.0,
      double = 1.15,
      feint = 1.20,
      heavy = 1.35,
      chain = 1.25,
      ranged = 1.25,
      shield = 1.35,
      goblin = 1.75
    }

    -- goblin chance preempts everything else
    local pGob = (tier >= 3) and util.clamp(0.03 + (tier - 3) * 0.002, 0.03, 0.06) or 0

    local function wavg(kinds, weights)
      local s = 0
      for _, w in ipairs(weights) do s = s + w end
      if s <= 0 then return danger.basic end
      local acc = 0
      for i = 1, #kinds do
        local k = kinds[i]
        local w = weights[i] / s
        acc = acc + w * (danger[k] or 1.0)
      end
      return acc
    end

    local baseAvg
    if tier < 2 then
      baseAvg = danger.basic
    elseif tier < 4 then
      baseAvg = wavg({ "basic", "double" }, { 0.75, 0.25 })
    elseif tier < 6 then
      baseAvg = wavg({ "basic", "double", "shield" }, { 0.60, 0.25, 0.15 })
    else
      -- ranged has a flat 1/3 chance
      local pR = 1 / 3
      local restAvg
      if tier < 7 then
        restAvg = wavg({ "basic", "double", "feint", "shield" }, { 0.48, 0.24, 0.16, 0.12 })
      elseif tier < 10 then
        restAvg = wavg({ "basic", "double", "feint", "heavy", "chain", "shield" }, { 0.30, 0.20, 0.16, 0.14, 0.12, 0.08 })
      else
        restAvg = wavg({ "basic", "double", "feint", "heavy", "chain", "shield" }, { 0.26, 0.18, 0.14, 0.12, 0.22, 0.08 })
      end
      baseAvg = pR * danger.ranged + (1 - pR) * restAvg
    end

    return pGob * danger.goblin + (1 - pGob) * baseAvg
  end

  -- Dynamic required: tuned to target ~100 kills per guardian given current spawn weights.
  g.getRiftRequired = function(_g, tier)
    tier = math.max(1, tonumber(tier) or 1)
    local targetKills = 100
    local avg = expectedDangerForTier(tier)
    -- Small tier scaling so very high tiers don't become trivial due to faster kill rates.
    local scale = 1.0 + util.clamp((tier - 1) / 9999, 0, 1) * 0.12
    return math.floor(targetKills * avg * scale + 0.5)
  end

  g.riftRequired = g:getRiftRequired(g.wave)

  -- Endless still uses the old wave-ish auto-perk cadence.
  g.killsThisWave = 0
  g.killsToAdvance = 6
  g.spawnTimer = 0
  g.spawnInterval = 0.85
  g.bossActive = false
  g.pendingBoss = false
  g.bossId = nil
  g.endless = {
    bossTimer = 0,
    nextBossIn = 45,
    bossMinGap = 28
  }

  g.enemies = {}
  g.nextEnemyId = 1

  g.perk = { choices = nil }

  -- FX tables are owned by Game/FX subsystem; ensure tables exist.
  g.fx = g.fx or { particles = {}, rings = {}, bursts = {}, afterimages = {}, deaths = {} }

  g.announce = g.announce or { timer = 0, text = "", sub = "" }
end

function Spawn:startGame(mode, seed)
  local g = self.game
  g.mode = mode or "run"
  self:resetRun(seed or os.time())
  g.state = "playing"

  if g.mode == "endless" then
    g.killsToAdvance = 10
    g.endless.bossTimer = 0
    g.endless.nextBossIn = love.math.random(38, 55)
    g.pendingBoss = false
  end

  if g.mode == "hardcore" then
    g.player.maxHp = 1
    g.player.hp = 1
    g.player.parryWindowBase = 0.190
    g.player.parryWindowMin = 0.032
    g.player.perfectWindowCap = 0.040
  end
end

local function difficultyScale(wave, diffId, modeId, dda)
  local spawn = util.clamp(0.90 - (wave - 1) * 0.05, 0.32, 0.90)
  local speed = 150 + (wave - 1) * 18
  local teleMin = util.clamp(0.55 - (wave - 1) * 0.03, 0.22, 0.55)
  local teleMax = util.clamp(0.95 - (wave - 1) * 0.03, 0.40, 0.95)
  diffId = diffId or "normal"
  if diffId == "easy" then
    spawn = spawn * 1.12
    speed = speed * 0.95
    teleMin = teleMin * 1.12
    teleMax = teleMax * 1.12
  elseif diffId == "hard" then
    spawn = spawn * 0.92
    speed = speed * 1.05
    teleMin = teleMin * 0.92
    teleMax = teleMax * 0.92
  end
  if modeId == "hardcore" then
    spawn = spawn * 0.92
    speed = speed * 1.08
    teleMin = teleMin * 0.82
    teleMax = teleMax * 0.82
  end

  dda = util.clamp(dda or 0, 0, 1)
  if dda > 0 then
    spawn = spawn * (1.0 - 0.12 * dda)
    speed = speed * (1.0 + 0.06 * dda)
    teleMin = teleMin * (1.0 - 0.20 * dda)
    teleMax = teleMax * (1.0 - 0.20 * dda)
  end
  return spawn, speed, teleMin, teleMax
end

local function pickEnemyKindForWave(wave)
  if wave < 2 then return "basic" end
  -- Rare special spawn: teleporting treasure goblin (high reward).
  if wave >= 3 and love.math.random() < util.clamp(0.03 + (wave - 3) * 0.002, 0.03, 0.06) then
    return "goblin"
  end
  if wave < 4 then
    return util.weightedChoice({ "basic", "double" }, { 0.75, 0.25 })
  end
  if wave < 6 then
    -- Introduce a simple durability check unit.
    return util.weightedChoice({ "basic", "double", "shield" }, { 0.60, 0.25, 0.15 })
  end
  if love.math.random() < (1 / 3) then
    return "ranged"
  end

  if wave < 7 then
    return util.weightedChoice({ "basic", "double", "feint", "shield" }, { 0.48, 0.24, 0.16, 0.12 })
  end
  if wave < 10 then
    return util.weightedChoice({ "basic", "double", "feint", "heavy", "chain", "shield" }, { 0.30, 0.20, 0.16, 0.14, 0.12, 0.08 })
  end
  return util.weightedChoice({ "basic", "double", "feint", "heavy", "chain", "shield" }, { 0.26, 0.18, 0.14, 0.12, 0.22, 0.08 })
end

function Spawn:spawnEnemy()
  local g = self.game
  local spawnInt, speed, teleMin, teleMax = difficultyScale(g.wave, (g.settings and g.settings.difficulty) or "normal", g.mode, g:getDda())
  g.spawnInterval = spawnInt

  local side = (love.math.random() < 0.5) and "left" or "right"
  local y = love.math.random(110, g.h - 110)
  local x = (side == "left") and -40 or (g.w + 40)
  local telegraph = love.math.random() * (teleMax - teleMin) + teleMin
  local windup = 0.20

  local kind = pickEnemyKindForWave(g.wave)
  local hp = nil
  if kind == "goblin" then
    hp = util.clamp(3 + math.floor((g.wave - 3) * 0.25), 3, 7)
    -- Make goblin windows snappy and readable.
    telegraph = math.max(0.38, telegraph * 0.75)
    windup = 0.18
  end
  local e = enemy.spawn(kind, {
    id = g.nextEnemyId or 1,
    x = x,
    y = y,
    side = side,
    speed = speed,
    telegraph = telegraph,
    windup = windup,
    hp = hp
  })
  g.nextEnemyId = (g.nextEnemyId or 1) + 1
  table.insert(g.enemies, e)
end

function Spawn:spawnBoss()
  local g = self.game
  g.bossActive = true

  local _, speed = difficultyScale(g.wave, (g.settings and g.settings.difficulty) or "normal", g.mode, g:getDda())
  local e = enemy.spawn("boss", {
    id = g.nextEnemyId or 1,
    x = g.centerX,
    y = 120,
    side = "top",
    speed = speed * 0.65,
    telegraph = g:getBossTelegraph(),
    windup = 0.26,
    hp = 8 + math.floor((g.wave - 5) * 0.4),
    bossInterval = 0.55
  })
  g.nextEnemyId = (g.nextEnemyId or 1) + 1
  table.insert(g.enemies, e)
  g.bossId = e.id

  if g.announce then
    g.announce.timer = 2.0
    g.announce.text = "RIFT GUARDIAN"
    g.announce.sub = ("Seal the gate: %d parries"):format(e.hp or 1)
  end
  g.flash = math.max(g.flash, 0.12)
  g.shake = math.max(g.shake, 0.18)

  -- In Standard, guardian spawn is driven by rift progress, not kill quotas.
end

function Spawn:enterPerkChoice()
  local g = self.game
  g.state = "perk"
  local picked = perks.pickChoices(g, g.pool, 3)
  if #picked < 3 then
    local fill = perks.fallbackChoices(g, 3 - #picked)
    for i = 1, #fill do
      picked[#picked + 1] = fill[i]
    end
  end
  g.perk.choices = picked
end

function Spawn:advanceWaveIfNeeded()
  local g = self.game
  if g.mode ~= "endless" then return end
  if g.killsThisWave >= g.killsToAdvance then
    g.wave = g.wave + 1
    g.killsThisWave = 0
    g.killsToAdvance = math.floor(6 + (g.wave - 1) * 1.5)
    g.meta.shieldUsedThisWave = false
    if g.mode == "endless" then
      g.pendingBoss = false
      g:autoGrantRandomPerk()
    else
      g.bossActive = false
      g.pendingBoss = (g.wave % 5 == 0)
      g.enemies = {}
      g.spawnTimer = 0
      self:enterPerkChoice()
    end
  end
end

return Spawn

