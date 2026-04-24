local util = require("src.util")

local Audio = {}
Audio.__index = Audio

function Audio.new(game)
  local self = setmetatable({}, Audio)
  self.game = game
  return self
end

function Audio:applySettings()
  local g = self.game
  if not g.settings then return end

  g.settings.musicEnabled = (g.settings.musicEnabled ~= false)
  g.settings.musicVolume = util.clamp(tonumber(g.settings.musicVolume) or 0.35, 0, 1)
  g.settings.sfxVolume = util.clamp(tonumber(g.settings.sfxVolume) or 1.0, 0, 1)

  if g.music then
    g.musicDuckMul = g.musicDuckMul or 1.0
    g.music:setVolume(g.settings.musicVolume * g.musicDuckMul)
    if g.settings.musicEnabled then
      if not g.music:isPlaying() then g.music:play() end
    else
      if g.music:isPlaying() then g.music:pause() end
    end
  end
end

function Audio:duckMusic(mul, dur)
  local g = self.game
  mul = util.clamp(tonumber(mul) or 0.65, 0.10, 1.0)
  dur = util.clamp(tonumber(dur) or 0.15, 0.05, 0.35)
  g.musicDuckMulTarget = math.min(g.musicDuckMulTarget or 1.0, mul)
  g.musicDuckT = math.max(g.musicDuckT or 0, dur)
  g.musicDuckDur = dur
end

function Audio:refreshMusicVolume()
  local g = self.game
  if not g.music or not g.settings then return end
  local base = g.settings.musicVolume or 0
  g.musicDuckMul = g.musicDuckMul or 1.0
  g.music:setVolume(base * g.musicDuckMul)
end

function Audio:update(dt)
  local g = self.game
  -- Music ducking envelope (short perceived "sidechain" on perfect/hit/deflect)
  if not (g.music and g.settings) then return end
  g.musicDuckMul = g.musicDuckMul or 1.0
  g.musicDuckMulTarget = g.musicDuckMulTarget or 1.0
  g.musicDuckT = g.musicDuckT or 0
  g.musicDuckDur = g.musicDuckDur or 0.15

  if g.musicDuckT > 0 then
    g.musicDuckT = math.max(0, g.musicDuckT - dt)
    local t = 1.0 - (g.musicDuckT / math.max(0.001, g.musicDuckDur))
    g.musicDuckMul = util.lerp(g.musicDuckMulTarget, 1.0, t)
  else
    g.musicDuckMul = util.lerp(g.musicDuckMul, 1.0, util.clamp(dt * 10, 0, 1))
    g.musicDuckMulTarget = 1.0
  end
  self:refreshMusicVolume()
end

function Audio:playSfx(name, vol, pitch)
  local g = self.game
  if not g.sfx then return end
  local base = g.sfx[name]
  if not base then return end
  local src = base:clone()
  local sv = (g.settings and g.settings.sfxVolume) or 1.0
  local v = (vol or 1) * sv
  local p = pitch or 1.0
  -- pitch/volume dynamics: subtle random pitch (±3–6%)
  local jitter = 0.04
  p = p * util.lerp(1.0 - jitter, 1.0 + jitter, love.math.random())
  src:setVolume(v)
  src:setPitch(p)
  src:play()
end

return Audio

