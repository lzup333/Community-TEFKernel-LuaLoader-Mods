-- 更好的体验 v1.2.0  四合一：战斗(增益家具) + 制作(制作站随身) + 晶塔 + NPC入住
-- 单页面板：刷怪倍率滑条 + 可展开的功能开关组；状态写私有目录 ui_state.txt
mod.meta = { pkg_id = "lua.qing.betterexperience", version = "1.6.5", version_code = 1641, api_version = 1 }
local P = mod.patch
local g = mod.gui

-- ==== 气候(时间/天气) 状态 · 必须在任何绘制函数之前声明 ====
local cur_tab = 1   -- 1=属性, 2=气候, 3=刷怪倍率, 4=配置
local C = {}        -- Main 类气候字段句柄
local W = {}        -- WorldFile 类气候字段句柄
local SS = {}       -- Terraria.GameContent.Events.Sandstorm 字段句柄
local CB = {}       -- bool 字段标记
local CT = {}       -- 类型
local g_rain_hold = nil
local g_wind_hold = nil
local g_time_hold = nil
local g_freeze = false
local ch_time = true
local ch_weather = true
local ch_special = false

local LOGF = "/sdcard/Download/betterexp.txt"
local function log(s)
  -- 发布版：日志关闭
end

-- ============================================================
--  开关状态：读写私有目录 ui_state.txt（简单 key=0/1）
-- ============================================================
local S = {
  buff       = true,    -- 战斗：增益家具
  craft      = true,    -- 制作：制作站随身
  pylon_num  = true,    -- 晶塔：取消数量限制
  pylon_npc  = true,    -- 晶塔：取消所需NPC限制
  npc        = true,    -- NPC入住
  banner     = true,    -- 旗帜随身（Test：强制true）
  spawn      = 1.0,     -- 刷怪倍率（0=关闭，1=原版）
  grow       = false,   -- 植物生长加速（树/草药/草）
}

local STATE_KEY = { "buff", "craft", "pylon_num", "pylon_npc", "npc", "grow" }

local function state_path()
  local d = mod.private_dir
  if type(d) ~= "string" then return nil end
  return d .. "/ui_state.txt"
end

local function load_state()
  local p = state_path()
  if not p then log("load_state: private_dir 不可用"); return end
  local f = io.open(p, "r")
  if not f then log("load_state: 无文件，用默认"); return end
  local txt = f:read("*a") or ""
  f:close()
  for k, v in txt:gmatch("(%w+)=(%d)") do
    if S[k] ~= nil then S[k] = (v == "1") end
  end
  local sp = txt:match("spawn=([%d%.]+)")
  if sp then S.spawn = tonumber(sp) or 1.0 end
  log("load_state ok: buff="..tostring(S.buff).." craft="..tostring(S.craft).." pnum="..tostring(S.pylon_num).." pnpc="..tostring(S.pylon_npc).." npc="..tostring(S.npc).." grow="..tostring(S.grow).." spawn="..tostring(S.spawn))
end

local function save_state()
  local p = state_path()
  if not p then return end
  local f = io.open(p, "w")
  if not f then log("save_state: 打不开 "..tostring(p)); return end
  for _, k in ipairs(STATE_KEY) do
    f:write(k.."="..(S[k] and "1" or "0").."\n")
  end
  f:write("spawn="..string.format("%.2f", S.spawn).."\n")
  f:close()
end

-- ============================================================
--  公共读取
-- ============================================================
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

local T_Main, T_Player, T_NPC, T_Item, T_IS
local F_player, F_inv, F_itemtype, F_btype, F_btime, F_adjtile
local F_bank, F_bank2, F_bank3, F_bank4, F_isitem
local M_getmyplayer
local M_getr, F_sa
local F_npcArr, F_npc_active, F_npc_type, F_npc_pos, F_npc_vel, F_npc_hx, F_npc_hy, F_npc_who, F_npc_h, F_npc_tp

-- ============================================================
--  战斗：增益家具
-- ============================================================
local BUFF_MAP = {
  [966]=87, [3046]=87, [3047]=87, [3048]=87, [3049]=87, [3050]=87,
  [3723]=87, [3724]=87, [4689]=87, [4690]=87, [4691]=87, [4692]=87,
  [4693]=87, [4694]=87,
  [1859]=89, [1431]=158, [487]=29, [2177]=93, [2999]=150,
  [3814]=348, [3198]=159, [4276]=215, [3117]=157, [63]=146,
  [148]=86, [5322]=350, [621]=192,
}
local MAXBUFF  = 44
local BUFFTIME = 2

local function give_buff(me, bid)
  local ba = rd(F_btype, me, "object")
  local bt = rd(F_btime, me, "object")
  if not (ba and bt) then return end
  local free = -1
  for i = 0, MAXBUFF - 1 do
    local cur = arr_get(ba, i, "int32")
    if cur == bid then
      pcall(P.array_set, bt, i, BUFFTIME, "int32")
      return
    elseif cur == 0 and free < 0 then
      free = i
    end
  end
  if free >= 0 then
    pcall(P.array_set, ba, free, bid, "int32")
    pcall(P.array_set, bt, free, BUFFTIME, "int32")
  end
end

-- ============================================================
--  制作：制作站随身
-- ============================================================
local CRAFT_ST = {
  [31]=13, [35]=16, [716]=16, [33]=17, [36]=18, [221]=77, [332]=86, [352]=94,
  [345]=96, [354]=101, [363]=106, [398]=114, [487]=125, [524]=133, [525]=134,
  [995]=217, [996]=218, [997]=219, [998]=220, [1120]=228, [1430]=243, [1551]=247,
  [2172]=283, [2192]=300, [2193]=301, [2194]=302, [2195]=303, [2196]=304,
  [2197]=305, [2198]=306, [2203]=307, [2204]=308, [3000]=355, [3549]=412, [5008]=622,
}
local CRAFT_ALIAS = {
  [77]={17}, [302]={17}, [133]={17,77}, [134]={16},
  [354]={14}, [487]={14}, [469]={14}, [355]={13,14},
}

local function make_item_sources(me)
  local src = {}
  local inv = rd(F_inv, me, "object")
  src[1] = { arr = inv, lim = 59 }
  local banks = { F_bank, F_bank2, F_bank3, F_bank4 }
  for k = 1, 4 do
    local fb = banks[k]
    local a = false
    if fb and T_IS and F_isitem then
      local ok, st = pcall(P.get_field_value, fb, me, "object")
      if ok and st then
        local ok2, x = pcall(P.get_field_value, F_isitem, st, "object")
        if ok2 and x then a = x end
      end
    end
    src[k + 1] = { arr = a }
  end
  return src
end

local g_tick_npc = { cursor = 0 }

local function get_me()
  local arr = rd(F_player, nil, "object")
  if not arr then return nil end
  local ok, mi = pcall(P.invoke, M_getmyplayer, nil)
  if not (ok and type(mi) == "number") then return nil end
  return arr_get(arr, mi)
end

local g_tick = 0
local g_buff_now = false
local function scan_items_tick(me)
  local adj = rd(F_adjtile, me, "object")
  local src = make_item_sources(me)
  for k = 1, #src do
    local s0 = src[k]
    if s0.arr then
      local n = 0
      pcall(function() n = P.array_length(s0.arr) end)
      if n and n > 0 then
        if s0.lim and n > s0.lim then n = s0.lim end
        for i = 0, n - 1 do
          local it = arr_get(s0.arr, i)
          if it then
            local t = rd(F_itemtype, it, "int32")
            if t then
              if S.buff then
                local bid = BUFF_MAP[t]
                if bid and g_buff_now then pcall(give_buff, me, bid) end
              end
              if S.craft then
                local tid = CRAFT_ST[t]
                if tid and adj then
                  pcall(P.array_set, adj, tid, true, "bool")
                  local al = CRAFT_ALIAS[tid]
                  if al then for _, x in ipairs(al) do pcall(P.array_set, adj, x, true, "bool") end end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- ============================================================
--  刷怪倍率：改 NPC.defaultSpawnRate(默认600,越小越快) + defaultMaxSpawns(默认5,上限)
-- ============================================================
local F_dsr, F_dms, F_netmode, M_gamemenu, F_worldname
local g_sp_last = -1

-- 是否在世界里（主菜单 gameMenu=true 时不弹窗口）
-- Main.gameMenu 是属性，走 getter
local function in_world()
  -- 主判据：gameMenu（属性 getter），退世界立刻变 true
  if M_gamemenu then
    local ok, v = pcall(P.invoke, M_gamemenu, nil)
    if ok and type(v) == "boolean" then return not v end
  end
  -- 兜底：worldName 非空 = 在世界里
  if F_worldname then
    local ok, v = pcall(P.get_field_value, F_worldname, nil, "string")
    if ok and type(v) == "string" then return v ~= "" end
  end
  return false
end

-- 只有单人(0)或主机(2)可用；客机(1)禁用
local function net_ok()
  if not F_netmode then return true end
  local ok, v = pcall(P.get_field_value, F_netmode, nil, "int32")
  if not ok or type(v) ~= "number" then return true end
  return (v == 0 or v == 2)
end

-- 当前联机模式文案
local function net_label()
  if not F_netmode then return "单人" end
  local ok, v = pcall(P.get_field_value, F_netmode, nil, "int32")
  if not ok or type(v) ~= "number" then return "单人" end
  if v == 1 then return "客机"
  elseif v == 2 then return "主机"
  else return "单人" end
end

local function spawn_calc(rate)
  if rate <= 0 then return 999999, 0 end
  local sr = math.floor(600 / rate + 0.5)
  local ms = math.floor(5 * rate + 0.5)
  if sr < 1 then sr = 1 end
  if ms < 1 then ms = 1 end
  if ms > 500 then ms = 500 end
  return sr, ms
end

local g_vis_n = 0
local function tick_visible()
  if type(g) ~= "table" then return end
  local w = in_world()
  g_vis_n = g_vis_n + 1
  -- 进/退世界的瞬间都强制收起成小图标（手动展开后不会被反复收回）
  if w ~= _G.g_last_in_world then
    _G.g_last_in_world = w
    if type(g.set_collapsed) == "function" then pcall(g.set_collapsed, true) end
    log("WORLD CHANGE -> "..tostring(w).." collapsed=true")
  end

end

local function tick_spawn()
  if not F_dsr then return end
  if not net_ok() then
    -- 客机：恢复默认，不干扰主机
    pcall(P.set_field_value, F_dsr, nil, 600, "int32")
    pcall(P.set_field_value, F_dms, nil, 5, "int32")
    return
  end
  local sr, ms = spawn_calc(S.spawn)
  pcall(P.set_field_value, F_dsr, nil, sr, "int32")
  pcall(P.set_field_value, F_dms, nil, ms, "int32")
  if S.spawn ~= g_sp_last then
    g_sp_last = S.spawn
    log("spawn apply rate="..string.format("%.1f", S.spawn).." sr="..sr.." ms="..ms)
  end
end

local function tick_grow() end -- 植物生长加速已废弃（不能清 genRand）

local function tick_buff()
  if not (S.buff or S.craft) then return end   -- 两个都关 → 不扫
  g_tick = g_tick + 1
  if g_tick >= 2 then g_tick = 0; g_buff_now = true else g_buff_now = false end
  local me = get_me()
  if not me then return end
  scan_items_tick(me)
end

-- ============================================================
--  NPC tick：入住瞬移
-- ============================================================
local g_prev = {}
local CHUNK_NPC = 4
local function move_home(npc, who, st)
  if st.hx < 0 or st.hy < 0 then return end
  local h = rd(F_npc_h, npc, "int32") or 42
  local px = st.hx * 16
  local py = st.hy * 16 - h
  pcall(P.set_field_vec2, F_npc_pos, npc, px, py)
  pcall(P.set_field_vec2, F_npc_vel, npc, 0.0, 0.0)
  pcall(P.set_field_value, F_npc_tp, npc, true, "bool")
end
local function tick_npc()
  if not S.npc then return end
  local arr = rd(F_npcArr, nil, "object")
  if not arr then return end
  local n = 0
  pcall(function() n = P.array_length(arr) end)
  if not n or n <= 0 then return end
  if n > 200 then n = 200 end
  local walked = 0
  while walked < CHUNK_NPC do
    if g_tick_npc.cursor >= n then g_tick_npc.cursor = 0 end
    local i = g_tick_npc.cursor
    g_tick_npc.cursor = g_tick_npc.cursor + 1
    walked = walked + 1
    local npc = arr_get(arr, i)
    if npc then
      local act = rd(F_npc_active, npc, "bool")
      if act then
        local who = rd(F_npc_who, npc, "int32") or i
        local st = {
          hx = rd(F_npc_hx, npc, "int32") or -1,
          hy = rd(F_npc_hy, npc, "int32") or -1,
        }
        local key = tostring(who)
        local p = g_prev[key]
        if not p then
          if st.hx >= 0 and st.hy >= 0 then move_home(npc, key, st) end
          g_prev[key] = st
        elseif p.hx ~= st.hx or p.hy ~= st.hy then
          move_home(npc, key, st)
          g_prev[key] = st
        end
      end
    end
  end
end

-- ============================================================
--  晶塔：两道 hook（每次 setup 装一次，行为按 S.pylon_num/S.pylon_npc 现判）
-- ============================================================
local function pylon_setup()
  local T = P.get_type("Terraria.GameContent", "TeleportPylonsSystem")
  if not T then log("pylon: 类型拿不到"); return end
  -- 开→返回 false/true 解除限制；关→返回 nil（override 遇 nil 不覆盖，保持原逻辑）
  local m1 = P.get_method(T, "HasPylonOfType", 1)
  if m1 then
    pcall(P.install_hook, m1, {
      postfix = function() if S.pylon_num then return false end return nil end,
      override_result = true })
  end
  local m2 = P.get_method(T, "DoesPositionHaveEnoughNPCs", 2)
  if m2 then
    pcall(P.install_hook, m2, {
      postfix = function() if S.pylon_npc then return true end return nil end,
      override_result = true })
  end
  log("pylon hooks ok m1="..tostring(m1 ~= nil).." m2="..tostring(m2 ~= nil))
end

-- ============================================================
--  GUI 面板（单页）
-- ============================================================
local IMG = {}
local has_image_api = false
local THEME = {
  panel  = {33, 67, 78, 245},
  title  = {29, 57, 69, 255},
  button = {46, 91, 105, 255},
  hover  = {66, 122, 138, 255},
  active = {86, 148, 164, 255},
  border = {9, 19, 27, 255},
  text   = {228, 237, 232, 255},
}
local GOLD = {232, 220, 165, 255}
local GREEN = {120, 200, 120, 255}
local GRAY = {150, 150, 150, 255}

local skin_done = false
local function ensure_images()
  if type(g) ~= "table" then return end
  if not has_image_api then return end
  if not IMG.panel then
    IMG.panel  = g.load_image("lib/ui/panel.png")
    IMG.icon   = g.load_image("lib/ui/leaf.png")
    IMG.white  = g.load_image("lib/ui/white.png")
    log("images: panel="..tostring(IMG.panel).." icon="..tostring(IMG.icon).." white="..tostring(IMG.white))
  end
  if not skin_done and IMG.panel and IMG.icon then
    pcall(g.set_skin, IMG.panel, 10, IMG.icon, 48)
    skin_done = true
  end
end

-- 功能开关行：只写功能名 + 开关状态
local function toggle_row(label, key)
  local on = S[key] == true
  local nv = g.checkbox(label .. "：" .. (on and "开" or "关"), on)
  if nv ~= on then
    S[key] = nv
    save_state()
  end
end

local cfg_open = false

-- ============================================================
--  属性页：装备/饰品加成
-- ============================================================
local T_Player, F_meleeDamage, F_magicDamage, F_rangedDamage, F_minionDamage
local F_meleeCrit, F_magicCrit, F_rangedCrit
local F_statDefense, F_moveSpeed, F_luck
local F_player_arr, M_get_myPlayer
local attr_ready = false
local function attr_setup()
  if attr_ready then return end
  local P = mod.patch
  if not P then return end
  T_Player = P.get_type("Terraria", "Player")
  if not T_Player then return end
  F_meleeDamage  = P.get_field(T_Player, "meleeDamage")
  F_magicDamage  = P.get_field(T_Player, "magicDamage")
  F_rangedDamage = P.get_field(T_Player, "rangedDamage")
  F_minionDamage = P.get_field(T_Player, "minionDamage")
  F_meleeCrit    = P.get_field(T_Player, "meleeCrit")
  F_magicCrit    = P.get_field(T_Player, "magicCrit")
  F_rangedCrit   = P.get_field(T_Player, "rangedCrit")
  F_statDefense  = P.get_field(T_Player, "statDefense")
  F_moveSpeed    = P.get_field(T_Player, "moveSpeed")
  F_luck         = P.get_field(T_Player, "luck")
  local T_Main = P.get_type("Terraria", "Main")
  F_player_arr   = P.get_field(T_Main, "player")
  M_get_myPlayer = P.get_method(T_Main, "get_myPlayer", 0)
  attr_ready = true
end

-- 读 float 字段（pcall 保护）
local function rfloat(f, inst)
  if not f or not inst then return nil end
  local ok, v = pcall(mod.patch.get_field_value, f, inst, "float")
  if ok and type(v) == "number" then return v end
  return nil
end
-- 读 int 字段
local function rint(f, inst)
  if not f or not inst then return nil end
  local ok, v = pcall(mod.patch.get_field_value, f, inst, "int32")
  if ok and type(v) == "number" then return v end
  return nil
end

local GREEN = {120, 200, 120, 255}
local RED   = {220, 100, 100, 255}
local NEU   = {150, 150, 150, 255}

local function col_of(delta)
  if delta > 0.0001 then return GREEN
  elseif delta < -0.0001 then return RED
  else return NEU end
end

-- 每排两个：左值 + 右值（label + 数值）
local function attr_row(l1, v1, d1, l2, v2, d2)
  if l2 then
    g.same_line()
  end
end

local function draw_attrs()
  if not in_world() then g.text("未识别到玩家", NEU); return end
  if not attr_ready then attr_setup() end
  local P = mod.patch
  if not attr_ready then g.text("属性不可用（未就绪）", NEU); return end
  -- 取 player 实例
  local inst = nil
  do
    local ok, mp = pcall(P.invoke, M_get_myPlayer, nil)
    if ok and type(mp) == "number" then
      local oka, arr = pcall(P.get_field_value, F_player_arr, nil, "object")
      if oka and arr then
        local okb, pl = pcall(P.array_at, arr, mp)
        if okb then inst = pl end
      end
    end
  end
  if not inst then g.text("未识别到玩家", NEU); return end

  local md  = rfloat(F_meleeDamage, inst)  or 1.0
  local gd  = rfloat(F_magicDamage, inst)  or 1.0
  local rd  = rfloat(F_rangedDamage, inst) or 1.0
  local sd  = rfloat(F_minionDamage, inst) or 1.0
  local mc  = rint(F_meleeCrit, inst)  or 0
  local gc  = rint(F_magicCrit, inst)  or 0
  local rc  = rint(F_rangedCrit, inst) or 0
  local df  = rint(F_statDefense, inst) or 0
  local ms  = rfloat(F_moveSpeed, inst)   or 1.0
  local lk  = rfloat(F_luck, inst)        or 0.0

  local function pct(x) return string.format("%+.0f%%", x * 100) end
  local function pcti(x) return string.format("%+d%%", x) end

  -- 每排两个：标签黄色 + 数值按正负绿/红；用 same_line 拼一行四段
  -- 每排两个，各占一半宽：全部用 text_at 绝对坐标（不碰流式 cy）
  local ROW = 32       -- 行高
  local COL2 = 178     -- 右列起始 x（内容宽约356的一半）
  local row_y = 46       -- 从页签栏下方开始
  local function draw_pair(l1, s1, d1, l2, s2, d2)
    local y = row_y
    -- 左列
    g.text_at(0, y, l1, GOLD)
    if type(g.text_width) == "function" then
      g.text_at(4 + (g.text_width(l1) or 48), y, s1, col_of(d1))
    else
      g.text_at(88, y, s1, col_of(d1))
    end
    -- 右列
    if l2 then
      g.text_at(COL2, y, l2, GOLD)
      if type(g.text_width) == "function" then
        g.text_at(COL2 + 4 + (g.text_width(l2) or 48), y, s2, col_of(d2))
      else
        g.text_at(COL2 + 88, y, s2, col_of(d2))
      end
    end
    row_y = row_y + ROW
  end
  draw_pair("近战伤害", pct(md - 1), md - 1, "远程伤害", pct(rd - 1), rd - 1)
  draw_pair("魔法伤害", pct(gd - 1), gd - 1, "召唤伤害", pct(sd - 1), sd - 1)
  draw_pair("近战暴击", pcti(mc), mc, "远程暴击", pcti(rc), rc)
  draw_pair("魔法暴击", pcti(gc), gc, "防御", string.format("%+d", df), df)
  draw_pair("移速", pct(ms - 1), ms - 1, "幸运", string.format("%+.2f", lk), lk)
  -- 把内容高度撑到最后一行的底部，保证窗口完整
  if type(g.set_content_height) == "function" then g.set_content_height(row_y) end
end


-- ============================================================
--  气候：时间 / 天气 / 特殊
-- ============================================================
-- Main 类气候字段
local C_NAMES = { "dayTime","time","moonPhase","moonType","sunModY","moonModY","numStars",
  "raining","maxRaining","rainTime","maxRain",
  "numClouds","cloudAlpha","cloudBGAlpha","cloudBGActive",
  "windSpeedTarget","windSpeedCurrent",
  "lightning","thunderDelay","thunderDistance",
  "bloodMoon","pumpkinMoon","snowMoon","eclipse","eclipseLight",
  "weatherCounter","atmo" }
local C_BOOL  = { dayTime=true, raining=true, bloodMoon=true, eclipse=true,
  pumpkinMoon=true, snowMoon=true }
local C_TYPE  = { dayTime="bool", time="double", moonPhase="int32", moonType="int32",
  sunModY="short", moonModY="short", numStars="int32",
  raining="bool", maxRaining="float", rainTime="int32", maxRain="int32",
  numClouds="int32", cloudAlpha="float", cloudBGAlpha="float", cloudBGActive="float",
  windSpeedTarget="float", windSpeedCurrent="float",
  lightning="float", thunderDelay="int32", thunderDistance="int32",
  bloodMoon="bool", pumpkinMoon="bool", snowMoon="bool", eclipse="bool", eclipseLight="float",
  weatherCounter="int32", atmo="float" }

-- WorldFile 类气候字段(沙尘暴等)
local W_NAMES = { "_tempSandstormHappening","_tempSandstormTimeLeft",
  "_tempSandstormSeverity","_tempSandstormIntendedSeverity",
  "_tempPartyGenuine","_tempPartyManual","_tempPartyCooldown",
  "_tempLanternNightGenuine","_tempLanternNightManual","_tempLanternNightCooldown",
  "_isWorldOnCloud" }
local W_BOOL  = { _tempSandstormHappening=true, _tempPartyGenuine=true, _tempPartyManual=true,
  _tempLanternNightGenuine=true, _tempLanternNightManual=true, _isWorldOnCloud=true }
local W_TYPE  = { _tempSandstormHappening="bool", _tempSandstormTimeLeft="int32",
  _tempSandstormSeverity="float", _tempSandstormIntendedSeverity="float",
  _tempPartyGenuine="bool", _tempPartyManual="bool", _tempPartyCooldown="int32",
  _tempLanternNightGenuine="bool", _tempLanternNightManual="bool", _tempLanternNightCooldown="int32",
  _isWorldOnCloud="bool" }

local function c_rd_bool(fld)
  local ok, ptr = pcall(P.field_pointer, fld, nil)
  if not (ok and ptr) then return false end
  local ok2, bs = pcall(P.mem_read, ptr, 0, 1)
  if not (ok2 and bs and #bs >= 1) then return false end
  return string.byte(bs, 1) ~= 0
end
local function c_rd_num(fld, ty)
  local ok, v = pcall(P.get_field_value, fld, nil, ty)
  if ok then return v end
  return 0
end
local function c_rd(n)
  if C_BOOL[n] then return c_rd_bool(C[n]) end
  if W_TYPE[n] then
    if W_BOOL[n] then return c_rd_bool(W[n]) end
    return c_rd_num(W[n], W_TYPE[n])
  end
  return c_rd_num(C[n], C_TYPE[n])
end
local function c_wr_bool(fld, v)
  local ok, ptr = pcall(P.field_pointer, fld, nil)
  if not (ok and ptr) then return end
  pcall(P.mem_write, ptr, 0, string.char(v and 1 or 0))
end
local function c_wr(n, v)
  if W_TYPE[n] then
    if W_BOOL[n] then c_wr_bool(W[n], v) else pcall(P.set_field_value, W[n], nil, v, W_TYPE[n]) end
    return
  end
  if C_BOOL[n] then c_wr_bool(C[n], v) else pcall(P.set_field_value, C[n], nil, v, C_TYPE[n]) end
end

-- 设定游戏时刻(一天): 白天段 time 0=4:30~54000=19:30, 夜晚段独立
local function c_set_clock(hour, minute)
  local m = hour * 60 + minute
  if m >= 270 and m < 1170 then
    c_wr("dayTime", true)
    c_wr("time", (m - 270) * 60 + 0.0)
  else
    local nm = m
    if nm < 270 then nm = nm + 1440 end
    c_wr("dayTime", false)
    c_wr("time", (nm - 1170) * 60 + 0.0)
  end
end

local function draw_climate()
  -- 时间
  local t = c_rd("time")
  local mins = math.floor(t / 60.0 + 270.0) % 1440
  g.text(string.format("游戏时刻 %02d:%02d (%s)", math.floor(mins/60), mins%60,
    c_rd("dayTime") and "白天" or "夜晚"))
  local c = nil
  if g.button("正午 12:00") then c = {12,0} end
  if g.button("午夜 00:00") then c = {0,0} end
  if g.button("黎明 04:30") then c = {4,30} end
  if g.button("黄昏 19:30") then c = {19,30} end
  if c then c_set_clock(c[1], c[2]) end
  g.separator()

  -- 天气：下雨 / 雨量 / 停雨 / 风力 / 风归零 / 打雷 / 云
  local rn = c_rd("raining")
  if g.checkbox("下雨", rn) ~= rn then
    local on = not rn
    c_wr("raining", on)
    if on then
      c_wr("rainTime", 3600)
      g_rain_hold = g_rain_hold or 0.9
    else
      c_wr("rainTime", 0); c_wr("maxRaining", 0.0)
      g_rain_hold = nil
    end
  end
  local rv = g.slider("雨量", (g_rain_hold or c_rd("maxRaining")) * 100.0, 0.0, 100.0)
  if math.abs(rv - (g_rain_hold or c_rd("maxRaining")) * 100.0) >= 0.5 then
    g_rain_hold = rv / 100.0
    c_wr("maxRaining", g_rain_hold)
    if rv <= 0.5 then
      if c_rd("raining") then c_wr("raining", false); c_wr("rainTime", 0) end
    else
      if not c_rd("raining") then c_wr("raining", true) end
    end
  end
  if g.button("停雨") then
    c_wr("raining", false); c_wr("maxRaining", 0.0); c_wr("rainTime", 0)
    g_rain_hold = nil
  end
  local wv = g.slider("风力", (g_wind_hold or c_rd("windSpeedTarget")), -1.0, 1.0)
  if math.abs(wv - (g_wind_hold or c_rd("windSpeedTarget"))) >= 0.02 then
    g_wind_hold = wv
    c_wr("windSpeedTarget", g_wind_hold)
  end
  if g.button("风归零") then g_wind_hold = 0.0; c_wr("windSpeedTarget", 0.0) end
  if g.button("打雷") then
    c_wr("lightning", 1.0)
    c_wr("thunderDelay", 0)
    c_wr("thunderDistance", 300)
  end
  g.text(string.format("云 %d", math.floor(c_rd("numClouds"))))
  g.separator()

  -- 特殊：血月 / 日蚀 / 沙尘暴 / 冻结时间 / 月相
  local bm = c_rd("bloodMoon")
  if g.checkbox("血月", bm) ~= bm then c_wr("bloodMoon", not bm) end
  local ec = c_rd("eclipse")
  if g.checkbox("日蚀", ec) ~= ec then c_wr("eclipse", not ec) end
  local function ss_rd(fld)
    if not fld then return 0 end
    local ok, ptr = pcall(P.field_pointer, fld, nil)
    if not (ok and ptr) then return 0 end
    local ok2, bs = pcall(P.mem_read, ptr, 0, 1)
    if ok2 and bs and #bs >= 1 then return string.byte(bs,1) end
    return 0
  end
  local ss = ss_rd(SS.Happening) ~= 0
  if g.checkbox("沙尘暴", ss) ~= ss then
    local on = not ss
    pcall(P.set_field_value, SS.Happening, nil, on, "bool")
    pcall(P.set_field_value, SS.TimeLeft, nil, on and 36000 or 0, "int32")
    pcall(P.set_field_value, SS.Severity, nil, on and 1.0 or 0.0, "float")
    pcall(P.set_field_value, SS.IntendedSeverity, nil, on and 1.0 or 0.0, "float")
  end
  if g.checkbox("冻结时间", g_freeze) ~= g_freeze then
    g_freeze = not g_freeze
    if g_freeze then g_time_hold = c_rd("time") else g_time_hold = nil end
  end
  g.text("月相：" .. tostring(math.floor(c_rd("moonPhase"))))
  if g.button("月相 +1") then c_wr("moonPhase", (math.floor(c_rd("moonPhase")) + 1) % 8) end
  if g.button("月相归零") then c_wr("moonPhase", 0) end
end

-- 气候字段每帧保持(雨量/风/冻结时间)
local function clim_tick()
  if g_rain_hold then
    c_wr("maxRaining", g_rain_hold)
    c_wr("rainTime", 3600)
  end
  if g_wind_hold then
    c_wr("windSpeedTarget", g_wind_hold)
  end
  if g_time_hold then
    pcall(P.set_field_value, C.time, nil, g_time_hold, "double")
  end
end

local g_og_n = 0
local function on_gui()
  if type(g) ~= "table" then return end
  g_og_n = g_og_n + 1
  local issv = "?"
  if type(g.is_visible) == "function" then local o,v = pcall(g.is_visible); issv = tostring(v) end
  if g_og_n % 180 == 1 then log("OG# "..g_og_n.." in_world="..tostring(in_world()).." is_visible="..issv) end
  pcall(g.set_visible, true)
  -- 首次进世界默认收起
  if not _G.g_default_collapsed then
    _G.g_default_collapsed = true
  end
  has_image_api = (type(g.load_image) == "function")
  ensure_images()
  if IMG.icon then pcall(g.image, IMG.icon, 0, 0, 1, 1, {0,0,0,0}) end
  pcall(g.set_style, THEME)
  pcall(g.set_width, 380)
  pcall(g.set_title, "更好的体验", "册")

  local ok = net_ok()
  local DIS = {140,140,145,255}

  -- 顶部四个按钮：属性 | 气候 | 刷怪倍率 | 配置
  do
    local y = 4
    local gap = 6
    local total = 356
    local tabw = math.floor((total - gap * 3) / 4)
    if type(g.button_at) == "function" then
      if g.button_at(0, y, tabw, 34, "属性") then cur_tab = 1 end
      if g.button_at(tabw + gap, y, tabw, 34, "气候") then cur_tab = 2 end
      if g.button_at((tabw + gap) * 2, y, tabw, 34, "刷怪倍率") then cur_tab = 3 end
      if g.button_at((tabw + gap) * 3, y, tabw, 34, "配置") then cur_tab = 4 end
      if IMG.white then
        if cur_tab == 1 then g.image(IMG.white, 0, y+32, tabw, 3, GOLD)
        elseif cur_tab == 2 then g.image(IMG.white, tabw+gap, y+32, tabw, 3, GOLD)
        elseif cur_tab == 3 then g.image(IMG.white, (tabw+gap)*2, y+32, tabw, 3, GOLD)
        else g.image(IMG.white, (tabw+gap)*3, y+32, tabw, 3, GOLD) end
      end
    end
  end
  if type(g.set_cursor) == "function" then g.set_cursor(0, 46) end

  -- 气候页滚动壳
  local PGY, VP_H = 46, 160
  local CLIM_H = 706   -- 气候页内容实际高度（21 控件 + 3 分隔 + 行距）
  local SCROLL = (type(g.begin_scroll) == "function" and type(g.end_scroll) == "function")

  if cur_tab == 1 then
    -- 属性页：装备/饰品加成
    draw_attrs()
  elseif cur_tab == 3 then
    -- 刷怪倍率页
    do
      local nv = g.slider("倍率", S.spawn, 0.0, 100.0)
      if math.abs(nv - S.spawn) >= 0.05 then S.spawn = nv; save_state() end
      if not ok then g.text("联机时倍率由主机决定", DIS) end
      -- 常用倍率（横向可滚，超出窗口宽度可划）
      if type(g.begin_scroll) == "function" and type(g.button_at) == "function" then
        g.separator()
        local pres = { {0, "关"}, {0.5, "0.5x"}, {1, "1x"}, {10, "10x"}, {50, "50x"}, {100, "100x"} }
        local BW, GAP = 56, 8
        local cw = #pres * BW + (#pres - 1) * GAP
        local vh = 40
        g.begin_scroll("pres", 0, 100, 356, vh, cw, vh)
        for i = 1, #pres do
          local bx = (i - 1) * (BW + GAP)
          if g.button_at(bx, 4, BW, 32, pres[i][2]) then
            S.spawn = pres[i][1]; save_state()
          end
        end
        g.end_scroll()
        if type(g.set_content_height) == "function" then g.set_content_height(148) end
      end
      if type(g.button) == "function" then
        if g.button("恢复默认") then S.spawn = 1.0; save_state() end
      end
    end
  elseif cur_tab == 4 then
    -- 配置页：5 行开关，平铺
    do
      toggle_row("随身增益家具", "buff")
      toggle_row("随身制作站", "craft")
      toggle_row("取消晶塔数量限制", "pylon_num")
      toggle_row("取消晶塔传送NPC要求", "pylon_npc")
      toggle_row("NPC瞬移进房", "npc")
    end
  else
    -- 气候页
    if SCROLL then
      g.begin_scroll("pg_clim", 0, PGY, 356, VP_H, 356, CLIM_H)
      if type(g.set_cursor) == "function" then g.set_cursor(0, 0) end
    end
    draw_climate()
    if SCROLL then
      g.end_scroll()
      if type(g.set_content_height) == "function" then g.set_content_height(PGY + VP_H) end
    end
  end
end
mod.on_gui = on_gui

-- ============================================================
--  setup
-- ============================================================


function setup()
  if _G.g_betterexp_done then return end
  _G.g_betterexp_done = true
  log("=== betterexp "..(mod.meta and mod.meta.version or "?").." setup ===")
  load_state()
  T_Main   = P.get_type("Terraria", "Main")
  T_Player = P.get_type("Terraria", "Player")
  T_NPC    = P.get_type("Terraria", "NPC")
  T_Item   = P.get_type("Terraria", "Item")
  T_IS     = P.get_type("Terraria", "InventoryStorage")
  if not (T_Main and T_Player) then log("TYPE NIL"); return end

  F_player      = P.get_field(T_Main, "player")
  M_getmyplayer = P.get_method(T_Main, "get_myPlayer", 0)
  F_inv         = P.get_field(T_Player, "inventory")
  F_itemtype    = P.get_field(T_Item, "type")
  F_btype       = P.get_field(T_Player, "buffType")
  F_btime       = P.get_field(T_Player, "buffTime")
  F_adjtile     = P.get_field(T_Player, "adjTile")
  F_bank        = P.get_field(T_Player, "bank")
  F_bank2       = P.get_field(T_Player, "bank2")
  F_bank3       = P.get_field(T_Player, "bank3")
  F_bank4       = P.get_field(T_Player, "bank4")
  if T_IS then F_isitem = P.get_field(T_IS, "item") end
  if T_NPC then
    F_npcArr    = P.get_field(T_Main, "npc")
    F_npc_active= P.get_field(T_NPC, "active")
    F_npc_type  = P.get_field(T_NPC, "type")
    F_npc_pos   = P.get_field(T_NPC, "position")
    F_npc_vel   = P.get_field(T_NPC, "velocity")
    F_npc_h     = P.get_field(T_NPC, "height")
    F_npc_hx    = P.get_field(T_NPC, "homeTileX")
    F_npc_hy    = P.get_field(T_NPC, "homeTileY")
    F_npc_who   = P.get_field(T_NPC, "whoAmI")
    F_npc_tp    = P.get_field(T_NPC, "teleporting")
  end

  F_dsr = P.get_field(T_NPC, "defaultSpawnRate")
  F_dms = P.get_field(T_NPC, "defaultMaxSpawns")
  F_netmode = P.get_field(T_Main, "netMode")
  do
    local T_NP = P.get_type("", "Netplay") or P.get_type("Terraria", "Netplay")
    if T_NP then F_isrunning = P.get_field(T_NP, "IsServerRunning") end
    log("Netplay type="..tostring(T_NP).." F_isrunning="..tostring(F_isrunning))
  end
  M_gamemenu = P.get_method(T_Main, "get_gameMenu", 0)
  F_worldname = P.get_field(T_Main, "worldName")
  log("spawn fields: dsr="..tostring(F_dsr).." dms="..tostring(F_dms).." netmode="..tostring(F_netmode))

  local M_upd = P.get_method(T_Main, "Update", 1) or P.get_method(T_Main, "Update", 0)
  if M_upd then
    pcall(P.install_hook, M_upd, { postfix = function()
      pcall(tick_buff)
      pcall(tick_npc)
      pcall(tick_spawn)
      pcall(tick_visible)
      pcall(clim_tick)
    end })
  end

  -- 气候字段
  do
    for _,n in ipairs(C_NAMES) do
      C[n] = P.get_field(T_Main, n)
    end
    local T_WF = P.get_type("Terraria.IO", "WorldFile")
    if T_WF then
      for _,n in ipairs(W_NAMES) do W[n] = P.get_field(T_WF, n) end
    end
    local T_SS = P.get_type("Terraria.GameContent.Events", "Sandstorm")
    if T_SS then
      SS.Happening = P.get_field(T_SS, "Happening")
      SS.TimeLeft  = P.get_field(T_SS, "TimeLeft")
      SS.Severity  = P.get_field(T_SS, "Severity")
      SS.IntendedSeverity = P.get_field(T_SS, "IntendedSeverity")
      log("SS fields: H="..tostring(SS.Happening).." Sev="..tostring(SS.Severity))
    else
      log("SS type NIL")
    end
    log("climate: time="..tostring(C.time).." lightning="..tostring(C.lightning)
      .." sand="..tostring(W._tempSandstormHappening))
  end

  pylon_setup()


  log("setup done")
end

todo_list = { "setup" }
