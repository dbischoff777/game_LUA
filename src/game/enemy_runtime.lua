local enemy = require("src.enemy")

local EnemyRuntime = {}
EnemyRuntime.__index = EnemyRuntime

function EnemyRuntime.new(game)
  local self = setmetatable({}, EnemyRuntime)
  self.game = game
  return self
end

function EnemyRuntime:update(dt)
  local g = self.game
  for _, e in ipairs(g.enemies) do
    enemy.update(g, e, dt)
  end

  local alive = {}
  for _, e in ipairs(g.enemies) do
    if e.phase ~= "done" then
      alive[#alive + 1] = e
    end
  end
  g.enemies = alive
end

return EnemyRuntime

