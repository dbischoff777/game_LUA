local util = require("src.util")

local DDA = {}
DDA.__index = DDA

function DDA.new(game)
  local self = setmetatable({}, DDA)
  self.game = game
  return self
end

function DDA:update(dt)
  local g = self.game
  if not g.dda then return end
  local streak = g.player.streak or 0
  local streakTarget = util.clamp((streak - 1) / 18, 0, 1) * 0.70
  g.dda.target = util.clamp(math.max(g.dda.target or 0, streakTarget), 0, 1)
  g.dda.target = util.clamp((g.dda.target or 0) - dt * 0.015, 0, 1)
  g.dda.v = util.lerp(g.dda.v or 0, g.dda.target or 0, util.clamp(dt * 0.85, 0, 1))
end

return DDA

