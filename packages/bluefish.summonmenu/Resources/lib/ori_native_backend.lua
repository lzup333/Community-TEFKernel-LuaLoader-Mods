--[[ 起源重构：拟态 —— 原生后端（纯 Lua 单实现）
     新版 LuaLoader 已移除原生模块接口，本文件不再探测 .so，全部用 Lua 复刻。
     语义与原 native/or_native.c 逐行对齐：bridge / rng / stats / difficulty_stats /
     score / kill_match / choose ]]
local M = { version = '2.9.6-purelua' }

local math_floor = math.floor
local function floor(x) return math_floor(x) end
local function lo(a, b) return a < b and a or b end
local function hi(a, b) return a > b and a or b end
local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end
local function num(t, k)
  local v = type(t) == 'table' and t[k] or nil
  return type(v) == 'number' and v or 0
end

-- ── bridge：原版用 patchlib_field_get_pointer 直接读写内存提速；
--    纯 Lua 版直接转发给加载器自己的 patch.*（语义等价，只是慢一点）──
function M.bridge(patch)
  local wrapper = {}
  local names = { 'get_field_value', 'set_field_value', 'get_field_vec2', 'set_field_vec2' }
  for i = 1, #names do
    local name = names[i]
    local fn = patch and patch[name]
    if type(fn) == 'function' then
      wrapper[name] = function(...) return fn(...) end
    else
      wrapper[name] = function() return nil end
    end
  end
  return setmetatable(wrapper, { __index = patch })
end

-- ── rng：Park-Miller（48271 / 2147483647），与 C 版一致 ──
function M.rng(seed)
  local n = finite(seed) and seed or 1
  local v = floor(n)
  v = v - floor(v / 2147483647) * 2147483647
  local s = v
  if s <= 0 then s = 1 end
  return function()
    s = (s * 48271) % 2147483647
    return s / 2147483647
  end
end

-- ── stats：NPC 分档强化（runtime.lua 调用 stats(base, tier, stage, mode, m)）──
local lifeScale = {
  { 1.25, 1.65, 0 },
  { 1.45, 2.10, 3.20 },
  { 1.70, 2.70, 4.20 },
  { 2.00, 3.40, 5.50 },
  { 2.40, 4.40, 7.00 },
}
local damageScale = {
  { 1.10, 1.30, 0 },
  { 1.25, 1.60, 2.00 },
  { 1.45, 2.00, 2.50 },
  { 1.70, 2.50, 3.10 },
  { 2.00, 3.10, 3.80 },
}
local defenseFlat = {
  { 2, 4, 0 },
  { 4, 7, 12 },
  { 6, 10, 16 },
  { 8, 14, 22 },
  { 10, 18, 30 },
}

function M.stats(base, tier, stage, _, m)
  tier = floor(tier or 0)
  stage = floor(stage or 0)
  if tier < 1 or tier > 3 or stage < 1 or stage > 5 then
    error('purelua stats: tier/stage 越界 (' .. tostring(tier) .. '/' .. tostring(stage) .. ')', 0)
  end
  m = type(m) == 'table' and m or {}
  local multLife = num(m, 'life')
  local multDamage = num(m, 'damage')
  local multDefense = num(m, 'defense')
  if multLife == 0 then multLife = 1 end
  if multDamage == 0 then multDamage = 1 end
  if multDefense == 0 then multDefense = 1 end

  local baseMax = num(base, 'max')
  local baseLife = num(base, 'life')
  local damage = num(base, 'damage')
  local def = num(base, 'defense')
  local value = num(base, 'value')

  local hp = hi(1, floor(baseMax * lifeScale[stage][tier] * multLife + 0.5))
  local keepRatio = (baseMax > 0) and (baseLife / baseMax) or 1
  local life = hi(1, floor(hp * lo(1, keepRatio) + 0.5))
  local outDamage = hi(1, floor(damage * damageScale[stage][tier] * multDamage + 0.5))

  local ds = { 1.1, 1.2, 1.3 }
  local vs = { 1.5, 3, 6 }
  local st = { 1, 1.15, 1.35, 1.60, 2 }
  local sc = { 1.05, 1.10, 1.15 }
  local kn = { 0.8, 0.6, 0.4 }

  local outDef = floor((def * ds[tier] + defenseFlat[stage][tier]) * multDefense + 0.5)
  return {
    max = hp,
    life = life,
    damage = outDamage,
    defense = outDef,
    value = lo(value * 15, value * vs[tier] * st[stage]),
    scale = num(base, 'scale') * sc[tier],
    knock = num(base, 'knock') * kn[tier],
  }
end

-- ── difficulty_stats：难度加成（就地改写 target 并返回）──
function M.difficulty_stats(base, target, diff, tier)
  tier = floor(tier or 0)
  if tier < 1 or tier > 3 then
    error('purelua difficulty_stats: tier 越界 (' .. tostring(tier) .. ')', 0)
  end
  diff = type(diff) == 'table' and diff or {}
  target = type(target) == 'table' and target or {}

  local bonus = num(diff, 'bonus')
  local baseMax = num(base, 'max')
  local damage = num(base, 'damage')
  local def = num(base, 'defense')

  local ratioMax = (baseMax > 0) and (num(target, 'max') / baseMax) or 1
  local hp = hi(1, floor(baseMax * lo(num(diff, 'lifeCap'), 1 + hi(0, ratioMax - 1) * bonus) + 0.5))
  target.max = hp

  local keepRatio = (baseMax > 0) and (num(base, 'life') / baseMax) or 1
  target.life = hi(1, lo(hp, floor(hp * lo(1, keepRatio) + 0.5)))

  local ratioDamage = num(target, 'damage') / hi(1, damage)
  target.damage = hi(1, floor(damage * lo(num(diff, 'damageCap'),
    1 + hi(0, ratioDamage - 1) * bonus) + 0.5))

  target.defense = def + lo(num(diff, 'defenseCap'),
    floor(hi(0, num(target, 'defense') - def) * bonus + 0.5))

  local kn = { 0.2, 0.4, 0.6 }
  target.knock = num(base, 'knock') * hi(0.25, 1 - kn[tier] * bonus)
  return target
end

-- ── score：单动作时机评分，不可用返回 nil ──
local function score_value(action, ctx)
  if type(ctx) ~= 'table' then return nil end
  local d = num(ctx, 'distance')
  local dy = num(ctx, 'dy')
  local blocked = ctx.blocked and true or false
  local hurt = ctx.hurt and true or false

  if action == 'echo' then
    return d >= 70 and 55 or 30
  elseif action == 'dash' then
    if not blocked and d >= 80 and d <= 420 and math.abs(dy) < 100 then return 65 end
  elseif action == 'pounce' then
    if not blocked and d >= 70 and d <= 360 and dy < 90 then return dy < -40 and 85 or 58 end
  elseif action == 'retreat' then
    if d < 180 then return hurt and 95 or 75 end
  elseif action == 'guard' then
    if d <= 260 and (hurt or ctx.weak or d < 180) then return hurt and 85 or 50 end
  elseif action == 'blink' then
    if blocked or ctx.stuck or d > 280 or d < 100 then return 80 end
  elseif action == 'illusion' then
    -- 距离门槛与原 echoRange 同步（640）；诡变风格拿到最高优先级，保证真的优先放分身
    if d < 640 then return hurt and 90 or (ctx.style == 'trick' and 95 or 60) end
  elseif action == 'summon' then
    if d >= 90 and num(ctx, 'helperTotal') < 4 and num(ctx, 'helperOwn') < 2 then return 70 end
  end
  return nil
end

function M.score(action, ctx)
  return score_value(action, ctx)
end

-- ── choose：在 action / shot 两条 lane 里挑最高分配方 ──
function M.choose(state, recipes, blockedMap, randomFn, ctx)
  if type(state) ~= 'table' or type(recipes) ~= 'table' then return nil end
  local clock = num(state, 'clock')
  local last = num(state, 'lastRecipe')
  local failUntil = type(state.failUntil) == 'table' and state.failUntil or {}
  blockedMap = type(blockedMap) == 'table' and blockedMap or {}

  local bestScore, bestLane, bestIndex, bestRecipe = -math.huge, nil, 0, 0
  local lanes = { 'action', 'shot' }

  for laneIndex = 1, 2 do
    local laneName = lanes[laneIndex]
    local lane = state[laneName]
    if type(lane) == 'table' and num(lane, 'due') <= clock then
      local due = num(lane, 'due')
      local indices = lane.indices
      if type(indices) == 'table' then
        local count = #indices
        if count > 128 then count = 128 end
        for i = 1, count do
          local index = indices[i]
          local recipe = recipes[index]
          if type(recipe) == 'table' and not recipe.disabled then
            local action = recipe.action
            local blocked = false
            if action == 'echo' and type(recipe.echo) == 'table' then
              local key = recipe.echo.key
              if key then blocked = blockedMap[key] and true or false end
            end
            local untilTime = tonumber(failUntil[index]) or 0
            if not blocked and clock >= untilTime then
              local value = score_value(action, ctx)
              if value then
                local random = 0
                if type(randomFn) == 'function' then
                  local ok, v = pcall(randomFn)
                  if ok and type(v) == 'number' then random = v end
                end
                value = value + lo(25, (clock - due) / 30) + random * 15
                if last == index then value = value - 15 end
                if laneName == 'shot' and state.lastLane == 'action' then
                  value = value + 15
                end
                if not bestLane or value > bestScore then
                  bestScore, bestLane, bestIndex, bestRecipe = value, laneName, i, index
                end
              end
            end
          end
        end
      end
    end
  end

  if not bestLane then return nil end
  return { key = bestLane, index = bestIndex, recipe = bestRecipe }
end

-- ── kill_match：讨伐契约击杀判定（styles 写进 stylesTable 去重）──
function M.kill_match(kind, required, tier, styleKey, stylesTable)
  tier = floor(tier or 0)
  required = floor(required or 0)
  if kind == 'ordinary' and tier ~= 0 then return nil end
  if kind ~= 'ordinary' and tier <= 0 then return nil end
  if kind == 'tier' and tier ~= required then return nil end
  if kind == 'extreme' and tier < 2 then return nil end
  if kind == 'styles' then
    if type(styleKey) ~= 'string' or type(stylesTable) ~= 'table' then return nil end
    if stylesTable[styleKey] then return nil end
    stylesTable[styleKey] = true
  end
  return true
end

return M