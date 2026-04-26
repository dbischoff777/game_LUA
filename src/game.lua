local util = require("src.util")
local perks = require("src.perks")
local Menu = require("src.menu")
local PostFX = require("src.postfx")
local Settings = require("src.settings")
local Audio = require("src.game.audio")
local MenuController = require("src.game.menu_controller")
local WorldRenderer = require("src.game.world_renderer")
local Viewport = require("src.game.viewport")
local Assets = require("src.game.assets")
local Projectiles = require("src.game.projectiles")
local DDA = require("src.game.dda")
local Resources = require("src.game.resources")
local SpawnRuntime = require("src.game.spawn_runtime")
local EnemyRuntime = require("src.game.enemy_runtime")
local FX = require("src.game.fx")
local Combat = require("src.game.combat")
local Spawn = require("src.game.spawn")
local UI = require("src.game.ui")

local Game = {}
Game.__index = Game

function Game.new(w, h, preloaded)
  local g = setmetatable({}, Game)
  g.vw, g.vh = w, h -- virtual resolution
  g.w, g.h = w, h
  g.centerX, g.centerY = w * 0.5, h * 0.5
  g.postfx = PostFX.new(w, h)

  g.pool = perks.defaultPool()
  g.rarity = perks.rarityMeta()

  g:boot(preloaded)
  return g
end

function Game:boot(preloaded)
  self.t = 0
  self.state = "menu" -- menu | playing | perk | dead | paused
  self.freeze = 0
  self.shake = 0
  self.flash = 0

  self.menu = Menu.new("title")
  self.settings = Settings.load()
  self.settings.kills = self.settings.kills or {}
  self.settingsDirty = false
  self.settingsSaveCooldown = 0
  self.shakeMult = (self.settings.screenshake and 1.0) or 0.0
  if self.postfx then self.postfx.enabled = (self.settings.postfx == true) end
  self.menuReturnKind = "title"
  self.optionsReturnKind = "title"
  self.quitReturnKind = "title"
  self.awaitBind = nil -- { key = "keyParry"|"keyPause" }
  self.seedInput = { active = false, text = "" }
  self.tutorial = { active = false, step = 1, seenHeat = false, usedFocus = false, deflected = false, parried = false }
  self.compendiumTab = self.compendiumTab or "player"
  self.viewport = Viewport.new(self)
  self:applyWindowMode()

  self.assets = (preloaded and preloaded.icons) or Assets.loadIcons()
  self.sfx = (preloaded and preloaded.sfx) or Assets.loadSfx()

  -- persistent bests across runs
  self.bests = self.bests or { bestStreak = 0, bestScore = 0 }

  -- Core gameplay subsystems (must exist before resetRun/startGame).
  self.fxSys = FX.new(self)
  self.combat = Combat.new(self)
  self.spawnSys = Spawn.new(self)
  self.ui = UI.new(self)
  self.menuCtl = MenuController.new(self)

  self:resetRun(os.time())
  self:goToMenu("title")

  self.music = (preloaded and preloaded.music) or Assets.loadMusic(self.music)
  self.audio = Audio.new(self)
  self.projectilesSys = Projectiles.new(self)
  self.ddaSys = DDA.new(self)
  self.resourcesSys = Resources.new(self)
  self.spawnRuntime = SpawnRuntime.new(self)
  self.enemyRuntime = EnemyRuntime.new(self)
  self:applyAudioSettings()
end

function Game:applyAudioSettings()
  if self.audio and self.audio.applySettings then
    return self.audio:applySettings()
  end
end

function Game:duckMusic(mul, dur)
  if self.audio and self.audio.duckMusic then
    return self.audio:duckMusic(mul, dur)
  end
end

function Game:refreshMusicVolume()
  if self.audio and self.audio.refreshMusicVolume then
    return self.audio:refreshMusicVolume()
  end
end

function Game:playSfx(name, vol, pitch)
  if self.audio and self.audio.playSfx then
    return self.audio:playSfx(name, vol, pitch)
  end
end

function Game:getWindowSize()
  if self.viewport and self.viewport.getWindowSize then
    return self.viewport:getWindowSize()
  end
  return love.graphics.getDimensions()
end

function Game:getScaleAndOffset()
  if self.viewport and self.viewport.getScaleAndOffset then
    return self.viewport:getScaleAndOffset()
  end
  local ww, wh = self:getWindowSize()
  local sx = ww / self.vw
  local sy = wh / self.vh
  local s = math.min(sx, sy)
  local ox = math.floor((ww - self.vw * s) * 0.5 + 0.5)
  local oy = math.floor((wh - self.vh * s) * 0.5 + 0.5)
  return s, ox, oy, ww, wh
end

function Game:toVirtual(x, y)
  if self.viewport and self.viewport.toVirtual then
    return self.viewport:toVirtual(x, y)
  end
  local s, ox, oy = self:getScaleAndOffset()
  return (x - ox) / s, (y - oy) / s
end

function Game:applyWindowMode()
  if self.viewport and self.viewport.applyWindowMode then
    return self.viewport:applyWindowMode()
  end
end

function Game:prettyKey(k)
  if not k or k == "" then return "" end
  local map = { ["space"] = "SPACE", ["escape"] = "ESC", ["return"] = "ENTER", ["kpenter"] = "ENTER" }
  if map[k] then return map[k] end
  return tostring(k):upper()
end

function Game:xpNeedForLevel(level)
  -- Quadratic XP curve: smooth early, slows down later without a hard cap.
  -- XP needed to advance from `level` -> `level+1`.
  level = math.max(1, math.min(999, tonumber(level) or 1))
  return math.floor(20 + 10 * level + 5 * level * level)
end

function Game:recalcLevelFromXp()
  if not self.settings then return 1, 0, self:xpNeedForLevel(1) end
  local xpTotal = math.max(0, tonumber(self.settings.xp) or 0)
  local level = 1
  local remaining = xpTotal
  while true do
    local need = self:xpNeedForLevel(level)
    if remaining < need then
      return level, remaining, need
    end
    remaining = remaining - need
    level = level + 1
    if level > 999 then
      return 999, remaining, self:xpNeedForLevel(999)
    end
  end
end

function Game:resetRun(seed)
  if self.spawnSys and self.spawnSys.resetRun then
    return self.spawnSys:resetRun(seed)
  end
end

function Game:spawnProjectile(fromX, fromY, speed, radius, shooterId)
  if self.projectilesSys and self.projectilesSys.spawn then
    return self.projectilesSys:spawn(fromX, fromY, speed, radius, shooterId)
  end
end

function Game:getDeflectRadius()
  if self.projectilesSys and self.projectilesSys.getDeflectRadius then
    return self.projectilesSys:getDeflectRadius()
  end
  return 58
end

function Game:findEnemyById(id)
  if not id then return nil end
  for _, e in ipairs(self.enemies or {}) do
    if e and e.id == id and e.phase ~= "done" then
      return e
    end
  end
  return nil
end

function Game:killEnemy(e)
  if not e or e.phase == "done" then return end
  self:spawnEnemyDeathJuice(e)
  e.phase = "done"

  self.foesSlain = (self.foesSlain or 0) + 1
  if self.mode == "endless" and self.endless then
    self.endless.foesSinceBoss = (self.endless.foesSinceBoss or 0) + 1
  end

  -- Life leech: earn charge on kills (heal when it fills).
  self:addLifeLeech(0.34)

  local function isRiftMode()
    return self.mode ~= "endless"
  end

  -- Rift Guardian kill: advance to the next tier (Standard/Hardcore/Seeded).
  if e.kind == "boss" and isRiftMode() then
    self.bossActive = false
    self.bossId = nil
    self.pendingBoss = false

    self.wave = math.min(9999, (self.wave or 1) + 1)
    self.riftPoints = 0
    self.riftRequired = (self.getRiftRequired and self:getRiftRequired(self.wave)) or (100 * 1.25)
    if self.meta then
      self.meta.shieldUsedThisWave = false
    end

    -- Clear arena and give a perk between rifts.
    self.enemies = {}
    self.projectiles = {}
    self.spawnTimer = 0
    self.spawnInterval = 0.85

    if self.announce then
      self.announce.timer = 2.0
      self.announce.text = "GATE SEALED"
      self.announce.sub = ("Descending: Tier %d"):format(self.wave)
    end
    self.flash = math.max(self.flash or 0, 0.12)
    self.shake = math.max(self.shake or 0, 0.12)

    self:enterPerkChoice()
    return
  end

  -- Endless guardian kill: allow future guardian spawns.
  if e.kind == "boss" and self.mode == "endless" then
    self.bossActive = false
    self.bossId = nil
    if self.endless then
      self.endless.bossTimer = 0
      self.endless.nextBossIn = love.math.random(38, 60)
      self.endless.nextBossKills = love.math.random(45, 75)
      self.endless.foesSinceBoss = 0
    end
  end

  if e.kind == "goblin" then
    local bonus = 220 + (self.wave or 1) * 35
    local add = self:addScore(bonus)
    self.player.lastPerkTimer = 1.1
    self.player.lastPerkText = ("TREASURE +%d"):format(add)
    self.flash = math.max(self.flash or 0, 0.10)
    self.shake = math.max(self.shake or 0, 0.12)
  end

  -- Lightweight meta-progression (shown in Compendium).
  if self.settings then
    self.settings.xp = (self.settings.xp or 0) + 1
    local newLevel = self:recalcLevelFromXp()
    local oldLevel = math.max(1, tonumber(self.settings.level) or 1)
    self.settings.level = math.min(999, newLevel)
    if newLevel > oldLevel then
      self:playSfx("blip", 0.7, 1.08)
      Settings.save(self.settings)
    end

    local kind = (e and e.kind) or "unknown"
    self.settings.kills = self.settings.kills or {}
    self.settings.kills[kind] = (self.settings.kills[kind] or 0) + 1
    self.settingsDirty = true
    self.settingsSaveCooldown = 2.0
  end

  if self.mode == "endless" then
    self.killsThisWave = (self.killsThisWave or 0) + 1
    self:advanceWaveIfNeeded()
    return
  end

  -- Standard: build rift progress based on enemy danger. When full, spawn guardian.
  if isRiftMode() and (not self.bossActive) then
    local req = math.max(1, tonumber(self.riftRequired) or 18)
    local kind = (e and e.kind) or "basic"
    local danger = ({
      basic = 1.0,
      double = 1.15,
      feint = 1.20,
      heavy = 1.35,
      chain = 1.25,
      ranged = 1.25,
      shield = 1.35,
      goblin = 1.75
    })[kind] or 1.0

    -- Progress contribution: tuned for ~100 kills per guardian on average.
    local add = 1.0 * danger
    self.riftPoints = (self.riftPoints or 0) + add

    if (self.riftPoints or 0) >= req then
      self.riftPoints = req
      self.pendingBoss = true
      -- Stop regular spawns; guardian is next.
      self.spawnInterval = 999
      if self.announce then
        self.announce.timer = 2.0
        self.announce.text = "RIFT SURGES"
        self.announce.sub = "A guardian answers your defiance."
      end
      self.flash = math.max(self.flash or 0, 0.10)
      self.shake = math.max(self.shake or 0, 0.10)
    end
  end
end

function Game:startGame(mode, seed)
  if self.spawnSys and self.spawnSys.startGame then
    return self.spawnSys:startGame(mode, seed)
  end
end

function Game:difficultyLabel()
  local d = (self.settings and self.settings.difficulty) or "normal"
  if d == "easy" then return "EASY" end
  if d == "hard" then return "HARD" end
  return "NORMAL"
end

function Game:getDda()
  return util.clamp((self.dda and self.dda.v) or 0, 0, 1)
end

function Game:getHeat()
  return util.clamp((self.player and self.player.heat) or 0, 0, 1)
end

function Game:isOverheated()
  return (self.player and self.player.overheatActive) == true
end

function Game:getComboStep()
  return 5
end

function Game:getComboMult()
  local streak = (self.player and self.player.streak) or 0
  -- Streak multiplier curve (arcade-style):
  -- - fast early growth so players feel it quickly
  -- - diminishing returns via a soft cap to keep leaderboards sane
  -- Tiers are displayed as a simple rank (HUD), and mistakes reset streak elsewhere.
  local step = self:getComboStep() -- every N streak = next tier
  local perStep = 0.10  -- +0.10x per tier
  local cap = 2.50

  local tiers = math.floor(math.max(0, streak) / step)
  local mult = math.min(cap, 1.0 + tiers * perStep)
  local prog = (streak % step) / step

  local ranks = { "D", "C", "B", "A", "S", "SS", "SSS" }
  local rank = ranks[math.min(#ranks, 1 + math.floor(tiers / 3))] or "D"

  return mult, prog, tiers, rank
end

function Game:addScore(base)
  if not self.player then return 0 end
  base = math.floor(tonumber(base) or 0)
  if base <= 0 then return 0 end
  local mult = self:getComboMult()
  local add = math.max(1, math.floor(base * mult + 0.5))
  self.player.score = (self.player.score or 0) + add
  return add
end

function Game:addLifeLeech(charge)
  if not (self.player and self.meta) then return end
  local stacks = tonumber(self.meta.lifeLeechStacks) or 0
  if stacks <= 0 then return end
  if (self.player.hp or 0) >= (self.player.maxHp or 0) then return end
  charge = tonumber(charge) or 0
  if charge <= 0 then return end

  self.meta.lifeLeechCharge = (self.meta.lifeLeechCharge or 0) + charge * (1.0 + 0.35 * math.max(0, stacks - 1))
  while (self.meta.lifeLeechCharge or 0) >= 1.0 and (self.player.hp or 0) < (self.player.maxHp or 0) do
    self.meta.lifeLeechCharge = (self.meta.lifeLeechCharge or 0) - 1.0
    self.player.hp = math.min(self.player.maxHp, (self.player.hp or 0) + 1)
    -- Reuse the perk announcement style popup.
    self.player.lastPerkTimer = math.max(self.player.lastPerkTimer or 0, 0.65)
    self.player.lastPerkText = "LEECH +1"
    self:playSfx("blip", 0.60, 1.15)
    self.flash = math.max(self.flash or 0, 0.06)
  end
end

function Game:getEnemySpeedMult()
  -- Overheat buff: once heat hits full, enemies are buffed while it drains.
  return self:isOverheated() and 1.12 or 1.0
end

function Game:getParryDifficultyMult()
  local d = (self.settings and self.settings.difficulty) or "normal"
  local m = 1.0
  if d == "easy" then m = 1.06 end
  if d == "hard" then m = 0.94 end
  if self.mode == "hardcore" then m = m * 0.90 end
  m = m * (1.0 - 0.18 * self:getDda())
  -- Overheat tightens timing (enemy buff window).
  if self:isOverheated() then
    m = m * 0.90
  end
  -- Focus temporarily widens window (hold Shift).
  if self.player and self.player.focusActive then
    m = m * 1.22
  end
  return util.clamp(m, 0.70, 1.20)
end

function Game:getBossTelegraph()
  local d = (self.settings and self.settings.difficulty) or "normal"
  local m = 1.0
  if d == "easy" then m = 1.12 end
  if d == "hard" then m = 0.92 end
  if self.mode == "hardcore" then m = m * 0.82 end
  m = m * (1.0 - 0.22 * self:getDda())
  if self:isOverheated() then
    m = m * 0.90
  end
  return util.clamp(0.90 * m, 0.42, 1.20)
end

function Game:grantPerk(perkDef)
  if not perkDef then return end
  -- Allow perk apply() to override the popup text (e.g. conditional perks).
  self.meta.perkPopupOverride = nil
  perkDef.apply(self)
  if self.mode == "hardcore" then
    -- Hardcore rule: always 1 life.
    self.player.maxHp = 1
    self.player.hp = math.min(self.player.hp or 1, 1)
  end
  -- only mark taken for non-stackable perks
  if perkDef.stackable ~= true then
    self.run.takenPerks[perkDef.id] = true
  end

  -- Minimal popups: only meaningful events.
  self.player.lastParry.ok = true
  self.player.lastParry.dt = 999
  self.player.lastParry.timer = 0
  self.player.lastParry.label = ""

  self.player.lastPerkTimer = 1.35
  self.player.lastPerkText = self.meta.perkPopupOverride or ("Perk gained: %s"):format(perkDef.name or perkDef.id)
end

function Game:autoGrantRandomPerk()
  local picked = perks.pickChoices(self, self.pool, 1)
  local p = picked[1]
  if not p then
    local fill = perks.fallbackChoices(self, 1)
    p = fill[1]
  end
  if not p then return end
  self:playSfx("blip", 0.65, 1.0)
  self:grantPerk(p)
end

function Game:currentParryWindowForEnemy(e)
  if self.combat and self.combat.currentParryWindowForEnemy then
    return self.combat:currentParryWindowForEnemy(e)
  end
  return 0.12
end

function Game:getLateParryGrace(e)
  if self.combat and self.combat.getLateParryGrace then
    return self.combat:getLateParryGrace(e)
  end
  return self:currentParryWindowForEnemy(e)
end

function Game:getHitCommitDelay()
  if self.combat and self.combat.getHitCommitDelay then
    return self.combat:getHitCommitDelay()
  end
  return 1 / 60
end

function Game:getPerfectWindowForEnemy(e)
  if self.combat and self.combat.getPerfectWindowForEnemy then
    return self.combat:getPerfectWindowForEnemy(e)
  end
  return 0
end

function Game:addScoreForParry(dtFromImpact, parryWindowUsed)
  if self.combat and self.combat.addScoreForParry then
    return self.combat:addScoreForParry(dtFromImpact, parryWindowUsed)
  end
  return false
end

function Game:playerTakeHit()
  if self.combat and self.combat.playerTakeHit then
    return self.combat:playerTakeHit()
  end
end

function Game:spawnParticles(x, y, col, count, speedMin, speedMax, lifeMin, lifeMax, sizeMin, sizeMax)
  if self.fxSys and self.fxSys.spawnParticles then
    return self.fxSys:spawnParticles(x, y, col, count, speedMin, speedMax, lifeMin, lifeMax, sizeMin, sizeMax)
  end
end

function Game:spawnRing(x, y, col, r0, r1, life)
  if self.fxSys and self.fxSys.spawnRing then
    return self.fxSys:spawnRing(x, y, col, r0, r1, life)
  end
end

function Game:spawnEnemyDeathJuice(e)
  if self.fxSys and self.fxSys.spawnEnemyDeathJuice then
    return self.fxSys:spawnEnemyDeathJuice(e)
  end
end

function Game:spawnParryBurst(x, y, perfect)
  if self.fxSys and self.fxSys.spawnParryBurst then
    return self.fxSys:spawnParryBurst(x, y, perfect)
  end
end

function Game:onEnemyImpact(_e)
  local e = _e
  if e and e.kind == "chain" then
    -- chain rule: one failure breaks the whole sequence
    for _, imp in ipairs(e.impacts or {}) do
      imp.resolved = true
    end
    self:killEnemy(e)
  elseif e and e.kind == "goblin" then
    -- Goblin: if it lands a hit, it escapes (no treasure).
    for _, imp in ipairs(e.impacts or {}) do
      imp.resolved = true
    end
    e.phase = "done"
    self.player.lastParry.ok = true
    self.player.lastParry.dt = 0
    self.player.lastParry.timer = 0.8
    self.player.lastParry.label = "ESCAPED!"
  end
  self:playerTakeHit()
end

function Game:spawnEnemy()
  if self.spawnSys and self.spawnSys.spawnEnemy then
    return self.spawnSys:spawnEnemy()
  end
end

function Game:spawnBoss()
  if self.spawnSys and self.spawnSys.spawnBoss then
    return self.spawnSys:spawnBoss()
  end
end

function Game:enterPerkChoice()
  if self.spawnSys and self.spawnSys.enterPerkChoice then
    return self.spawnSys:enterPerkChoice()
  end
end

function Game:advanceWaveIfNeeded()
  if self.spawnSys and self.spawnSys.advanceWaveIfNeeded then
    return self.spawnSys:advanceWaveIfNeeded()
  end
end

function Game:tryShockwave(x, y)
  local stacks = self.meta.shockwave or 0
  if stacks <= 0 then return 0 end
  if love.math.random() > (0.18 + 0.10 * stacks) then return 0 end

  local radius = 80 + 25 * stacks
  local toKill = {}
  for _, e in ipairs(self.enemies) do
    if e and e.phase ~= "done" then
      local dx, dy = e.x - x, e.y - y
      if (dx * dx + dy * dy) <= radius * radius then
        -- "pop" only enemies that are not already mid-strike impact resolution
        if e.phase ~= "strike" then
          toKill[#toKill + 1] = e
        end
      end
    end
  end
  for _, e in ipairs(toKill) do
    self:killEnemy(e)
  end
  local killed = #toKill

  if killed > 0 then
    self.flash = math.max(self.flash, 0.10)
    self.shake = math.max(self.shake, 0.12)
    self.freeze = math.max(self.freeze, 0.02)
    self:addScore(5 * killed)
    self.killsThisWave = self.killsThisWave + killed
    self:advanceWaveIfNeeded()
  end

  return killed
end

function Game:onSuccessfulParry(e, dtFromImpact)
  if self.combat and self.combat.onSuccessfulParry then
    return self.combat:onSuccessfulParry(e, dtFromImpact)
  end
end

function Game:onFailedParry(dtFromImpact)
  if self.combat and self.combat.onFailedParry then
    return self.combat:onFailedParry(dtFromImpact)
  end
end

function Game:attemptParry()
  if self.combat and self.combat.attemptParry then
    return self.combat:attemptParry()
  end
end

function Game:pickPerk(index)
  if self.state ~= "perk" then return end
  local c = self.perk.choices and self.perk.choices[index]
  if not c then return end
  self:playSfx("blip", 0.7, 1.0)
  self:grantPerk(c)
  self.state = "playing"

  self.flash = math.max(self.flash, 0.10)
  self.shake = math.max(self.shake, 0.08)
end

function Game:goToMenu(kind)
  if self.menuCtl and self.menuCtl.goToMenu then
    return self.menuCtl:goToMenu(kind)
  end
end

function Game:startRun(seed)
  self:startGame("run", seed or os.time())
end

function Game:startEndless(seed)
  self:startGame("endless", seed or os.time())
end

function Game:togglePause()
  if self.state == "playing" then
    self:goToMenu("pause")
  elseif self.state == "paused" then
    self.state = "playing"
  end
end

function Game:activateMenuAction(action)
  if self.menuCtl and self.menuCtl.activateMenuAction then
    return self.menuCtl:activateMenuAction(action)
  end
end

function Game:keypressed(key)
  if self.menuCtl and self.menuCtl.keypressed then
    return self.menuCtl:keypressed(key)
  end
end

function Game:mousepressed(x, y, button)
  if self.menuCtl and self.menuCtl.mousepressed then
    return self.menuCtl:mousepressed(x, y, button)
  end
end

function Game:mousereleased(_x, _y, button)
  if self.menuCtl and self.menuCtl.mousereleased then
    return self.menuCtl:mousereleased(_x, _y, button)
  end
end

function Game:mousemoved(x, y, _dx, _dy)
  if self.menuCtl and self.menuCtl.mousemoved then
    return self.menuCtl:mousemoved(x, y, _dx, _dy)
  end
end

function Game:wheelmoved(_dx, dy)
  if self.menuCtl and self.menuCtl.wheelmoved then
    return self.menuCtl:wheelmoved(_dx, dy)
  end
end

function Game:update(dt)
  -- Smooth GC during menu navigation to avoid small hitching.
  if self.state == "menu" then
    collectgarbage("step", 1)
  end
  if self.freeze > 0 then
    self.freeze = math.max(0, self.freeze - dt)
    return
  end

  -- World clock (drives enemy strike timings + ring shrink).
  -- When Focus is active, we slow the world clock noticeably.
  local worldDtForClock = dt
  if self.state == "playing" and self.player and self.player.focusActive then
    worldDtForClock = dt * 0.55
  end

  self.t = self.t + worldDtForClock
  if self.postfx then self.postfx:update(dt) end

  if self.audio and self.audio.update then
    self.audio:update(dt)
  end

  self.flash = math.max(0, self.flash - dt)
  self.shake = math.max(0, self.shake - dt)
  if self.player then
    self.player.cd = math.max(0, (self.player.cd or 0) - dt)
    self.player.invuln = math.max(0, (self.player.invuln or 0) - dt)
    self.player.recovery = math.max(0, (self.player.recovery or 0) - dt)
    if self.player.lastParry then
      self.player.lastParry.timer = math.max(0, (self.player.lastParry.timer or 0) - dt)
    end
    self.player.lastPerkTimer = math.max(0, (self.player.lastPerkTimer or 0) - dt)
  end
  if self.announce then
    self.announce.timer = math.max(0, (self.announce.timer or 0) - dt)
  end

  if self.settingsDirty then
    self.settingsSaveCooldown = math.max(0, (self.settingsSaveCooldown or 0) - dt)
    if self.settingsSaveCooldown <= 0 then
      Settings.save(self.settings)
      self.settingsDirty = false
    end
  end

  if self.state == "menu" or self.state == "paused" or self.state == "dead" then
    self.menu:update(dt)
    return
  end

  if self.state ~= "playing" then return end

  -- Boss spawn is handled deterministically after perk selection via `pendingBoss`.

  -- Focus "bullet time": slow the world noticeably to make parrying easier.
  -- Important: keep resource drain on real time to avoid exploiting slow-time.
  local worldDt = worldDtForClock

  if self.fxSys and self.fxSys.update then
    self.fxSys:update(worldDt)
  end

  if self.ddaSys and self.ddaSys.update then self.ddaSys:update(dt) end
  if self.resourcesSys and self.resourcesSys.update then self.resourcesSys:update(dt) end

  if self.projectilesSys and self.projectilesSys.update then
    self.projectilesSys:update(worldDt)
  end

  if self.spawnRuntime and self.spawnRuntime.update then self.spawnRuntime:update(worldDt) end
  if self.enemyRuntime and self.enemyRuntime.update then self.enemyRuntime:update(worldDt) end
end

function Game:updateUiFonts(scale)
  if self.ui and self.ui.updateFonts then
    return self.ui:updateFonts(scale)
  end
end

function Game:drawUI(scale, ox, oy, ww, wh)
  if self.ui and self.ui.draw then
    return self.ui:draw(scale, ox, oy, ww, wh)
  end
end

function Game:drawScene()
  self.world = self.world or WorldRenderer.new(self)
  return self.world:draw()
end

function Game:draw()
  local s, ox, oy, ww, wh = self:getScaleAndOffset()

  -- letterbox background
  love.graphics.setColor(0.04, 0.045, 0.06, 1)
  love.graphics.rectangle("fill", 0, 0, ww, wh)

  -- World pass (render at virtual res, then scale to window).
  -- Keep menus/UI out of the scaled canvas to avoid blurry text.
  if self.state ~= "menu" and self.postfx then
    self.postfx:begin()
    self:drawScene()
    self.postfx:draw(ox, oy, s)
  else
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(s, s)
    self:drawScene()
    love.graphics.pop()
  end

  -- Native-pixel UI pass (sharp text, aligned to game area)
  self:drawUI(s, ox, oy, ww, wh)
  if self.uiFonts and self.uiFonts.normal then
    love.graphics.setFont(self.uiFonts.normal)
  end

  -- Announcement banner (after pop: stable position, no shake)
  if self.announce and (self.announce.timer or 0) > 0 and self.state ~= "menu" then
    local total = 2.0
    local t = self.announce.timer
    local inA = util.clamp((total - t) / 0.20, 0, 1)
    local outA = util.clamp(t / 0.35, 0, 1)
    local a = math.min(inA, outA)

    local bw, bh = ww * 0.72, 86
    local bx, by = (ww - bw) * 0.5, 92
    love.graphics.setColor(0.08, 0.10, 0.16, 0.82 * a)
    love.graphics.rectangle("fill", bx, by, bw, bh, 16, 16)
    love.graphics.setColor(0.55, 0.85, 1.00, 0.45 * a)
    love.graphics.rectangle("line", bx, by, bw, bh, 16, 16)

    love.graphics.setColor(0.95, 0.85, 0.35, a)
    local f = love.graphics.getFont()
    local text = self.announce.text or ""
    local tw = f:getWidth(text)
    love.graphics.print(text, (ww - tw) * 0.5, by + 14)

    local sub = self.announce.sub or ""
    if sub ~= "" then
      love.graphics.setColor(0.86, 0.90, 0.96, 0.92 * a)
      local sw = f:getWidth(sub)
      love.graphics.print(sub, (ww - sw) * 0.5, by + 56)
    end
  end

  if self.state == "menu" then
    local sub = (self.menuCtl and self.menuCtl.getMenuSubtitle) and self.menuCtl:getMenuSubtitle()
      or ("Best score: %d   Best streak: %d"):format(self.bests.bestScore or 0, self.bests.bestStreak or 0)
    self.menu:draw(ww, wh, "ONE-BUTTON PARRY", sub)

    if self.menu and self.menu.kind == "howto" then
      if self.ui and self.ui.drawHowTo then
        self.ui:drawHowTo(ww, wh)
      end
    end
    if self.menu and self.menu.kind == "compendium" then
      if self.ui and self.ui.drawCompendium then
        self.ui:drawCompendium(ww, wh)
      end
    end
  elseif self.state == "paused" then
    local sub = ("Wave %d   Score %d"):format(self.wave, self.player.score)
    self.menu:draw(ww, wh, "PAUSED", sub)
  elseif self.state == "dead" then
    local sub = ("Run score: %d   Best score: %d"):format(self.player.score or 0, self.bests.bestScore or 0)
    self.menu:draw(ww, wh, "YOU DIED", sub)
  end
end

return Game
