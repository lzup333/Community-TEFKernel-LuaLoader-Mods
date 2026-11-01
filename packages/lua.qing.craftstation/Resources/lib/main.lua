-- 更好的体验(制作) v1.2.0  制作站随身
mod.meta = { pkg_id = "lua.qing.craftstation", version = "1.0.0", version_code = 100, api_version = 1 }
local P = mod.patch

local function log(s) end

-- 物品ID -> 游戏配方要求的图格ID（对齐 Recipe.requiredTile + AdjTiles 别名机制）
-- 左值=背包里的家具物品；右值=要写 true 的 adjTile 槽位
local ST = {
  [31]=13,    -- 玻璃瓶 -> 13(瓶/炼金)
  [35]=16,    -- 铁砧 -> 16
  [716]=16,   -- 铅砧 -> 16
  [33]=17,    -- 熔炉 -> 17
  [36]=18,    -- 工作台 -> 18（所有工作台变体同槽）
  [221]=77,   -- 地狱熔炉 -> 77（+17）
  [332]=86,   -- 织布机 -> 86
  [352]=94,   -- 酒桶 -> 94
  [345]=96,   -- 烹饪锅 -> 96
  [354]=101,  -- 书架 -> 101（+14）
  [363]=106,  -- 锯木机 -> 106
  [398]=114,  -- 工匠作坊 -> 114
  [487]=125,  -- 水晶球 -> 125（+14）
  [524]=133,  -- 精金熔炉 -> 133（+17,+77）
  [525]=134,  -- 秘银砧 -> 134（+16）
  [995]=217,  -- 搅拌机 -> 217
  [996]=218,  -- 绞肉机 -> 218
  [997]=219,  -- 提炼机 -> 219
  [998]=220,  -- 固化机 -> 220
  [1120]=228, -- 染缸 -> 228
  [1430]=243, -- 灌注站 -> 243
  [1551]=247, -- 自动锻锤 -> 247
  [2172]=283, -- 重型工作台 -> 283
  [2192]=300, -- 骨头焊机 -> 300
  [2193]=301, -- 血肉克隆台 -> 301
  [2194]=302, -- 玻璃窑 -> 302（+17）
  [2195]=303, -- 丛林蜥蜴熔炉 -> 303
  [2196]=304, -- 生命木织机 -> 304
  [2197]=305, -- 天磨 -> 305
  [2198]=306, -- 制冰机 -> 306
  [2203]=307, -- 蒸汽朋克锅炉 -> 307
  [2204]=308, -- 蜂蜜分配机 -> 308
  [3000]=355, -- 炼金台 -> 355（+13,+14）
  [3549]=412, -- 远古操纵机 -> 412
  [5008]=622, -- 茶壶 -> 622
}
-- 别名补写：某些站图格额外要求其它槽位（对齐 PC AdjTiles）
local ALIAS = {
  [77]={17}, [302]={17}, [133]={17,77}, [134]={16},
  [354]={14}, [487]={14}, [469]={14}, [355]={13,14},
}

local T_Main, T_Player, T_Item
local F_player, F_inv, F_itemtype, F_adjtile, M_getmyplayer
local T_IS, F_isitem, F_bank, F_bank2, F_bank3, F_bank4
local scan_arr, scan_storage, rd, arr_get
local g_dbg = 0

local function scan_arr(a, want, lim)
  local n = 0
  pcall(function() n = P.array_length(a) end)
  if not n or n <= 0 then return end
  if lim and n > lim then n = lim end
  for i = 0, n - 1 do
    local it = arr_get(a, i)
    if it then
      local t = rd(F_itemtype, it, "int32")
      if t and ST[t] then
        local tid = ST[t]
        want[tid] = true
        local al = ALIAS[tid]
        if al then for _,x in ipairs(al) do want[x] = true end end
      end
    end
  end
end

local function scan_storage(me, fbank, want)
  if not (fbank and T_IS and F_isitem) then return end
  local ok, st = pcall(P.get_field_value, fbank, me, "object")
  if not (ok and st) then return end
  local ok2, a = pcall(P.get_field_value, F_isitem, st, "object")
  if not (ok2 and a) then return end
  scan_arr(a, want)
end

local function tick()
  local arr = rd(F_player, nil, "object")
  if not arr then return end
  local ok, mi = pcall(P.invoke, M_getmyplayer, nil)
  if not (ok and type(mi) == "number") then return end
  local ok2, me = pcall(P.array_at, arr, mi)
  if not (ok2 and me) then return end
  local inv = rd(F_inv, me, "object")
  if not inv then return end
  local adj = rd(F_adjtile, me, "object")
  if not adj then return end
  local want = {}
  scan_arr(inv, want, 59)
  scan_storage(me, F_bank, want)
  scan_storage(me, F_bank2, want)
  scan_storage(me, F_bank3, want)
  scan_storage(me, F_bank4, want)
  local n2 = 0
  for tid, _ in pairs(want) do
    n2 = n2 + 1
    pcall(P.array_set, adj, tid, true, "bool")
  end
  g_dbg = g_dbg + 1
  if g_dbg % 60 == 0 then
    local s = ""
    for tid, _ in pairs(want) do s = s .. tid .. "," end
    log(("TICK hit=%d [%s]"):format(n2, s))
  end
end

function setup()
  if _G.g_cs_done then return end
  _G.g_cs_done = true
  log("=== craftstation 1.2.0 setup ===")
  T_Main   = P.get_type("Terraria", "Main")
  T_Player = P.get_type("Terraria", "Player")
  T_Item   = P.get_type("Terraria", "Item")
  if not (T_Main and T_Player and T_Item) then log("TYPE NIL"); return end
  F_player      = P.get_field(T_Main, "player")
  M_getmyplayer = P.get_method(T_Main, "get_myPlayer", 0)
  F_inv         = P.get_field(T_Player, "inventory")
  F_itemtype    = P.get_field(T_Item, "type")
  F_adjtile     = P.get_field(T_Player, "adjTile")
  F_bank        = P.get_field(T_Player, "bank")
  F_bank2       = P.get_field(T_Player, "bank2")
  F_bank3       = P.get_field(T_Player, "bank3")
  F_bank4       = P.get_field(T_Player, "bank4")
  T_IS          = P.get_type("Terraria", "InventoryStorage")
  if T_IS then F_isitem = P.get_field(T_IS, "item") end
  arr_get = function(a, i, ty)
    local o, v = pcall(P.array_at, a, i, ty); if o then return v end
  end
  rd = function(field, inst, ty)
    local o, v = pcall(P.get_field_value, field, inst, ty); if o then return v end
  end
  local M_upd = P.get_method(T_Main, "Update", 1) or P.get_method(T_Main, "Update", 0)
  if M_upd then
    local ok = pcall(P.install_hook, M_upd, { postfix = function() pcall(tick) end })
    log("HOOK ok=" .. tostring(ok))
  else
    log("HOOK FAIL")
  end
end

todo_list = { "setup" }
