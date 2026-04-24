function love.conf(t)
    t.identity = "one_button_parry"
    t.window.title = "One-Button Parry Roguelite"
    -- Actual size is set at runtime to fit desktop resolution.
    t.window.width = 960
    t.window.height = 540
    t.window.vsync = 1
    t.window.resizable = true
    t.window.fullscreen = false
  end