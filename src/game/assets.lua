local Assets = {}
Assets.__index = Assets

function Assets.loadIcons()
  local function loadImage(path)
    if not love.filesystem.getInfo(path) then return nil end
    local img = love.graphics.newImage(path, { mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear", 1)
    return img
  end

  local function loadIcon(path, tol)
    tol = tol or 0.08
    local data = love.image.newImageData(path)
    local br, bg, bb, _ = data:getPixel(0, 0)
    data:mapPixel(function(_x, _y, r, g, b, a)
      local dr = r - br
      local dg = g - bg
      local db = b - bb
      local d = math.sqrt(dr * dr + dg * dg + db * db)
      if d <= tol then
        return r, g, b, 0
      end
      return r, g, b, a
    end)
    -- These icons are often drawn scaled down; mipmaps avoid blur/shimmer and preserve detail.
    local img = love.graphics.newImage(data, { mipmaps = true })
    img:setFilter("linear", "linear")
    img:setMipmapFilter("linear", 1)
    return img
  end

  return {
    hero = loadIcon("assets/images/hero.png", 0.10),
    arena = loadImage("assets/images/menu/game/arena.png"),
    enemy = loadIcon("assets/images/basic.png", 0.06),
    basic = loadIcon("assets/images/basic.png", 0.06),
    double = loadIcon("assets/images/double.png", 0.06),
    feint = loadIcon("assets/images/feint.png", 0.06),
    heavy = loadIcon("assets/images/heavy.png", 0.06),
    chain = loadIcon("assets/images/chain.png", 0.06),
    ranged = loadIcon("assets/images/ranged_Enemy.png", 0.06),
    shieldbearer = loadIcon("assets/images/shieldbearer.png", 0.06),
    goblin = loadIcon("assets/images/goblin.png", 0.06),
    boss = loadIcon("assets/images/boss.png", 0.06),
    heart = loadIcon("assets/images/heart.png", 0.10),
    heatFocus = loadIcon("assets/images/Heat_and_focus.png", 0.14)
  }
end

function Assets.loadSfx()
  return {
    blip = love.audio.newSource("assets/sounds/Blip.wav", "static"),
    hit = love.audio.newSource("assets/sounds/Hit.wav", "static"),
    parry = love.audio.newSource("assets/sounds/Parry.mp3", "static")
  }
end

function Assets.loadMusic(existing)
  if existing then return existing end
  local music = love.audio.newSource("assets/music/The_Parry_Window.mp3", "stream")
  music:setLooping(true)
  return music
end

return Assets

