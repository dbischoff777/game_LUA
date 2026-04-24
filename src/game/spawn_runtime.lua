local SpawnRuntime = {}
SpawnRuntime.__index = SpawnRuntime

function SpawnRuntime.new(game)
  local self = setmetatable({}, SpawnRuntime)
  self.game = game
  return self
end

function SpawnRuntime:update(dt)
  local g = self.game

  g.spawnTimer = (g.spawnTimer or 0) + dt
  if g.spawnTimer >= (g.spawnInterval or 0.85) then
    g.spawnTimer = g.spawnTimer - (g.spawnInterval or 0.85)
    g:spawnEnemy()
  end

  if g.mode == "endless" then
    g.endless.bossTimer = (g.endless.bossTimer or 0) + dt
    if (not g.bossActive) and g.endless.bossTimer >= (g.endless.nextBossIn or 45) then
      g.endless.bossTimer = 0
      g.endless.nextBossIn = love.math.random(38, 60)
      g:spawnBoss()
    end
  end
end

return SpawnRuntime

