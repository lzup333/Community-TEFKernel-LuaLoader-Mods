--[[ 全武器成长 —— 后端（纯 Lua 单实现）
     新版 LuaLoader 已移除原生模块接口，本文件用 Lua 复刻 wg_native.c 的全部导出：
     damage / combine_coefficients / kill_damage_multiplier / experience / level / cap /
     allowed / attributes / init / lookup / bind / clear_slot / parent / has_parent /
     spawn_source / begin_damage / end_damage / reset / shutdown /
     install_combat / combat_reset / combat_remove
     语义与原 C 对齐；热路径（Projectile.Damage、NPC.StrikeNPC）改用 P.install_hook。 ]]
local M = { version = '1.9.0-purelua' }

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max
local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
local function positive(n) return finite(n) and n > 0 end
local function num(v) return type(v) == 'number' and v or 0 end
local function patch() return mod and mod.patch or nil end

-- ────────────────────────── 纯函数部分 ──────────────────────────
function M.damage(base, coefficient)
  local v = num(base) * num(coefficient)
  return max(1, min(2147483647, floor(v + 0.500000001)))
end

local function combined(p, l, cap)
  if not positive(p) then p = 1 end
  if not positive(l) then l = 1 end
  local r
  if p < 1 then r = p * min(1.2, l) else r = 1 + max(0, p - 1) + max(0, l - 1) end
  r = min(1.6, r)
  if positive(cap) then return min(cap, r) end
  return r
end

function M.combine_coefficients(p, l, cap) return combined(p, l, cap) end

local CLASSES = { melee = true, ranged = true, magic = true, summon = true }
function M.kill_damage_multiplier(level, class)
  if type(level) ~= 'number' or level ~= level or not CLASSES[class] then return 1 end
  return 1 + max(0, min(20, floor(level))) * 0.01
end

function M.experience(life, boss, stage)
  if not (life > 0) or not finite(life) then return 0 end
  local e = floor(sqrt(life) + 0.5)
  local base = max(12, floor(e / 3 + 0.5) * 3)
  if boss then
    base = floor(base * (2 + 0.25 * max(0, min(10, num(stage)))) / 3 + 0.5) * 3
    return min(3000, base)
  end
  return min(600, base)
end

function M.level(xp)
  xp = num(xp)
  local level = 0
  while level < 20 do
    local need = 100 + 50 * level
    if xp < need then return level, xp, need end
    xp = xp - need
    level = level + 1
  end
  return 20, 0, 0
end

local CAPS = { [0] = 5, 7, 9, 10, 12, 14, 15, 17, 18, 19, 20 }
local function stagecap(s)
  if s >= 0 and s <= 10 and floor(s) == s then return CAPS[s] end
  return 5
end
function M.cap(stage) return stagecap(num(stage)) end
local function threshold(l) return 100 * l + 25 * l * (l - 1) end
function M.allowed(xp, amount, stage)
  xp, amount = num(xp), num(amount)
  if xp ~= xp or amount ~= amount or amount <= 0 then return 0 end
  return max(0, min(floor(amount), threshold(stagecap(num(stage))) - xp))
end

local function kind(info)
  local c = type(info) == 'table' and info.category or nil
  if c == 'melee' then
    if info.channel then return 'melee_control' end
    return info.noMelee == false and 'melee_swing' or 'melee_projectile'
  end
  if c == 'ranged' then return num(info.useTime) >= 25 and 'ranged_heavy' or 'ranged_fast' end
  if c == 'magic' then return info.channel and 'magic_channel' or 'magic_projectile' end
  if c == 'summon' then
    if info.isWhip then return 'summon_whip' end
    if info.sentry then return 'summon_sentry' end
    return 'summon_minion'
  end
  return nil
end

function M.attributes(level, info)
  local out = {}
  if type(info) ~= 'table' or info.growthDisabled then return out end
  local x = max(0, min(20, floor(num(level)))) / 20
  local k = kind(info)
  local function attr(name, amount) out[name] = amount * x end
  if k == 'melee_swing' then
    attr('attackSpeed', .03); attr('size', .04)
  elseif k == 'melee_projectile' then
    out.crit = floor(3 * x)
    if num(info.shoot) > 0 and not info.channel then attr('projectileSpeed', .06) end
  elseif k == 'melee_control' or k == 'ranged_heavy' then
    out.crit = floor(3 * x); attr('knockback', .8)
  elseif k == 'ranged_fast' then
    attr('useTime', .025)
    if num(info.useAmmo) > 0 then attr('ammoSave', .10) end
  elseif k == 'magic_projectile' then
    attr('castSpeed', .025); attr('manaCost', .10)
  elseif k == 'magic_channel' then
    out.crit = floor(3 * x); attr('manaCost', .12)
  elseif k == 'summon_whip' then
    attr('attackSpeed', .03); attr('whipRange', .05)
  elseif k == 'summon_minion' then
    attr('knockback', 1.2)
  elseif k == 'summon_sentry' then
    attr('knockback', 1.5)
  end
  return out
end

-- ────────────────────────── 状态 ──────────────────────────
local MAXS, DEPTH = 5000, 128
local S = {
  ready = false, combatReady = false,
  pf = {}, nf = {},
  playerIndex = nil, animation = nil, noMelee = nil, heldGetter = nil,
  generation = nil, bomb = nil, api = nil, hooks = {},
  bindings = {},
  parents = {}, np = 0, parentOverflow = 0,
  damageStack = {}, nd = 0,
  projStack = {}, nproj = 0, projOverflow = 0,
  itemStack = {}, ni = 0, itemOverflow = 0,
  strikeStack = {}, nstrike = 0, strikeOverflow = 0,
  died = {}, deaths = {},
}

local PKIND = {
  whoAmI = 'int32', owner = 'int32', type = 'int32', active = 'bool',
  identity = 'uint32', friendly = 'bool', trap = 'bool', npcProj = 'bool',
}
local NKIND = {
  whoAmI = 'int32', life = 'int32', lifeMax = 'int32', boss = 'bool',
  friendly = 'bool', townNPC = 'bool', immortal = 'bool', dontTakeDamage = 'bool',
  chaseable = 'bool', SpawnedFromStatue = 'bool', realLife = 'int32', type = 'int32',
}

local function pget(name, obj)
  local f, p = S.pf[name], patch()
  if not f or not obj or not p then return nil end
  local ok, v = pcall(p.get_field_value, f, obj, PKIND[name])
  if ok then return v end
  return nil
end
local function nget(name, obj)
  local f, p = S.nf[name], patch()
  if not f or not obj or not p then return nil end
  local ok, v = pcall(p.get_field_value, f, obj, NKIND[name])
  if ok then return v end
  return nil
end
local function fieldvalue(f, obj, k)
  local p = patch()
  if not f or not p then return nil end
  local ok, v = pcall(p.get_field_value, f, obj, k)
  if ok then return v end
  return nil
end
local function invoke(h, obj, ...)
  local p = patch()
  if not h or not p then return nil end
  local ok, v = pcall(p.invoke, h, obj, ...)
  if ok then return v end
  return nil
end
local function tablecopy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  return o
end

local function lookup(proj)
  if not S.ready or not proj then return nil end
  if pget('active', proj) ~= true then return nil end
  local slot = pget('whoAmI', proj)
  if type(slot) ~= 'number' or slot < 0 or slot >= MAXS then return nil end
  local b = S.bindings[slot]
  if not b then return nil end
  if b.owner == pget('owner', proj) and b.identity == pget('identity', proj)
    and b.type == pget('type', proj) then
    return b
  end
  S.bindings[slot] = nil
  return nil
end

-- ────────────────────────── 射弹来源 API ──────────────────────────
function M.init(metadata)
  if S.ready then error('后端已激活', 0) end
  if type(metadata) ~= 'table' then return false end
  for name in pairs(PKIND) do S.pf[name] = metadata[name] end
  for _, name in ipairs({ 'whoAmI', 'owner', 'type', 'active', 'identity',
    'friendly', 'trap', 'npcProj' }) do
    if not S.pf[name] then return false end
  end
  S.ready = true
  S.bindings = {}
  local p = patch()
  if metadata.ai and p and p.install_hook then
    local hookok, hook = pcall(p.install_hook, metadata.ai, {
      prefix = function(instance)
        if S.np >= DEPTH then S.parentOverflow = S.parentOverflow + 1 return false end
        local b = lookup(instance)
        S.np = S.np + 1
        S.parents[S.np] = b and b.source or nil
        return false
      end,
      postfix = function()
        if S.parentOverflow > 0 then S.parentOverflow = S.parentOverflow - 1 return false end
        if S.np > 0 then S.parents[S.np] = nil; S.np = S.np - 1 end
        return false
      end,
    })
    if not hookok or not hook then S.ready = false; return false end
    S.hooks[#S.hooks + 1] = hook
  end
  return true
end

function M.lookup(proj)
  local b = lookup(proj)
  return b and b.source or nil
end

function M.bind(source, proj, slot)
  if not S.ready or type(source) ~= 'table' or not proj then return false end
  slot = tonumber(slot)
  if not slot or slot < 0 or slot >= MAXS then return false end
  if pget('whoAmI', proj) ~= slot then return false end
  if pget('active', proj) ~= true then return false end
  if pget('trap', proj) == true or pget('npcProj', proj) == true then return false end
  if pget('owner', proj) ~= source.owner then return false end
  local out = tablecopy(source)
  out.slot = slot
  out.identity = pget('identity', proj)
  if not out.embeddedCoefficient then out.embeddedCoefficient = 1 end
  S.bindings[slot] = {
    slot = slot, owner = pget('owner', proj), type = pget('type', proj),
    identity = out.identity, source = out,
  }
  return true
end

function M.clear_slot(slot)
  slot = tonumber(slot)
  if slot and slot >= 0 and slot < MAXS then S.bindings[slot] = nil end
end

function M.has_parent() return (S.np > 0 or S.parentOverflow > 0 or S.nd > 0) end
function M.parent() if S.np > 0 and S.parentOverflow == 0 then return S.parents[S.np] end end
function M.spawn_source()
  if S.nd > 0 then return S.damageStack[S.nd] end
  if S.parentOverflow > 0 then return false end
  if S.np > 0 then return S.parents[S.np] end
  return nil
end

function M.begin_damage(proj, token, confirmed)
  if S.nd >= DEPTH then error('damage scope overflow', 0) end
  local src
  if type(token) == 'table' then
    src = tablecopy(token)
  elseif token == nil then
    local b = lookup(proj)
    src = b and tablecopy(b.source) or nil
  end
  if src then
    if type(token) == 'table' then
      src.embeddedCoefficient = num(token.coefficient)
    elseif S.nd > 0 and S.damageStack[S.nd] then
      local prev = S.damageStack[S.nd]
      if num(prev.slot) == num(src.slot) and num(prev.identity) == num(src.identity) then
        src.embeddedCoefficient = num(prev.embeddedCoefficient)
      end
    end
  end
  S.nd = S.nd + 1
  S.damageStack[S.nd] = src
end

function M.end_damage()
  if S.nd > 0 then S.damageStack[S.nd] = nil; S.nd = S.nd - 1 end
end

function M.reset()
  S.bindings = {}
  S.died = {}
  S.parents, S.np, S.parentOverflow = {}, 0, 0
  S.damageStack, S.nd = {}, 0
  S.projStack, S.nproj, S.projOverflow = {}, 0, 0
  S.itemStack, S.ni, S.itemOverflow = {}, 0, 0
  S.strikeStack, S.nstrike, S.strikeOverflow = {}, 0, 0
end

local function removehooks(from)
  local i = #S.hooks
  while i >= (from or 1) do
    local hook = S.hooks[i]
    if hook and hook.remove then pcall(function() hook:remove() end) end
    S.hooks[i] = nil
    i = i - 1
  end
end

function M.shutdown()
  removehooks(1)
  S.ready = false
  S.combatReady = false
  S.api = nil
  M.reset()
end

-- ────────────────────────── 战斗与经验 ──────────────────────────
local function apicall(name, ...)
  local api = S.api
  if not api then return nil end
  local fn = api[name]
  if type(fn) ~= 'function' then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end
local function apibool(name) return apicall(name) == true end
local function apinum(name)
  local v = apicall(name)
  return type(v) == 'number' and v or -1
end

local function bombcontains(id)
  if not S.bomb or type(id) ~= 'number' or id < 0 then return false end
  local arr = fieldvalue(S.bomb, nil, 'object')
  local p = patch()
  if not arr or not p then return false end
  local len = invoke(p.array_length, arr)
  if type(len) ~= 'number' or id >= len then return false end
  local ok, flag = pcall(p.array_at, arr, id, 'bool')
  return ok and flag == true
end

local function source_from_binding(b)
  if not b or not apibool('active') then return nil end
  local src = b.source
  if type(src) ~= 'table' then return nil end
  if num(src.owner) ~= apinum('localPlayer') then return nil end
  local profile = apicall('profile')
  if type(profile) ~= 'string' then return nil end
  local out = tablecopy(src)
  out.profile = profile
  return out
end

local function melee_source()
  if S.nproj > 0 or S.projOverflow > 0 or S.ni == 0 or S.itemOverflow > 0 then return nil end
  if not S.heldGetter or not apibool('active') then return nil end
  local top = S.itemStack[S.ni]
  if not top or type(top.profile) ~= 'string' then return nil end
  if top.profile ~= apicall('profile') then return nil end
  local anim = tonumber(invoke(S.animation, top.player)) or 0
  if anim <= 0 then return nil end
  local item = invoke(S.heldGetter, top.player)
  if not item then return nil end
  if S.noMelee and fieldvalue(S.noMelee, item, 'bool') == true then return nil end
  local info = apicall('identify', item)
  if type(info) ~= 'table' or info.category ~= 'melee' then return nil end
  return { category = 'melee', weaponId = num(info.id), owner = top.owner, profile = top.profile }
end

local function strike_begin_trace(frame, npc, args)
  if S.nproj == 0 then return end
  local top = S.projStack[S.nproj]
  if not top or not top.summon then return end
  local snapshot = {}
  for i = 1, 6 do snapshot[i] = args and args[i] or nil end
  local token = apicall('summonStrikeBegin', npc, snapshot, top.weapon >= 0 and top.weapon or nil)
  if type(token) == 'table' then frame.trace = token end
end

local function strike_end_trace(frame, npc, args, result)
  if not frame.trace then return end
  local snapshot = {}
  for i = 1, 6 do snapshot[i] = args and args[i] or nil end
  apicall('summonStrikeEnd', npc, snapshot, result, frame.trace)
  frame.trace = nil
end

function M.install_combat(fields, api)
  if not S.ready then error('射弹后端未就绪', 0) end
  if S.combatReady then error('战斗后端已激活', 0) end
  if type(fields) ~= 'table' then error('战斗元数据缺失', 0) end
  for name in pairs(NKIND) do S.nf[name] = fields[name] end
  for _, name in ipairs({ 'whoAmI', 'life', 'lifeMax', 'boss', 'friendly', 'townNPC',
    'immortal', 'dontTakeDamage', 'chaseable', 'SpawnedFromStatue', 'realLife', 'type' }) do
    if not S.nf[name] then error('战斗字段缺失 ' .. name, 0) end
  end
  S.playerIndex = fields.playerIndex
  S.animation = fields.animation
  S.noMelee = fields.noMelee
  S.heldGetter = fields.heldGetter
  S.generation = fields.generation
  S.bomb = fields.bomb
  if not (S.playerIndex and S.animation and S.noMelee and S.generation) then
    error('战斗元数据不完整', 0)
  end
  S.api = api
  local p = patch()
  local before = #S.hooks
  local function addhook(method, prefix, postfix)
    local hook = p.install_hook(method, { prefix = prefix, postfix = postfix })
    if not hook then error('Hook 安装失败', 0) end
    S.hooks[#S.hooks + 1] = hook
  end
  local ok, err = pcall(function()
    if fields.itemCheck and S.heldGetter then
      addhook(fields.itemCheck, function(player)
        if S.ni >= DEPTH then S.itemOverflow = S.itemOverflow + 1 return false end
        local owner = fieldvalue(S.playerIndex, player, 'int32')
        owner = type(owner) == 'number' and owner or -1
        local entry = { player = player, owner = owner, profile = nil }
        if S.combatReady and owner == apinum('localPlayer') and apibool('active') then
          entry.profile = apicall('profile')
        end
        S.ni = S.ni + 1
        S.itemStack[S.ni] = entry
        return false
      end, function()
        if S.itemOverflow > 0 then S.itemOverflow = S.itemOverflow - 1 return false end
        if S.ni > 0 then S.itemStack[S.ni] = nil; S.ni = S.ni - 1 end
        return false
      end)
    end

    addhook(fields.damage, function(proj)
      if S.nproj >= DEPTH then S.projOverflow = S.projOverflow + 1 return false end
      local entry = { source = nil, summon = false, weapon = -1 }
      S.nproj = S.nproj + 1
      S.projStack[S.nproj] = entry
      if not S.combatReady then return false end
      local b = lookup(proj)
      local id, owner = pget('type', proj), pget('owner', proj)
      local friendly = pget('friendly', proj) == true and pget('trap', proj) ~= true
        and pget('npcProj', proj) ~= true and not bombcontains(id)
      if friendly and b then
        entry.source = source_from_binding(b)
        if type(b.source) == 'table' then
          entry.summon = b.source.category == 'summon' and owner == apinum('localPlayer')
          entry.weapon = num(b.source.weaponId)
        end
      end
      return false
    end, function()
      if S.projOverflow > 0 then S.projOverflow = S.projOverflow - 1 return false end
      if S.nproj > 0 then S.projStack[S.nproj] = nil; S.nproj = S.nproj - 1 end
      return false
    end)

    addhook(fields.strike, function(npc, args)
      if S.nstrike >= DEPTH then S.strikeOverflow = S.strikeOverflow + 1 return false end
      local frame = { source = nil, bossprofile = nil, trace = nil }
      S.nstrike = S.nstrike + 1
      S.strikeStack[S.nstrike] = frame
      if not S.combatReady or not args or not apibool('active') then return false end
      local fromNet = args[5] == true
      local life = num(nget('life', npc))
      local boss = nget('boss', npc) == true
      local real = num(nget('realLife', npc))
      if not fromNet and boss and life > 0 and real < 0 then
        local profile = apicall('profile')
        if type(profile) == 'string' then
          frame.bossprofile = profile
          frame.bossid = num(nget('type', npc))
        end
      end
      strike_begin_trace(frame, npc, args)
      if S.projOverflow > 0 then return false end
      local src
      if S.nproj > 0 then src = S.projStack[S.nproj].source else src = melee_source() end
      if type(src) ~= 'table' then return false end
      local owner = num(src.owner)
      local slot = num(nget('whoAmI', npc))
      local maxlife = num(nget('lifeMax', npc))
      local damage = num(args[1])
      local attackOwner = type(args[6]) == 'number' and args[6] or -1
      local gen = invoke(S.generation, npc)
      local eligible = life > 0 and maxlife > 5 and damage > 0 and damage < 1000000
        and not fromNet and (attackOwner == -1 or attackOwner == owner)
        and real < 0 and slot >= 0 and slot < MAXS
        and nget('chaseable', npc) == true
        and nget('friendly', npc) ~= true
        and nget('townNPC', npc) ~= true
        and nget('immortal', npc) ~= true
        and nget('dontTakeDamage', npc) ~= true
        and nget('SpawnedFromStatue', npc) ~= true
        and gen ~= nil
        and (not S.died[slot] or S.deaths[slot] ~= gen)
      if eligible then
        frame.life, frame.max, frame.slot, frame.generation = life, maxlife, slot, gen
        frame.boss, frame.source = boss, src
      end
      return false
    end, function(npc, args, result)
      if S.strikeOverflow > 0 then S.strikeOverflow = S.strikeOverflow - 1 return false end
      if S.nstrike == 0 then return false end
      local frame = S.strikeStack[S.nstrike]
      S.strikeStack[S.nstrike] = nil
      S.nstrike = S.nstrike - 1
      if not frame then return false end
      if frame.bossprofile and S.combatReady and apibool('active')
        and frame.bossprofile == apicall('profile')
        and num(nget('life', npc)) <= 0 then
        apicall('bossKill', frame.bossprofile, frame.bossid or 0)
      end
      strike_end_trace(frame, npc, args, result)
      if type(frame.source) == 'table' and S.combatReady
        and type(result) == 'number' and result > 0 and apibool('active') then
        local profile = frame.source.profile
        local gen = invoke(S.generation, npc)
        if type(profile) == 'string' and profile == apicall('profile')
          and num(nget('whoAmI', npc)) == frame.slot
          and gen ~= nil and gen == frame.generation
          and num(nget('life', npc)) <= 0
          and (not S.died[frame.slot] or S.deaths[frame.slot] ~= gen) then
          S.died[frame.slot] = true
          S.deaths[frame.slot] = gen
          local xp = M.experience(frame.max, frame.boss, apinum('worldStage'))
          apicall('award', profile, frame.source.category, xp, num(frame.source.weaponId),
            num(frame.source.owner), frame.boss == true, frame.max)
        end
      end
      return false
    end)
  end)
  if not ok then
    removehooks(before + 1)
    S.api = nil
    error(tostring(err), 0)
  end
  S.combatReady = true
  return true
end

function M.combat_reset() S.died = {} end

function M.combat_remove()
  removehooks(2)
  S.combatReady = false
  S.api = nil
end

return M