local util = require("src.util")
local Menu = require("src.menu")
local Settings = require("src.settings")

local MenuController = {}
MenuController.__index = MenuController

function MenuController.new(game)
  local self = setmetatable({}, MenuController)
  self.game = game
  return self
end

function MenuController:goToMenu(kind)
  local g = self.game
  kind = kind or "title"
  g.menu.kind = kind
  g.menu.fade = 0
  local curMode = (g.runStartMode or g.mode or "run")

  if kind == "title" then
    g.state = "menu"
    g.menu:setButtons({
      Menu.btn("play", "Play", ""),
      Menu.btn("compendium", "Compendium", ""),
      Menu.btn("options", "Options", ""),
      Menu.btn("quit", "Quit", "Esc")
    })
  elseif kind == "compendium" then
    g.state = "menu"
    g.compendiumTab = g.compendiumTab or "player"
    -- Compendium uses custom in-panel tabs (drawn/handled by UI), so keep the menu button list empty.
    g.menu:setButtons({})
  elseif kind == "confirm_quit" then
    g.state = "menu"
    g.menu:setButtons({
      Menu.btn("yes", "Yes", ""),
      Menu.btn("no", "No", "")
    })
  elseif kind == "mode_select" then
    g.state = "menu"
    g.menu:setButtons({
      Menu.btn("standard", "Standard", ""),
      Menu.btn("endless", "Endless", ""),
      Menu.btn("hardcore", "Hardcore", ""),
      Menu.btn("seeded", "Seeded", ""),
      Menu.bind("difficulty", "Difficulty", function() return g:difficultyLabel() end),
      Menu.btn("back", "Back to Home", "Esc")
    })
  elseif kind == "seed_input" then
    g.state = "menu"
    g.seedInput.active = true
    g.seedInput.text = g.seedInput.text or ""
    g.menu:setButtons({
      Menu.btn("seed_start", "Start", ""),
      Menu.btn("seed_clear", "Clear", ""),
      Menu.btn("back", "Back", "Esc")
    })
  elseif kind == "pause" then
    g.state = "paused"
    g.menu:setButtons({
      Menu.btn("resume", "Resume", "Esc"),
      Menu.btn("restart_seed", "Restart (same seed)", "Enter"),
      Menu.btn("start", (curMode == "endless") and "New Endless" or "New Run", "R"),
      Menu.btn("options", "Options", ""),
      Menu.btn("to_title", "Title Menu", "Back")
    })
  elseif kind == "dead" then
    g.state = "dead"
    g.menu:setButtons({
      Menu.btn("restart_seed", "Try Again (same seed)", "Enter"),
      Menu.btn("start", (curMode == "endless") and "New Endless" or "New Run", "R"),
      Menu.btn("options", "Options", ""),
      Menu.btn("to_title", "Title Menu", "Esc")
    })
  elseif kind == "options" then
    g.state = "menu"
    g.menu:setButtons({
      Menu.btn("sound", "Sound", ""),
      Menu.btn("visuals", "Visuals", ""),
      Menu.btn("keybinds", "Keybinds", ""),
      Menu.btn("back", "Back", "Esc")
    })
  elseif kind == "sound" then
    g.state = "menu"
    g.menuReturnKind = "options"
    g.menu:setButtons({
      Menu.toggle("opt_music", "Music", function() return g.settings.musicEnabled end, function(v)
        g.settings.musicEnabled = v
        Settings.save(g.settings)
        g:applyAudioSettings()
      end, ""),
      Menu.slider("opt_musicvol", "Music Volume", function()
        return g.settings.musicVolume or 0
      end, function(v)
        g.settings.musicVolume = util.clamp(v, 0, 1)
        Settings.save(g.settings)
        g:applyAudioSettings()
      end, 0.05),
      Menu.slider("opt_sfxvol", "SFX Volume", function()
        return g.settings.sfxVolume or 0
      end, function(v)
        g.settings.sfxVolume = util.clamp(v, 0, 1)
        Settings.save(g.settings)
      end, 0.05),
      Menu.btn("back", "Back", "Esc")
    })
  elseif kind == "visuals" then
    g.state = "menu"
    g.menuReturnKind = "options"
    g.menu:setButtons({
      Menu.toggle("opt_fullscreen", "Fullscreen", function() return g.settings.fullscreen end, function(v)
        g.settings.fullscreen = v
        Settings.save(g.settings)
        g:applyWindowMode()
      end, "F11"),
      Menu.toggle("opt_pixel", "Pixel Perfect Scale", function() return g.settings.pixelPerfect end, function(v)
        g.settings.pixelPerfect = v
        Settings.save(g.settings)
      end, ""),
      Menu.toggle("opt_postfx", "Post FX", function() return g.settings.postfx end, function(v)
        g.settings.postfx = v
        if g.postfx then g.postfx.enabled = v end
        Settings.save(g.settings)
      end, ""),
      Menu.toggle("opt_shake", "Screen Shake", function() return g.settings.screenshake end, function(v)
        g.settings.screenshake = v
        g.shakeMult = v and 1.0 or 0.0
        Settings.save(g.settings)
      end, ""),
      Menu.btn("back", "Back", "Esc")
    })
  elseif kind == "keybinds" then
    g.state = "menu"
    g.menu:setButtons({
      Menu.bind("bind_parry", "Parry", function() return g:prettyKey(g.settings.keyParry) end),
      Menu.bind("bind_pause", "Pause/Back", function() return g:prettyKey(g.settings.keyPause) end),
      Menu.bind("bind_focus", "Focus", function() return g:prettyKey(g.settings.keyFocus or "lshift") end),
      Menu.btn("bind_reset", "Reset Defaults", ""),
      Menu.btn("back", "Back", "Esc")
    })
  end
end

function MenuController:getMenuSubtitle()
  local g = self.game
  local sub = ("Best score: %d   Best streak: %d"):format(g.bests.bestScore or 0, g.bests.bestStreak or 0)
  if g.menu and g.menu.kind == "mode_select" then
    sub = "Choose a game mode"
  elseif g.menu and g.menu.kind == "title" then
    sub = ""
  elseif g.menu and g.menu.kind == "options" then
    sub = ""
  elseif g.menu and g.menu.kind == "sound" then
    sub = ""
  elseif g.menu and g.menu.kind == "visuals" then
    sub = ""
  elseif g.menu and g.menu.kind == "keybinds" then
    sub = g.awaitBind and "Press a key to bind (Esc cancels)" or ""
  elseif g.menu and g.menu.kind == "seed_input" then
    local t = g.seedInput and g.seedInput.text or ""
    local maxLen = 18
    local shown = (t ~= "" and t) or "—"
    sub = ("Enter seed (up to %d digits, e.g. 123456789): %s  (%d/%d)"):format(maxLen, shown, #t, maxLen)
  elseif g.menu and g.menu.kind == "confirm_quit" then
    sub = "Quit the game?"
  elseif g.menu and g.menu.kind == "howto" then
    sub = "Learn the basics"
  elseif g.menu and g.menu.kind == "compendium" then
    sub = ""
  end
  return sub
end

function MenuController:activateMenuAction(action)
  local g = self.game
  if action == "play" then
    g.menuReturnKind = "title"
    self:goToMenu("mode_select")
    return
  end
  if action == "howto" then
    self:goToMenu("compendium")
    g.compendiumTab = "howto"
    return
  end
  if action == "compendium" then
    self:goToMenu("compendium")
    return
  end
  if action == "comp_tab_player" then
    g.compendiumTab = "player"
    g:playSfx("blip", 0.55, 1.02)
    return
  end
  if action == "comp_tab_enemies" then
    g.compendiumTab = "enemies"
    g:playSfx("blip", 0.55, 1.02)
    return
  end
  if action == "comp_tab_howto" then
    g.compendiumTab = "howto"
    g:playSfx("blip", 0.55, 1.02)
    return
  end
  if action == "standard" then
    g:startRun(os.time())
    return
  end
  if action == "hardcore" then
    g:startGame("hardcore", os.time())
    return
  end
  if action == "start" then
    if g.menu and g.menu.kind == "mode_select" then
      g:startRun(os.time())
    elseif g.menu and g.menu.kind == "title" then
      g:startRun(os.time())
    else
      if (g.runStartMode or "run") == "endless" then g:startEndless(os.time()) else g:startRun(os.time()) end
    end
    return
  end
  if action == "endless" then
    g:startEndless(os.time())
    return
  end
  if action == "seeded" then
    g.seedInput.text = ""
    g.menuReturnKind = "mode_select"
    self:goToMenu("seed_input")
    return
  end
  if action == "difficulty" then
    local order = { "easy", "normal", "hard" }
    local cur = (g.settings and g.settings.difficulty) or "normal"
    local idx = 2
    for i = 1, #order do if order[i] == cur then idx = i end end
    idx = (idx % #order) + 1
    g.settings.difficulty = order[idx]
    Settings.save(g.settings)
    g:playSfx("blip", 0.6, 1.02)
    self:goToMenu("mode_select")
    return
  end
  if action == "seed_start" then
    local n = tonumber(g.seedInput.text or "")
    if not n then n = os.time() end
    g.seedInput.active = false
    g:startRun(n)
    return
  end
  if action == "seed_clear" then
    g.seedInput.text = ""
    g:playSfx("blip", 0.6, 1.0)
    return
  end
  if action == "keybinds" then
    self:goToMenu("keybinds")
    return
  end
  if action == "sound" then
    self:goToMenu("sound")
    return
  end
  if action == "visuals" then
    self:goToMenu("visuals")
    return
  end
  if action == "bind_parry" then
    g.awaitBind = { key = "keyParry" }
    g:playSfx("blip", 0.6, 1.0)
    return
  end
  if action == "bind_pause" then
    g.awaitBind = { key = "keyPause" }
    g:playSfx("blip", 0.6, 1.0)
    return
  end
  if action == "bind_focus" then
    g.awaitBind = { key = "keyFocus" }
    g:playSfx("blip", 0.6, 1.0)
    return
  end
  if action == "bind_reset" then
    g.settings.keyParry = "space"
    g.settings.keyPause = "escape"
    g.settings.keyFocus = "lshift"
    Settings.save(g.settings)
    g:playSfx("blip", 0.6, 1.0)
    self:goToMenu("keybinds")
    return
  end
  if action == "restart_seed" then
    if (g.runStartMode or "run") == "endless" then
      g:startEndless(g.run.seed)
    else
      g:startRun(g.run.seed)
    end
    return
  end
  if action == "resume" then
    g.state = "playing"
    return
  end
  if action == "to_title" then
    self:goToMenu("title")
    return
  end
  if action == "options" then
    g.optionsReturnKind = g.menu.kind
    self:goToMenu("options")
    return
  end
  if action == "back" then
    if g.menu and g.menu.kind == "keybinds" then
      self:goToMenu("options")
    elseif g.menu and g.menu.kind == "seed_input" then
      g.seedInput.active = false
      self:goToMenu(g.menuReturnKind or "mode_select")
    elseif g.menu and (g.menu.kind == "sound" or g.menu.kind == "visuals") then
      self:goToMenu("options")
    elseif g.menu and g.menu.kind == "options" then
      self:goToMenu(g.optionsReturnKind or "title")
    elseif g.menu and g.menu.kind == "confirm_quit" then
      self:goToMenu(g.quitReturnKind or "title")
    elseif g.menu and g.menu.kind == "mode_select" then
      self:goToMenu("title")
    else
      self:goToMenu("title")
    end
    return
  end
  if action == "quit" then
    g.quitReturnKind = (g.menu and g.menu.kind) or "title"
    self:goToMenu("confirm_quit")
    return
  end
  if action == "yes" or action == "quit_yes" then
    love.event.quit()
    return
  end
  if action == "no" or action == "quit_no" then
    self:goToMenu(g.quitReturnKind or "title")
    return
  end
end

function MenuController:keypressed(key)
  local g = self.game

  if g.awaitBind then
    if key == "escape" then
      g.awaitBind = nil
      g:playSfx("blip", 0.5, 1.0)
      return
    end
    local field = g.awaitBind.key
    g.awaitBind = nil
    if field == "keyParry" or field == "keyPause" or field == "keyFocus" then
      g.settings[field] = key
      Settings.save(g.settings)
      g:playSfx("blip", 0.7, 1.0)
      self:goToMenu("keybinds")
      return
    end
  end

  if key == "f11" then
    g.settings.fullscreen = not g.settings.fullscreen
    Settings.save(g.settings)
    g:applyWindowMode()
    return
  end

  if key == "escape" then
    if g.state == "playing" then
      self:goToMenu("pause")
      return
    end
    if g.state == "paused" then
      g.state = "playing"
      return
    end
    if g.state == "dead" then
      self:goToMenu("title")
      return
    end
    if g.state == "perk" then
      return
    end
    if g.state == "menu" then
      if g.menu.kind == "options"
        or g.menu.kind == "sound"
        or g.menu.kind == "visuals"
        or g.menu.kind == "keybinds"
        or g.menu.kind == "mode_select"
        or g.menu.kind == "seed_input"
        or g.menu.kind == "compendium"
      then
        self:activateMenuAction("back")
      elseif g.menu.kind == "confirm_quit" then
        self:activateMenuAction("quit_no")
      else
        self:activateMenuAction("quit")
      end
      return
    end
  end

  if g.state == "menu" and g.menu and g.menu.kind == "compendium" then
    if key == "left" then
      g.compendiumTab = "player"
      g.compendiumScroll = 0
      g:playSfx("blip", 0.50, 1.02)
      return
    end
    if key == "right" then
      local t = g.compendiumTab or "player"
      if t == "player" then
        g.compendiumTab = "enemies"
      elseif t == "enemies" then
        g.compendiumTab = "howto"
      else
        g.compendiumTab = "player"
      end
      g.compendiumScroll = 0
      g:playSfx("blip", 0.50, 1.02)
      return
    end
    if key == "tab" then
      local t = g.compendiumTab or "player"
      if t == "player" then
        g.compendiumTab = "enemies"
      elseif t == "enemies" then
        g.compendiumTab = "howto"
      else
        g.compendiumTab = "player"
      end
      g.compendiumScroll = 0
      g:playSfx("blip", 0.50, 1.04)
      return
    end
  end

  if g.state == "menu" or g.state == "paused" or g.state == "dead" then
    if g.menu and g.menu.kind == "seed_input" then
      if key == "backspace" then
        local t = g.seedInput.text or ""
        g.seedInput.text = t:sub(1, math.max(0, #t - 1))
        return
      end
      if key == "return" or key == "kpenter" then
        self:activateMenuAction("seed_start")
        return
      end
      if key == "c" then
        g.seedInput.text = ""
        return
      end
      if key:match("^%d$") then
        local t = g.seedInput.text or ""
        if #t < 18 then
          g.seedInput.text = t .. key
        end
        return
      end
    end

    if key == "up" or key == "w" then g.menu:move(-1); g:playSfx("blip", 0.55, 1.0) end
    if key == "down" or key == "s" then g.menu:move(1); g:playSfx("blip", 0.55, 1.0) end
    if key == "left" or key == "a" then g.menu:toggleSelected(-1) end
    if key == "right" or key == "d" then g.menu:toggleSelected(1) end
    if key == "return" or key == "space" then
      local act = g.menu:activateSelected()
      if act then self:activateMenuAction(act) end
      g:playSfx("blip", 0.7, 1.02)
    end
    if key == "r" then
      self:activateMenuAction("start")
    end
    return
  end

  if g.state == "perk" then
    local idx =
      (key == "1" and 1) or (key == "2" and 2) or (key == "3" and 3) or
      (key == "kp1" and 1) or (key == "kp2" and 2) or (key == "kp3" and 3) or nil
    if idx then g:pickPerk(idx) end
    if key == "space" then g:pickPerk(1) end
    return
  end

  if g.state == "playing" then
    if key == (g.settings.keyParry or "space") then g:attemptParry() end
    if key == (g.settings.keyPause or "escape") then self:goToMenu("pause") end
    if key == "return" then
      if (g.runStartMode or "run") == "endless" then g:startEndless(g.run.seed) else g:startRun(g.run.seed) end
    end
    if key == "r" then
      if (g.runStartMode or "run") == "endless" then g:startEndless(os.time()) else g:startRun(os.time()) end
    end
  end
end

function MenuController:mousepressed(x, y, button)
  local g = self.game
  if button ~= 1 then return end

  if g.state == "perk" then
    x, y = g:toVirtual(x, y)
    local idx = nil
    for i = 1, 3 do
      local yy = 210 + (i - 1) * 92
      local bx, by, bw, bh = 160, yy, g.w - 320, 72
      if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
        idx = i
        break
      end
    end
    g:pickPerk(idx or 1)
    return
  end

  if g.state == "playing" then
    g:attemptParry()
    return
  end

  if g.state == "menu" or g.state == "paused" or g.state == "dead" then
    if g.menu and g.menu.kind == "compendium" and g.ui and g.ui.compendiumHitTest then
      local act = g.ui:compendiumHitTest(x, y, love.graphics.getDimensions())
      if act then
        g:playSfx("blip", 0.70, 1.02)
        self:activateMenuAction(act)
      end
      return
    end
    local act = g.menu:mousePressed(x, y, love.graphics.getDimensions())
    if act then
      g:playSfx("blip", 0.70, 1.02)
      self:activateMenuAction(act)
    end
    return
  end
end

function MenuController:mousereleased(_x, _y, button)
  local g = self.game
  if button ~= 1 then return end
  if g.menu and g.menu.mouseReleased then
    g.menu:mouseReleased()
  end
end

function MenuController:mousemoved(x, y, _dx, _dy)
  local g = self.game
  if g.state == "menu" or g.state == "paused" or g.state == "dead" then
    local prev = g.menu and g.menu.selected or nil
    g.menu:mouseMoved(x, y, love.graphics.getDimensions())
    local cur = g.menu and g.menu.selected or nil
    if prev and cur and prev ~= cur then
      g:playSfx("blip", 0.40, 1.10)
    end
    if g.menu and g.menu.mouseDragged then
      g.menu:mouseDragged(x, y, love.graphics.getDimensions())
    end
    return
  end
end

function MenuController:wheelmoved(_dx, dy)
  local g = self.game
  if not (g.state == "menu" or g.state == "paused" or g.state == "dead") then return end
  if g.menu and g.menu.kind == "compendium" then
    -- Compendium uses an internal scroll region (enemies list / how-to text).
    g.compendiumScroll = math.max(0, (g.compendiumScroll or 0) - dy * 32)
    return
  end
  if not g.menu or not g.menu.wheelAdjust then return end
  local mx, my = love.mouse.getPosition()
  g.menu:wheelAdjust(mx, my, dy, love.graphics.getDimensions())
end

return MenuController

