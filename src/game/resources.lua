local util = require("src.util")

local Resources = {}
Resources.__index = Resources

function Resources.new(game)
  local self = setmetatable({}, Resources)
  self.game = game
  return self
end

function Resources:update(dt)
  local g = self.game
  if not g.player then return end

  g.player.heatFlash = math.max(0, (g.player.heatFlash or 0) - dt)
  g.player.focusFlash = math.max(0, (g.player.focusFlash or 0) - dt)
  g.player.overheatFlash = math.max(0, (g.player.overheatFlash or 0) - dt)

  -- Focus (hold Shift): temporary window widen for clutch saves.
  local focusKey = (g.settings and g.settings.keyFocus) or "lshift"
  local down = love.keyboard.isDown(focusKey)
  local focus0 = g.player.focus or 0
  local focus = focus0
  local regenBonus = (g.meta and g.meta.focusRegenBonus) or 0
  local drainMult = (g.meta and g.meta.focusDrainMult) or 1.0
  if down and focus > 0.02 then
    g.player.focusActive = true
    focus = focus - dt * 0.30 * drainMult
  else
    g.player.focusActive = false
    focus = focus + dt * (0.06 + regenBonus)
  end
  g.player.focus = util.clamp(focus, 0, 1)
  if g.player.focus < focus0 - 1e-4 then
    g.player.focusFlash = math.max(g.player.focusFlash or 0, 0.06)
  end

  -- Heat cycle:
  -- - builds up from parry/perfect (see Combat)
  -- - once full, "overheat" buffs enemies and heat drains back to 0
  local heat = g.player.heat or 0
  if g.player.overheatActive then
    local mult = (g.meta and g.meta.overheatDrainMult) or 1.0
    heat = heat - dt * 0.18 * mult
    if heat <= 0 then
      heat = 0
      g.player.overheatActive = false
    end
    g.player.heat = util.clamp(heat, 0, 1)
  else
    g.player.heat = util.clamp(heat, 0, 1)
  end
end

return Resources

