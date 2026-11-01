-- NPC入住 v1.0.0
mod.meta = { pkg_id = "lua.qing.npchome", version = "1.0.1", version_code = 101, api_version = 1 }
local P = mod.patch

local function log(s) end

local Main, T_NPC
local F_npcArr, F_active, F_type, F_pos, F_vel, F_hx, F_hy, F_who, F_h, F_tp
local g_prev = {}

local function rd(field, inst, ty)
  local ok,v = pcall(P.get_field_value, field, inst, ty)
  if ok then return v end
  return nil
end
local function rdv(field, inst)
  local ok,x,y = pcall(P.get_field_vec2, field, inst)
  if ok then return x,y end
  return nil
end

-- 已经瞬移过的 (who -> hx:hy)，只有家再次变化才重复动作
local function move_home(npc, who, s, reason)
  if s.hx < 0 or s.hy < 0 then
    log(("SKIP who=%s ty=%s hx=%s hy=%s (%s, invalid)"):format(who,s.ty,s.hx,s.hy,reason))
    return
  end
  local h = rd(F_h, npc, "int32") or 42
  local px = s.hx * 16
  local py = s.hy * 16 - h
  pcall(P.set_field_vec2, F_pos, npc, px, py)
  pcall(P.set_field_vec2, F_vel, npc, 0.0, 0.0)
  pcall(P.set_field_value, F_tp, npc, true, "bool")
  local rx,ry = rdv(F_pos, npc)
  log(("MOVE who=%s ty=%s home(%s,%s) -> pos(%s,%s) rb=(%s,%s) [%s] done"):format(
    who,s.ty,s.hx,s.hy,px,py,tostring(rx),tostring(ry),reason))
end

-- 分片轮询：每帧只扫 CHUNK 个槽，游标循环；200槽/50帧 ≈ 0.83秒轮完一遍
local CHUNK = 4
local g_cursor = 0

local function scan()
  local arr = rd(F_npcArr, nil, "object")
  if not arr then return end
  local n = 0
  pcall(function() n = P.array_length(arr) end)
  if not n or n <= 0 then return end
  if n > 200 then n = 200 end
  local walked = 0
  while walked < CHUNK do
    if g_cursor >= n then g_cursor = 0 end
    local i = g_cursor
    g_cursor = g_cursor + 1
    walked = walked + 1
    local ok, npc = pcall(P.array_at, arr, i)
    if ok and npc then
      local act = rd(F_active, npc, "bool")
      if act then
        local who = rd(F_who, npc, "int32") or i
        local st = {
          hx = rd(F_hx, npc, "int32") or -1,
          hy = rd(F_hy, npc, "int32") or -1,
          ty = rd(F_type, npc, "int32") or -1,
        }
        local key = tostring(who)
        local p = g_prev[key]
        if not p then
          if st.hx >= 0 and st.hy >= 0 then
            move_home(npc, key, st, "first")
          end
          g_prev[key] = st
        elseif p.hx ~= st.hx or p.hy ~= st.hy then
          move_home(npc, key, st, "chg")
          g_prev[key] = st
        end
      end
    end
  end
end

local function init()
  Main  = P.get_type("Terraria","Main")
  T_NPC = P.get_type("Terraria","NPC")
  log("=== npchome 0.3.2 init ===")
  if not (Main and T_NPC) then log("type nil"); return end
  F_npcArr  = P.get_field(Main,"npc")
  F_active  = P.get_field(T_NPC,"active")
  F_type    = P.get_field(T_NPC,"type")
  F_pos     = P.get_field(T_NPC,"position")
  F_vel     = P.get_field(T_NPC,"velocity")
  F_h       = P.get_field(T_NPC,"height")
  F_hx      = P.get_field(T_NPC,"homeTileX")
  F_hy      = P.get_field(T_NPC,"homeTileY")
  F_who     = P.get_field(T_NPC,"whoAmI")
  F_tp      = P.get_field(T_NPC,"teleporting")
  log("f pos="..tostring(F_pos~=nil).." vel="..tostring(F_vel~=nil).." hx="..tostring(F_hx~=nil).." tp="..tostring(F_tp~=nil))

  local M_upd = P.get_method(Main,"Update",1)
  if not M_upd then M_upd = P.get_method(Main,"Update",0) end
  if M_upd then
    pcall(P.install_hook, M_upd, {postfix=function() pcall(scan) end})
  end
  log("hook ok="..tostring(M_upd~=nil))
end

function setup()
  if _G.g_npchome_done then return end
  _G.g_npchome_done = true
  pcall(init)
end

todo_list = { "setup" }
