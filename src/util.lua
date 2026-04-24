local util = {}

function util.clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

function util.lerp(a, b, t)
  return a + (b - a) * t
end

function util.round(x)
  if x >= 0 then return math.floor(x + 0.5) end
  return math.ceil(x - 0.5)
end

function util.shuffle(t)
  for i = #t, 2, -1 do
    local j = love.math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- weights: array of numbers, same length as items
function util.weightedChoice(items, weights)
  local total = 0
  for i = 1, #weights do total = total + weights[i] end
  if total <= 0 then return items[1] end
  local r = love.math.random() * total
  local acc = 0
  for i = 1, #items do
    acc = acc + weights[i]
    if r <= acc then return items[i] end
  end
  return items[#items]
end

return util
