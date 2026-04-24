local Game = require("src.game")
local Loader = require("src.loader")

local W, H = 960, 540
local app = nil

function love.load()
  -- Smooth out occasional GC spikes (common source of tiny hitches on screen/menu switches).
  ---@diagnostic disable-next-line: param-type-mismatch
  collectgarbage("setpause", 120)
  ---@diagnostic disable-next-line: param-type-mismatch
  collectgarbage("setstepmul", 250)

  love.graphics.setBackgroundColor(0.06, 0.07, 0.09)
  app = Loader.new(W, H, function(preloaded)
    app = Game.new(W, H, preloaded)
  end)
end

function love.keypressed(key)
  if app and app.keypressed then
    app:keypressed(key)
  end
end

function love.mousepressed(x, y, button)
  if app and app.mousepressed then
    app:mousepressed(x, y, button)
  end
end

function love.mousemoved(x, y, dx, dy)
  if app and app.mousemoved then
    app:mousemoved(x, y, dx, dy)
  end
end

function love.mousereleased(x, y, button)
  if app and app.mousereleased then
    app:mousereleased(x, y, button)
  end
end

function love.wheelmoved(dx, dy)
  if app and app.wheelmoved then
    app:wheelmoved(dx, dy)
  end
end

function love.update(dt)
  if app and app.update then
    app:update(dt)
  end
end

function love.draw()
  if app and app.draw then
    app:draw()
  end
end

function love.resize(w, h)
  if app and app.resize then
    app:resize(w, h)
  end
end