-- DamageProbe 1.0 : Boss damage meter (per-boss)
mod.meta = { pkg_id = "lua.qing.dmgprobe", version = "1.1.0", version_code = 110, api_version = 1 }

local Main, NPC, Projectile, Lang, ChatCmd, ChatMessage, WorldGen
local f_npc_boss, f_npc_type, f_npc_who, f_npc_life, f_npc_lifemax, f_npc_bufftype
-- event fields (verified on PE 1.4.5.8)
local f_ev_invtype, f_ev_eclipse, f_ev_pumpkin, f_ev_snow, f_ev_blood, f_ev_slime
local f_ev_invwave, f_npc_wavenum
local g_kill_dbg = 20
local g_kill_who, g_kill_t = -1, 0
-- world-save shared state (referenced by early functions)
local g_save_dirty, g_save_t, g_loaded_world = false, os.time(), nil
local g_write_enabled = true   -- /open /close : master switch for file writing
local g_world_fp = nil
local SAVE_DIR = nil
local f_world_name = nil
-- session clock: g_t0 = os.clock() at world load; elapsed = os.clock()-g_t0
local g_t0 = os.clock()
local f_pr_type, f_pr_dmg, f_pr_friendly
local m_GetProjName, m_GetNPCName, m_GetBuffName
local m_NewText
local g_get_msg_text, g_main_debuff_arr

-- per-boss stat: key = boss instance id (increment)
local stat = {}
local g_next_id = 0
local g_next_order = 0
local nameCache = {}
local buffNameCache = {}
local npcNameCache = {}
local g_last_dump = -10
-- recent boss-entry creation guard: g_boss_recent[ntype] = { id=, t= }
local g_boss_recent = {}
-- chat-command dedup: same command within 0.3s fires only once
local g_last_cmd, g_last_cmd_t = nil, -10
local BOSS_NEW_GAP = 0.3

-- track current boss per whoAmI slot
local slot = {}   -- slot[who] = { id=..., lifeMax=... }

-- scratch for DOT life before/after
local dot_before = {}

-- last friendly damaging projectile (for naming)
local g_ptype = -2

-- diagnostic log
local g_logf = nil
local g_dbg_all = ""
local g_dbg_pick = 0
local function dlog(s) if g_logf then g_logf:write(s.."\n"); g_logf:flush() end end

local function proj_name(ptype)
  if type(ptype) ~= "number" or ptype < 0 then return "?" end
  local c = nameCache[ptype]; if c then return c end
  local nm = nil
  pcall(function()
    local h = mod.patch.invoke(m_GetProjName, ptype)
    if not h then return end
    local vt = mod.patch.get_type("Terraria.Localization", "LocalizedText")
    local prop = mod.patch.get_property(vt, "Value")
    local getter = mod.patch.property_get_method(prop)
    local sh = mod.patch.invoke(getter, h)
    local s = nil
    pcall(function() s = mod.patch.string_value(sh) end)
    if type(s) == "string" and #s > 0 then nm = s end
  end)
  if not nm or #nm == 0 then nm = "Proj"..tostring(ptype) end
  nameCache[ptype] = nm
  return nm
end

local function npc_name(ntype)
  if type(ntype) ~= "number" then return "?" end
  local c = npcNameCache[ntype]; if c then return c end
  local nm = nil
  pcall(function()
    local h = mod.patch.invoke(m_GetNPCName, ntype)
    if h then
      local s = nil
      pcall(function() s = mod.patch.string_value(h) end)
      if type(s) == "string" and #s > 0 then nm = s end
    end
  end)
  if not nm or #nm == 0 then nm = "Boss "..tostring(ntype) end
  npcNameCache[ntype] = nm
  return nm
end

local function newtext(s)
  if not s or not m_NewText then return end
  pcall(function()
    local h = mod.patch.string_create(s)
    mod.patch.invoke(m_NewText, h)
  end)
end
local C_BOSS = "C060FF"   -- 紫
local C_WPN  = "66CCFF"   -- 浅蓝
local C_DMG  = "CC2222"   -- 深红
local C_DOT  = "FFAA00"
local C_WHT  = "FFFFFF"   -- 序号白
local C_OK   = "55FF55"   -- 成功绿
g_cur_detail = nil   -- { kind="boss"/"event", n=编号 } 当前详情页
local C_ERR  = "FF5555"   -- 失败红
-- format a real-clock timestamp as HH:MM:SS
local function vtime(t)
  if type(t) ~= "number" then return "--:--:--" end
  local d = os.date("*t", t)
  if not d then return "--:--:--" end
  return string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
end
local function vtime_full(t)
  if type(t) ~= "number" then return "--/-- --:--:--" end
  local d = os.date("*t", t)
  if not d then return "--/-- --:--:--" end
  return string.format("%02d/%02d %02d:%02d:%02d", d.month, d.day, d.hour, d.min, d.sec)
end
local function ct(color, s) return "[c/" .. color .. ":" .. s .. "]" end

local function dumpStats()
  local now = os.clock()
  if now - g_last_dump < 0.3 then return end
  g_last_dump = now
  local list = {}
  for k, e in pairs(stat) do list[#list+1] = e end
  table.sort(list, function(a,b) return a.order < b.order end)
  local total_n = #list
  if total_n == 0 then newtext(ct(C_ERR, "no boss data")); return end
  local from = total_n
  for i = from, total_n do
    local e = list[i]
    newtext(ct(C_BOSS, npc_name(e.type)) .. "  " .. ct(C_DMG, tostring(e.total)))
    local rows = {}
    for nm, w in pairs(e.weapons) do rows[#rows+1] = { name = nm, dmg = w.dmg, dot = false } end
    for dn, d in pairs(e.dots or {}) do rows[#rows+1] = { name = dn, dmg = d.dmg, dot = true } end
    table.sort(rows, function(a,b)
      if a.dmg ~= b.dmg then return a.dmg > b.dmg end
      return tostring(a.name) < tostring(b.name)
    end)
    for _, r in ipairs(rows) do
      local col = r.dot and C_DOT or C_WPN
      
      newtext("  " .. ct(col, r.name) .. " " .. ct(C_DMG, tostring(r.dmg)))
    end
  end
  if #list == 0 then newtext(ct(C_ERR, "no boss damage")) end
end

local function chat_text(cm)
  if not cm or not g_get_msg_text then return nil end
  local r = nil
  pcall(function() r = mod.patch.invoke(g_get_msg_text, cm) end)
  if r == nil then return nil end
  local txt = nil
  pcall(function() txt = mod.patch.string_value(r) end)
  if type(txt) == "string" then return txt end
  if type(r) == "string" then return r end
  return nil
end

-- detect current event name from Main (nil if none)
local EVENT_INV = { [1]="哥布林入侵", [2]="霜月军团", [3]="海盗入侵", [4]="火星暴乱" }
-- returns (name, wave_key). wave_key splits an ongoing event into per-wave entries.
local function current_event()
  local it
  pcall(function() it = mod.patch.get_field_value(f_ev_invtype, nil, "int32") end)
  if it and it > 0 and EVENT_INV[it] then
    local w = 0
    pcall(function() w = mod.patch.get_field_value(f_ev_invwave, nil, "int32") or 0 end)
    return EVENT_INV[it], tostring(it)..":"..tostring(w)
  end
  local b
  pcall(function() b = mod.patch.get_field_value(f_ev_eclipse, nil, "bool") end)
  if b then return "日蚀", "eclipse:0" end
  pcall(function() b = mod.patch.get_field_value(f_ev_pumpkin, nil, "bool") end)
  if b then
    local w = 0
    pcall(function() w = mod.patch.get_field_value(f_npc_wavenum, nil, "int32") or 0 end)
    return "南瓜月", "pm:"..tostring(w)
  end
  pcall(function() b = mod.patch.get_field_value(f_ev_snow, nil, "bool") end)
  if b then
    local w = 0
    pcall(function() w = mod.patch.get_field_value(f_npc_wavenum, nil, "int32") or 0 end)
    return "霜月", "sm:"..tostring(w)
  end
  pcall(function() b = mod.patch.get_field_value(f_ev_blood, nil, "bool") end)
  if b then return "血月", "blood:0" end
  pcall(function() b = mod.patch.get_field_value(f_ev_slime, nil, "bool") end)
  if b then return "史莱姆雨", "slime:0" end
  return nil, nil
end

-- event list: evelist[] = { name=, t0=, t1=, total=, kills=, npcs={}, wdmg={} }
-- each event TRIGGER creates a new independent entry (session-scoped, t=frames since game start)
local evelist = {}
-- global combined list built by /list : gsession[] = {kind="boss"/"event", ref=entry, t0=}
local gsession = nil
local g_lastlist = nil
-- page history stack (stores command strings); /exit pops back
local gstack = {}
local g_in_nav = false
local function push_page(cmdstr)
  if g_in_nav then return end
  -- avoid pushing identical consecutive page
  if gstack[#gstack] == cmdstr then return end
  gstack[#gstack+1] = cmdstr
  if #gstack > 50 then table.remove(gstack, 1) end
end
local function mark_dirty()
  g_save_dirty = true
end

-- forward declaration (real body is defined after save_world, near the IO section)
local flush_now = function() end


local g_ev_active = nil   -- current active event entry
-- start a new event entry (every trigger / every wave = independent record)
local function ev_start(evname, evkey)
  local e = { name=evname, key=evkey, t0=os.time(), t1=nil, total=0, kills=0, npcs={}, wdmg={} }
  evelist[#evelist+1] = e
  g_ev_active = e
  mark_dirty()
  dlog("event start: "..evname.." key="..tostring(evkey))
  return e
end
-- seal the active entry if the running event (or its wave) changed
local function ev_check_active(curkey)
  if g_ev_active and curkey ~= g_ev_active.key then
    g_ev_active.t1 = os.time()
    dlog("EV sealed: "..tostring(g_ev_active.name).." total="..tostring(g_ev_active.total).." -> flush")
    g_ev_active = nil
    pcall(flush_now)
  end
end
local function ev_add_dmg(evname, evkey, npcname, wname, amount, iskill, npckey)
  if not evname or amount <= 0 then return end
  local e
  if g_ev_active and g_ev_active.key == evkey then
    e = g_ev_active
  else
    ev_check_active(evkey)
    e = ev_start(evname, evkey)
  end
  amount = math.floor(amount)
  e.total = e.total + amount
  local n = e.npcs[npcname]
  if not n then n = { dmg=0, cnt=0, kills=0 }; e.npcs[npcname] = n end
  n.dmg = n.dmg + amount
  n.cnt = n.cnt + 1
  if iskill then
    -- dedup: the same npc slot may report several kills within one hit
    local now = os.clock()
    if g_kill_who == -1 or g_kill_who ~= npckey or (now - g_kill_t) > 0.1 then
      e.kills = e.kills + 1; n.kills = n.kills + 1
    end
    g_kill_who = npckey; g_kill_t = now
  end
  mark_dirty()
  local w = e.wdmg[wname]
  if not w then w = { dmg=0, cnt=0 }; e.wdmg[wname] = w end
  w.dmg = w.dmg + amount
  w.cnt = w.cnt + 1
end
-- mark stats dirty; write at most once per 3s (survives crashes)
-- periodic auto-save: while a resumable (pausable) event is active, flush every 3 seconds.
-- Boss stats still only flush on death / leaving world; this keeps long events safe.
local function save_tick()
  if not g_loaded_world then return end
  if not g_save_dirty then return end          -- nothing changed since last flush
  local now = os.time()                        -- wall clock (seconds)
  if (now - g_save_t) < 3 then return end
  g_save_t = now
  g_save_dirty = false
  pcall(flush_now)
end

-- periodic: seal finished events/waves
local function ev_tick()
  local curkey = nil
  pcall(function() local _, k = current_event(); curkey = k end)
  ev_check_active(curkey)
end

-- on world enter: reconcile persisted (unfinished) events against the live game state.
--   live event present  -> resume the matching record (same name, t1==nil)
--   live event absent   -> seal it (it was cancelled/ended while away)
local function ev_reconcile_on_enter()
  local liveName, liveKey = nil, nil
  pcall(function() liveName, liveKey = current_event() end)
  local n_resume, n_seal = 0, 0
  for _, e in ipairs(evelist) do
    if e.t1 == nil then
      if liveName and e.name == liveName then
        -- resume: rebind active entry to this record
        g_ev_active = e
        n_resume = n_resume + 1
      else
        -- no matching live event -> it ended/was cancelled while we were away
        e.t1 = os.time()
        n_seal = n_seal + 1
      end
    end
  end
  if n_resume > 0 or n_seal > 0 then
    dlog("EV reconcile: resume="..n_resume.." seal="..n_seal.." live="..tostring(liveName))
    mark_dirty()
  end
end

-- list all bosses: idx. name  time  total
function dumpBossList()
  local list = {}
  for k, e in pairs(stat) do list[#list+1] = e end
  table.sort(list, function(a,b) return a.order < b.order end)
  if #list == 0 then newtext(ct(C_ERR, "no boss data")); return end
  gsession = {}; g_lastlist = "boss"
  for i, e in ipairs(list) do
    gsession[#gsession+1] = { kind="boss", ref=e, t0=e.t0 or 0 }
  end
  for i, e in ipairs(list) do
    newtext(string.format("%s %s  %s  %s",
      ct(C_WHT, tostring(i).."."), ct(C_BOSS, npc_name(e.type)), ct(C_WPN, vtime(e.t0)), ct(C_DMG, tostring(e.total))))
  end
end

-- boss detail by index
function dumpBossDetail(n)
  local list = {}
  for k, e in pairs(stat) do list[#list+1] = e end
  table.sort(list, function(a,b) return a.order < b.order end)
  local e = list[n]
  if not e then newtext(ct(C_ERR, "no such boss #"..tostring(n))); return end
  g_cur_detail = { kind="boss", n=n }
  newtext(string.format("%s  %s", ct(C_BOSS, npc_name(e.type)), ct(C_DMG, tostring(e.total))))
  local rows = {}
  for nm, w in pairs(e.weapons) do rows[#rows+1] = { name=nm, dmg=w.dmg, dot=false } end
  for dn, d in pairs(e.dots or {}) do rows[#rows+1] = { name=dn, dmg=d.dmg, dot=true } end
  table.sort(rows, function(a,b)
    if a.dmg ~= b.dmg then return a.dmg > b.dmg end
    return tostring(a.name) < tostring(b.name)
  end)
  for _, r in ipairs(rows) do
    local col = r.dot and C_DOT or C_WPN
    newtext("  " .. ct(col, r.name) .. " " .. ct(C_DMG, tostring(r.dmg)))
  end
end

-- list all events: idx. name  time  total
function dumpEventList()
  if #evelist == 0 then newtext(ct(C_ERR, "no event data")); return end
  gsession = {}; g_lastlist = "event"
  for i, e in ipairs(evelist) do
    gsession[#gsession+1] = { kind="event", ref=e, t0=e.t0 or 0 }
  end
  for i, e in ipairs(evelist) do
    newtext(string.format("%s %s  %s  %s",
      ct(C_WHT, tostring(i).."."), ct(C_BOSS, e.name), ct(C_WPN, vtime(e.t0)), ct(C_DMG, tostring(e.total))))
  end
end

-- event detail by index (n=nil -> latest)
function dumpEventDetail(n)
  if #evelist == 0 then newtext(ct(C_ERR, "no event data")); return end
  if n == nil then n = #evelist end
  local e = evelist[n]
  if not e then newtext(ct(C_ERR, "no such event #"..tostring(n))); return end
  g_cur_detail = { kind="event", n=n }
  newtext(string.format("%s  %s", ct(C_BOSS, e.name), ct(C_DMG, tostring(e.total))))
  local rows = {}
  for nm, w in pairs(e.wdmg) do rows[#rows+1] = { name=nm, dmg=w.dmg } end
  table.sort(rows, function(a,b)
    if a.dmg ~= b.dmg then return a.dmg > b.dmg end
    return tostring(a.name) < tostring(b.name)
  end)
  for i, r in ipairs(rows) do
    if i > 15 then break end
    newtext("  " .. ct(C_WPN, r.name) .. " " .. ct(C_DMG, tostring(r.dmg)))
  end
end

-- kill page: per-event kill counts (n=nil -> latest event)
function dumpKills(n)
  if #evelist == 0 then newtext(ct(C_ERR, "no event data")); return end
  local list
  if n == nil then
    list = { evelist[#evelist] }
  else
    local e = evelist[n]
    if not e then newtext(ct(C_ERR, "no such event #"..tostring(n))); return end
    list = { e }
  end
  for _, e in ipairs(list) do
    local tstr = ""
    if e.t1 then tstr = ct(C_WPN, vtime_full(e.t1)) .. "  " end
    newtext(string.format("%s  %s%s", ct(C_BOSS, e.name), tstr, ct(C_WPN, "击杀 "..tostring(e.kills).." 只")))
    local rows = {}
    for n, v in pairs(e.npcs) do
      if v.kills and v.kills > 0 then rows[#rows+1] = {name=n, kills=v.kills} end
    end
    table.sort(rows, function(a,b)
      if a.kills ~= b.kills then return a.kills > b.kills end
      return tostring(a.name) < tostring(b.name)
    end)
    for i, r in ipairs(rows) do
      if i > 15 then break end
      newtext(string.format("  %s  %s", ct(C_WHT, r.name), ct(C_WPN, "x"..tostring(r.kills))))
    end
    if #rows == 0 then
      newtext(ct(C_WPN, "  (无击杀明细)"))
    end
  end
end

-- build the merged global session (bosses + events, sorted by time). No output.
local function build_global_session()
  gsession = {}; g_lastlist = "global"
  for _, e in pairs(stat) do gsession[#gsession+1] = { kind="boss", ref=e, t0=e.t0 or 0 } end
  for _, e in ipairs(evelist) do gsession[#gsession+1] = { kind="event", ref=e, t0=e.t0 or 0 } end
  table.sort(gsession, function(a,b)
    if a.t0 ~= b.t0 then return a.t0 < b.t0 end
    return tostring(a.ref.name or a.ref.type) < tostring(b.ref.name or b.ref.type)
  end)
  return gsession
end

-- global list: all bosses + all events merged, sorted by time
function dumpGlobalList()
  build_global_session()
  if #gsession == 0 then newtext(ct(C_ERR, "no data")); return end
  for i, it in ipairs(gsession) do
    if it.kind == "boss" then
      newtext(string.format("%s %s  %s  %s",
        ct(C_WHT, tostring(i).."."), ct(C_BOSS, npc_name(it.ref.type)), ct(C_WPN, vtime(it.ref.t0)), ct(C_DMG, tostring(it.ref.total))))
    else
      newtext(string.format("%s %s  %s  %s",
        ct(C_WHT, tostring(i).."."), ct(C_BOSS, it.ref.name), ct(C_WPN, vtime(it.ref.t0)), ct(C_DMG, tostring(it.ref.total))))
    end
  end
end

-- global detail by unified index (requires /list first)
function dumpGlobalDetail(n)
  if not gsession then newtext(ct(C_ERR, "run /list first")); return end
  local it = gsession[n]
  if not it then newtext(ct(C_ERR, "no such #"..tostring(n))); return end
  local e = it.ref
  if it.kind == "boss" then
    newtext(string.format("%s  %s", ct(C_BOSS, npc_name(e.type)), ct(C_DMG, tostring(e.total))))
    local rows = {}
    for nm, w in pairs(e.weapons) do rows[#rows+1] = { name=nm, dmg=w.dmg, dot=false } end
    for dn, d in pairs(e.dots or {}) do rows[#rows+1] = { name=dn, dmg=d.dmg, dot=true } end
    table.sort(rows, function(a,b)
      if a.dmg ~= b.dmg then return a.dmg > b.dmg end
      return tostring(a.name) < tostring(b.name)
    end)
    for _, r in ipairs(rows) do
      local col = r.dot and C_DOT or C_WPN
      newtext("  " .. ct(col, r.name) .. " " .. ct(C_DMG, tostring(r.dmg)))
    end
  else
    newtext(string.format("%s  %s", ct(C_BOSS, e.name), ct(C_DMG, tostring(e.total))))
    local rows = {}
    for nm, w in pairs(e.wdmg) do rows[#rows+1] = { name=nm, dmg=w.dmg } end
    table.sort(rows, function(a,b)
      if a.dmg ~= b.dmg then return a.dmg > b.dmg end
      return tostring(a.name) < tostring(b.name)
    end)
    for i, r in ipairs(rows) do
      if i > 15 then break end
      newtext("  " .. ct(C_WPN, r.name) .. " " .. ct(C_DMG, tostring(r.dmg)))
    end
  end
end

-- parse a raw command string -> cmd, arg  (nil if not a known command)
local KNOWN0 = {}  -- filled below
local function parse_cmd(raw)
  local t = raw:gsub("^%s+", ""):gsub("%s+$", "")
  t = t:lower()
  if t:sub(1,1) ~= "/" then return nil end
  local nm = t:match("^/(%a+)(%d+)$")   -- /boss1, /event2, /kill3
  if nm then t = "/" .. nm .. " " .. select(2, t:match("^/(%a+)(%d+)$")) end
  local cmd, arg
  local a, b = t:match("^(%S+)%s+(%S+)$")
  if a then cmd, arg = a, b
  else
    cmd = t
    local w = cmd:match("^/(%a+)$")
    if w == "bosslist" then cmd, arg = "/boss", "list"
    elseif w == "eventlist" then cmd, arg = "/event", "list"
    end
  end
  -- normalized t (for /N form)
  local cmd2 = cmd
  if cmd2 == "/boss" or cmd2 == "/event" or cmd2 == "/kill" or cmd2 == "/list"
     or cmd2 == "/exit" or cmd2 == "/a"
     or cmd2 == "/clean" or cmd2 == "/bossclean" or cmd2 == "/eventclean" then
    return cmd2, arg
  end
  if t:match("^/(%d+)$") then return "/N", t:match("^/(%d+)$") end
  return nil
end

local function is_valid_cmd(raw)
  return parse_cmd(raw) ~= nil
end

-- core: execute a command string (no chat parsing)
-- page turn: /+[k] next, /-[k] prev (k defaults 1); out of range -> warn only
local function turn_page(dir, k)
  if type(k) ~= "number" or k < 1 then k = 1 end
  if not g_cur_detail then
    newtext(ct(C_ERR, "no detail page (open /boss N or /event N first)"))
    return
  end
  local kind, cur = g_cur_detail.kind, g_cur_detail.n
  local maxn
  if kind == "boss" then
    local list = {}
    for _, e in pairs(stat) do list[#list+1] = e end
    maxn = #list
  else
    maxn = #evelist
  end
  local target = cur + dir * k
  if target < 1 or target > maxn then
    newtext(ct(C_ERR, "超出已有页数"))
    return
  end
  if kind == "boss" then dumpBossDetail(target) else dumpEventDetail(target) end
end

local function dispatch_text(t)
  t = t:gsub("^%s+", ""):gsub("%s+$", "")
  t = t:lower()
  local low = t
  local nm = low:match("^/(%a+)(%d+)$")   -- /boss1, /event2, /kill3
  if nm then t = "/" .. nm .. " " .. select(2, low:match("^/(%a+)(%d+)$")) end
  local cmd, arg
  local a, b = t:match("^(%S+)%s+(%S+)$")
  if a then cmd, arg = a, b
  else
    cmd = t
    -- glued words: /bosslist /eventlist
    local w = cmd:match("^/(%a+)$")
    if w == "bosslist" then cmd, arg = "/boss", "list"
    elseif w == "eventlist" then cmd, arg = "/event", "list"
    end
  end
  if cmd == "/boss" then
    if arg == "list" then dumpBossList()
    elseif arg and tonumber(arg) then dumpBossDetail(tonumber(arg))
    else dumpStats() end
  elseif cmd == "/event" then
    if arg == "list" then dumpEventList()
    elseif arg and tonumber(arg) then dumpEventDetail(tonumber(arg))
    else dumpEventDetail(nil) end
  elseif cmd == "/kill" then
    if arg and tonumber(arg) then dumpKills(tonumber(arg)) else dumpKills(nil) end
  elseif cmd == "/list" then
    dumpGlobalList()
  elseif t:match("^/%+%d*$") or t:match("^/%-%d*$") then
    local d = t:find("%+") and 1 or -1
    local k = tonumber(t:match("[%+%-](%d*)")) or 1
    turn_page(d, k)
  elseif t:match("^/(%d+)$") then
    dumpGlobalDetail(tonumber(t:match("^/(%d+)$")))
  end
end

--==================== world save/load ====================
local function _init_save_dir()
  if SAVE_DIR then return SAVE_DIR end
  local base = nil
  pcall(function() base = mod.private_dir end)
  if type(base) == "string" and #base > 0 then
    SAVE_DIR = base
  else
    SAVE_DIR = "/sdcard/Download"
  end
  return SAVE_DIR
end
local g_save_dir_ready = false
local function _mk_save_dir()
  if g_save_dir_ready then return end
  local d = _init_save_dir()
  -- try to create via shell (non-fatal if blocked)
  pcall(function() os.execute("mkdir -p '"..d.."'") end)
  -- no probe file: trust private_dir after mkdir attempt
  g_save_dir_ready = true
end
local function _safe_name(wn)
  -- sanitize world name for use as a file name
  local x = wn:gsub("[/\\:*?\"<>|]", "_")
  x = x:gsub("%s+", "_")
  if #x > 60 then x = x:sub(1, 60) end
  return x
end
-- file name is keyed by the world's creation-time fingerprint (survives renames).
-- falls back to the world name only if no fingerprint is available.
local function _fp_tag(wn)
  if g_world_fp and g_world_fp ~= "" then
    return (g_world_fp:gsub(":", "_"))
  end
  return _safe_name(wn or "unknown")
end
local function _boss_path(wn)
  return _init_save_dir().."/dmg_boss_".._fp_tag(wn)..".txt"
end
local function _event_path(wn)
  return _init_save_dir().."/dmg_event_".._fp_tag(wn)..".txt"
end

-- 读某存档文件的 FP 行；返回 fp 字符串或 nil
local function _read_fp(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local head = f:read("*l")
  local fp = nil
  local cnt = 0
  while head and cnt < 5 do
    if head:sub(1,3) == "FP|" then fp = _unesc(head:sub(4)); break end
    head = f:read("*l"); cnt = cnt + 1
  end
  f:close()
  return fp
end

-- 列出 saves 下所有 boss_*.txt，返回 {path=..., name=...}
local function _list_saves(prefix)
  local out = {}
  local dir = _init_save_dir()
  local p = io.popen and io.popen('ls "'..dir..'" 2>/dev/null')
  dlog("_list_saves: popen="..tostring(p ~= nil).." dir="..tostring(dir))
  if not p then return out end
  for fname in p:lines() do
    dlog("_list_saves line: ["..fname.."]")
    if fname:sub(1, #prefix) == prefix and fname:sub(-4) == ".txt" then
      out[#out+1] = { name = fname, path = dir.."/"..fname }
    end
  end
  p:close()
  dlog("_list_saves: matched="..#out)
  return out
end

-- 按指纹找存档（返回匹配的世界名或 nil）；不含 exname（排除当前名字）
local function _find_world_by_fp(fp, exname)
  if not fp or fp == "" then return nil end
  local hits = _list_saves("dmg_boss_")
  local found = nil
  for _, it in ipairs(hits) do
    local f = _read_fp(it.path)
    if f and f == fp then
      local wn = it.name:sub(10, -5)  -- strip "dmg_boss_" and ".txt"
      if wn ~= exname then found = wn; break end
    end
  end
  return found
end

-- escape | and \n inside a token
local function _esc(x)
  x = tostring(x or "")
  x = x:gsub("\\", "\\\\")
  x = x:gsub("|", "\\p")
  x = x:gsub("\n", "\\n")
  return x
end
local function _unesc(x)
  x = x:gsub("\\n", "\n")
  x = x:gsub("\\p", "|")
  x = x:gsub("\\\\", "\\")
  return x
end
local function _split(str, sep)
  local out = {}
  for part in (str..sep):gmatch("(.-)"..sep) do out[#out+1] = part end
  return out
end

local function save_boss(wn)
  if not wn or wn == "" then return end
  _mk_save_dir()
  local path = _boss_path(wn)
  local f = io.open(path, "w")
  if not f then dlog("save boss: open fail "..path); return end
  f:write("W|".._esc(wn).."\n")
  if g_world_fp then f:write("FP|".._esc(g_world_fp).."\n") end
  f:write("NEXT|"..tostring(g_next_id).."|"..tostring(g_next_order).."\n")
  for _, e in pairs(stat) do
    local line = "B|"..tostring(e.type).."|"..tostring(e.order).."|"..tostring(e.t0 or 0).."|"..tostring(e.t1 or 0).."|"..tostring(e.total or 0)
    local ws = {}
    for k, v in pairs(e.weapons or {}) do ws[#ws+1] = _esc(k)..":"..tostring(v.dmg)..":"..tostring(v.cnt) end
    line = line.."|"..table.concat(ws, "~")
    local ds = {}
    for k, v in pairs(e.dots or {}) do ds[#ds+1] = _esc(k)..":"..tostring(v.dmg)..":"..tostring(v.cnt) end
    line = line.."|"..table.concat(ds, "~")
    f:write(line.."\n")
  end
  f:close()
  dlog("save boss ok: "..path)
end

local function save_event(wn)
  if not wn or wn == "" then return end
  _mk_save_dir()
  local path = _event_path(wn)
  local f = io.open(path, "w")
  if not f then dlog("save event: open fail "..path); return end
  f:write("W|".._esc(wn).."\n")
  if g_world_fp then f:write("FP|".._esc(g_world_fp).."\n") end
  for _, e in ipairs(evelist) do
    local line = "E|".._esc(e.name).."|".._esc(e.key or "").."|"..tostring(e.t0 or 0).."|"..tostring(e.t1 or 0).."|"..tostring(e.total or 0).."|"..tostring(e.kills or 0)
    local ns = {}
    for k, v in pairs(e.npcs or {}) do ns[#ns+1] = _esc(k)..":"..tostring(v.dmg)..":"..tostring(v.cnt)..":"..tostring(v.kills) end
    line = line.."|"..table.concat(ns, "~")
    local ws = {}
    for k, v in pairs(e.wdmg or {}) do ws[#ws+1] = _esc(k)..":"..tostring(v.dmg)..":"..tostring(v.cnt) end
    line = line.."|"..table.concat(ws, "~")
    f:write(line.."\n")
  end
  f:close()
  dlog("save event ok: "..path)
end

local function save_world(wn)
  if not g_write_enabled then dlog("write disabled, skip save"); return end
  local ok1, e1 = pcall(save_boss, wn)
  if not ok1 then dlog("save_boss ERR "..tostring(e1)) end
  local ok2, e2 = pcall(save_event, wn)
  if not ok2 then dlog("save_event ERR "..tostring(e2)) end
end

-- real implementation (needs save_world in scope)
flush_now = function()
  if not g_loaded_world then dlog("flush: no g_loaded_world"); return end
  g_save_dirty = false
  g_save_t = os.time()
  local ok, err = pcall(function() save_world(g_loaded_world) end)
  if not ok then dlog("flush: save_world ERR "..tostring(err)) end
end

local function _iter_lines(path, fn)
  local f = io.open(path, "r")
  if not f then dlog("_iter: open(r) FAIL "..path); return false end
  local txt = f:read("*a"); f:close()
  dlog("_iter: read len="..tostring(txt and #txt or -1).." "..path)
  if not txt or #txt == 0 then return false end
  for line in (txt.."\n"):gmatch("(.-)\n") do
    if #line > 0 then fn(line) end
  end
  return true
end

local function load_boss(wn)
  if not wn or wn == "" then return false end
  local path = _boss_path(wn)
  local n = 0
  local ok = _iter_lines(path, function(line)
    local parts = _split(line, "|")
    local tag = parts[1]
    if tag == "NEXT" then
      g_next_id = tonumber(parts[2]) or 0
      g_next_order = tonumber(parts[3]) or 0
    elseif tag == "B" then
      -- new fmt: B|type|order|t0|t1|total|weapons|dots
      -- old fmt: B|type|order|t0|total|weapons|dots
      local t0 = tonumber(parts[4]) or 0
      local t1, total, wpart, dpart
      if #parts >= 8 then
        t1 = tonumber(parts[5]) or 0; if t1 == 0 then t1 = nil end
        total = tonumber(parts[6]) or 0
        wpart = parts[7]; dpart = parts[8]
      else
        t1 = nil
        total = tonumber(parts[5]) or 0
        wpart = parts[6]; dpart = parts[7]
      end
      local e = { type=tonumber(parts[2]) or 0, order=tonumber(parts[3]) or 0,
                  t0=t0, t1=t1, total=total,
                  weapons={}, dots={} }
      local ws = wpart or ""
      if #ws > 0 then
        for _, ent in ipairs(_split(ws, "~")) do
          local a,b,c = ent:match("^(.-):(%d+):(%d+)$")
          if a then e.weapons[_unesc(a)] = { dmg=tonumber(b), cnt=tonumber(c) } end
        end
      end
      local ds = dpart or ""
      if #ds > 0 then
        for _, ent in ipairs(_split(ds, "~")) do
          local a,b,c = ent:match("^(.-):(%d+):(%d+)$")
          if a then e.dots[_unesc(a)] = { dmg=tonumber(b), cnt=tonumber(c) } end
        end
      end
      stat[e.order] = e
      n = n + 1
    end
  end)
  dlog("load boss: "..path.." ok="..tostring(ok).." n="..n)
  if ok then renumber_boss() end
  return ok
end

local function load_event(wn)
  if not wn or wn == "" then return false end
  local path = _event_path(wn)
  local n = 0
  local ok = _iter_lines(path, function(line)
    local parts = _split(line, "|")
    local tag = parts[1]
    if tag == "E" then
      local e = { name=_unesc(parts[2] or ""), key=_unesc(parts[3] or ""),
                  t0=tonumber(parts[4]) or 0, t1=tonumber(parts[5]) or 0,
                  total=tonumber(parts[6]) or 0, kills=tonumber(parts[7]) or 0,
                  npcs={}, wdmg={} }
      if e.t1 == 0 then e.t1 = nil end
      local ns = parts[8] or ""
      if #ns > 0 then
        for _, ent in ipairs(_split(ns, "~")) do
          local a,b,c,d = ent:match("^(.-):(%d+):(%d+):(%d+)$")
          if a then e.npcs[_unesc(a)] = { dmg=tonumber(b), cnt=tonumber(c), kills=tonumber(d) } end
        end
      end
      local ws = parts[9] or ""
      if #ws > 0 then
        for _, ent in ipairs(_split(ws, "~")) do
          local a,b,c = ent:match("^(.-):(%d+):(%d+)$")
          if a then e.wdmg[_unesc(a)] = { dmg=tonumber(b), cnt=tonumber(c) } end
        end
      end
      evelist[#evelist+1] = e
      n = n + 1
    end
  end)
  dlog("load event: "..path.." ok="..tostring(ok).." n="..n)
  return ok
end

-- load both; returns true if any file existed
local function load_world(wn)
  if not wn or wn == "" then return false end
  -- fresh containers first
  stat = {}; slot = {}; g_boss_recent = {}
  evelist = {}
  g_next_id = 0; g_next_order = 0
  g_ev_active = nil
  local okb = false; local oke = false
  pcall(function() okb = load_boss(wn) end)
  pcall(function() oke = load_event(wn) end)
  return (okb or oke)
end

--==================== /world save/load ====================

-- wipe all collected data (on world enter)
local function clear_all(auto)
  stat = {}; slot = {}; g_next_id = 0; g_next_order = 0
  g_boss_recent = {}; g_boss_seen_ids = {}; g_ptype = -2; g_t0 = os.clock()
  evelist = {}; g_ev_active = nil; gsession = nil; g_lastlist = nil
  mark_dirty()
  if not auto then flush_now() end   -- auto (world-enter) only clears memory, never writes
end

local function clear_boss()
  stat = {}; slot = {}; g_next_id = 0; g_next_order = 0
  g_boss_recent = {}; g_boss_seen_ids = {}; g_last_dump = -10
  gsession = nil; g_lastlist = nil; gstack = {}
  mark_dirty(); flush_now()
end

local function clear_event()
  evelist = {}; g_ev_active = nil
  gsession = nil; g_lastlist = nil; gstack = {}
  mark_dirty(); flush_now()
end

-- sorted boss list (by order)
local function boss_sorted()
  local list = {}
  for k, e in pairs(stat) do list[#list+1] = e end
  table.sort(list, function(a,b) return a.order < b.order end)
  return list
end

-- renumber every boss so order is contiguous 0..n-1 (no gaps after deletes)
local function renumber_boss()
  local list = boss_sorted()
  for i, e in ipairs(list) do e.order = i - 1 end
  g_next_order = #list
  return list
end

-- delete Nth boss; renumber order afterwards
local function del_boss(n)
  local list = boss_sorted()
  local e = list[n]
  if not e then return false end
  -- find its key in stat
  for k, v in pairs(stat) do
    if v == e then stat[k] = nil; slot = {}; break end
  end
  -- renumber remaining so order stays contiguous
  renumber_boss()
  g_boss_recent = {}; g_boss_seen_ids = {}
  gsession = nil; g_lastlist = nil
  mark_dirty(); flush_now()
  return true
end

-- delete Nth event (array, shifts automatically)
local function del_event(n)
  if n < 1 or n > #evelist then return false end
  table.remove(evelist, n)
  gsession = nil; g_lastlist = nil
  mark_dirty(); flush_now()
  return true
end

-- delete Nth global entry (auto-builds list if needed); kind-aware
local function del_global(n)
  if not gsession then build_global_session() end
  local it = gsession and gsession[n]
  if not it then return false end
  if it.kind == "boss" then
    local e = it.ref
    for k, v in pairs(stat) do
      if v == e then stat[k] = nil; slot = {}; break end
    end
    renumber_boss()
    g_boss_recent = {}; g_boss_seen_ids = {}
  else
    for i, ee in ipairs(evelist) do
      if ee == it.ref then table.remove(evelist, i); break end
    end
  end
  gsession = nil; g_lastlist = nil
  mark_dirty(); flush_now()
  return true
end

-- detect "just entered a world": worldName "" -> non-empty edge
-- pre-built closure (avoid allocating a new one every frame)
local g_cwe_wn = ""
local function _cwe_read()
  g_cwe_wn = mod.patch.get_field_value(f_world_name, nil, "string") or ""
end
local g_last_world = nil   -- name of the world we last greeted in
local g_greet_world = nil  -- world name pending a delayed greeting
local g_greet_at = 0       -- os.clock() deadline for the pending greeting
local function check_world_enter()
  if not f_world_name then if not g_cwe_warned then g_cwe_warned=true; dlog("cwe: no f_world_name") end; return end
  g_cwe_wn = ""
  pcall(_cwe_read)
  local wn = g_cwe_wn
  if wn == "" then
    -- leaving the world: seal unfinished bosses (t1 = now), flush, then wipe memory
    if g_loaded_world then
      pcall(function()
        local sealed = 0
        for _, e in pairs(stat) do
          if e.t1 == nil then e.t1 = os.time(); sealed = sealed + 1 end
        end
        for _, e in ipairs(evelist) do
          if e.t1 == nil then e.t1 = os.time(); sealed = sealed + 1 end
        end
        if sealed > 0 then dlog("SEAL unfinished bosses="..sealed) end
      end)
      pcall(function() save_world(g_loaded_world) end)
      g_loaded_world = nil
      -- wipe all in-memory data so nothing leaks into the next world
      pcall(clear_all, true)
      g_world_fp = nil
    end
    g_last_world = nil
    g_greet_world = nil
    return
  end
  -- new world: load this world's saved stats (falls back to a clean slate)
  if wn ~= g_last_world then
    g_last_world = wn
    g_greet_world = wn
    g_greet_at = os.clock() + 10.0
    dlog("world enter: ["..tostring(wn).."]")
    g_world_fp = nil
    if __wfp_probe then pcall(__wfp_probe) end
    local loaded = false
    pcall(function() loaded = load_world(wn) end)
    if not loaded then pcall(clear_all, true) end
    g_loaded_world = wn
    pcall(ev_reconcile_on_enter)
  end
  -- fire the pending greeting once the delay elapses
  if g_greet_world and os.clock() >= g_greet_at then
    g_greet_world = nil
    pcall(function() newtext(ct("FFD700", "输入 /a 获取命令帮助")) end)
  end
end

local function handle_chat(cm)
  local txt = chat_text(cm); if not txt then return end
  check_world_enter()
  local t = txt:gsub("^%s+", ""):gsub("%s+$", "")
  t = t:lower()
  -- dedup: hook may fire several times for one chat message
  local now = os.clock()
  if t == g_last_cmd and (now - g_last_cmd_t) < 0.3 then return end
  g_last_cmd = t; g_last_cmd_t = now
  if t == "/exit" then
    if #gstack >= 2 then
      table.remove(gstack)
      local prev = gstack[#gstack]
      g_in_nav = true
      dispatch_text(prev)
      g_in_nav = false
    elseif #gstack == 1 then
      table.remove(gstack)
      newtext(ct(C_BOSS, "(top)"))
    else
      newtext(ct(C_BOSS, "(no history)"))
    end
    return
  end
  -- clean family, with optional index: /bossclean[ N], /eventclean[ N], /clean[ N]
  local cn, cnm = t:match("^/(%a+clean)(%d+)$")
  if cn then t = "/" .. cn .. " " .. cnm end
  local cc, ca = t:match("^(/%a+clean)%s+(%S+)$")
  if not cc then cc, ca = (t:match("^(/%a+clean)$")), nil end
  if cc == "/eventclean" then
    local n = ca and tonumber(ca)
    if n then
      newtext(del_event(n) and ct(C_OK, "event #"..n.." removed") or ct(C_ERR, "no event #"..n))
    else clear_event(); newtext(ct(C_OK, "event reset")) end
    return
  elseif cc == "/bossclean" then
    local n = ca and tonumber(ca)
    if n then
      newtext(del_boss(n) and ct(C_OK, "boss #"..n.." removed") or ct(C_ERR, "no boss #"..n))
    else clear_boss(); newtext(ct(C_OK, "boss reset")) end
    return
  elseif cc == "/clean" then
    local n = ca and tonumber(ca)
    if n then
      newtext(del_global(n) and ct(C_OK, "#"..n.." removed") or ct(C_ERR, "no #"..n))
    else clear_all(); newtext(ct(C_OK, "all reset")) end
    return
  end
  if t == "/open" then
    g_write_enabled = true
    newtext(ct(C_OK, "write ON"))
    g_save_dirty = true
    flush_now()
    return
  end
  if t == "/close" then
    g_write_enabled = false
    newtext(ct(C_OK, "write OFF"))
    return
  end
  if t == "/a" then
    newtext(ct("FFD700", "== 命令详情 / 命令解释 =="))
    local function H(c, d) newtext("  " .. ct("FFD700", string.format("%-11s", c)) .. ct("FFFFFF", d)) end
    H("/boss",       "Boss详情(默认最新，可跟数字按需查看)")
    H("/bosslist",   "世界Boss列表")
    H("/event",      "事件详情(默认最新，可跟数字按需查看)")
    H("/eventlist",  "事件列表")
    H("/kill",       "事件击杀详情(默认最新，可跟数字按需查看)")
    H("/list",       "全局列表")
    H("/N",          "查全局第N条(需先 /list)")
    H("/+",          "详情页 下一页")
    H("/-",          "详情页 上一页")
    H("/exit",       "返回上一页")
    H("/bossclean",  "清除Boss记录(默认全部，可跟数字按需清除)")
    H("/eventclean", "清除事件记录(默认全部，可跟数字按需清除)")
    H("/clean",      "清理全局列表(默认全部，可跟数字按需清除)")
    H("/open",       "开启记录保存(默认)")
    H("/close",      "关闭记录保存")
    return
  end
  push_page(t)
  dispatch_text(t)
end

-- lifeRegen CONTRIBUTION of each DoT debuff = share when life drops
-- (source: NPC.cs UpdateNPC_BuffApplyDOTs; value = how much it feeds lifeRegen)
local DOT_PPS = {
  [20]  = 12,   -- Poisoned
  [24]  = 12,   -- Poisoned2
  [39]  = 48,   -- Cursed Inferno
  [44]  = 0,    -- (unused)
  [69]  = 48,   -- Cursed Inferno alt
  [70]  = 60,   -- Venom
  [153] = 30,   -- Shadowflame
  [189] = 800,  -- Daybreak (per stack; num=100)
  [232] = 8,    -- On Fire!
  [324] = 8     -- On Fire! alt
}

-- returns: bestName (for display), weights = { {id=,name=,w=}, ... }
local function dot_kind(inst)
  local all = {}
  local weights = {}
  local best_id, best_pps = 0, -1
  pcall(function()
    local arr = mod.patch.get_field_value(f_npc_bufftype, inst, "object")
    if not arr then return end
    local n = mod.patch.array_length(arr)
    for i = 0, n-1 do
      local id = mod.patch.array_at(arr, i, "int32")
      if id and id > 0 then
        all[#all+1] = id
        local w = DOT_PPS[id]
        if w and w > 0 then
          if w > best_pps then best_pps = w; best_id = id end
          weights[#weights+1] = { id = id, w = w }
        end
      end
    end
  end)
  g_dbg_all = table.concat(all, ",")
  g_dbg_pick = best_id
  if #weights == 0 then return nil, nil end
  -- fetch names
  for _, e in ipairs(weights) do
    local nm = buffNameCache[e.id]
    if not nm then
      pcall(function()
        local h = mod.patch.invoke(m_GetBuffName, e.id)
        if h then nm = mod.patch.string_value(h) end
      end)
      if type(nm) ~= "string" or #nm == 0 then nm = "Buff"..e.id end
      buffNameCache[e.id] = nm
    end
    e.name = nm
  end
  local bname = buffNameCache[best_id]
  return bname, weights
end

local function get_boss_entry(who, life_before, lifeMax, ntype)
  local now = os.clock()
  -- reuse an entry created recently for the same boss type
  -- (summon/event on the same frame can spawn several npc slots for one boss)
  local function recent_id()
    local rc = g_boss_recent[ntype]
    if rc and (now - rc.t) < BOSS_NEW_GAP then return rc.id end
    return nil
  end
  local s = slot[who]
  if not s then
    local rid = recent_id()
    if rid ~= nil and stat[rid] then
      s = { id = rid, lifeMax = lifeMax }
    else
      s = { id = g_next_id, lifeMax = lifeMax }
      g_next_id = g_next_id + 1
      g_boss_recent[ntype] = { id = s.id, t = now }
    end
    slot[who] = s
  else
    -- detect respawn: life went back near full while we already have damage
    local e = stat[s.id]
    if e and e.total > 0 and lifeMax > 0 and life_before >= lifeMax then
      local rid = recent_id()
      if rid ~= nil and stat[rid] then
        s = { id = rid, lifeMax = lifeMax }
        slot[who] = s
      else
        s = { id = g_next_id, lifeMax = lifeMax }
        g_next_id = g_next_id + 1
        g_boss_recent[ntype] = { id = s.id, t = now }
        slot[who] = s
      end
    end
  end
  local e = stat[s.id]
  if not e then
    e = { type = ntype, order = #boss_sorted(), total = 0, weapons = {}, dots = {}, t0 = os.time(), t1 = nil }
    g_next_order = e.order + 1
    stat[s.id] = e
    mark_dirty()
  end
  return e
end

function setup()
  if _G.g_dp_setup_done then return end
  _G.g_dp_setup_done = true
  g_logf = nil  -- logging disabled
  Main = mod.patch.get_type("Terraria", "Main")
  NPC = mod.patch.get_type("Terraria", "NPC")
  Projectile = mod.patch.get_type("Terraria", "Projectile")
  Lang = mod.patch.get_type("Terraria", "Lang")
  WorldGen = mod.patch.get_type("Terraria", "WorldGen")
  if not (Main and NPC and Projectile and Lang) then return end

  f_world_name = mod.patch.get_field(Main, "worldName")
  -- === 世界创建时间指纹探测（只读 int32 + raw，不碰 struct）===
  __wfp_probe = function()
    local ok, r = pcall(function()
      local WFDT = mod.patch.get_type("Terraria.IO", "WorldFileData")
      if not WFDT then return "NO-WFDT" end
      local awfd = mod.patch.get_field(Main, "ActiveWorldFileData")
      local inst = mod.patch.get_field_value(awfd, nil, "object")
      if not inst then return "NOINST" end
      local sx, sy = -1, -1
      pcall(function() sx = mod.patch.get_field_value(mod.patch.get_field(WFDT, "WorldSizeX"), inst, "int32") end)
      pcall(function() sy = mod.patch.get_field_value(mod.patch.get_field(WFDT, "WorldSizeY"), inst, "int32") end)
      local rawh = "nil"
      pcall(function()
        local raw = mod.patch.get_field_raw(mod.patch.get_field(WFDT, "CreationTime"), inst)
        if raw then
          local hex = ""
          for i=1,#raw do hex = hex..string.format("%02x", string.byte(raw, i)) end
          rawh = tostring(#raw)..":"..hex
        end
      end)
      return "sx="..tostring(sx).." sy="..tostring(sy).." ctRaw="..rawh
    end)
    dlog("WFP: "..tostring(r).." ok="..tostring(ok))
    -- 提取 ctHex 作为指纹
    local hex = tostring(r):match("ctRaw=%d+:(%x+)")
    if hex and #hex == 16 then g_world_fp = "ct:"..hex else g_world_fp = nil end
    dlog("WFP fp="..tostring(g_world_fp))
  end
  f_ev_invtype = mod.patch.get_field(Main, "invasionType")
  f_ev_eclipse = mod.patch.get_field(Main, "eclipse")
  f_ev_pumpkin = mod.patch.get_field(Main, "pumpkinMoon")
  f_ev_snow    = mod.patch.get_field(Main, "snowMoon")
  f_ev_blood   = mod.patch.get_field(Main, "bloodMoon")
  f_ev_slime   = mod.patch.get_field(Main, "slimeRain")
  f_ev_invwave = mod.patch.get_field(Main, "invasionProgressWave")
  f_npc_wavenum = mod.patch.get_field(NPC, "waveNumber")
  f_npc_boss = mod.patch.get_field(NPC, "boss")
  f_npc_type = mod.patch.get_field(NPC, "type")
  f_npc_who  = mod.patch.get_field(NPC, "whoAmI")
  f_npc_life = mod.patch.get_field(NPC, "life")
  f_npc_lifemax = mod.patch.get_field(NPC, "lifeMax")
  f_npc_bufftype = mod.patch.get_field(NPC, "buffType")
  m_GetBuffName  = mod.patch.get_method(Lang, "GetBuffName", 1)
  local f_mdb = mod.patch.get_field(Main, "debuff")
  if f_mdb then
    pcall(function() g_main_debuff_arr = mod.patch.get_field_value(f_mdb, nil, "object") end)
  end
  f_pr_type     = mod.patch.get_field(Projectile, "type")
  f_pr_dmg      = mod.patch.get_field(Projectile, "damage")
  f_pr_friendly = mod.patch.get_field(Projectile, "friendly")
  m_GetProjName = mod.patch.get_method(Lang, "GetProjectileName", 1)
  m_GetNPCName  = mod.patch.get_method(Lang, "GetNPCNameValue", 1)

  m_NewText = mod.patch.get_method(Main, "NewText", 3)
  if not m_NewText then m_NewText = mod.patch.get_method(Main, "NewText", 5) end
  ChatMessage = mod.patch.get_type("Terraria.Chat", "ChatMessage")
  if ChatMessage then
    local prop = mod.patch.get_property(ChatMessage, "Text")
    if prop then g_get_msg_text = mod.patch.property_get_method(prop) end
  end

  -- Main.Update -> per-frame world-enter/exit detection
  local mUpd = mod.patch.get_method(Main, "Update", 1)
  dlog("setup: mUpd=" .. tostring(mUpd ~= nil))
  if mUpd then
    local fc = 0
    mod.patch.install_hook(mUpd, { prefix = function(inst,args,res)
      fc = fc + 1
      -- world-enter detection ~every 6 calls (Main.Update fires several times per frame)
      if (fc % 6) == 0 then pcall(check_world_enter) end
      if (fc % 30) == 0 then pcall(ev_tick) end
      if (fc % 30) == 0 then pcall(save_tick) end
      return false
    end })
  end

  -- WorldLoaded -> clear all
  dlog("setup: WorldGen=" .. tostring(WorldGen ~= nil))
  if WorldGen then
    local mWL = mod.patch.get_method(WorldGen, "WorldLoaded", 0)
    dlog("setup: mWL=" .. tostring(mWL ~= nil))
    if mWL then
      mod.patch.install_hook(mWL, { postfix = function(inst,args,res)
        dlog("WorldLoaded FIRED")
        pcall(function() clear_all(true) end)
        pcall(function() newtext(ct("FFD700", "输入 /a 获取命令帮助")) end) end })
    end
  end

  -- Projectile.Damage : only friendly damaging projectiles update g_ptype
  local mPD = mod.patch.get_method(Projectile, "Damage", 0)
  if mPD then
    mod.patch.install_hook(mPD, { prefix = function(inst,args,res)
      pcall(function()
        local fr = mod.patch.get_field_value(f_pr_friendly, inst, "bool")
        if not fr then return end
        local dmg = mod.patch.get_field_value(f_pr_dmg, inst, "int32")
        if not dmg or dmg <= 0 then return end
        g_ptype = mod.patch.get_field_value(f_pr_type, inst, "int32")
      end)
      return false
    end })
  end

  -- StrikeNPC(6)
  local mSN = mod.patch.get_method(NPC, "StrikeNPC", 6)
  if mSN then
    local pend_boss, pend_type, pend_who, pend_lb, pend_lmax = false,0,-1,0,0
    mod.patch.install_hook(mSN, {
      prefix = function(inst,args,res)
        pend_boss = false
        check_world_enter()
        pcall(function()
          -- always record type/life (needed for both boss and event stats)
          pend_type = mod.patch.get_field_value(f_npc_type, inst, "int32") or 0
          pend_who  = mod.patch.get_field_value(f_npc_who, inst, "int32") or -1
          pend_lb   = mod.patch.get_field_value(f_npc_life, inst, "int32") or 0
          pend_lmax = mod.patch.get_field_value(f_npc_lifemax, inst, "int32") or 0
          local isboss = mod.patch.get_field_value(f_npc_boss, inst, "bool")
          if isboss then
            pend_boss = true
            -- Boss first sighted: create its entry immediately and persist once
            local e = get_boss_entry(pend_who, pend_lb, pend_lmax, pend_type)
            if e and e.total == 0 then
              g_boss_seen_ids = g_boss_seen_ids or {}
              if not g_boss_seen_ids[e.order] then
                g_boss_seen_ids[e.order] = true
                dlog("BOSS sighted: type="..tostring(pend_type).." order="..tostring(e.order).." (memory only)")
                mark_dirty()
              end
            end
          end
        end)
        return false
      end,
      postfix = function(inst,args,res)
        -- compute real damage (independent of boss/event)
        local pend_b = pend_boss
        local pend_t = pend_type
        local pend_l = pend_lb
        local pend_lm = pend_lmax
        local pend_w = pend_who
        pend_boss = false
        pcall(function()
          local ret = tonumber(res) or 0
          if ret <= 0 then
            local d2 = 0
            pcall(function() d2 = tonumber(args and args[1]) or 0 end)
            if d2 > 0 then ret = d2 end
          end
          local real = ret
          if pend_l > 0 and real > pend_l then real = pend_l end
          if real <= 0 then return end
          local wname = proj_name(g_ptype)
          -- Boss stats (need pend_boss)
          if pend_b then
            local e = get_boss_entry(pend_w, pend_l, pend_lm, pend_t)
            local w = e.weapons[wname]
            if not w then w = {dmg=0, cnt=0}; e.weapons[wname] = w end
            w.dmg = w.dmg + math.floor(real)
            w.cnt = w.cnt + 1
            e.total = e.total + math.floor(real)
            mark_dirty()
            -- boss death -> seal and flush immediately
            local cur = nil
            pcall(function() cur = mod.patch.get_field_value(f_npc_life, inst, "int32") end)
            if cur ~= nil and cur <= 0 and e.t1 == nil then
              e.t1 = os.time()
              dlog("BOSS died: type="..tostring(pend_t).." order="..tostring(e.order).." total="..tostring(e.total).." -> flush")
              pcall(flush_now)
            end
          end
          -- Event stats (any npc damage while event active, incl. non-boss)
          local ev, evk = current_event()
          if ev then
            local iskill = false
            local cur = nil
            pcall(function()
              cur = mod.patch.get_field_value(f_npc_life, inst, "int32")
              if cur ~= nil and cur <= 0 and pend_l > 0 then iskill = true end
            end)
            if g_kill_dbg > 0 then
              g_kill_dbg = g_kill_dbg - 1
              dlog("KILL t="..tostring(pend_t).." lb="..tostring(pend_l).." cur="..tostring(cur).." real="..tostring(real).." k="..tostring(iskill))
            end
            local nn = npc_name(pend_t)
            ev_add_dmg(ev, evk, nn, wname, real, iskill, pend_w)
          end
        end)
      end
    })
  end


  local mDOT = mod.patch.get_method(NPC, "UpdateNPC_BuffApplyDOTs", 0)
  if mDOT then
    mod.patch.install_hook(mDOT, {
      prefix = function(inst, args, res)
        check_world_enter()
        pcall(function()
          dot_before[inst] = mod.patch.get_field_value(f_npc_life, inst, "int32")
        end)
        return false
      end,
      postfix = function(inst, args, res)
        pcall(function()
          local before = dot_before[inst]
          dot_before[inst] = nil
          if before == nil then return end
          local isboss = mod.patch.get_field_value(f_npc_boss, inst, "bool")
          if not isboss then return end
          local after = mod.patch.get_field_value(f_npc_life, inst, "int32")
          if after == nil then return end
          local dealt = before - after
          if dealt <= 0 or dealt > 10000 then return end
          local who  = mod.patch.get_field_value(f_npc_who, inst, "int32")
          local ntype = mod.patch.get_field_value(f_npc_type, inst, "int32")
          local lmax = mod.patch.get_field_value(f_npc_lifemax, inst, "int32")
          local e = get_boss_entry(who, before, lmax, ntype)
          local dname, weights = dot_kind(inst)
          if not weights then
            dlog(string.format("DOT who=%d dealt=%d buffs=[%s] (no known dot) skip", who, dealt, g_dbg_all))
            return
          end
          -- split dealt across debuffs by lifeRegen contribution ratio
          local sum = 0
          for _, e2 in ipairs(weights) do sum = sum + e2.w end
          local remain = dealt
          local n = #weights
          dlog(string.format("DOT who=%d dealt=%d buffs=[%s] pick=%d nw=%d sum=%d",
                who, dealt, g_dbg_all, g_dbg_pick, n, sum))
          for i, e2 in ipairs(weights) do
            local part
            if i == n then
              part = remain
            else
              part = math.floor(dealt * e2.w / sum)
              remain = remain - part
            end
            if part < 0 then part = 0 end
            local d = e.dots[e2.name]
            if not d then d = {dmg=0, cnt=0}; e.dots[e2.name] = d end
            d.dmg = d.dmg + part
            d.cnt = d.cnt + 1
            dlog(string.format("   share %s id=%d w=%d part=%d", e2.name, e2.id, e2.w, part))
            -- event: record dot damage while event active
            local ev, evk = current_event()
            if ev then
              local iskill = false
              pcall(function() if after ~= nil and after <= 0 and before > 0 then iskill = true end end)
              ev_add_dmg(ev, evk, npc_name(ntype), e2.name, part, iskill, who)
            end
          end
        end)
        return false
      end
    })
  end
  ChatCmd = mod.patch.get_type("Terraria.Chat", "ChatCommandProcessor")
  if ChatCmd then
    local mPM = mod.patch.get_method(ChatCmd, "ProcessIncomingMessage", 2)
    if mPM then
      mod.patch.install_hook(mPM, { postfix = function(inst,args,res)
        pcall(function() handle_chat(args[1]) end) end })
    end
  end
  -- hot-reload recovery: new Lua state means empty memory; if we're already in a
  -- world, re-probe fingerprint and reload this world's saved data so we don't
  -- clobber the save file with fresh empty stats.
  pcall(function()
    if f_world_name then
      local wn = mod.patch.get_field_value(f_world_name, nil, "string") or ""
      if wn ~= "" then
        g_world_fp = nil
        if __wfp_probe then pcall(__wfp_probe) end
        local loaded = false
        pcall(function() loaded = load_world(wn) end)
        if not loaded then pcall(clear_all, true) end
        g_loaded_world = wn
        g_last_world = wn
        pcall(ev_reconcile_on_enter)
      end
    end
  end)
end

todo_list = { "setup" }
