local Viewport = {}
Viewport.__index = Viewport

function Viewport.new(game)
  local self = setmetatable({}, Viewport)
  self.game = game
  return self
end

function Viewport:getWindowSize()
  return love.graphics.getDimensions()
end

function Viewport:getScaleAndOffset()
  local g = self.game
  local ww, wh = self:getWindowSize()
  local sx = ww / g.vw
  local sy = wh / g.vh
  local s = math.min(sx, sy)
  if g.settings and g.settings.pixelPerfect then
    s = math.floor(s)
    if s < 1 then s = 1 end
  end
  local ox = math.floor((ww - g.vw * s) * 0.5 + 0.5)
  local oy = math.floor((wh - g.vh * s) * 0.5 + 0.5)
  return s, ox, oy, ww, wh
end

function Viewport:toVirtual(x, y)
  local s, ox, oy = self:getScaleAndOffset()
  return (x - ox) / s, (y - oy) / s
end

function Viewport:applyWindowMode()
  local g = self.game
  local ww, wh = self:getWindowSize()
  local flags = {
    fullscreen = (g.settings and g.settings.fullscreen) or false,
    fullscreentype = "desktop",
    resizable = true,
    vsync = 1
  }
  if not flags.fullscreen then
    -- Fit window to the user's desktop resolution on boot, while staying windowed.
    local dw, dh = love.window.getDesktopDimensions()
    local targetW = math.floor(dw * 0.88 + 0.5)
    local targetH = math.floor(dh * 0.88 + 0.5)
    -- Keep the game's aspect (virtual res aspect) to avoid stretching.
    local aspect = g.vw / math.max(1, g.vh)
    local wByH = math.floor(targetH * aspect + 0.5)
    local hByW = math.floor(targetW / aspect + 0.5)
    if wByH <= targetW then
      targetW = wByH
    else
      targetH = hByW
    end
    if targetW < 960 then targetW = 960 end
    if targetH < 540 then targetH = 540 end
    love.window.setMode(targetW, targetH, flags)
  else
    love.window.setMode(0, 0, flags)
  end
end

function Viewport:resize(_w, _h)
  -- Nothing to do: scaling is dynamic every frame.
end

return Viewport

