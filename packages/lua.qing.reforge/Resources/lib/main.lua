mod.meta = { pkg_id = "lua.qing.reforge", version = "5.3.3", version_code = 5303, api_version = 1 }
local P = mod.patch
mod.gui = mod.gui or {}
-- 日志开关：0=关（发布版），1=开（调试）
local LOG_ON = 0
local function w(s)
  if LOG_ON == 0 then return end
  local ok,f=pcall(io.open,"/sdcard/Download/reforge.txt","a")
  if ok and f then f:write(s.."\n"); f:close() end
end

local PFX = {
 [1]="大",[2]="巨大",[3]="危险",[4]="野蛮",[5]="锋利",[6]="尖锐",[7]="微小",[8]="可怕",
 [9]="小",[10]="钝",[11]="倒霉",[12]="笨重",[13]="可耻",[14]="重",[15]="轻",[16]="精准",
 [17]="迅速",[18]="急速",[19]="恐吓",[20]="致命",[21]="可靠",[22]="可畏",[23]="无力",[24]="笨拙",
 [25]="强力",[26]="神秘",[27]="熟练",[28]="精湛",[29]="无能",[30]="无知",[31]="错乱",[32]="威猛",
 [33]="禁忌",[34]="天界",[35]="狂怒",[36]="锐利",[37]="高端",[38]="强力",[39]="碎裂",[40]="损坏",
 [41]="粗劣",[42]="迅捷",[43]="致命",[44]="灵活",[45]="灵巧",[46]="凶残",[47]="缓慢",[48]="迟缓",
 [49]="懒惰",[50]="恼人",[51]="恶毒",[52]="狂躁",[53]="伤害",[54]="强壮",[55]="粗鲁",[56]="虚弱",
 [57]="无情",[58]="狂热",[59]="神级",[60]="恶魔",[61]="狂热信仰",[62]="坚硬",[63]="守护",[64]="装甲",
 [65]="护佑",[66]="奥秘",[67]="精确",[68]="幸运",[69]="锯齿",[70]="尖刺",[71]="愤怒",[72]="险恶",
 [73]="轻快",[74]="快速",[75]="急速",[76]="迅捷",[77]="狂野",[78]="鲁莽",[79]="勇猛",[80]="暴力",
 [81]="传奇",[82]="虚幻",[83]="神话",[84]="传奇",[85]="传说",[86]="忠诚",[87]="值得",[88]="专注",
 [89]="耐心",[90]="狂犬",[91]="暴躁",[92]="小气",[93]="衰弱",[94]="胆怯",[95]="热切",[96]="弹道",
 [97]="瘦长",
}

local T_Main, T_GUI, T_Grg, T_Pop, T_Item, T_Player, T_Snd, T_Ent, T_LSP
local F_popCtl, F_guiPop
local F_Active, F_grg, F_pop, F_player, F_type, F_prefix, F_inv, F_stack
local F_pos, M_roll, M_rst, M_buy2, M_act, M_pfx
local F_lsp, M_lsp_play
local F_p_pos, F_p_w, F_p_h, M_newtext6, M_snd4, T_Pop2, M_snd6
local T_PopupTx, M_popup6, M_popup4, F_i_w, F_i_h
local F_bestReforge, F_sndId, F_style, g_best = nil, nil, nil
local GUARD_CURSOR = 0
local F_popup_arr, F_pt_act, F_pt_pos, F_pt_vel, F_pt_name, F_pt_stack
local M_affix, T_PopupText, M_getpop
local F_pt_scale, F_pt_rot, F_pt_life, F_pt_ctx, F_pt_npc, F_pt_nostack, F_pt_coin, F_pt_color
local M_itemname
local T_IS, F_isitem, F_bank, F_bank2, F_bank3, F_bank4
local M_getItem, M_myp, M_canroll, M_prefix, M_cost, M_buy, M_upd, M_popOpen, M_over, M_reset

local S = { selected = nil, rolling = false, pool = {}, item = nil, cost = 0, cur = 0, want = false }
local fmt_money   -- 先占位，实现在文件后部赋值

local function get_grg()
  local ok, act = pcall(P.get_field_value, F_Active, nil, "object")
  if not (ok and act) then return nil end
  local ok2, grg = pcall(P.get_field_value, F_grg, act, "object")
  if ok2 and grg then return grg end
  return nil
end

-- ★分帧前缀池扫描：每帧读 POOL_BUDGET 个
local POOL_BUDGET = 12
local PS = { idx = 0, cur = {}, item = nil }
local S_pool_tmp = nil

local function refresh_item()
  local grg = get_grg()
  if not grg then S.item=nil; S.pool={}; PS.idx=0; PS.item=nil; return end
  local ok, it = pcall(P.invoke, M_getItem, grg)
  if not (ok and it) then S.item=nil; S.pool={}; PS.idx=0; PS.item=nil; return end
  local _, typ = pcall(P.get_field_value, F_type, it, "int32")
  if type(typ)~="number" or typ<=0 then S.item=nil; S.pool={}; PS.idx=0; PS.item=nil; return end
  local item_changed = (PS.item ~= it)
  S.item = it; S.typ = typ
  local _, cur = pcall(P.get_field_value, F_prefix, it, "int8")
  S.cur = cur or 0
  local _, cost = pcall(P.invoke, M_cost, grg)
  S.cost = cost or 0

  -- 换物品 → 重启前缀扫描
  if item_changed then
    PS.idx = 0
    PS.cur = {}
    PS.item = it
    S.pool = {}          -- 换物品立刻清空，等下一轮扫满再显示
  end

  -- 增量扫 12 个
  local done = 0
  while PS.idx <= 84 and done < POOL_BUDGET do
    local id = PS.idx
    local okc, r = pcall(P.invoke, M_canroll, it, id)
    if okc and r==true then PS.cur[#PS.cur+1] = id end
    PS.idx = PS.idx + 1
    done = done + 1
  end
  -- 扫完一轮 → 提交结果，准备下一轮
  local full = (PS.idx > 84)
  if full then
    local newpool = PS.cur
    PS.cur = {}
    PS.idx = 0
    if #newpool ~= #S.pool or item_changed then
      w(string.format("POOL item=%d cur=%s(%s) cost=%s n=%d", typ, tostring(S.cur), tostring(PFX[S.cur]), tostring(S.cost), #newpool))
    end
    S.pool = newpool
  end

  -- 换物品 → 自动暂停并清空已选前缀
  if S.pool_item and S.pool_item ~= it then
    if S.rolling then w("<<< AUTO pause: item changed") end
    S.rolling = false
    S.selected = nil
    S.tries = 0
  end
  S.pool_item = it
end

local function arr_get(arr, i)
  local ok, v = pcall(P.array_at, arr, i)
  if ok then return v end
  return nil
end

local g_pl_cache, g_pl_t = nil, 0
local function get_player()
  local now = os.clock()
  if g_pl_cache and (now - g_pl_t) < 0.2 then return g_pl_cache end
  local _, idx = pcall(P.invoke, M_myp, nil)
  local _, arr = pcall(P.get_field_value, F_player, nil, "object")
  if type(idx)~="number" or not arr then return nil end
  local _, pl = pcall(P.array_at, arr, idx)
  g_pl_cache, g_pl_t = pl, now
  return pl
end
local get_player_cached = get_player

-- ★分帧增量余额扫描：每帧只读 COIN_BUDGET 格，几帧轮完一圈
local COIN_BUDGET = 20
local SC = {
  phase = 0,       -- 0=准备数组引用  1=扫背包  2..5=扫4个银行  6=收尾
  arr = nil,       -- 当前数组
  idx = 0,         -- 当前下标
  n = -1,          -- 当前数组长度(-1=未取)
  acc = 0,         -- 本圈累计铜币
  total = 0,       -- 上圈结果（显示用）
  known = false,   -- 是否已跑完至少一圈
}
local bank_fields = {}

local function coin_scan_reset()
  SC.phase = 0; SC.arr = nil; SC.idx = 0; SC.n = 0; SC.acc = 0
end

-- 每帧调用一次，均摊读取（背包 + 4 个银行，每帧 20 格）
local function coin_scan_step()
  local budget = COIN_BUDGET
  while budget > 0 do
    if SC.phase == 0 then
      -- 准备：拿玩家 + 背包数组
      local pl = get_player_cached()
      if not pl then return end
      local _, inv = pcall(P.get_field_value, F_inv, pl, "object")
      SC.acc = 0
      if inv then
        SC.phase, SC.arr, SC.idx, SC.n = 1, inv, 0, -1
      else
        SC.phase = 6
      end
    elseif SC.phase >= 1 and SC.phase <= 5 then
      -- SC.n == -1 表示长度还没取过
      if SC.n < 0 then
        local ln = 0
        pcall(function() ln = P.array_length(SC.arr) end)
        SC.n = ln or 0
        SC.idx = 0
      end
      if SC.idx >= SC.n then
        -- 本批扫完 → 切下一批
        SC.phase = SC.phase + 1
        SC.arr, SC.n = nil, -1
        if SC.phase <= 5 then
          local pl2 = get_player_cached()
          local fb = pl2 and bank_fields[SC.phase - 1] or nil
          if fb and T_IS and F_isitem then
            local ok, st = pcall(P.get_field_value, fb, pl2, "object")
            if ok and st then
              local ok2, arr2 = pcall(P.get_field_value, F_isitem, st, "object")
              if ok2 and arr2 then SC.arr = arr2
              else SC.phase = SC.phase + 1 end
            else SC.phase = SC.phase + 1 end
          else
            SC.phase = SC.phase + 1
          end
          -- 跳过空银行（可能连跳几个）
          while SC.phase >= 2 and SC.phase <= 5 and SC.arr == nil do
            local pl3 = get_player_cached()
            local fb2 = pl3 and bank_fields[SC.phase - 1] or nil
            local got = nil
            if fb2 and T_IS and F_isitem then
              local ok, st = pcall(P.get_field_value, fb2, pl3, "object")
              if ok and st then
                local ok2, arr2 = pcall(P.get_field_value, F_isitem, st, "object")
                if ok2 then got = arr2 end
              end
            end
            SC.arr = got
            if not got then SC.phase = SC.phase + 1 end
          end
        end
      else
        local cnt = math.min(budget, SC.n - SC.idx)
        for k = 1, cnt do
          local ok, v = pcall(P.array_at, SC.arr, SC.idx)
          SC.idx = SC.idx + 1
          if ok and v then
            local _, ty = pcall(P.get_field_value, F_type, v, "int32")
            local mult = (ty==71 and 1) or (ty==72 and 100) or (ty==73 and 10000) or (ty==74 and 1000000) or nil
            if mult then
              local _, st = pcall(P.get_field_value, F_stack, v, "int32")
              if type(st)=="number" and st>0 then SC.acc = SC.acc + st*mult end
            end
          end
        end
        budget = budget - cnt
      end
    else
      -- phase 6：一圈扫完，提交结果
      SC.total = SC.acc
      SC.known = true
      SC.phase = 0
      SC.arr, SC.idx, SC.n = nil, 0, -1
      return
    end
  end
end

local function count_coins(pl)
  if not SC.known then return -1 end
  return SC.total
end


local function play_sfx(stype, sstyle)
  if not M_snd6 then return end
  local px, py = -1, -1
  local pl = get_player()
  if pl and F_p_pos then
    local okv, vx, vy = pcall(P.get_field_vec2, F_p_pos, pl)
    if okv then px, py = math.floor(vx), math.floor(vy) end
  end
  local oks, rr = pcall(P.invoke, M_snd6, stype, px, py, sstyle, 1.0, 0.0)
  w("SND "..tostring(stype).."/"..tostring(sstyle).." ok="..tostring(oks).." r="..tostring(rr))
end

local function show_popup(item)
  w("POPUP enter item="..tostring(item))
  if not item then w("POPUP no-item") return end
  if not M_getpop then w("POPUP no-Mgetpop") return end
  if not F_pt_act then w("POPUP no-Fact") return end
  -- 物品名（托管 string）
  local okn, nm = pcall(P.invoke, M_affix, item)
  w("POPUP name-raw ok="..tostring(okn).." nm="..tostring(nm))
  if not (okn and nm) then return end
  local sname = P.string_value(nm)
  w("POPUP sname="..tostring(sname))
  if type(sname) ~= "string" or sname == "" then return end
  -- 位置用玩家中心（PE 版 Item 无 position 字段）
  local pl = get_player()
  if not pl then w("POPUP no-player") return end
  local okv2, px, py = pcall(P.get_field_vec2, F_p_pos, pl)
  w("POPUP ppos ok="..tostring(okv2).." x="..tostring(px).." y="..tostring(py))
  if not okv2 then return end
  local _, pw = pcall(P.get_field_value, F_p_w, pl, "int32")
  local _, ph = pcall(P.get_field_value, F_p_h, pl, "int32")
  pw, ph = pw or 20, ph or 42
  local ix, iy, iw, ih = px, py, pw, ph


  local okA, arr = pcall(P.invoke, M_getpop)
  w("POPUP arr ok="..tostring(okA).." arr="..tostring(arr))
  if not (okA and arr) then return end
  for i = 0, 19 do
    local okE, pt = pcall(P.array_at, arr, i)
    if okE and pt then
      local okAct, isAct = pcall(P.get_field_value, F_pt_act, pt, "bool")
      if okAct and not isAct then
        -- position 是文字中心点（游戏用 MouseText.MeasureString 按中心绘制）
        local ok1 = pcall(P.set_field_vec2, F_pt_pos, pt, ix + iw * 0.5, iy + ih * 0.5)
        local ok2 = pcall(P.set_field_vec2, F_pt_vel, pt, 0, -7)
        local ok3 = pcall(P.set_field_value, F_pt_name, pt, sname, "string")
        local ok4 = pcall(P.set_field_value, F_pt_stack, pt, 1, "int64")
        local ok5 = pcall(P.set_field_value, F_pt_scale, pt, 1.0, "float")
        local ok6 = pcall(P.set_field_value, F_pt_rot, pt, 0.0, "float")
        local ok7 = pcall(P.set_field_value, F_pt_life, pt, 60, "int32")
        local ok8 = pcall(P.set_field_value, F_pt_ctx, pt, 3, "int32")
        local ok9 = pcall(P.set_field_value, F_pt_npc, pt, 0, "int32")
        local ok10 = pcall(P.set_field_value, F_pt_nostack, pt, true, "bool")
        local ok11 = pcall(P.set_field_value, F_pt_coin, pt, false, "bool")
        -- PE 版 Color 内存布局 = A,B,G,R（0x0=A 0x1=B 0x2=G 0x3=R）
        local cp = P.field_pointer(F_pt_color, pt)
        local ok12 = false
        if cp then ok12 = pcall(P.mem_write, cp, 0, string.char(255,255,255,255)) end
        local ok13 = pcall(P.set_field_value, F_pt_act, pt, true, "bool")
        w("POPUP ok slot="..i.." name="..sname
          .." F["..tostring(ok1)..tostring(ok2)..tostring(ok3)..tostring(ok4)..tostring(ok5)
          ..tostring(ok6)..tostring(ok7)..tostring(ok8)..tostring(ok9)..tostring(ok10)
          ..tostring(ok11)..tostring(ok12)..tostring(ok13).."]")
        return i
      end
    end
  end
  -- 20 个槽位全占满：从上次覆盖位置继续往后轮，绕回 0 强行覆盖
  GUARD_CURSOR = ((GUARD_CURSOR or -1) + 1) % 20
  local okE, pt = pcall(P.array_at, arr, GUARD_CURSOR)
  if not (okE and pt) then w("POPUP wrap-fail") return end
  pcall(P.set_field_vec2, F_pt_pos, pt, ix + iw * 0.5, iy + ih * 0.5)
  pcall(P.set_field_vec2, F_pt_vel, pt, 0, -7)
  pcall(P.set_field_value, F_pt_name, pt, sname, "string")
  pcall(P.set_field_value, F_pt_stack, pt, 1, "int64")
  pcall(P.set_field_value, F_pt_scale, pt, 1.0, "float")
  pcall(P.set_field_value, F_pt_rot, pt, 0.0, "float")
  pcall(P.set_field_value, F_pt_life, pt, 60, "int32")
  pcall(P.set_field_value, F_pt_ctx, pt, 3, "int32")
  pcall(P.set_field_value, F_pt_npc, pt, 0, "int32")
  pcall(P.set_field_value, F_pt_nostack, pt, true, "bool")
  pcall(P.set_field_value, F_pt_coin, pt, false, "bool")
  local cp2 = P.field_pointer(F_pt_color, pt)
  if cp2 then pcall(P.mem_write, cp2, 0, string.char(255,255,255,255)) end
  pcall(P.set_field_value, F_pt_act, pt, true, "bool")
  w("POPUP wrap slot="..GUARD_CURSOR.." name="..sname)
end

local function play_sfx_and_text(ctl_inst)
  -- 音效：PlaySound(int type, int x, int y, int style, float vol, float pitch) 全标量，无 Vector2
  if M_snd6 then
    local px, py = -1, -1
    local pl = get_player()
    if pl and F_p_pos then
      local okv, vx, vy = pcall(P.get_field_vec2, F_p_pos, pl)
      if okv then px, py = math.floor(vx), math.floor(vy) end
    end
    local oks, rr = pcall(P.invoke, M_snd6, 2, px, py, 37, 1.0, 0.0)
    w("SND6 ok="..tostring(oks).." r="..tostring(rr))
  end
  w("POPUP gate m6="..tostring(M_popup6).." item="..tostring(S.item))
  if M_popup6 and S.item then show_popup(S.item) end
end

local function do_one_reforge()
  -- 自己扣钱：Activate() 是 pairip 转发桩，P.invoke 调它不会扣金币
  w("R1 enter item="..tostring(S.item).." sel="..tostring(S.selected))
  if not S.item or not S.selected then w("R1 abort: no item/selected") return false end
  local grg = get_grg()
  if grg then local _, c = pcall(P.invoke, M_cost, grg); S.cost = c or 0 end
  w("R2 cost="..tostring(S.cost))
  if type(S.cost) ~= "number" or S.cost <= 0 then w("R2 abort: cost<=0 "..tostring(S.cost)) return false end

  local pl = get_player()
  w("R3 player="..tostring(pl).." buy="..tostring(M_buy))
  if not pl or not M_buy then w("R3 abort: no player/buy") return false end
  local okb, paid = pcall(P.invoke, M_buy, pl, S.cost, -1)
  w("BUY ok="..tostring(okb).." cost="..tostring(S.cost).." paid="..tostring(paid))
  if not okb or paid ~= true then
    w("R4 abort: paid="..tostring(paid).." okb="..tostring(okb))
    local balnow = count_coins(pl)
    local diff = (type(balnow) == "number" and balnow >= 0) and (S.cost - balnow) or S.cost
    if type(diff) ~= "number" or diff < 0 then diff = S.cost end
    S.err = "金币不足（还差 "..fmt_money(diff).."）"
    S.err_t = os.clock()
    return false
  end
  S.err = nil

  local okr = pcall(P.invoke, M_rst, S.item)
  local okp = pcall(P.invoke, M_pfx, S.item, -2)
  w("R5 reset="..tostring(okr).." prefix="..tostring(okp))
  play_sfx_and_text(S.ctl_inst)
  local _, cur = pcall(P.get_field_value, F_prefix, S.item, "int8")
  S.cur = cur or -1
  if S.cur == S.selected then
    if g_best then play_sfx(g_best[1], g_best[2]) end
  end
  w("REROLL cur="..tostring(S.cur).." want="..tostring(S.selected))
  return true
end


local function tick()
  if S.want then
    if (S.dbg or 0) < 3 then
      S.dbg = (S.dbg or 0) + 1
      local okg, gv = pcall(P.get_field_value, F_Active, nil, "object")
      local ogy, gv2 = pcall(P.get_field_value, F_guiPop, gv, "object")
      w("DBG gui="..tostring(okg).."/"..tostring(gv).." pop="..tostring(ogy).."/"..tostring(gv2))
    end
    if not S.ctl_inst and F_guiPop and F_popCtl then
      local okg, gv = pcall(P.get_field_value, F_Active, nil, "object")
      if okg and gv then
        local okp, pi = pcall(P.get_field_value, F_guiPop, gv, "object")
        if okp and pi then
          local okc, ci = pcall(P.get_field_value, F_popCtl, pi, "object")
          if okc and ci then
            S.ctl_inst = ci
            w("CTL GOT "..tostring(ci))
          end
        end
      end
    end
    if not get_grg() then
      -- OpenPopup 首帧 GUIReforge 可能还没赋值，连续 15 帧读不到才关
      S.miss = (S.miss or 0) + 1
      if S.miss >= 15 then S.want=false; S.rolling=false; S.miss=0 end
      return
    end
    S.miss = 0
    refresh_item()
    coin_scan_step()
    if S.rolling and S.item and S.selected then
      if S.cur == S.selected then
        S.rolling = false
        w("<<< AUTO done cur="..tostring(S.cur))
      else
        local now = os.clock()
        if not S.next_tick or now >= S.next_tick then
          S.next_tick = now + 0.3
          if not do_one_reforge() then S.rolling = false else
            S.tries = (S.tries or 0) + 1
            if S.cur == S.selected then S.rolling = false; w("<<< AUTO done cur="..tostring(S.cur)) end
          end
        end
      end
    end
  end
end

-- 每次进世界都执行：清掉上个世界的一切残留
local function rf_world_reset()
  S.item = nil; S.pool = {}; S.selected = nil; S.rolling = false
  S.cur = 0; S.cost = 0; S.typ = nil; S.pool_item = nil
  S.want = false; S.tries = 0; S.err = nil; S.cost_hint = nil; S.roll_n = 0
  SC.phase = 0; SC.known = false; SC.total = 0
  PS.idx = 0; PS.cur = {}; PS.item = nil
  if mod.gui and mod.gui.set_visible then pcall(mod.gui.set_visible, false) end
end

local function do_init()
  rf_world_reset()
  if _G.g_rf380 then return end
  _G.g_rf380 = true
  local _v = (mod.meta and mod.meta.version) or "?"
  w("=== Reforge ".._v.." BUILD-5300 ===")
  T_Main = P.get_type("Terraria", "Main")
  T_GUI = P.get_type("", "GUIInstance")
  T_Grg = P.get_type("", "GUIReforge")
  T_Pop = P.get_type("", "GUIReforgePopup")
  F_popCtl = T_Pop and P.get_field(T_Pop, "_controller") or nil
  F_guiPop = T_GUI and P.get_field(T_GUI, "GUIReforgePopup") or nil
  w("POPCTL pop="..tostring(F_guiPop).." ctl="..tostring(F_popCtl))
  T_Item = P.get_type("Terraria", "Item")
  T_Player = P.get_type("Terraria", "Player")
  T_Snd = P.get_type("Terraria.Audio", "SoundEngine")
  T_Ent = P.get_type("Terraria", "Entity")
  F_Active = P.get_field(T_GUI, "Active")
  F_grg = P.get_field(T_GUI, "GUIReforge")
  F_player = P.get_field(T_Main, "player")
  F_type = P.get_field(T_Item, "type")
  F_prefix = P.get_field(T_Item, "prefix")
  F_inv = P.get_field(T_Player, "inventory")
  F_stack = P.get_field(T_Item, "stack")
  T_LSP = P.get_type("Terraria.Audio", "LegacySoundPlayer")
  F_lsp = T_Snd and P.get_field(T_Snd, "LegacySoundPlayer") or nil
  M_lsp_play = T_LSP and P.get_method(T_LSP, "PlaySound", 6) or nil
  w("SND lsp="..tostring(F_lsp).." play="..tostring(M_lsp_play))
  -- 飘字：PopupText.NewText(PopupTextContext, Item, Vector2, int, bool, bool)
  T_PopupTx = P.get_type("Terraria", "PopupText")
  if T_PopupTx then
    M_popup6 = P.get_method(T_PopupTx, "NewText", 6)
    M_popup4 = P.get_method(T_PopupTx, "NewText", 4)
    local all = P.get_methods(T_PopupTx, true)
    if all then
      for i = 1, #all do
        local m = all[i]
        local okn, nm = pcall(P.method_name, m)
        if okn and nm == "NewText" then
          local okc, cn = pcall(P.method_param_count, m)
          local oki, inst = pcall(P.method_is_instance, m)
          local okt, tk = pcall(P.method_token, m)
          w("NTTN cnt="..tostring(cn).." inst="..tostring(inst).." tok="..tostring(tk))
        end
      end
    end
  end
  F_i_w = P.get_field(T_Item, "width")
  F_i_h = P.get_field(T_Item, "height")
  T_PopupText = P.get_type("Terraria", "PopupText")
  if T_PopupText then
    -- Main.popupText 取不到；改用 PopupText.popupText（静态属性 get_popupText）
    M_getpop = P.get_method(T_PopupText, "get_popupText", 0)
    if M_getpop then
      local okp, arrp = pcall(P.invoke, M_getpop)
      if okp and arrp then F_popup_arr = arrp end
    end
    if not F_popup_arr then
      local fTmp = P.get_field(T_Main, "popupText")
      w("PT fallback field="..tostring(fTmp))
      F_popup_arr = fTmp
    end
    F_pt_act = P.get_field(T_PopupText, "active")
    F_pt_pos = P.get_field(T_PopupText, "position")
    F_pt_vel = P.get_field(T_PopupText, "velocity")
    F_pt_name = P.get_field(T_PopupText, "name")
    F_pt_stack = P.get_field(T_PopupText, "stack")
    F_pt_scale = P.get_field(T_PopupText, "scale")
    F_pt_rot = P.get_field(T_PopupText, "rotation")
    F_pt_life = P.get_field(T_PopupText, "lifeTime")
    F_pt_ctx = P.get_field(T_PopupText, "context")
    F_pt_npc = P.get_field(T_PopupText, "npcNetID")
    F_pt_nostack = P.get_field(T_PopupText, "NoStack")
    F_pt_coin = P.get_field(T_PopupText, "coinText")
    F_pt_color = P.get_field(T_PopupText, "color")
    M_affix = P.get_method(T_Item, "AffixName", 0)
    w("PT arr="..tostring(F_popup_arr).." act="..tostring(F_pt_act).." affix="..tostring(M_affix))
  end
  w("POPUP m6="..tostring(M_popup6).." w="..tostring(F_i_w).." h="..tostring(F_i_h))
  M_getItem = P.get_method(T_Grg, "get_ReforgeItem", 0)
  M_cost = P.get_method(T_Grg, "ReforgeCost", 0)
  M_myp = P.get_method(T_Main, "get_myPlayer", 0)
  M_canroll = P.get_method(T_Item, "CanRollPrefix", 1)
  M_prefix = P.get_method(T_Item, "Prefix", 1)
  M_over = P.get_method(T_Grg, "ReforgeItemOver", 1)
  w("M_over="..tostring(M_over))

  -- ★自实现重铸所需
  M_roll = P.get_method(T_Item, "GetRollablePrefixes", 0)
  M_rst  = P.get_method(T_Item, "ResetPrefix", 0)
  M_pfx  = P.get_method(T_Item, "Prefix", 1)
  M_buy2 = P.get_method(T_Player, "BuyItem", 2)
  F_pos  = P.get_field(T_Player, "position")
  M_reset = P.get_method(T_Grg, "Reset", 0)
  w("M_reset="..tostring(M_reset))
  -- 精确拿 BuyItem(long,int)
  local T64 = P.get_basic_type and P.get_basic_type("int64")
  local T32 = P.get_basic_type and P.get_basic_type("int32")
  if P.get_method_by_param_types and T64 and T32 then
    M_buy = P.get_method_by_param_types(T_Player, "BuyItem", {T64, T32})
    w("M_buy(sig)="..tostring(M_buy))
  end
  if not M_buy then M_buy = P.get_method(T_Player, "BuyItem", 2); w("M_buy(fallback)="..tostring(M_buy)) end
  M_upd = P.get_method(T_Main, "Update", 1)
  -- popup
  if T_Pop then
    M_popOpen = P.get_method(T_Pop, "OpenPopup", 0)
    if M_popOpen then
      P.install_hook(M_popOpen, { postfix = function()
        S.want = true
        S.miss = 0
        w(">>> OpenPopup -> show ours")
      end })
    end
    local mdraw = P.get_method(T_Pop, "Draw", 0)
    if mdraw then P.install_hook(mdraw, { prefix = function() return true end }) end
    local mclose = P.get_method(T_Pop, "ClosePopup", 0)
    if mclose then
      P.install_hook(mclose, { prefix = function()
        S.want = false; S.rolling = false; w("<<< ClosePopup -> hide ours"); return false
      end })
    end
  end
  -- ★接管重铸：让游戏自己跑（扣钱/音效/飘字全原生），跑完覆盖前缀
  local T_Ctl = P.get_type("", "GUIControllerReforgePopup")
  M_act = T_Ctl and P.get_method(T_Ctl, "Activate", 0) or nil
  local F_ctlSel = T_Ctl and P.get_field(T_Ctl, "selectedControl") or nil
  w("ACHOOK ctl="..tostring(T_Ctl).." act="..tostring(M_act).." sel="..tostring(F_ctlSel))
  -- 飘字 + 带位置音效
  T_Pop2 = P.get_type("Terraria", "PopupText")
  M_newtext6 = T_Pop2 and P.get_method(T_Pop2, "NewText", 6) or nil
  M_snd6 = T_Snd and P.get_method(T_Snd, "PlaySound", 6) or nil
  local T_Lang = P.get_type("Terraria", "Lang")
  M_itemname = (T_Lang and P.get_method(T_Lang, "GetItemNameValue", 1)) or nil
  F_namcache = T_Lang and P.get_field(T_Lang, "_itemNameCache") or nil
  local T_LT = P.get_type("Terraria.Localization", "LocalizedText")
  F_ltval = T_LT and P.get_field(T_LT, "<Value>k__BackingField") or nil
  if not F_ltval and T_LT then F_ltval = P.get_field(T_LT, "Value") end
  _G.g_rf_name = T_Item and P.get_method(T_Item, "get_Name", 0) or nil
  T_IS = P.get_type("Terraria", "InventoryStorage")
  if T_IS then F_isitem = P.get_field(T_IS, "item") end
  F_bank  = P.get_field(T_Player, "bank")
  F_bank2 = P.get_field(T_Player, "bank2")
  F_bank3 = P.get_field(T_Player, "bank3")
  F_bank4 = P.get_field(T_Player, "bank4")
  bank_fields[1] = F_bank
  bank_fields[2] = F_bank2
  bank_fields[3] = F_bank3
  bank_fields[4] = F_bank4
  -- 完美重铸音效：读 SoundID.BestReforge 的 SoundId / _style
  local T_ID = P.get_type("Terraria.ID", "SoundID")
  F_bestReforge = T_ID and P.get_field(T_ID, "BestReforge") or nil
  local T_LSS = P.get_type("Terraria.Audio", "LegacySoundStyle")
  F_sndId = T_LSS and P.get_field(T_LSS, "SoundId") or nil
  F_style = T_LSS and P.get_field(T_LSS, "_style") or nil
  if F_bestReforge and F_sndId and F_style then
    local okb, obj = pcall(P.get_field_value, F_bestReforge, nil, "object")
    if okb and obj then
      local ok1, sid = pcall(P.get_field_value, F_sndId, obj, "int32")
      local ok2, st  = pcall(P.get_field_value, F_style, obj, "int32")
      if ok1 and ok2 and sid and st then g_best = { sid, st } end
    end
  end
  w("BESTREFORGE "..tostring(g_best and (g_best[1].."/"..g_best[2]) or "nil"))
  local T_Plr = P.get_type("Terraria","Player")
  F_p_pos = T_Plr and P.get_field(T_Plr, "position") or nil
  F_p_w   = T_Plr and P.get_field(T_Plr, "width") or nil
  F_p_h   = T_Plr and P.get_field(T_Plr, "height") or nil
  w("POP snd6="..tostring(M_snd6))
  if M_act then
    P.install_hook(M_act, {
      prefix = function(inst)
        local okc, cv = pcall(P.get_field_value, F_ctlSel, inst, "int32")
        if okc and cv == 0 then
          S.act_hit = true
          w(">>> Activate(Reforge) hit")
          if not S.selected then return true end
        end
        return false
      end,
      postfix = function(inst)
        if not S.act_hit then return end
        S.act_hit = false
        if not S.item or not S.selected then return end
        local F_pfx = F_prefix
        local ok1, cur = pcall(P.get_field_value, F_pfx, S.item, "int8")
        pcall(P.invoke, M_rst, S.item)
        local ok2, r = pcall(P.invoke, M_pfx, S.item, -2)
        local ok3, now = pcall(P.get_field_value, F_pfx, S.item, "int8")
        w(string.format("OVERRIDE native=%s want=%d -> %s (ok2=%s)", tostring(cur), S.selected, tostring(now), tostring(ok2)))
      end,
    })
  end
  if M_upd then
    P.install_hook(M_upd, { postfix = tick })
    -- 进世界后补挂 Update，用于检测退出世界（启动阶段不挂）
    if not _G.g_rf_upd_hooked then
      _G.g_rf_upd_hooked = true
      P.install_hook(M_upd, { postfix = function() pcall(check_world) end })
    end
  end
end

fmt_money = function(total)
  if type(total) ~= "number" or total < 0 then return "?" end
  local p = math.floor(total / 1000000)
  local g = math.floor(total / 10000) % 100
  local s_ = math.floor(total / 100) % 100
  local c = total % 100
  local out = ""
  if p > 0 then out = out .. p .. "铂 " end
  if g > 0 or p > 0 then out = out .. g .. "金 " end
  if s_ > 0 or g > 0 or p > 0 then out = out .. s_ .. "银 " end
  out = out .. c .. "铜"
  return out
end

local function ui_body()

  local g = mod.gui
  if g.set_visible then g.set_visible(S.want) end
  if not _G.g_rf_t then pcall(g.set_title, "自动重铸", "铸"); _G.g_rf_t = true end
  if not _G.g_rf_w then pcall(g.set_width, 280); _G.g_rf_w = true end
  if not S.want then return end

  local pl0 = get_player()
  local bal = pl0 and count_coins(pl0) or -1

  -- 物品名 + 当前前缀
  local iname = "?"
  if S.typ and M_itemname then
    local okn, h = pcall(P.invoke, M_itemname, math.floor(S.typ))
    if okn and h ~= nil then
      if type(h) == "string" then
        if h ~= "" then iname = h end
      else
        local sv = nil
        pcall(function() sv = P.string_value(h) end)
        if type(sv) == "string" and sv ~= "" then iname = sv end
      end
      if iname == "?" then w("NAME miss: ok="..tostring(okn).." t="..type(h)) end
    else
      w("NAME nil: ok="..tostring(okn))
    end
  end
  local curname = (S.cur and PFX[S.cur]) and PFX[S.cur] or "无"
  g.text(iname.."　"..curname)

  g.text("花费 "..fmt_money(S.cost))
  g.text("余额 "..fmt_money(bal))

  if not S.item then
    g.separator()
    g.text("(请在游戏里放入要重铸的物品)")
    if g.set_content_height then g.set_content_height(190) end
    return
  end

  -- 开始重铸
  if not S.rolling then
    local err_show = (S.err and S.err_t and (os.clock() - S.err_t) < 3)
    if err_show then
      g.text(S.err)
    elseif g.button("开始重铸") then
      if S.selected then
        w(">>> AUTO start want="..tostring(S.selected).." ("..tostring(PFX[S.selected])..")")
        S.rolling = true
        S.tries = 0
        S.next_tick = os.clock() + 0.3
      end
    end
    local want = S.selected and (PFX[S.selected] or tostring(S.selected)) or "未选"
    g.text("目标 "..want.."　已重铸 "..tostring(S.tries or 0).." 次")
  else
    g.text("重铸中… 已重铸 "..tostring(S.tries or 0).." 次")
  end

  g.separator()

  -- 可选前缀
  local ROW, VP_H, VW = 32, 128, 250
  local n = #S.pool
  local TOP = 174   -- 物品名32+花费32+余额32+按钮36+目标32+分隔10
  if n < 1 then
    g.text("(该物品没有可洗前缀)")
    if g.set_content_height then g.set_content_height(TOP + 30) end
    return
  end
  if type(g.begin_scroll) == "function" then
    g.set_cursor(0, TOP)
    local okb, sx, sy, vw, vh = pcall(g.begin_scroll, "pfxcol", 0, TOP, VW, VP_H, VW, n * ROW)
    if not okb then
      -- 视口非法（栈残留/尺寸异常）：跳过本帧滚动区，不抛错
      g.text("(前缀列表异常，请重开面板)")
      if g.set_content_height then g.set_content_height(TOP + 30) end
      return
    end
    local okdraw, derr = pcall(function()
      local first = math.max(1, math.floor((sy or 0) / ROW) + 1)
      local last  = math.min(n, math.ceil(((sy or 0) + (vh or VP_H)) / ROW))
      for i = first, last do
        local id = S.pool[i]
        if id then
          local label = PFX[id] or ("#"..tostring(id))
          if id == S.selected then label = "> "..label end
          if g.button_at(0, (i - 1) * ROW, VW - 16, ROW - 4, label) then
            if S.selected ~= id then
              if S.rolling then S.rolling = false; w("<<< AUTO pause: prefix changed -> "..tostring(id)) end
              S.selected = id
            end
          end
        end
      end
    end)
    pcall(g.end_scroll)   -- ★必须执行，否则滚动栈累积会报 invalid scroll viewport
    if g.set_content_height then g.set_content_height(TOP + VP_H + 8) end
    if not okdraw then
      if not S.werr2 then S.werr2 = true; w("!!! SCROLL DRAW ERR: "..tostring(derr)) end
    end
  end
end



function mod.on_gui()
  if not S.want then
    if mod.gui.set_visible then pcall(mod.gui.set_visible, false) end
    return
  end
  local okc, err = pcall(ui_body)
  if not okc then
    if not S.werr then
      S.werr = true
      local f = io.open("/sdcard/Download/reforge.txt","a")
      if f then f:write("!!! GUI ERROR: "..tostring(err).."\n"); f:close() end
    end
  end
end

-- ★进世界检测：解析类型/装 hook 全部推迟到进世界后，避免启动阶段碰 IL2CPP
local g_last_world = nil

local F_worldName = nil

local function check_world()
  if not F_worldName then
    F_worldName = P.get_field(T_MainRef, "worldName")
    if not F_worldName then return end
  end
  local okw, v = pcall(P.get_field_value, F_worldName, nil, "string")
  local wn = (okw and type(v) == "string") and v or ""

  if wn == "" then
    if g_last_world ~= nil then
      -- 退出世界：清世界相关状态，hook 不动
      g_last_world = nil
      rf_world_reset()
    end
    return
  end

  if wn ~= g_last_world then
    g_last_world = wn
    do_init()
  end
end

function setup()
  if _G.g_rf_setup then return end
  _G.g_rf_setup = true
  -- ★启动阶段只挂 WorldGen.playWorld（真·进世界信号），不碰任何游戏对象/帧循环
  T_MainRef = P.get_type("Terraria", "Main")
  local T_WG = P.get_type("Terraria", "WorldGen")
  if T_WG then
    local m_pw = P.get_method(T_WG, "playWorld", 0)
    if m_pw then
      P.install_hook(m_pw, { postfix = function() pcall(check_world) end })
    end
  end
end

todo_list = { "setup" }
