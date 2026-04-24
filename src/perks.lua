local util = require("src.util")

local perks = {}

local RARITY = {
  common = { weight = 1.00, color = { 0.88, 0.90, 0.96 } },
  rare   = { weight = 0.35, color = { 0.55, 0.80, 1.00 } },
  epic   = { weight = 0.12, color = { 0.95, 0.55, 1.00 } }
}

function perks.rarityMeta()
  return RARITY
end

local function perk(def)
  return def
end

function perks.defaultPool()
  return {
    perk({
      id = "wider_window_1",
      rarity = "common",
      stackable = true,
      name = "Wider Window",
      desc = "+30ms base parry window",
      apply = function(g)
        g.player.parryWindowBase = (g.player.parryWindowBase or 0.110) + 0.030
      end
    }),
    perk({
      id = "faster_cd_1",
      rarity = "common",
      stackable = true,
      name = "Faster Recovery",
      desc = "-50ms parry cooldown (min 80ms)",
      apply = function(g)
        g.player.cooldown = math.max(0.08, g.player.cooldown - 0.05)
      end
    }),
    perk({
      id = "heal_1",
      rarity = "common",
      stackable = true,
      name = "Patch Up",
      desc = "+1 HP (up to max)",
      apply = function(g)
        g.player.hp = math.min(g.player.maxHp, g.player.hp + 1)
      end
    }),
    perk({
      id = "maxhp_1",
      rarity = "rare",
      stackable = true,
      name = "Tough Skin",
      desc = "+1 max HP and heal 1",
      apply = function(g)
        g.player.maxHp = g.player.maxHp + 1
        g.player.hp = math.min(g.player.maxHp, g.player.hp + 1)
      end
    }),
    perk({
      id = "combo_greed",
      rarity = "common",
      stackable = true,
      name = "Combo Greed",
      desc = "Streak adds more score",
      apply = function(g)
        g.meta.comboBonus = (g.meta.comboBonus or 0) + 1
      end
    }),
    perk({
      id = "perfect_parry",
      rarity = "rare",
      stackable = true,
      name = "Perfect Parry",
      desc = "Wider perfect window cap + big score",
      apply = function(g)
        g.player.perfectWindowCap = (g.player.perfectWindowCap or 0.040) + 0.010
        g.meta.perfectBonus = (g.meta.perfectBonus or 20) + 10
      end
    }),
    perk({
      id = "life_leech",
      rarity = "rare",
      stackable = true,
      name = "Life Leech",
      desc = "Build leech charge on kills + perfects. Heal when it fills.",
      apply = function(g)
        g.meta.lifeLeechStacks = (g.meta.lifeLeechStacks or 0) + 1
      end
    }),
    perk({
      id = "shockwave",
      rarity = "epic",
      stackable = false,
      name = "Counter Shockwave",
      desc = "Successful parry can pop nearby enemies",
      apply = function(g)
        g.meta.shockwave = (g.meta.shockwave or 0) + 1
      end
    }),
    perk({
      id = "deflect_radius",
      rarity = "common",
      stackable = true,
      name = "Deflect Magnet",
      desc = "+10px deflect radius",
      apply = function(g)
        g.meta.deflectRadiusBonus = (g.meta.deflectRadiusBonus or 0) + 10
      end
    }),
    perk({
      id = "focus_flow",
      rarity = "rare",
      stackable = true,
      name = "Flow State",
      desc = "+30% focus regen, -10% focus drain",
      apply = function(g)
        g.meta.focusRegenBonus = (g.meta.focusRegenBonus or 0) + 0.018
        g.meta.focusDrainMult = util.clamp((g.meta.focusDrainMult or 1.0) * 0.90, 0.55, 1.0)
      end
    }),
    perk({
      id = "coolant_loops",
      rarity = "rare",
      stackable = true,
      name = "Coolant Loops",
      desc = "Overheat drains faster (shorter enemy buff window)",
      apply = function(g)
        g.meta.overheatDrainMult = util.clamp((g.meta.overheatDrainMult or 1.0) + 0.35, 1.0, 3.0)
      end
    }),
    perk({
      id = "streak_shield",
      rarity = "rare",
      stackable = false,
      name = "Streak Shield",
      desc = "Once per wave: a miss doesn't hurt",
      apply = function(g)
        g.meta.streakShield = true
      end
    }),
    perk({
      id = "cheat_death",
      rarity = "epic",
      stackable = true,
      name = "Last Stand",
      desc = "Prevent 1 fatal hit (consumed). If at full HP: gain +1 max HP instead.",
      apply = function(g)
        if g and g.player and (g.player.hp or 0) >= (g.player.maxHp or 0) and (g.player.maxHp or 0) > 0 then
          g.player.maxHp = g.player.maxHp + 1
          g.player.hp = g.player.hp + 1
          if g.meta then
            g.meta.perkPopupOverride = "Perk gained: Extra Life"
          end
          return
        end
        g.meta.fatalGuard = (g.meta.fatalGuard or 0) + 1
      end
    })
  }
end

local function isUnlocked(_g, p)
  -- Hook: later you can gate perks behind achievements/unlocks.
  return p.unlocked ~= false
end

local function rarityWeight(rarityId)
  local meta = RARITY[rarityId]
  return meta and meta.weight or 1.0
end

function perks.pickChoices(g, pool, count)
  local candidates = {}
  for _, p in ipairs(pool) do
    local taken = g.run.takenPerks[p.id]
    local stackable = (p.stackable == true)
    if isUnlocked(g, p) and (stackable or (not taken)) then
      table.insert(candidates, p)
    end
  end
  if #candidates == 0 then return {} end

  local out = {}
  local used = {}
  while #out < count and #out < #candidates do
    local weights = {}
    for i = 1, #candidates do
      local p = candidates[i]
      weights[i] = used[p.id] and 0 or rarityWeight(p.rarity)
    end
    local picked = util.weightedChoice(candidates, weights)
    if picked and not used[picked.id] then
      used[picked.id] = true
      table.insert(out, picked)
    end
  end
  return out
end

function perks.fallbackChoices(g, count)
  g.run.fallbackCounter = (g.run.fallbackCounter or 0) + 1
  local n = g.run.fallbackCounter

  local defs = {
    {
      id = ("fallback_heal_%d"):format(n),
      rarity = "common",
      name = "First Aid",
      desc = "+1 HP (up to max)",
      apply = function(gg)
        gg.player.hp = math.min(gg.player.maxHp, gg.player.hp + 1)
      end
    },
    {
      id = ("fallback_window_%d"):format(n),
      rarity = "common",
      name = "Breathing Room",
      desc = "+20ms base parry window",
      apply = function(gg)
        gg.player.parryWindowBase = (gg.player.parryWindowBase or 0.250) + 0.020
      end
    },
    {
      id = ("fallback_score_%d"):format(n),
      rarity = "common",
      name = "Loose Change",
      desc = "+50 score",
      apply = function(gg)
        gg:addScore(50)
      end
    }
  }

  local out = {}
  for i = 1, math.min(count, #defs) do
    out[#out + 1] = defs[i]
  end
  return out
end

return perks
