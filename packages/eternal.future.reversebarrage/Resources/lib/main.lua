-- main.lua
-- 反方向的弹幕（Reverse Barrage）：只逆转自己的弹幕，终点在弹幕所有者附近；
-- 飞回后沿“飞回来的方向”继续飞行，交还游戏原逻辑。

mod.meta = { pkg_id = "eternal.future.reversebarrage", version = "1.0.0" }

local S = {
  ready = false,
  H = {},
  tick = 0,
  subjectIndex = 0,
  hooks = {},
  enabled = true,
  -- 弹幕倒飞
  projInfo = {},             -- id -> { bornTick, originX, originY, endX, endY, duration, released }
  -- 弹幕终点离所有者的最大距离（像素）
  maxEndDistance = 900,
  -- 弹幕回飞总时长（tick）
  reverseDuration = 45,
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
local function LOG(fmt, ...) mod.info("[reverse-barrage-] " .. string.format(fmt, ...)) end

----------------------------------------------------------------------
-- 1. 安全读写
----------------------------------------------------------------------
local function safe_get(type_handle, name, obj, type_name)
  local P = mod.patch
  if type_handle then
    local prop = P.get_property(type_handle, name)
    if prop then
      local getter = P.property_get_method(prop)
      if getter then
        local ok, v = pcall(P.invoke, getter, obj)
        if ok and v ~= nil then return v end
      end
    end
    local field = P.get_field(type_handle, name)
    if field then
      local ok, v = pcall(P.get_field_value, field, obj, type_name)
      if ok and v ~= nil then return v end
    end
  end
  local ok, v = pcall(function() return obj[name] end)
  if ok then return v end
  return nil
end

local function safe_vec2(field, obj)
  if not field then return 0, 0 end
  local ok, x, y = pcall(mod.patch.get_field_vec2, field, obj)
  if ok then return x or 0, y or 0 end
  return 0, 0
end
local function safe_set_vec2(field, obj, x, y)
  if not field then return false end
  return pcall(mod.patch.set_field_vec2, field, obj, x, y)
end

----------------------------------------------------------------------
-- 2. 句柄初始化
----------------------------------------------------------------------
local function init_handles()
  if S.ready then return true end
  local P = mod.patch
  local H = S.H
  local ok, err = pcall(function()
    H.Player     = P.get_type("Terraria", "Player")
    H.NPC        = P.get_type("Terraria", "NPC")
    H.Projectile = P.get_type("Terraria", "Projectile")
    H.Main       = P.get_type("Terraria", "Main")
    H.playerArr  = P.get_field(H.Main, "player")
    H.npcArr     = P.get_field(H.Main, "npc")
    H.projArr    = P.get_field(H.Main, "projectile")

    H.p_position = P.get_field(H.Player, "position")
    H.p_velocity = P.get_field(H.Player, "velocity")
    H.p_direction = P.get_field(H.Player, "direction")

    H.pr_position = P.get_field(H.Projectile, "position")
    H.pr_velocity = P.get_field(H.Projectile, "velocity")
    H.pr_type     = P.get_field(H.Projectile, "type")
    H.pr_timeLeft = P.get_field(H.Projectile, "timeLeft")
    H.pr_owner    = P.get_field(H.Projectile, "owner")
    H.pr_damage   = P.get_field(H.Projectile, "damage")

    H.m_Update = P.get_method(H.Player, "Update", 1)
              or P.get_method(H.Player, "Update", 0)
  end)
  if not ok then mod.error("[reverse-barrage-] init_handles: " .. tostring(err)); return false end
  if not (H.Player and H.NPC and H.Projectile and H.Main) then
    mod.error("[reverse-barrage-] 核心类型缺失"); return false
  end
  S.ready = true
  return true
end

----------------------------------------------------------------------
-- 弹幕倒飞：只逆转弹幕，终点在所有者附近
----------------------------------------------------------------------
-- 思路：
--   1. 首次见到自己的伤害弹幕时，计算它“原本的终点” end = pos + vel * timeLeft。
--   2. 如果 end 离所有者太远（> maxEndDistance），沿 end -> 所有者方向拉近到
--      maxEndDistance，得到一个“靠近所有者”的终点。
--   3. 之后每帧 pos = lerp(end -> origin, progress)，progress 从 0 到 1，
--      弹幕从“靠近所有者的终点”飞回 origin（所有者发射处）。
--   4. 飞回过程中速度方向 = origin - pos（即飞回来的方向）。
--   5. progress 到 1（或超过 duration 兜底）时：
--      - 把位置钉在 origin；
--      - 速度保持“飞回来的方向”（origin - end 的归一化方向），
--        让弹幕沿这个方向继续飞出去，而不是被修正回原方向；
--      - 标记 released，之后完全交还游戏原逻辑，不再接管。
--
-- 排除：
--   - 装饰类弹幕（damage <= 0）不处理。
--   - timeLeft <= 3 的弹幕不处理（太短，插值没意义）。
local function is_own_projectile(p)
  local H = S.H
  local owner = safe_get(H.Projectile, "owner", p, "int32")
  if owner == nil then return false end
  return owner == S.subjectIndex
end

local function is_damaging_projectile(p)
  local H = S.H
  local dmg = safe_get(H.Projectile, "damage", p, "int32") or 0
  return dmg > 0
end

local function reverse_own_projectiles()
  local P = mod.patch
  local H = S.H
  local projs = P.get_field_value(H.projArr, nil, "object")
  local nProj = projs and P.array_length(projs) or 0
  if nProj == 0 then
    for k in pairs(S.projInfo) do S.projInfo[k] = nil end
    return
  end

  -- 所有者位置
  local players = P.get_field_value(H.playerArr, nil, "object")
  local nPlayers = players and P.array_length(players) or 0
  local px, py = 0, 0
  for i = 1, nPlayers do
    local pl = P.array_at(players, i - 1, "object")
    if pl and safe_get(H.Player, "active", pl, "bool") then
      px, py = safe_vec2(H.p_position, pl)
      break
    end
  end

  local seen = {}
  for i = 1, nProj do
    local p = P.array_at(projs, i - 1, "object")
    if p and safe_get(H.Projectile, "active", p, "bool") then
      local id = "PR" .. tostring(i - 1)
      seen[id] = true

      if is_own_projectile(p) and is_damaging_projectile(p) then
        local info = S.projInfo[id]

        if info and info.released then
          -- 已释放：完全交给游戏原逻辑，不再接管
        elseif not info then
          local timeLeft = safe_get(H.Projectile, "timeLeft", p, "int32") or 0
          if timeLeft > 3 then
            -- 首次见到：算终点并拉近到所有者附近
            local x, y = safe_vec2(H.pr_position, p)
            local vx, vy = safe_vec2(H.pr_velocity, p)
            local rawEndX = x + vx * timeLeft
            local rawEndY = y + vy * timeLeft

            -- 若终点离所有者太远，沿 end -> player 方向拉近到 maxEndDistance
            local dx, dy = rawEndX - px, rawEndY - py
            local dist = math.sqrt(dx * dx + dy * dy)
            local endX, endY = rawEndX, rawEndY
            if dist > S.maxEndDistance and dist > 0.001 then
              local k = S.maxEndDistance / dist
              endX = px + dx * k
              endY = py + dy * k
            end

            info = {
              bornTick = S.tick,
              originX = x, originY = y,
              endX = endX, endY = endY,
              duration = S.reverseDuration,
              released = false,
            }
            S.projInfo[id] = info

            -- 立即把弹幕放到终点
            safe_set_vec2(H.pr_position, p, endX, endY)
          end
        end

        if info and not info.released then
          -- progress: 0（在终点）-> 1（回到 origin）
          local elapsed = S.tick - info.bornTick
          local progress = clamp(elapsed / info.duration, 0, 1)

          if progress >= 1 then
            -- 飞回完成：释放接管，位置钉在 origin，
            -- 速度保持“飞回来的方向”（origin - end 归一化），沿该方向继续飞
            info.released = true
            safe_set_vec2(H.pr_position, p, info.originX, info.originY)

            local fx, fy = info.originX - info.endX, info.originY - info.endY
            local flen = math.sqrt(fx * fx + fy * fy)
            if flen > 0.001 then
              local vx, vy = safe_vec2(H.pr_velocity, p)
              local speed = math.sqrt(vx * vx + vy * vy)
              if speed < 0.001 then speed = 8 end
              safe_set_vec2(H.pr_velocity, p, fx / flen * speed, fy / flen * speed)
            end
          else
            local nx = info.endX + (info.originX - info.endX) * progress
            local ny = info.endY + (info.originY - info.endY) * progress
            safe_set_vec2(H.pr_position, p, nx, ny)

            -- 速度指向 origin（即飞回来的方向）
            local dx, dy = info.originX - nx, info.originY - ny
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.001 then
              local vx, vy = safe_vec2(H.pr_velocity, p)
              local speed = math.sqrt(vx * vx + vy * vy)
              if speed < 0.001 then speed = 8 end
              safe_set_vec2(H.pr_velocity, p, dx / len * speed, dy / len * speed)
            end
          end
        end
      end
    end
  end

  for k in pairs(S.projInfo) do
    if not seen[k] then S.projInfo[k] = nil end
  end
end

----------------------------------------------------------------------
-- 4. 每帧驱动
----------------------------------------------------------------------
local function drive_entities()
  if not S.enabled then return end
  S.tick = S.tick + 1
  reverse_own_projectiles()
end

----------------------------------------------------------------------
-- 5. 钩子
----------------------------------------------------------------------
local function install_hooks()
  local P = mod.patch
  local H = S.H

  if H.m_Update then
    S.hooks.update = P.install_hook(H.m_Update, {
      prefix = function(instance, args)
        if S.subjectIndex == 0 then
          local players = P.get_field_value(H.playerArr, nil, "object")
          local n = players and P.array_length(players) or 0
          for i = 1, n do
            local pl = P.array_at(players, i - 1, "object")
            if pl == instance then S.subjectIndex = i - 1; break end
          end
        end
        return false
      end,
      postfix = function(instance, args)
        local ok, err = pcall(drive_entities)
        if not ok then mod.error("[reverse-barrage-] drive_entities: " .. tostring(err)) end
        return nil
      end,
    })
  else
    mod.error("[reverse-barrage-] Player.Update 未匹配到")
  end
end

----------------------------------------------------------------------
-- 入口
----------------------------------------------------------------------
function setup()
  if not init_handles() then
    mod.error("[reverse-barrage-] 初始化失败，终止")
    return
  end
  install_hooks()
  LOG("初始化完成；maxEndDistance=%d duration=%d",
      S.maxEndDistance, S.reverseDuration)
end

function mod.cleanup()
  for _, h in pairs(S.hooks) do
    if h and h.remove then pcall(h.remove) end
  end
  S.hooks = {}
  S.ready = false
  LOG("cleanup 完成")
end

todo_list = { "setup" }
