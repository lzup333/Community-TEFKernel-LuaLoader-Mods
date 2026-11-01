mod.meta = { pkg_id = "lua.qing.randdrop", version = "1.1.0", version_code = 110, api_version = 1 }
local P = mod.patch

local function w(s) end

local Main = P.get_type("Terraria", "Main")
local m_NewText
local function ct(color, s) return "[c/" .. color .. ":" .. s .. "]" end
local function newtext(s)
  if not s or not m_NewText then return end
  pcall(function() P.invoke(m_NewText, P.string_create(s)) end)
end

local C_TITLE, C_CD, C_ON = "FFD700", "FFAA00", "55FF55"

local T_Item, T_Main, M_rst, M_upd, M_gm
local T_WI, F_inner, F_type, F_stack
local f_main_item
local f_world_name
local g_busy = false
local g_hit = 0
local MAX_TYPE = 5455
local CYCLE = 600

local g_map, g_seed, g_round = {}, 0, 0
local g_pend = {}

local g_last_world, g_pending_world, g_pending_at = nil, nil, 0
local g_armed, g_cd, g_said_title = false, -1, false

local function invM(m)
  if not m then return nil end
  local ok, r = pcall(P.invoke, m, nil)
  if not ok then return nil end
  return r
end

-- 是否在世界里：Main.gameMenu 属性 getter，true=主菜单/加载中
local g_was_ingame = false
local function in_world()
  local gm = invM(M_gm)
  if type(gm) == "boolean" then return not gm end
  return nil
end

local function new_cycle(now)
  g_map = {}; g_seed = now; g_round = g_round + 1; g_cd = -1
  w("MAP new cycle @"..now)
  newtext(ct(C_ON, string.format("掉落表已更改，当前随机次数 %d", g_round)))
end

local function pick(cur)
  local v = g_map[cur]
  if v then return v end
  local t = math.random(1, MAX_TYPE)
  if t == cur then t = t % MAX_TYPE + 1 end
  g_map[cur] = t
  return t
end

local function wr_int(f, inst, v)
  local p = P.field_pointer(f, inst)
  if not p then return false end
  return pcall(P.mem_write, p, 0, string.pack("<i4", v))
end

local function rd_int(f, inst)
  local ok, v = pcall(P.get_field_value, f, inst, "int32")
  if ok and type(v) == "number" then return v end
  return -1
end

local function check_world_enter()
  local iw = in_world()
  if iw == nil then return end
  if not iw then
    -- 主菜单/加载中：清状态
    if g_was_ingame then
      g_was_ingame = false
      g_armed = false; g_pending_world = nil; g_round = 0; g_cd = -1; g_said_title = false
      w("ENTER MENU")
    end
    return
  end
  -- 在世界里
  if not g_was_ingame then
    -- 刚进世界（含重进），重新计时
    g_was_ingame = true
    g_pending_world = true; g_pending_at = os.clock()
    g_armed = false; g_round = 0; g_cd = -1; g_said_title = false
    w("WORLD IN")
  end
  if g_pending_world then
    local el = os.clock() - g_pending_at
    if el >= 15 then
      g_pending_world = nil; g_armed = true; w("ARMED"); new_cycle(os.time())
    elseif el >= 10 then
      local sec = 15 - math.floor(el)
      if g_cd ~= sec then g_cd = sec; newtext(ct(C_CD, "倒计时:" .. sec)); w("CD "..sec) end
    elseif el >= 9 then
      if not g_said_title then g_said_title = true; newtext(ct(C_TITLE, "随机掉落即将开启")); w("TITLE") end
    end
  end
end

local function tick_cycle()
  if not g_armed then return end
  local now = os.time()
  local left = g_seed + CYCLE - now
  if left <= 0 then new_cycle(now)
  elseif left <= 5 and g_cd ~= left then
    g_cd = left; newtext(ct(C_CD, "倒计时:" .. left))
  end
end

-- 收集当前地面掉落物的 inner 实例 -> true
local function build_ground_set()
  local set = {}
  if not f_main_item then return set end
  local oka, arr = pcall(P.get_field_value, f_main_item, nil, "object")
  if not (oka and arr) then return set end
  local okn, n = pcall(P.array_length, arr)
  if not (okn and n) then return set end
  for i = 0, n - 1 do
    local okw, wi = pcall(P.array_at, arr, i)
    if okw and wi then
      local okg, inner = pcall(P.get_field_value, F_inner, wi, "object")
      if okg and inner then set[inner] = true end
    end
  end
  return set
end

-- 下一帧统一处理：此时 stack 已被游戏写好
local function flush()
  if #g_pend == 0 then return end
  local list = g_pend
  g_pend = {}
  local now = os.time()
  if now - g_seed >= CYCLE then new_cycle(now) end
  local gset = build_ground_set()
  for _, inst in ipairs(list) do
    local cur = rd_int(F_type, inst)
    if cur > 0 and gset[inst] then
      local nt = pick(cur)
      if nt ~= cur then
        g_busy = true
        wr_int(F_type, inst, nt)
        pcall(P.invoke, M_rst, inst, nt)
        wr_int(F_stack, inst, 1)
        g_busy = false
        g_hit = g_hit + 1
        if g_hit <= 40 then w("RW#"..g_hit.." "..cur.." -> "..nt) end
      end
    end
  end
end

function setup()
  if _G.g_rd300 then return end
  _G.g_rd300 = true
  
  T_Item  = P.get_type("Terraria","Item")
  T_Main  = P.get_type("Terraria","Main")
  if not (T_Item and T_Main) then w("type NIL"); return end
  M_rst   = P.get_method(T_Item,"ResetStats",1)
  M_upd   = P.get_method(T_Main,"Update",1)
  F_type  = P.get_field(T_Item,"type")
  F_stack = P.get_field(T_Item,"stack")
  T_WI    = P.get_type("Terraria","WorldItem")
  if T_WI then F_inner = P.get_field(T_WI,"inner") end
  f_main_item = P.get_field(Main,"item")
  f_world_name = P.get_field(Main, "worldName")
  M_gm = P.get_method(T_Main, "get_gameMenu", 0)
  m_NewText = P.get_method(Main, "NewText", 3)
  if not m_NewText then m_NewText = P.get_method(Main, "NewText", 5) end
  w("M_rst="..tostring(M_rst).." M_upd="..tostring(M_upd).." wn="..tostring(f_world_name))
  if not (M_rst and M_upd and F_type and F_stack) then return end
  math.randomseed(os.time())
  g_map = {}; g_seed = os.time(); g_round = 0

  local fc = 0
  pcall(P.install_hook, M_upd, { postfix = function()
    pcall(flush)
    fc = fc + 1
    if (fc % 3) == 0 then pcall(check_world_enter) end
    if (fc % 15) == 0 then pcall(tick_cycle) end
  end })

  local ok, id = pcall(P.install_hook, M_rst, {
    postfix = function(inst, a, res)
      if g_busy then return end
      local cur = a and a[1]
      if type(cur) ~= "number" or cur <= 0 then return end
      if not g_armed then return end
      g_pend[#g_pend + 1] = inst
    end
  })
  w("hook ok="..tostring(ok).." id="..tostring(id))
end

todo_list = { "setup" }
