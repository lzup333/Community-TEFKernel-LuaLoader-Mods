-- 增益家具 v1.0.0
mod.meta = { pkg_id = "lua.qing.autofurniture", version = "1.0.0", version_code = 100, api_version = 1 }
local P = mod.patch

local function log(s) end

local MAP = {
  [966]=87, [3046]=87, [3047]=87, [3048]=87, [3049]=87, [3050]=87,
  [3723]=87, [3724]=87, [4689]=87, [4690]=87, [4691]=87, [4692]=87,
  [4693]=87, [4694]=87,
  [1859]=89, [1431]=158, [487]=29, [2177]=93, [2999]=150,
  [3814]=348, [3198]=159, [4276]=215, [3117]=157, [63]=146,
  [148]=86, [5322]=350,
}

local MAXBUFF  = 44
local BUFFTIME = 2

local T_Main, T_Player
local F_player, F_inv, F_itemtype, F_btype, F_btime
local F_bank, F_bank2, F_bank3, F_bank4, F_isitem, T_IS
local M_getmyplayer
local g_tick = 0
local g_dbg = 0

local function rd(field, inst, ty)
  local ok, v = pcall(P.get_field_value, field, inst, ty)
  if ok then return v end
  return nil
end
local function arr_get(arr, i, ty)
  local ok, v = pcall(P.array_at, arr, i, ty)
  if ok then return v end
  return nil
end

local function scan_arr(arr, want, lim)
  local cnt = 0
  local n = 0
  pcall(function() n = P.array_length(arr) end)
  if not n or n <= 0 then return 0 end
  if lim and n > lim then n = lim end
  for i = 0, n - 1 do
    local it = arr_get(arr, i)
    if it then
      local t = rd(F_itemtype, it, "int32")
      if t and t > 0 then
        cnt = cnt + 1
        if MAP[t] then want[MAP[t]] = true end
      end
    end
  end
  return cnt
end

-- 扫一个 InventoryStorage(bank/bank2/...) 的 .item
local function scan_storage(me, fbank, want)
  if not (fbank and T_IS and F_isitem) then return 0 end
  local ok, st = pcall(P.get_field_value, fbank, me, "object")
  if not (ok and st) then return 0 end
  local ok2, arr = pcall(P.get_field_value, F_isitem, st, "object")
  if not (ok2 and arr) then return 0 end
  return scan_arr(arr, want)
end

local function scan_bag(inv)
  local want = {}
  local cnt = scan_arr(inv, want, 59)
  return want, cnt
end

local function give_buff(me, bid)
  local ba = rd(F_btype, me, "object")
  local bt = rd(F_btime, me, "object")
  if not (ba and bt) then return "noarr" end
  local free = -1
  for i = 0, MAXBUFF - 1 do
    local cur = arr_get(ba, i, "int32")
    if cur == bid then
      local ok = pcall(P.array_set, bt, i, BUFFTIME, "int32")
      local rb = arr_get(bt, i, "int32")
      return ("refresh slot=%d ok=%s rb=%s"):format(i, tostring(ok), tostring(rb))
    elseif cur == 0 and free < 0 then
      free = i
    end
  end
  if free >= 0 then
    local ok1 = pcall(P.array_set, ba, free, bid, "int32")
    local ok2 = pcall(P.array_set, bt, free, BUFFTIME, "int32")
    local rb = arr_get(bt, free, "int32")
    return ("newslot slot=%d ok1=%s ok2=%s rb=%s"):format(free, tostring(ok1), tostring(ok2), tostring(rb))
  end
  return "full"
end

local function tick()
  g_tick = g_tick + 1
  if g_tick < 2 then return end
  g_tick = 0
  local arr = rd(F_player, nil, "object")
  if not arr then return end
  local ok, mi = pcall(P.invoke, M_getmyplayer, nil)
  if not (ok and type(mi) == "number") then
    g_dbg = g_dbg + 1
    if g_dbg % 60 == 0 then log("TICK mi_bad ok=" .. tostring(ok) .. " mi=" .. tostring(mi)) end
    return
  end
  local me = arr_get(arr, mi)
  if not me then return end
  local inv = rd(F_inv, me, "object")
  if not inv then return end
  local want, cnt = scan_bag(inv)
  cnt = cnt + scan_storage(me, F_bank, want)
  cnt = cnt + scan_storage(me, F_bank2, want)
  cnt = cnt + scan_storage(me, F_bank3, want)
  cnt = cnt + scan_storage(me, F_bank4, want)
  local n = 0
  local ids = ""
  local det = ""
  for bid, _ in pairs(want) do
    n = n + 1
    ids = ids .. bid .. ","
    det = det .. "[" .. give_buff(me, bid) .. "]"
  end
  g_dbg = g_dbg + 1
  if g_dbg % 30 == 0 then
    log(("TICK mi=%s totalItems=%d hit=%d [%s] det=%s"):format(tostring(mi), cnt, n, ids, det))
  end
end

function setup()
  if _G.g_af_done then return end
  _G.g_af_done = true
  log("=== autofurniture 1.1.0 setup ===")
  T_Main   = P.get_type("Terraria", "Main")
  T_Player = P.get_type("Terraria", "Player")
  if not (T_Main and T_Player) then log("TYPE NIL"); return end
  F_player      = P.get_field(T_Main, "player")
  M_getmyplayer = P.get_method(T_Main, "get_myPlayer", 0)
  F_inv         = P.get_field(T_Player, "inventory")
  local T_Item  = P.get_type("Terraria", "Item")
  F_itemtype    = P.get_field(T_Item, "type")
  F_btype       = P.get_field(T_Player, "buffType")
  F_btime       = P.get_field(T_Player, "buffTime")
  F_bank        = P.get_field(T_Player, "bank")
  F_bank2       = P.get_field(T_Player, "bank2")
  F_bank3       = P.get_field(T_Player, "bank3")
  F_bank4       = P.get_field(T_Player, "bank4")
  T_IS          = P.get_type("Terraria", "InventoryStorage")
  if T_IS then F_isitem = P.get_field(T_IS, "item") end
  log(("F player=%s gmp=%s inv=%s itype=%s btype=%s btime=%s"):format(
    tostring(F_player~=nil), tostring(M_getmyplayer~=nil), tostring(F_inv~=nil),
    tostring(F_itemtype~=nil), tostring(F_btype~=nil), tostring(F_btime~=nil)))
  local M_upd = P.get_method(T_Main, "Update", 1) or P.get_method(T_Main, "Update", 0)
  if M_upd then
    local ok = pcall(P.install_hook, M_upd, { postfix = function() pcall(tick) end })
    log("HOOK ok=" .. tostring(ok))
  else
    log("HOOK FAIL: Update nil")
  end
end

todo_list = { "setup" }
