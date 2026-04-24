local Settings = {}

local DEFAULTS = {
  postfx = true,
  screenshake = true,
  fullscreen = false,
  pixelPerfect = false,
  difficulty = "normal", -- easy | normal | hard
  musicEnabled = true,
  musicVolume = 0.35,
  sfxVolume = 1.0,
  keyParry = "space",
  keyPause = "escape",
  keyFocus = "lshift",
  tutorialDone = false,
  level = 1,
  xp = 0,
  kills = {} -- per-enemy-type kill counts for compendium unlocks
}

local function mergeDefaults(t)
  t = t or {}
  for k, v in pairs(DEFAULTS) do
    if t[k] == nil then t[k] = v end
  end
  return t
end

function Settings.load()
  if not love.filesystem.getInfo("settings.lua") then
    return mergeDefaults({})
  end

  local chunk = love.filesystem.load("settings.lua")
  if not chunk then
    return mergeDefaults({})
  end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then
    return mergeDefaults({})
  end
  return mergeDefaults(data)
end

function Settings.save(t)
  t = mergeDefaults(t)
  local function serializeKills(kills)
    kills = kills or {}
    local parts = { "{" }
    for k, v in pairs(kills) do
      if type(k) == "string" then
        parts[#parts + 1] = ("    [%q] = %d,"):format(k, math.max(0, math.floor(tonumber(v) or 0)))
      end
    end
    parts[#parts + 1] = "  }"
    return table.concat(parts, "\n")
  end

  local s = "return {\n"
  s = s .. ("  postfx = %s,\n"):format(t.postfx and "true" or "false")
  s = s .. ("  screenshake = %s,\n"):format(t.screenshake and "true" or "false")
  s = s .. ("  fullscreen = %s,\n"):format(t.fullscreen and "true" or "false")
  s = s .. ("  pixelPerfect = %s,\n"):format(t.pixelPerfect and "true" or "false")
  s = s .. ("  difficulty = %q,\n"):format(t.difficulty or "normal")
  s = s .. ("  musicEnabled = %s,\n"):format(t.musicEnabled and "true" or "false")
  s = s .. ("  musicVolume = %.3f,\n"):format(tonumber(t.musicVolume) or 0.35)
  s = s .. ("  sfxVolume = %.3f,\n"):format(tonumber(t.sfxVolume) or 1.0)
  s = s .. ("  keyParry = %q,\n"):format(t.keyParry or "space")
  s = s .. ("  keyPause = %q,\n"):format(t.keyPause or "escape")
  s = s .. ("  keyFocus = %q,\n"):format(t.keyFocus or "lshift")
  s = s .. ("  tutorialDone = %s,\n"):format(t.tutorialDone and "true" or "false")
  local lvl = tonumber(t.level) or 1
  if lvl < 1 then lvl = 1 end
  if lvl > 999 then lvl = 999 end
  s = s .. ("  level = %d,\n"):format(lvl)
  s = s .. ("  xp = %d,\n"):format(tonumber(t.xp) or 0)
  s = s .. ("  kills = %s,\n"):format(serializeKills(t.kills))
  s = s .. "}\n"
  love.filesystem.write("settings.lua", s)
end

return Settings

