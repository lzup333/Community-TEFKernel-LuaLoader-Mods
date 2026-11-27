-- star.fullmap —— 一键点亮全图（PE / Android）v1.1
--
-- v1.1 根因修复：PE 的 WorldMap.UnlockMapSection 是 4 字节空壳（RVA 0x89E888，
--       单条 ret），v1.0 逐节调它 384 次全部“成功”但一格都没写。
--       改为逐格调用 WorldMap.UpdateLighting(x, y, 255)（324 字节真实现，
--       语义 = CreateMapTile(x, y, max(old, 255))，与 PC 解锁做的事一致）。
--
-- 触发：屏幕原生触摸按钮「点亮全图」（mod.controls；Android 端 on_press 不派发，
--       用按下态轮询；按钮只在进入世界后显示）。
-- 性能：每帧一个整块 pcall，紧循环 P.invoke 直调（绕开 q.call 的 table.pack），
--       节循环 clamp 到 [40, max-40]（照抄 PC，顺带省 5% 格数），
--       首节打一条 µs/格 探针按实测决定每帧预算；IsRevealed 采样验收写入。
-- 联机：地图是「每玩家本地」的 .map 文件，只改自己这份 → 只对自己生效；
--       不发任何网络包，multiplayer_safe。
--       单机 / 房主：全部区块已加载 → 整图点亮；
--       联机客户端：只有已加载区块有地形数据，未加载的节自动跳过（无法凭空生成）。
local q = require("quickapi")
local P = mod.patch

mod.meta = { pkg_id = "star.fullmap", version = "1.1.0" }

-- 原生按钮 icon 字节（Resources/lib/btn_icon.lua，PNG 内联 \xNN 串）。
-- 走 pcall：图标缺失绝不能让整个 mod 加载失败；require 可能因 package.path
-- 没包进 mod 的 lib 目录而失败，失败就用 mod.mod_dir 塞进 package.path 再试。
local ok_icon, BTN_ICON = pcall(require, "btn_icon")
if (not ok_icon or type(BTN_ICON) ~= "string") and mod.mod_dir then
    package.path = tostring(mod.mod_dir) .. "/?.lua;" .. (package.path or "")
    ok_icon, BTN_ICON = pcall(require, "btn_icon")
end
if not ok_icon or type(BTN_ICON) ~= "string" then BTN_ICON = nil end

local BTN_ID   = "fullmap"
local BTN_NAME = "点亮全图"
local BUDGET   = 0.010          -- 每帧点亮时间预算（秒）
local MAX_TILES = 200000        -- 每帧格数硬上限（防时钟异常时单帧过载）
local CHECK_EVERY = 512         -- 每 N 格查一次时钟（os.clock 调用本身也有开销）
local EDGE     = 40             -- PC UnlockMapSection 的 BlackEdgeWidth
local SEC_W, SEC_H = 200, 150   -- 每节尺寸（格），与 WorldSections 构造一致

local H = {}                    -- setup 期解析的句柄
local S = { job = nil, ctl_ok = false, want = false, shown = nil, dead = false }

-- 方法解析包一层：名字/重载对不上时返回 nil，而不是让 setup 抛错
local function gm(t, name, argc)
    if not t then return nil end
    local ok, m = pcall(P.get_method, t, name, argc)
    if ok then return m end
    return nil
end

local function log(s) mod.info("[fullmap] " .. s) end
local function warn(s) mod.warn("[fullmap] " .. s) end

-- ============================ 读取辅助 ============================

local function rf_int(f) -- 读静态 int32
    if not f then return nil end
    local ok, v = pcall(P.get_field_value, f, nil, "int32")
    if ok then return v end
    return nil
end

local function rf_int2(f, inst) -- 读实例 int32
    if not f then return nil end
    local ok, v = pcall(P.get_field_value, f, inst, "int32")
    if ok then return v end
    return nil
end

-- 主菜单判定（gameMenu：优先 backing 字段，回退属性 getter）
local function in_menu()
    if H.f_menu then
        local ok, v = pcall(P.get_field_value, H.f_menu, nil, "bool")
        if ok then return v end
    end
    if H.m_getmenu then
        local ok, v = pcall(q.call, H.m_getmenu)
        if ok then return v end
    end
    return false
end

-- 句柄有效性（null 对象兜底，防原生空指针调用）
local function valid_obj(v)
    if not v then return nil end
    local okv, valid = pcall(P.is_valid, v)
    if okv and not valid then return nil end
    return v
end

-- 取 Main.Map（属性 getter；句柄只在当次调用内用，不跨帧缓存）
local function get_map()
    if not H.m_getmap then return nil end
    local ok, v = pcall(q.call, H.m_getmap)
    if ok then return valid_obj(v) end
    return nil
end

-- 取 Main.sectionManager
local function get_sm()
    if not H.m_getsm then return nil end
    local ok, v = pcall(q.call, H.m_getsm)
    if ok then return valid_obj(v) end
    return nil
end

-- 屏幕提示（聊天栏一行；失败退回日志）
local function toast(msg, r, g, b)
    if H.m_newtext then
        local ok = pcall(function()
            local s = P.string_create(msg)
            P.invoke(H.m_newtext, s, r, g, b, true)   -- onlyCurrentPlayer=true：不广播
        end)
        if ok then return end
        warn("聊天提示调用失败: " .. msg)
    end
    log("(提示) " .. msg)
end

-- ============================ 点亮任务 ============================

local function finish_job()
    local j = S.job
    S.job = nil
    if not j then return end

    -- 1) 写入 .map 存档（失败不碍事：正常退出世界时游戏也会保存）
    local map = get_map()
    if map and H.m_save then
        local ok, err
        if H.save_args == 1 then
            ok, err = pcall(q.call, H.m_save, map, true)   -- forceSave=true：立即写档
        else
            ok, err = pcall(q.call, H.m_save, map)
        end
        if not ok then warn("Map.Save 失败（退出世界时游戏仍会保存）: " .. tostring(err)) end
    end

    -- 2) 触发地图贴图全量重绘（clearMap 清贴图 + refreshMap 清区块绘制标记 + updateMap 触发重画）
    if H.m_setcl then pcall(q.call, H.m_setcl, true) end   -- clearMap=true
    if H.m_setrf then pcall(q.call, H.m_setrf, true) end   -- refreshMap=true
    if H.m_setum then pcall(q.call, H.m_setum, true) end   -- updateMap=true

    local el = os.clock() - j.t0
    toast(string.format("全图点亮完成：%d 格 / 跳过 %d 节", j.done, j.skip), 130, 255, 130)
    log(string.format("完成：写 %d 格（未变化 %d）跳过 %d 节 用时 %.1f 秒 揭示采样 %d/%d",
            j.done, j.unchanged or 0, j.skip, el, j.reveal_hits, j.reveal_n))
    if j.reveal_n > 0 and j.reveal_hits == 0 then
        warn("IsRevealed 采样全为 false：数据没有真正写进地图（UpdateLighting 路径需换方案）")
    elseif j.reveal_n > 0 and j.reveal_hits < j.reveal_n then
        warn(string.format("IsRevealed 采样部分未揭示（%d/%d），可能有节未加载或写入被忽略",
                j.reveal_hits, j.reveal_n))
    end
end

-- 节内实际要写的矩形：照抄 PC UnlockMapSection 的 clamp([40, max-40])。
-- 返回 nil 表示该节完全落在黑边里（无内容可写）。
local function section_rect(j, sx, sy)
    local x0 = sx * SEC_W
    if x0 < EDGE then x0 = EDGE end
    local x1 = (sx + 1) * SEC_W
    if x1 > j.maxx - EDGE then x1 = j.maxx - EDGE end
    local y0 = sy * SEC_H
    if y0 < EDGE then y0 = EDGE end
    local y1 = (sy + 1) * SEC_H
    if y1 > j.maxy - EDGE then y1 = j.maxy - EDGE end
    if x1 <= x0 or y1 <= y0 then return nil end
    return x0, x1, y0, y1
end

-- 取下一个已加载且有内容可写的节；没有则返回 false（整张图跑完）
local function next_section(j, sm, map)
    while j.sy < j.ny do
        local sx, sy = j.sx, j.sy
        j.sx = j.sx + 1
        if j.sx >= j.nx then
            j.sx = 0
            j.sy = j.sy + 1
        end
        local loaded = false
        local ok, v = pcall(P.invoke, H.m_secloaded, sm, sx, sy)
        if ok and v == true then loaded = true end
        if not loaded then
            j.skip = j.skip + 1
        else
            local x0, x1, y0, y1 = section_rect(j, sx, sy)
            if x0 then
                -- PE 的地图按 200×150 的节做“分块存储”，不加载分块时写入会落空。
                -- 先把这一节的存储区加载进来（全屏地图绘制走的就是这个 API）。
                if H.m_loadregions then
                    local lok = pcall(P.invoke, H.m_loadregions, map, x0, y0, x1, y1)
                    if not lok then
                        j.load_fail = (j.load_fail or 0) + 1
                        if j.load_fail == 1 then
                            warn("LoadChunkRegions 调用失败，继续尝试写入（稍后看采样）")
                        end
                    end
                end
                j.x0, j.x1, j.y0, j.y1 = x0, x1, y0, y1
                j.x, j.y = x0, y0
                j.sec_sx, j.sec_sy = sx, sy
                j.sec_t0 = os.clock()
                j.sec_n0 = j.done
                j.cur = true
                return true
            end
            j.skip = j.skip + 1
        end
    end
    return false
end

-- 解锁后采样 3 格 IsRevealed：这是“数据真的写进去了”的硬证据
local function sample_revealed(map, x0, x1, y0, y1)
    local hits = 0
    for i = 0, 2 do
        local x = x0 + math.floor((x1 - x0) * (i * 2 + 1) / 6)
        local y = y0 + math.floor((y1 - y0) * (i * 2 + 1) / 6)
        local ok, v = pcall(P.invoke, H.m_revealed, map, x, y)
        if ok and v == true then hits = hits + 1 end
    end
    return hits
end

local function finish_section(map, j)
    local hits = sample_revealed(map, j.x0, j.x1, j.y0, j.y1)
    local tiles = j.done - j.sec_n0
    local dt = os.clock() - j.sec_t0
    j.reveal_hits = j.reveal_hits + hits
    j.reveal_n = j.reveal_n + 3
    j.sec_done = j.sec_done + 1
    if j.sec_done == 1 then
        j.us_per_tile = tiles > 0 and (dt / tiles * 1e6) or 0
        log(string.format("性能探针：首节 %d 格 / %.1f ms / %.2f us/格；IsRevealed 采样 %d/3",
                tiles, dt * 1000, j.us_per_tile, hits))
        -- 按实测决定预算（接力棒 §3.1：>3us/格 要另想办法；默认 10ms，慢则 12ms）
        if j.us_per_tile > 2.5 then j.budget = 0.012 end
    elseif hits == 0 then
        j.zero_secs = j.zero_secs + 1
    end
    -- 节进度提示（每 25% 一条，不刷屏）
    local est = math.max(1, (j.maxx - 2 * EDGE) * (j.maxy - 2 * EDGE))
    local pct = math.floor(j.done * 100 / est)
    if pct >= j.next_pct and j.next_pct <= 75 then
        toast(string.format("点亮中… %d%%", j.next_pct), 255, 220, 80)
        j.next_pct = j.next_pct + 25
    end
end

-- 单帧紧循环：不逐格 pcall（整帧由 step_job 包一个 pcall）。
-- 返回 "done"（全图完成）或 "budget"（本帧预算用完）。
local function burn_frame(map, j, deadline)
    local n = 0
    while true do
        if not j.cur then
            if not next_section(j, j.sm, map) then return "done" end
        end

        local x, y = j.x, j.y
        -- 先推进游标：保证每格必前进，即使下面出错也不会死循环
        j.x = j.x + 1
        if j.x >= j.x1 then
            j.x = j.x0
            j.y = j.y + 1
        end
        -- 绕开 q.call 的 table.pack/unpack（每格一次表分配）
        local r = P.invoke(H.m_light, map, x, y, 255)
        j.done = j.done + 1
        if r == false then j.unchanged = j.unchanged + 1 end  -- false=本来就亮/无变化，非失败

        j.frame_tiles = j.frame_tiles + 1
        n = n + 1

        if j.y >= j.y1 then
            finish_section(map, j)
            j.cur = false
        end

        if n >= CHECK_EVERY then
            n = 0
            if j.frame_tiles >= MAX_TILES then return "budget" end
            if os.clock() >= deadline then return "budget" end
        end
    end
end

local function step_job()
    local j = S.job
    if not j then return end
    if in_menu() then
        S.job = nil
        warn("离开世界，点亮中止（已亮 " .. j.done .. " 格）")
        return
    end
    local map = get_map()
    local sm = get_sm()
    if not map or not sm then
        S.job = nil
        warn("地图/区块句柄失效，点亮中止（已亮 " .. j.done .. " 格）")
        return
    end
    j.sm = sm

    local t0 = os.clock()
    j.frame_tiles = 0
    local ok, why = pcall(burn_frame, map, j, t0 + j.budget)
    if not ok then
        j.err = (j.err or 0) + 1
        if j.err == 1 then warn("点亮循环出错（第 1 次，已跳过该格）: " .. tostring(why)) end
        if S.job == j and j.err > 3 then
            S.job = nil
            warn("点亮循环连续出错，任务中止（已亮 " .. j.done .. " 格）")
        end
        return
    end
    if why == "done" then finish_job() end
end

local function start_job()
    if S.job then return end
    if not (H.m_light and H.m_revealed and H.m_secloaded and H.m_getmap and H.m_getsm
            and H.f_maxx and H.f_maxy) then
        warn("关键句柄缺失，无法点亮")
        return
    end
    if in_menu() then
        toast("请先进入世界", 255, 140, 140)
        return
    end
    local map = get_map()
    if not map then
        toast("地图数据未加载", 255, 140, 140)
        log("Main.Map 为空")
        return
    end
    local sm = get_sm()
    if not sm then
        toast("区块管理器未加载", 255, 140, 140)
        return
    end
    local maxx, maxy = rf_int(H.f_maxx), rf_int(H.f_maxy)
    if not maxx or not maxy or maxx <= 0 or maxy <= 0 then
        toast("世界尺寸读取失败", 255, 140, 140)
        return
    end
    -- 节网格优先读 WorldSections 自身的 width/height（精确），读不到按 200×150 推算
    local nx, ny
    if H.f_sw and H.f_sh then
        nx = rf_int2(H.f_sw, sm)
        ny = rf_int2(H.f_sh, sm)
    end
    if not nx or not ny or nx <= 0 or ny <= 0 then
        nx = math.floor(maxx / SEC_W)
        ny = math.floor(maxy / SEC_H)
    end
    if nx <= 0 or ny <= 0 then
        toast("世界尺寸异常", 255, 140, 140)
        return
    end
    S.job = {
        sx = 0, sy = 0, nx = nx, ny = ny, maxx = maxx, maxy = maxy,
        done = 0, skip = 0, fail = 0, err = 0, unchanged = 0,
        sec_done = 0, zero_secs = 0, reveal_hits = 0, reveal_n = 0,
        budget = BUDGET, frame_tiles = 0, next_pct = 25,
        t0 = os.clock(), cur = false,
    }
    toast("全图点亮中…", 255, 220, 80)
    log(string.format("开始：%d×%d 节（世界 %d×%d，逐格 UpdateLighting，预算 %.0fms/帧）",
            nx, ny, maxx, maxy, BUDGET * 1000))
end

-- ============================ 每帧 ============================

local function tick_body()
    -- 按钮可见性：只在世界里显示
    if S.ctl_ok and mod.controls and mod.controls.set_visible then
        local show = not in_menu()
        if S.shown ~= show then
            pcall(mod.controls.set_visible, BTN_ID, show)
            S.shown = show
        end
    end

    -- 触发（Android 不派发 on_press → 轮询 pressed；S.want 兜底其它派发方式）
    if not S.job then
        local fire = false
        if S.want then
            fire = true
            S.want = false
        elseif S.ctl_ok then
            local ok, v = pcall(mod.controls.pressed, BTN_ID)
            if ok and v then fire = true end
        end
        if fire then start_job() end
    elseif S.want then
        S.want = false
    end

    -- 分帧推进
    if S.job then step_job() end
end

local function tick()
    if S.dead then return end
    local ok, err = pcall(tick_body)
    if not ok then
        S.dead = true
        mod.error("[fullmap] 每帧任务出错，已停用: " .. tostring(err))
    end
end

-- ============================ 启动 ============================

function setup()
    local MainT = q.type("Terraria", "Main")
    local PlayerT = q.type("Terraria", "Player")

    H.f_maxx = q.field("Terraria", "Main", "maxTilesX")
    H.f_maxy = q.field("Terraria", "Main", "maxTilesY")

    local p = q.property("Terraria", "Main", "Map")
    if p then H.m_getmap = P.property_get_method(p) end
    p = q.property("Terraria", "Main", "sectionManager")
    if p then H.m_getsm = P.property_get_method(p) end
    p = q.property("Terraria", "Main", "refreshMap")
    if p then H.m_setrf = P.property_set_method(p) end
    p = q.property("Terraria", "Main", "updateMap")
    if p then H.m_setum = P.property_set_method(p) end
    p = q.property("Terraria", "Main", "clearMap")
    if p then H.m_setcl = P.property_set_method(p) end

    H.f_menu = q.field("Terraria", "Main", "<gameMenu>k__BackingField")
    if not H.f_menu then
        p = q.property("Terraria", "Main", "gameMenu")
        if p then H.m_getmenu = P.property_get_method(p) end
    end

    local WM = q.type("Terraria.Map", "WorldMap")
    if WM then
        -- v1.1：逐格写；UnlockMapSection 在 PE 是空壳，不再使用
        H.m_light = gm(WM, "UpdateLighting", 3)
        H.m_revealed = gm(WM, "IsRevealed", 2)
        H.m_loadregions = gm(WM, "LoadChunkRegions", 4)
        local s1 = gm(WM, "Save", 1)
        if s1 then
            H.m_save = s1
            H.save_args = 1
        else
            H.m_save = gm(WM, "Save", 0)
            H.save_args = 0
        end
    end

    local WS = q.type("Terraria", "WorldSections")
    if WS then
        H.m_secloaded = gm(WS, "SectionLoaded", 2)
        H.f_sw = P.get_field(WS, "width")    -- private int：节网格宽
        H.f_sh = P.get_field(WS, "height")   -- private int：节网格高
    end

    if MainT then
        H.m_newtext = gm(MainT, "NewText", 5)
        if not H.m_newtext then
            local okn, m = pcall(P.get_method_by_names, MainT, "NewText",
                    { "newText", "R", "G", "B", "onlyCurrentPlayer" })
            if okn then H.m_newtext = m end
        end
    end

    -- 必需项自检
    local miss = {}
    local function need(v, name) if not v then miss[#miss + 1] = name end end
    need(H.m_getmap, "Main.Map")
    need(H.m_getsm, "Main.sectionManager")
    need(H.m_setrf, "Main.refreshMap setter")
    need(H.m_setum, "Main.updateMap setter")
    need(H.m_light, "WorldMap.UpdateLighting")
    need(H.m_revealed, "WorldMap.IsRevealed")
    need(H.m_secloaded, "WorldSections.SectionLoaded")
    need(H.f_maxx, "Main.maxTilesX")
    need(H.f_maxy, "Main.maxTilesY")
    if #miss > 0 then warn("缺失句柄: " .. table.concat(miss, ", ")) end
    if not H.m_save then warn("WorldMap.Save 未解析，点亮后不主动写档（退出世界时仍会保存）") end
    if not H.m_newtext then warn("NewText 未解析，改用日志提示") end

    -- 原生按钮：icon 字节先写进 private_dir（注册时内核从那里读 PNG），
    -- 写失败 / 注册失败就退回纯文字按钮（icon 是可选的，与空间魔杖同款回退）
    if type(BTN_ICON) == "string" and #BTN_ICON > 0 then
        local wok, wret, werr = pcall(mod.write_file, "btn_icon.png", BTN_ICON)
        if not wok or not wret then
            warn("btn_icon.png 写入失败: " .. tostring(werr or wret))
            BTN_ICON = nil
        end
    end
    if mod.controls and mod.controls.register then
        local ok, av, aerr = pcall(mod.controls.available)
        if ok and av then
            local desc = { id = BTN_ID, name = BTN_NAME, show_label = true,
                           on_press = function() S.want = true end }
            if BTN_ICON then desc.icon = "btn_icon.png" end
            local ok2, id = pcall(mod.controls.register, desc)
            if not ok2 and desc.icon then
                desc.icon = nil
                ok2, id = pcall(mod.controls.register, desc)
            end
            if ok2 and id then
                S.ctl_ok = true
                log("原生按钮已注册: " .. tostring(id))
            else
                warn("按钮注册失败: " .. tostring(id))
            end
        else
            warn("原生按钮不可用: " .. tostring(aerr or tostring(av)))
        end
    else
        warn("内核无 mod.controls，无法触发")
    end

    -- 每帧钩子（按钮轮询 + 分帧点亮），挂载点三级回退（与空间魔杖一致）
    local m, kind
    if MainT then
        m = gm(MainT, "Update", 1) or gm(MainT, "Update", 0)
        if m then kind = "Main.Update" end
    end
    if not m and PlayerT then
        m = gm(PlayerT, "ResetEffects", 0)
        if m then kind = "Player.ResetEffects" end
    end
    if not m then
        mod.error("[fullmap] 找不到 Main.Update / Player.ResetEffects，按钮无法轮询")
    else
        local ok, h = pcall(P.install_hook, m, { postfix = function() tick() end })
        if ok and h then
            S.tick_hook = h
            log("每帧钩子挂载: " .. kind)
        else
            mod.error("[fullmap] 每帧钩子安装失败: " .. tostring(h))
        end
    end

    if S.ctl_ok and S.tick_hook then
        log(string.format("就绪：每帧预算 %.0fms，节尺寸 %dx%d，逐格 UpdateLighting",
                BUDGET * 1000, SEC_W, SEC_H))
    else
        mod.error("[fullmap] 初始化未完成（按钮=" .. tostring(S.ctl_ok)
                .. " 钩子=" .. tostring(S.tick_hook ~= nil) .. "）")
    end
end

todo_list = { "setup" }
