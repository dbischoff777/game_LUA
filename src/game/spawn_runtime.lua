local SpawnRuntime = {}
SpawnRuntime.__index = SpawnRuntime

function SpawnRuntime.new(game)
  local self = setmetatable({}, SpawnRuntime)
  self.game = game
  return self
end

function SpawnRuntime:update(dt)
  local g = self.game

  -- Standard mode: spawn the Rift Guardian once progress is full.
  if g.mode ~= "endless" and g.pendingBoss and (not g.bossActive) then
    g.pendingBoss = false
    g:spawnBoss()
  end

  g.spawnTimer = (g.spawnTimer or 0) + dt
  if g.spawnTimer >= (g.spawnInterval or 0.85) then
    g.spawnTimer = g.spawnTimer - (g.spawnInterval or 0.85)
    g:spawnEnemy()
  end

  if g.mode == "endless" then
    g.endless.bossTimer = (g.endless.bossTimer or 0) + dt
    local byTime = (not g.bossActive) and g.endless.bossTimer >= (g.endless.nextBossIn or 45)
    local byKills = (not g.bossActive) and (g.endless.foesSinceBoss or 0) >= (g.endless.nextBossKills or 55)
    if byTime or byKills then
      g.endless.bossTimer = 0
      g.endless.nextBossIn = love.math.random(38, 60)
      g.endless.nextBossKills = love.math.random(45, 75)
      g.endless.foesSinceBoss = 0
      g:spawnBoss()
    end
  end
end

return SpawnRuntime

