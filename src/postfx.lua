local util = require("src.util")

local PostFX = {}
PostFX.__index = PostFX

local SHADER_SRC = [[
extern number u_time;
extern vec2 u_resolution;

vec2 hash2(vec2 p) {
  // cheap hash
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

number noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f*f*(3.0-2.0*f);
  number a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
  number b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
  number c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
  number d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px)
{
  vec4 c = Texel(tex, uv) * color;

  // Ensure u_resolution is used (LÖVE strips unused uniforms).
  vec2 res = max(u_resolution, vec2(1.0, 1.0));
  vec2 npx = px / res; // 0..1-ish

  // Vignette
  vec2 p = uv * 2.0 - 1.0;
  number r2 = dot(p, p);
  number vig = smoothstep(1.05, 0.15, r2);
  c.rgb *= mix(0.78, 1.08, vig);

  // Subtle scanlines
  number scan = 0.985 + 0.015 * sin((npx.y * res.y + u_time * 60.0) * 2.0);
  c.rgb *= scan;

  // Film grain (very subtle)
  number n = noise((npx * res) * 0.65 + u_time * 10.0);
  c.rgb += (n * 0.018);

  // Mild color grade (cool shadows, warm highlights)
  number luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 shadows = vec3(0.93, 0.98, 1.06);
  vec3 highs   = vec3(1.06, 1.02, 0.96);
  c.rgb *= mix(shadows, highs, smoothstep(0.25, 0.90, luma));

  // Clamp
  c.rgb = clamp(c.rgb, 0.0, 1.0);
  return c;
}
]]

function PostFX.new(w, h)
  local self = setmetatable({}, PostFX)
  self.w, self.h = w, h
  self.time = 0
  self.canvas = love.graphics.newCanvas(w, h, { msaa = 0 })
  self.canvas:setFilter("linear", "linear")
  self.shader = love.graphics.newShader(SHADER_SRC)
  self.enabled = true
  self:syncUniforms()
  return self
end

function PostFX:syncUniforms()
  if not self.shader then return end
  self.shader:send("u_resolution", { self.w, self.h })
end

function PostFX:resize(w, h)
  self.w, self.h = w, h
  self.canvas = love.graphics.newCanvas(w, h, { msaa = 0 })
  self.canvas:setFilter("linear", "linear")
  self:syncUniforms()
end

function PostFX:update(dt)
  self.time = self.time + dt
end

function PostFX:begin()
  if not self.enabled then return end
  love.graphics.setCanvas({ self.canvas, stencil = true })
  love.graphics.clear(0, 0, 0, 1)
end

function PostFX:finish()
  self:draw(0, 0, 1)
end

function PostFX:draw(x, y, scale)
  if not self.enabled then
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, x or 0, y or 0, 0, scale or 1, scale or 1)
    return
  end

  love.graphics.setCanvas()
  self.shader:send("u_time", self.time)
  love.graphics.setShader(self.shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.canvas, x or 0, y or 0, 0, scale or 1, scale or 1)
  love.graphics.setShader()
end

return PostFX

