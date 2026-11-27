-- 召唤生物菜单 (Summon Menu) —— LuaLoader Lua Mod
-- 由 lzup333 Creative Menu 裁剪而来。
-- v4.6.0：把「生成物品」页加回来（物品浏览 + 拼音搜索 + 生成），放在召唤生物前面。
-- v4.6.1：「切换月相」页改名「改变世界」，新增时间控制（暂停 / 四个时刻 / 0-24 倍流速）。
-- v4.6.2：跳时间改用原版 Main.SkipToTime，效果与游戏自己跳时间完全一致。
-- v4.6.3：面板加宽 500->620；改变世界页新增天气（风速/雨势，可锁定），整页可滑动。
-- v4.6.4：雨势改为同步原版旅途天气页（Main.StartRain / Main.StopRain，滑块取 cloudAlpha）。
-- v4.6.5：风速也同步原版旅途天气页（windSpeedCurrent = windSpeedTarget = Lerp(-0.8, 0.8, 滑块)）。
-- v4.6.6：新增「旅途力量」页（刷怪率 0.5~100 倍，滑块 + 七个快捷按钮）。
-- v4.6.7：旅途力量页对齐原版顺序 —— 无敌模式 / 放置范围 / 刷怪速度 / 传染扩散 / 难度。
-- v4.6.8：旅途力量并入「改变世界」页，删掉独立页签；放置范围改自己装钩子；刷怪率加 ×0。
-- v4.6.9：刷怪率 ×0 改用原版链路（SpawnRateSliderPerPlayerPower 滑块归零 + CanSpawnEnemiesNear 兜底）。
-- v4.6.10：放置范围改用属性 setter（PE 的 tileRangeX/Y 是静态属性不是字段）；文案随状态变化。
-- v4.6.11：修「放置范围」未开启时 same_line 串行，把下一行的刷怪速度粘到同一行的问题。
-- v4.7.0：并入一键建造（新增第 6 个页签，点进去整块面板交给它）；面板配色/皮肤统一成一键建造那套。
-- v4.7.1：一键建造面板宽度跟合集统一成 620；悬浮窗图标改回模组合集那张。
-- v4.7.2：面板 620 -> 760（6 个页签放不下）；一键建造进 host_mode，标题/图标/位置/折叠全交给合集。
-- v4.7.3：合集图标改回 launcher.png（之前误用了一键建造的）；一键建造恢复自己的原生宽度。
-- 召唤方式：NPC.NewNPC(source=nil, X, Y, Type, 0, ai0..3, Target)，在玩家脚下生成。
-- 目标版本 1.4.5.8（NPCID.Count=697）。

mod.meta = { pkg_id = "bluefish.summonmenu", version = "16.0.0", version_code = 1600, api_version = 1 }

-- ============================================================================
-- 【关于 v8.5.5 的时序探针】
--   v8.5.0 无探针会在主菜单刚出来 1~2 秒闪退；v8.5.1~8.5.5 加探针后不崩，
--   但定位不到具体模块 → 典型时序竞态。那套纯内存探针一直留在代码里。
--   v8.9.60 转正时全部删除：崩溃真因已在 v8.9.24/25 定位到 tg 模块
--   PlaceTile 的高频跨语言读取，探针没必要再占运行时开销。
-- ============================================================================
-- v8.8.0：分帧启动（取代 v8.5.x 那套「探针扰动时序」的闪退修复）
-- ----------------------------------------------------------------------------
-- 旧做法为什么不好：
--   8.5.0 在主菜单刚出来 1~2 秒必崩。8.5.1~8.5.5 的修法是在启动/运行路径上
--   插一堆探针（每帧心跳、定点采样、首调用标记），靠「多跑几行 Lua」把时序搅乱
--   来避开崩溃。结果是：说不清原理、不敢删、每加一点东西都得提心吊胆。
--
-- 现在正面解决 —— 把压力摊开：
--   setup 里只做「必须赶在加载期完成」的物品注册，
--   其余 42 个模块排成队列，由 Main.Update 每帧只启动 1 个，
--   原本集中在一瞬间的约 320ms 初始化，摊到约 42 帧（0.7 秒）里，
--   单帧压力降到 ~8ms，主菜单那 1~2 秒不再有密集的原生调用。
--   主菜单阶段本来就用不到这些功能，所以分帧对玩家完全无感。
--
-- 这里刻意不再保留每帧探针：BOOT_STEP 的每帧开销只有一次表比较。
-- ============================================================================
_G.BOOT = { q = {}, i = 1, done = true, hook = nil, n = 0 }
-- 推进器：每调用一次只启动一个模块（由 Main.Update 的 postfix 每帧调一次）
_G.BOOT_STEP = function()
    -- 主菜单期间每帧启动 1 个模块，不判世界状态
    if _G.GENW then return end
    local B = _G.BOOT
    if B.done then return end
    if B.i > #B.q then
        B.done = true
        return
    end
    local it = B.q[B.i]
    B.i = B.i + 1
    B.n = B.n + 1
    -- v8.9.15：启动打点。必须用纯 ASCII，中文写进内核日志会转码失败被丢弃。
    --   崩溃时日志最后一条 "BOOT start <名字>" 就是出事的模块。
    mod.info(string.format("[BOOT] start %d/%d %s", B.n, #B.q, tostring(it[1])))
    local ok, err = pcall(it[2])
    if ok then
        mod.info(string.format("[BOOT] ok %s", tostring(it[1])))
    else
        mod.error(string.format("[BOOT] FAIL %s : %s", tostring(it[1]), tostring(err)))
    end
end


-- ===== v5.9.4：LuaLoader 3.0.x（内置 Lua 5.5）路径兼容 =====
--   3.0.0 起私有目录的组织方式与 2.5.x 不同，表现为 require("builder") 报
--   "module 'builder' not found"，且 lib/ui/*.png 也加载不出来（按钮只剩文字）。
--   这里把几种可能的搜索根都补进 package.path，哪种结构都能命中。
pcall(function()
    local roots = { mod.mod_dir, mod.private_dir, (mod.private_dir or "") .. "/lib" }
    local add = ""
    for i = 1, #roots do
        local d = roots[i]
        if type(d) == "string" and d ~= "" then
            local a = d .. "/?.lua"
            if not package.path:find(a, 1, true) then
                add = add .. a .. ";" .. d .. "/?/init.lua;"
            end
        end
    end
    if add ~= "" then package.path = add .. package.path end
end)


local patch = mod.patch

-- 猛冲与跳跃模块（文件第二部分定义，setup/清理/总开关）
local jr_setup, jr_cleanup, jr_set_enabled, jr_is_enabled, jr_get_opt, jr_set_opt, jr_is_rolling
-- 动作优化模块（文件第三部分定义，do-end 作用域隔离）
local mp_setup, mp_cleanup, mp_set_enabled, mp_is_enabled
-- 连锁挖矿模块（文件第四部分定义，IIFE 作用域隔离；v1.4.0 起默认常开、无开关）
local vm_setup, vm_cleanup
-- Boss方向提示模块（文件第五部分定义，IIFE 作用域隔离；仅原版指针样式，默认常开）
local bd_setup, bd_cleanup
-- 光源穿透模块（文件第六部分定义，IIFE 作用域隔离；默认常开、无开关）
local lp_setup, lp_cleanup
-- 遗忘之物模块（文件第七部分定义，IIFE 作用域隔离；默认常开、无开关）
local fi_setup, fi_cleanup, fi_set_enabled, fi_is_enabled, fi_scan_slot
-- 快速放置模块（文件第八部分定义，IIFE 作用域隔离；总开关：开=300% 放置速度、关=100%，默认关闭）
local ps_setup, ps_cleanup, ps_set_enabled, ps_is_enabled
-- 三探测模块（文件第九部分定义，IIFE 作用域隔离；生物探测/宝藏探测/危险感知，默认常开）
local sn_setup, sn_cleanup
-- 晶塔四改模块（文件第十部分定义，IIFE 作用域隔离；无视距离/无视危险/同类型多座/传送不需NPC，常开）
local py_setup, py_cleanup
-- 复活规则模块（文件第十一部分定义，IIFE 作用域隔离；5 秒复活 + 不掉墓碑 默认常开；复活地点按钮 v2.0.8 起）
local rv_setup, rv_cleanup, rv_set_enabled, rv_is_enabled
local lk_setup, lk_cleanup, lk_gui
-- 缩放扩展模块（文件第二十一部分定义，IIFE 作用域隔离；最小缩放 0.58→0.36，默认常开、无开关）
local zm_setup, zm_cleanup
-- 一键点亮地图模块（文件第二十二部分定义，IIFE 作用域隔离；设置页右列按钮触发全图点亮，默认常开、无开关）
local lm_setup, lm_cleanup, lm_gui
-- 召神模块（切鞭协同；v2.11.29 并入合集，默认关闭、按钮开关）
local zs_setup, zs_cleanup, zs_gui
-- 我就是箭神模块（追踪箭 CD 强化；v2.19.2 由独立模组并入，默认关闭、按钮开关）
local ag_setup, ag_cleanup, ag_gui, ag_set_enabled, ag_is_enabled
-- 我就是哨兵神模块（投石索携带哨兵强化；v2.19.4 由独立模组并入，默认关闭、按钮开关）
--   注：主 chunk 的 local 已到 Lua 的 200 上限，故这些后来的模块都挂到同一张公共表 EXT 下，
--       一张表只占 1 个名额；以后再加模块往 EXT 里添子表即可。
-- 我就是协击神模块（碎裂之石系列协同攻击 CD；v2.19.8 由独立模组并入，默认关闭、按钮开关）
local EXT = { sn = {}, sx = {}, mm = {}, lh = {}, dh = {}, afm = {} }
-- 绘制钩子复用表：Boss方向提示占 Main.DrawNPCs、Boss血条占 Main.Draw。
-- 内核不允许同一方法装两个钩子，后来者只登记回调，由既有钩子转调。
_G.EXT_DH = EXT.dh

-- 增益家具模块（文件第十七部分定义，IIFE 作用域隔离；背包/仓库家具自动增益，默认常开、无开关）
local af_setup, af_cleanup
-- 每日商人刷新模块（文件第十八部分定义，IIFE 作用域隔离；旅商保底+骷髅商人保底，默认常开、无开关）
local dm_setup, dm_cleanup
-- NPC入住模块（文件第十九部分定义，IIFE 作用域隔离；分配房间后NPC自动瞬移入住，默认常开、无开关）
local nh_setup, nh_cleanup
-- 城镇NPC无敌模块（文件第十九部分之后定义，IIFE 作用域隔离；城镇NPC不受敌怪伤害，默认开启）
local ng_setup, ng_cleanup
-- 玩家属性页模块（文件第二十部分定义，IIFE 作用域隔离；只读显示，无钩子无开关）
local at_setup, at_cleanup, at_gui

-- ============================================================================
-- 节拍总线（v2.8.0 架构优化 · 第一部分之前的公共设施）
-- ----------------------------------------------------------------------------
-- 背景：此前每个「每帧轮询」型模块都各自 install_hook 一份 Main.Update /
--   Player.ResetEffects，游戏每帧要跨 Lua<->C 边界喊我们 6 次
--   （3 个 Main.Update + 3 个 ResetEffects）。合并后每帧只各喊 1 次，
--   由总线按注册顺序依次驱动各模块的 tick。
-- 原则：各模块的 tick 函数体保持原样，只把「注册方式」从 install_hook
--   换成 tb_reg_frame / tb_reg_reset。模块开关（若有）仍由模块自己的 tick
--   内部判断，总线钩子本身常驻（不再随开关装卸）。
-- 备注：sn/bd/lp/lk 等语义型钩子不走此总线，仍由各模块自行安装
--   （它们的挂点/参数/开关语义特殊）。
-- v2.9.0：jr/mp 的 Player.Update 已改并入下方「Player.Update 汇合总线」。
-- ============================================================================
local tb_frame, tb_reset = {}, {}      -- 注册表（按注册顺序执行）
local tb_frame_hook, tb_reset_hook     -- 总线钩子句柄（供 cleanup 移除）

-- 注册「每帧一次」（挂在 Main.Update postfix）
local function tb_reg_frame(name, fn)
    tb_frame[#tb_frame + 1] = { name = name, fn = fn }
end

-- 注册「每帧一次、带玩家实例」（挂在 Player.ResetEffects postfix）
local function tb_reg_reset(name, fn)
    tb_reset[#tb_reset + 1] = { name = name, fn = fn }
end

-- ----------------------------------------------------------------------------
-- 进世界自检播报（v2.8.1；v2.8.3 诊断版：日志改纯英文 + worldName 读取降频）
--    背景：v2.8.2 实测聊天栏没有播报，且内核日志被
--    "UTF-16 to UTF-8 conversion failed" 刷了 1167 条（20 秒内，约每帧一条）
--    —— 元凶是本函数每帧调用 patch.get_field_value(F_worldName, nil, "string")
--    去读 Main.worldName（.NET UTF-16 字符串），转换失败时内核就打一条 ERROR。
--    本版改动：
--      ① 中文日志 → 纯英文日志（避免中文在日志路径上转码失败导致「什么也看不到」）；
--      ② worldName 仅作兜底信号，且降到每 30 帧探测一次；
--      ③ 播报内容先用纯 ASCII 做二分定位：
--        能看到 → 发送路径 OK，之前是中文转码问题；
--        看不到 → 查下面几条英文日志，看卡在哪一步。
-- ----------------------------------------------------------------------------
local tb_announced = false
local tb_announce_frames = 0
local tb_world_frames = 0
local tb_world_probe = 0
local tb_newtext5, tb_newtext4, tb_game_menu, tb_world_name
local tb_send                                 -- v2.8.4：通用发送封装（中文/英文都走它）
local function tb_announce_init()
    local T = patch.get_type("Terraria", "Main")
    if not T then
        mod.warn("[CHEN] announce init: Main type not found")
        return
    end
    tb_newtext5   = patch.get_method(T, "NewText", 5)
    tb_newtext4   = patch.get_method(T, "NewText", 4)
    tb_game_menu  = patch.get_method(T, "get_gameMenu", 0)
    tb_world_name = patch.get_field(T, "worldName")
    mod.info(string.format(
        "[CHEN] announce init: NewText5=%s NewText4=%s gameMenu=%s worldName=%s",
        tostring(tb_newtext5 ~= nil), tostring(tb_newtext4 ~= nil),
        tostring(tb_game_menu ~= nil), tostring(tb_world_name ~= nil)))
end
local function tb_try_announce()
    if tb_announced then return end
    if not tb_newtext5 and not tb_newtext4 then return end
    local in_world = false
    if tb_game_menu then
        local ok, v = pcall(patch.invoke, tb_game_menu)
        if ok and v == false then in_world = true end
    end
    -- v2.8.3：worldName 仅作兜底信号，且 30 帧才探一次
    if (not in_world) and tb_world_name and not tb_game_menu then
        tb_world_probe = tb_world_probe + 1
        if tb_world_probe >= 30 then
            tb_world_probe = 0
            local ok, wn = pcall(patch.get_field_value, tb_world_name, nil, "string")
            if ok and type(wn) == "string" and wn ~= "" then
                in_world = true
                mod.info("[CHEN] in-world via worldName")
            end
        end
    end
    if not tb_game_menu and not tb_world_name then
        -- 两个句柄都没取到：退化为「游戏启动后 30 秒」兜底播报一次
        tb_announce_frames = tb_announce_frames + 1
        if tb_announce_frames < 1800 then return end
        in_world = true
    end
    if not in_world then
        tb_world_frames = 0
        return
    end
    tb_world_frames = tb_world_frames + 1
    if tb_world_frames == 1 then
        mod.info("[CHEN] in-world detected (gameMenu signal)")
    end
    if tb_world_frames < 90 then return end
    local ver = (mod.meta and mod.meta.version) or "?"
    -- v2.8.5 定稿：只发中文一行。
    --   实测结论（v2.8.4）：中英文两行都能正常显示，中文本身没问题；
    --   v2.8.2 之所以看不到，是文案里那个小圆点「·」害的（特殊符号转码失败），
    --   所以本条文案只使用汉字 / 方括号 / 空格 / ASCII 数字，不再用任何特殊符号。
    -- v2.8.6：文案改为用户指定（含表情符号；万一特殊符号过不去，自动回退纯文字版）
    -- v2.11.16：开局改为两行播报（Ciallo + 欢迎语，按用户指定文案）
    local msg_1 = "Ciallo～(∠·ω< )⌒☆"
    local msg_2 = "蓝色大肥鱼和MIMO欢迎你`(*^▽^*)`"
    local ok1, way1 = tb_send(msg_1)
    local ok2, way2 = tb_send(msg_2)
    local ok_cn, way_cn = (ok1 or ok2), (way2 or way1)
    if not ok_cn then
        ok_cn, way_cn = tb_send(string.format("[更适合陈什么] %s 已加载 节拍任务 %d+%d",
            tostring(ver), #tb_frame, #tb_reset))
    end
    mod.info(string.format("[CHEN] announce cn=%s via %s", tostring(ok_cn), way_cn))
    if ok_cn then
        tb_announced = true
    else
        tb_world_frames = 0
    end
end
tb_send = function(text)
    local s = nil
    if patch.string_create then
        local okc, r = pcall(patch.string_create, text)
        if okc then s = r end
    end
    if not s then return false, "no-string" end
    if tb_newtext5 then
        local okc, r = pcall(patch.invoke, tb_newtext5, s, 150, 255, 200, false)
        if okc and r ~= false then return true, "NewText5" end
    end
    if tb_newtext4 then
        local okc, r = pcall(patch.invoke, tb_newtext4, s, 150, 255, 200)
        if okc and r ~= false then return true, "NewText4" end
    end
    return false, "invoke-failed"
end
-- v2.11.1：全局「是否在世界」闸门（每帧由总线更新；所有独立钩子据此立即返回）
CHW = false
CHW_FRAMES = 0
-- v8.9.12：世界生成中标志（WorldGen.generatingWorld）。生成期间整个模组静默，
--   因为那时 TileData / 背包 / NPC / 配方都在重建，任何回调都可能读到半成品。
GENW = false
-- 安装总线：必须在所有模块 setup 跑完（注册表填充完毕）后调用一次
local function tb_install()
    local T_Main   = patch.get_type("Terraria", "Main")
    local T_Player = patch.get_type("Terraria", "Player")
    local F_gm     = T_Main and patch.get_field(T_Main, "gameMenu")
    local T_WG     = patch.get_type("Terraria", "WorldGen")
    local F_wg_gen = T_WG and patch.get_field(T_WG, "generatingWorld")
    -- v8.9.71：WorldGen.generatingWorld 在 PE 上可能是属性，get_field 拿不到。
    --   补一个 getter 回退，让 GENW 这个「世界生成中」标志真正可用。
    local m_wg_gen = nil
    if T_WG then
        local okg, mgw = pcall(patch.get_method, T_WG, "get_generatingWorld", 0)
        if okg then m_wg_gen = mgw end
    end
    -- v8.9.16 关键修复：PE 版 Main.gameMenu 是【属性】，patch.get_field 拿不到，
    --   于是 F_gm 恒为 nil，下面 "if F_gm then ... end" 整段跳过，inw 永远是 true，
    --   闸门 CHW 从来没生效过 —— 主菜单和世界生成期间所有模块都在全速跑。
    --   这里补上属性 getter（tb_try_announce 里一直用的是这个方式）。
    local m_gm = nil
    do
        local okg, mg = pcall(patch.get_method, T_Main, "get_gameMenu", 0)
        if okg then m_gm = mg end
    end

    if #tb_frame > 0 and T_Main then
        local m = patch.get_method(T_Main, "Update", 1) or patch.get_method(T_Main, "Update", 0)
        if m then
            local ok, h = pcall(patch.install_hook, m, {
                postfix = function()
                    -- v8.9.12：世界生成中直接跳过，不推进 BOOT、不派发任何模块 tick
                    local gb = nil
                    if m_wg_gen then
                        local okg, g = pcall(patch.invoke, m_wg_gen)
                        if okg then
                            if type(g) == "boolean" then gb = g
                            elseif type(g) == "number" then gb = (g ~= 0) end
                        end
                    end
                    if gb == nil and F_wg_gen then
                        local okg, g = pcall(patch.get_field_value, F_wg_gen, nil, "bool")
                        if okg then
                            if type(g) == "boolean" then gb = g
                            elseif type(g) == "number" then gb = (g ~= 0) end
                        end
                    end
                    if gb == true then
                        GENW = true
                        CHW = false
                        CHW_FRAMES = 0
                        return
                    end
                    -- 必须无条件复位：读不到 generatingWorld 时只能当作「不在生成中」。
                    --   曾经写成「只有读到 false 才复位」，结果读不出来时这个标志就永久
                    --   卡在 true，依赖它的模块再也不会启动，而且一声不响。
                    GENW = false
                    tb_try_announce()   -- v2.8.1：进世界后播报一次自检信息
                    -- v8.9.16：三路读取，任何一路成功就以它为准
                    local inw, decided = true, false
                    if m_gm then
                        local okv, v = pcall(patch.invoke, m_gm)
                        if okv and type(v) == "boolean" then
                            inw, decided = (v == false), true
                        elseif okv and type(v) == "number" then
                            inw, decided = (v == 0), true
                        end
                    end
                    if not decided and F_gm then
                        local okv, v = pcall(patch.get_field_value, F_gm, nil, "bool")
                        if okv and type(v) == "boolean" then inw, decided = (not v), true
                        elseif okv and type(v) == "number" then inw, decided = (v == 0), true end
                    end
                    if not decided then
                        -- v8.9.16：gameMenu 两路都读不到时，用 generatingWorld 兜底；
                        --   都拿不到才保守当作「在世界里」。
                        inw = not GENW
                    end
                    -- v8.9.11：进世界后先宽限 90 帧（约 1.5 秒）再派发业务 tick。
                    --   新世界刚生成完的那一刻，玩家/图格/背包数据还没完全就绪，
                    --   几十个模块同时开跑容易踩到半初始化状态（创建新地图闪退）。
                    -- v8.9.33：宽限期彻底删除。进入世界的第一帧 CHW 就为 true，
                    --   所有功能立刻处于工作状态，不存在「进图后过一会儿才生效」的观感。
                    --   闸门本身保留：主菜单期间（inw=false）和世界生成期间仍会让回调空转。
                    CHW = inw
                    CHW_FRAMES = 0
                    if CHW then for i = 1, #tb_frame do pcall(tb_frame[i].fn) end end
                    if _G.BOOT_STEP then pcall(_G.BOOT_STEP) end
                end,
            })
            if ok and h then tb_frame_hook = h
            else mod.warn("[CHEN] bus: Main.Update hook install FAILED " .. tostring(h)) end
        else
            mod.warn("[CHEN] bus: Main.Update not found")
        end
    end

    if #tb_reset > 0 and T_Player then
        local m = patch.get_method(T_Player, "ResetEffects", 0)
        if m then
            local ok, h = pcall(patch.install_hook, m, {
                postfix = function(inst)
                    if not CHW then return end
                    for i = 1, #tb_reset do pcall(tb_reset[i].fn, inst) end
                end,
            })
            if ok and h then tb_reset_hook = h
            else mod.warn("[CHEN] bus: Player.ResetEffects hook install FAILED " .. tostring(h)) end
        else
            mod.warn("[CHEN] bus: Player.ResetEffects not found")
        end
    end

    mod.info(string.format("[CHEN] bus installed: Main.Update tasks=%d, ResetEffects tasks=%d",
        #tb_frame, #tb_reset))

    tb_announce_init()   -- v2.8.1：解析聊天播报所需的句柄
end

local function tb_uninstall()
    if tb_frame_hook and tb_frame_hook.remove then pcall(function() tb_frame_hook:remove() end) end
    if tb_reset_hook and tb_reset_hook.remove then pcall(function() tb_reset_hook:remove() end) end
    tb_frame_hook, tb_reset_hook = nil, nil
end

-- ============================================================================
-- Player.Update 汇合总线（v2.9.0 架构优化）
-- ----------------------------------------------------------------------------
-- 背景：猛冲跳跃(jr) 与 动作优化(mp) 此前各装一份 Player.Update(int) 钩子，
--   游戏每帧为同一个方法要跨 Lua<->C 边界 2 次。本总线把两者汇成 1 个钩子：
--   两个模块只注册回调（不再各自 install_hook），由总线统一装 1 份钩子顺次派发。
-- 执行顺序：按注册顺序（setup 先 jr 后 mp，与原先两份钩子的安装顺序一致）。
-- 总开关语义：一律改为「回调内门控」——CFG.enabled / MP_EN 由各回调自行判断，
--   钩子本身常驻，开关不再装卸 Player.Update。
-- 说明：prefix 统一返回 false（不拦截原方法），与两个模块原先各自的行为一致。
-- ============================================================================
local pu_pre, pu_post = {}, {}           -- 注册表（按注册顺序执行）
local pu_hook                            -- 汇合钩子句柄（供 cleanup 移除）

local function pu_reg(list, name, fn)    -- 同名重复注册：原地替换，保持首次注册的顺序
    for i = 1, #list do
        if list[i].name == name then
            list[i].fn = fn
            return
        end
    end
    list[#list + 1] = { name = name, fn = fn }
end
local function pu_reg_pre(name, fn)  pu_reg(pu_pre, name, fn)  end
local function pu_reg_post(name, fn) pu_reg(pu_post, name, fn) end

-- 安装：必须在所有模块 setup 跑完（注册表填充完毕）后调用一次
local function pu_install()
    if pu_hook then return end
    if #pu_pre == 0 and #pu_post == 0 then return end
    local T = patch.get_type("Terraria", "Player")
    if not T then mod.warn("[CHEN] pu: Player type not found") return end
    local m = patch.get_method(T, "Update", 1)
    if not m then mod.warn("[CHEN] pu: Player.Update(int) not found") return end
    local ok, h = pcall(patch.install_hook, m, {
        prefix = function(inst, args, result)
            if not CHW then return false end
            for i = 1, #pu_pre do pcall(pu_pre[i].fn, inst, args, result) end
            return false
        end,
        postfix = function(inst, args, result)
            if not CHW then return false end
            for i = 1, #pu_post do pcall(pu_post[i].fn, inst, args, result) end
            return false
        end,
    })
    if ok and h then
        pu_hook = h
        mod.info(string.format("[CHEN] pu bus installed: Player.Update pre=%d post=%d",
            #pu_pre, #pu_post))
    else
        mod.warn("[CHEN] pu: Player.Update hook install FAILED " .. tostring(h))
    end
end

local function pu_uninstall()
    if pu_hook and pu_hook.remove then pcall(function() pu_hook:remove() end) end
    pu_hook = nil
end

local NPC_COUNT = 697
-- v4.5.0：NPC 上界改为运行时探测。做法同步自 CreativeMenu v1.1.1：
-- 原版 1.4.5.8 是 697；若其它模组注册了 NPC，Lang._npcNameCache 会比这更长。
-- 探测失败一律回退 697，行为与原版完全一致。
local npc_max = NPC_COUNT - 1

-- 列表网格
local COLS     = 3
local PER_PAGE = 12

-- 汉字 -> 无声调拼音
local pinyin = {}
do
    local ok, t = pcall(require, "pinyin")
    if ok and type(t) == "table" then pinyin = t end
end

-- ============ 拼音搜索（v2.7.0 起跟学 CreativeMenu v1.1.0）============
-- 多音字全部读音参与匹配；支持汉字 / 全拼 / 首字母。（v2.7.1 起固定全拼，不再提供双拼选项）
local py_mode = "full" -- 固定全拼；matches 保留模式分支便于以后扩展

-- 无声调拼音 → 微软双拼两键（键位取自 RIME 的 double_pinyin_mspy 方案）
local MS_FINAL = {
    a = "a", o = "o", e = "e", i = "i", u = "u", v = "y",
    ai = "l", ei = "z", ao = "k", ou = "b", an = "j", en = "f", ang = "h",
    eng = "g", er = "r",
    ia = "w", ie = "x", iao = "c", iu = "q", ian = "m", iang = "d", iong = "s",
    -- 微软双拼原本把 ing 放在 ';' 上，但 LuaLoader 虚拟键盘打不出符号，
    -- 所以 in / ing 都放 n 键（搜索只做子串匹配，不会因此变差）
    ["in"] = "n", ing = "n",
    ua = "w", uo = "o", uai = "y", ui = "v", uan = "r", un = "p", uang = "d",
    ong = "s",
    ue = "t", ve = "t", van = "r", vn = "p",
}

local function ms_syllable(py)
    if py:match("^[aoe]") then
        return "o" .. (MS_FINAL[py] or py:sub(1, 1)) -- 零声母统一加 o
    end
    local initial, final
    local two = py:sub(1, 2)
    if two == "zh" or two == "ch" or two == "sh" then
        initial, final = ({ zh = "v", ch = "i", sh = "u" })[two], py:sub(3)
    else
        initial, final = py:sub(1, 1), py:sub(2)
    end
    -- ju/qu/xu/yu 的 u 其实读 ü
    if final == "u" and (initial == "j" or initial == "q" or initial == "x" or initial == "y") then
        final = "v"
    end
    local key = MS_FINAL[final]
    if not key then key = final ~= "" and final:sub(1, 1) or "" end
    return initial .. key
end

--- 一个汉字的全部读音（返回数组；非汉字返回 nil）
local function readings_of(cp)
    local v = pinyin[cp]
    if type(v) == "string" then return { v } end
    if type(v) == "table" then return v end
    return nil
end

local MAX_VARIANTS = 8

--- 名字 → 三串候选（以 \1 分隔）：全拼 / 首字母 / 微软双拼
local function to_keys(name)
    local variants = { { p = "", i = "", s = "" } }
    local ok, iter, st, var = pcall(utf8.codes, name)
    if not ok then return "", "", "" end

    for _, cp in iter, st, var do
        local list = readings_of(cp)
        if list then
            local next_variants = {}
            for _, v in ipairs(variants) do
                for _, py in ipairs(list) do
                    next_variants[#next_variants + 1] = {
                        p = v.p .. py,
                        i = v.i .. py:sub(1, 1),
                        s = v.s .. ms_syllable(py),
                    }
                end
            end
            variants = next_variants
            for k = MAX_VARIANTS + 1, #variants do variants[k] = nil end
        else
            local ch = utf8.char(cp)
            for _, v in ipairs(variants) do
                v.p, v.i, v.s = v.p .. ch, v.i .. ch, v.s .. ch
            end
        end
    end

    local ps, is, ss = {}, {}, {}
    for _, v in ipairs(variants) do
        ps[#ps + 1], is[#is + 1], ss[#ss + 1] = v.p, v.i, v.s
    end
    local function join(list)
        local seen, out = {}, {}
        for _, s in ipairs(list) do
            if not seen[s] then seen[s] = true; out[#out + 1] = s end
        end
        return table.concat(out, "\1")
    end
    return join(ps), join(is), join(ss)
end

local function matches(needle, name, py, ini, ms)
    if needle == "" then return true end
    if name:lower():find(needle, 1, true) then return true end
    if ini and ini:find(needle, 1, true) then return true end
    if py_mode == "ms" then
        return ms ~= nil and ms:find(needle, 1, true) ~= nil
    end
    return py ~= nil and py:find(needle, 1, true) ~= nil
end

--- 按「显示宽度」截断并补齐空格，保证网格按钮宽度一致（CJK=2 格）
local function fit_label(s, cells)
    local out, width = {}, 0
    local ok, iter, st, var = pcall(utf8.codes, s)
    if not ok then return s end
    for _, cp in iter, st, var do
        local w = cp > 0x2E7F and 2 or 1
        if width + w > cells then return table.concat(out) .. "…" end
        out[#out + 1] = utf8.char(cp)
        width = width + w
    end
    local text = table.concat(out)
    return text .. string.rep(" ", math.max(0, cells - width))
end

-- ============ 类型 / 句柄 ============
local T_main, T_player, T_npc, T_lang

local F_main_player, F_my_player, M_get_my_player
local F_pos, F_width, F_height
local F_direction        -- Player.direction (1=右, -1=左)
local F_moon_phase       -- Main.moonPhase (0..7, 静态)
local M_get_moon, M_set_moon  -- 属性 getter/setter 兜底
local M_new_text
local M_new_npc          -- NPC.NewNPC(10)
local M_get_npc_name

local ready = false

-- ============ 状态 ============
local npc_filter, npc_page, npc_count = "", 0, 1
local npc_names, npc_py, npc_ini, npc_ms
local npc_filter_cache, npc_list_cache

-- ============ 工具 ============
local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local f = patch.get_field(cur, name)
        if f then return f end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function get_i32(field, inst, default)
    if not field then return default end
    local v = patch.get_field_value(field, inst, "int32")
    return v == nil and default or v
end

local function set_i32(field, inst, value)
    if field then patch.set_field_value(field, inst, value, "int32") end
end

-- ============ 月相 ============
local MOON_NAMES = { "满月", "亏凸月", "下弦月", "残月", "新月", "蛾眉月", "上弦月", "盈凸月" }

local function get_moon()
    if F_moon_phase then
        local v = patch.get_field_value(F_moon_phase, nil, "int32")
        if type(v) == "number" then return v % 8 end
    end
    if M_get_moon then
        local ok, v = pcall(patch.invoke, M_get_moon)
        if ok and type(v) == "number" then return v % 8 end
    end
    return 0
end

local function set_moon(v)
    v = v % 8
    if F_moon_phase then
        set_i32(F_moon_phase, nil, v)
        return true
    end
    if M_set_moon then
        local ok = pcall(patch.invoke, M_set_moon, v)
        return ok and true or false
    end
    return false
end

local function my_player_index()
    if M_get_my_player then
        local v = patch.invoke(M_get_my_player)
        if type(v) == "number" then return v end
    end
    if F_my_player then
        local v = patch.get_field_value(F_my_player, nil, "int32")
        if type(v) == "number" then return v end
    end
    return -1
end

local function local_player()
    if not F_main_player then return nil end
    local idx = my_player_index()
    if idx < 0 then return nil end
    local arr = patch.get_field_value(F_main_player, nil, "object")
    if not arr then return nil end
    local n = patch.array_length(arr)
    if idx >= n then return nil end
    return patch.array_at(arr, idx)
end
-- v2.10.9 根因修复：别名必须在 1130 行的同名 local_player(inst)（动作优化门禁函数）之前取。
-- 后段代码若直接写 local_player 会被它遮蔽：该函数返回 true（不是玩家对象），
-- 且 inst=nil 时会拿实例字段 whoAmI 配空实例去读 -> 原生 NULL+0x10，pcall 挡不住。
-- 这正是 v2.10.0 起所有属性页闪退的真凶（黑匣子 v2.10.8 step=2 定位）。
local local_player_get = local_player
-- v2.10.10：动作优化钩子在世界内每帧把本地玩家实例缓存到此，属性页作为备用实例源
local attr_cache_inst = nil

local function notify(msg)
    if not M_new_text then return end
    pcall(function()
        local s = patch.string_create(msg)
        if not s then return end
        if mod.platform == "android" then
            patch.invoke(M_new_text, s, 255, 220, 120, false)
        else
            patch.invoke(M_new_text, s, 255, 220, 120)
        end
    end)
end

-- ============ 召唤生物（在玩家面向方向 20 格处生成） ============
local function summon_npc(player, id, count)
    if not player or not M_new_npc then return false end
    local px, py = patch.get_field_vec2(F_pos, player)
    if not px then return false end
    local w = get_i32(F_width, player, 0)
    local h = get_i32(F_height, player, 0)
    local dir = get_i32(F_direction, player, 1)
    if dir >= 0 then dir = 1 else dir = -1 end
    local bx = math.floor(px) + math.floor(w / 2) + dir * 320  -- 20 格 * 16 px
    local by = math.floor(py) + math.floor(h)
    for i = 0, count - 1 do
        local sx = bx + (i % 8) * 24 - 84
        local sy = by + math.floor(i / 8) * 24
        patch.invoke(M_new_npc, nil, sx, sy, id, 0, 0.0, 0.0, 0.0, 0.0, 255)
    end
    return true
end

-- ============ 名称缓存 ============
local function lang_name(method, id)
    if not method then return nil end
    local ok, h = pcall(patch.invoke, method, id)
    if not ok or not h or h == false then return nil end
    local ok2, s = pcall(patch.string_value, h)
    if ok2 and type(s) == "string" then return s end
    return nil
end

-- v4.5.0：从 Lang._npcNameCache 的数组长度反推 NPC 数量（CreativeMenu v1.1.1 同款）。
-- 只读静态数组长度，不碰任何实例数组；任何一步失败都回退到原版 697。
local function probe_npc_max()
    if not T_lang then return NPC_COUNT - 1 end
    local ok, f = pcall(patch.get_field, T_lang, "_npcNameCache")
    if not ok or not f then return NPC_COUNT - 1 end
    local ok2, arr = pcall(patch.get_field_value, f, nil, "object")
    if not ok2 or not arr then return NPC_COUNT - 1 end
    local ok3, len = pcall(patch.array_length, arr)
    if ok3 and type(len) == "number" and len > 1 then return len - 1 end
    return NPC_COUNT - 1
end
local function build_npc_names()
    if npc_names then return end
    npc_names, npc_py, npc_ini, npc_ms = {}, {}, {}, {}
    if not M_get_npc_name then return end
    npc_max = probe_npc_max()
    local started, count = os.clock(), 0
    for id = 1, npc_max do
        local name = lang_name(M_get_npc_name, id)
        if name and name ~= "" then
            npc_names[id] = name
            local p, i, s = to_keys(name)
            npc_py[id], npc_ini[id], npc_ms[id] = p, i, s
            count = count + 1
        end
    end
    mod.info(string.format("建立NPC名称索引：%d 项，用时 %.2fs", count, os.clock() - started))
end

local function compute_list(filter)
    local list = {}
    local needle = filter:lower()
    if needle == "" then
        for id = 1, npc_max do
            if npc_names[id] then list[#list + 1] = id end
        end
    else
        for id, name in pairs(npc_names) do
            if matches(needle, name, npc_py[id], npc_ini[id], npc_ms[id]) then list[#list + 1] = id end
        end
    end
    table.sort(list)
    return list
end

-- ============ GUI ============
-- v4.6.0：新增第 5 参 name_map（物品页传入 item_names），不传时沿用 npc_names。
-- v9.0.6：物品/召唤页的按钮改用「圆角图按钮」（btn_at = image_button），
--   与模组设置页一致。代价是必须绝对定位：加载器的 image_button 只认 x/y。
--   三个可调常量（改完立即生效，思路同模组设置页的 TOP_Y / ROW_H / CENTER_X）：
--     PAGER_TOP_Y  物品区第一行（上一页/下一页）的顶端 y
--     PAGER_ROW_H  物品按钮行高（需 >= 按钮高 36）
--     PAGER_COL_W  列距（三列 x = 0 / COL_W / COL_W*2）
-- 主 chunk 的 local 已满 200，五个常量合并成一个表（只占 1 个 local）
local PAGER = {
    TOP_Y = 136, ROW_H = 44, COL_W = 242, BTN_W = 232,
    TXT   = { 235, 237, 229, 255 },
    -- v9.0.7：页签栏也改走圆角图按钮（btn_at），必须绝对定位
    -- v9.0.8：整体上移 8；v9.0.9：再上移 12（-10），与下面横线拉开 10
    TAB_Y = -10, TAB_H = 36, TAB_W = 112, TAB_STEP = 120, TAB_GAP = 10,
}

-- v9.0.10：物品名以前用 fit_label(名字, 12) —— 它会把名字用空格补齐到 12 格。
--   那是给流式按钮（左对齐）用的；换成图按钮后文字由内核居中，尾部补的空格
--   会把文字整体往左推，这就是「歪歪扭扭」的真正原因。
--   这里补一个只截断、不补齐的版本给图按钮用。
PAGER.cut = function(t, cells)
    local out, width = {}, 0
    local ok, iter, st, var = pcall(utf8.codes, t)
    if not ok then return t end
    for _, cp in iter, st, var do
        local w = cp > 0x2E7F and 2 or 1
        if width + w > cells then return table.concat(out) .. "…" end
        out[#out + 1] = utf8.char(cp)
        width = width + w
    end
    return table.concat(out)
end

local function gui_pager(g, list, page, on_click, name_map)
    local nm = name_map or npc_names
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    if page > pages - 1 then page = pages - 1 end
    local BA = _G.ms_btn_at
    if BA and type(g.set_cursor) == "function" then
        -- 上一页 / 下一页（v9.0.9：label 直接交给按钮，居中由内核负责）
        if BA(g, 0, PAGER.TOP_Y, "上一页", PAGER.BTN_W) and page > 0 then
            page = page - 1
        end
        if BA(g, PAGER.COL_W, PAGER.TOP_Y, "下一页", PAGER.BTN_W) and page < pages - 1 then
            page = page + 1
        end
        -- 页码文字（绝对定位，不参与流式排版）
        local cap = string.format("%d/%d · 共 %d 项", page + 1, pages, #list)
        if type(g.text_at) == "function" then
            g.text_at(PAGER.COL_W * 2 + 6, PAGER.TOP_Y + 8, cap, PAGER.TXT)
        end
        -- 物品网格：每行 COLS 个
        local last_y = PAGER.TOP_Y
        for i = 1, PER_PAGE do
            local idx = page * PER_PAGE + i
            local id = list[idx]
            if not id then break end
            local row = math.floor((i - 1) / COLS)
            local col = (i - 1) % COLS
            local y = PAGER.TOP_Y + PAGER.ROW_H * (row + 1)
            if BA(g, PAGER.COL_W * col, y, PAGER.cut(nm[id] or ("#" .. id), 14), PAGER.BTN_W) then
                on_click(id)
            end
            last_y = y
        end
        -- 绝对定位不撑开面板，补一行流式占位，否则末行按钮会被下沿裁掉
        g.set_cursor(0, last_y + 26)
        g.text(" ")
        return page
    end
    -- 回退：加载器没有 image_button / set_cursor 时用原来的流式按钮
    if g.button("上一页") and page > 0 then page = page - 1 end
    g.same_line()
    if g.button("下一页") and page < pages - 1 then page = page + 1 end
    g.same_line()
    g.text(string.format("  %d/%d · 共 %d 项", page + 1, pages, #list))
    for i = 1, PER_PAGE do
        local idx = page * PER_PAGE + i
        local id = list[idx]
        if not id then break end
        if g.button(fit_label(nm[id] or ("#" .. id), 12)) then on_click(id) end
        if (i % COLS) ~= 0 and list[idx + 1] then g.same_line() end
    end
    return page
end

local function gui_npcs(g)
    build_npc_names()
    npc_filter = g.input_text("搜索", npc_filter)
    npc_count = math.floor(g.slider("数量", npc_count, 1, 50))
    if npc_filter ~= npc_filter_cache then
        npc_filter_cache = npc_filter
        npc_list_cache = compute_list(npc_filter)
        npc_page = 0
    end
    g.separator()
    local p = local_player()
    npc_page = gui_pager(g, npc_list_cache or {}, npc_page, function(id)
        if summon_npc(p, id, npc_count) then
            notify("召唤 " .. (npc_names[id] or ("#" .. id)) .. " x" .. npc_count)
        else
            notify("召唤失败")
        end
    end)
end

-- ============ 生成物品（v4.6.0 新增） ============
-- 物品浏览/生成页。思路同 CreativeMenu v1.1.1：
--   名字用 Lang.GetItemNameValue(id)，数量用 Lang._itemNameCache 数组长度动态探测，
--   生成用 Item.NewItem(9 参) 让物品直接掉在脚下。
-- 注意：主 chunk 的 local 已接近 200 上限，所以整段包进 (function() ... end)() ——
--   函数内 local 独立计数（每个函数各自 200 上限），只把入口挂到一个 local 上。
--   内部可用的上层 local：patch / T_lang / F_pos / F_width / F_height /
--   get_i32 / to_keys / matches / fit_label / notify / local_player_get /
--   gui_pager / PER_PAGE / COLS。
_G.ms_gui_items = (function()
    local ITEM_FALLBACK = 6195          -- 探测失败时的上界（1.4.5.8 原版物品数 - 1）
    local item_max = ITEM_FALLBACK
    local item_filter, item_page, item_stack = "", 0, 1
    local item_names, item_py, item_ini, item_ms
    local item_filter_cache, item_list_cache
    local M_item_name, M_new_item, M_quick_spawn, T_item
    local built = false

    local function lang_name(method, id)
        if not method then return nil end
        local ok, h = pcall(patch.invoke, method, id)
        if not ok or not h or h == false then return nil end
        local ok2, s = pcall(patch.string_value, h)
        if ok2 and type(s) == "string" then return s end
        return nil
    end

    -- 与 probe_npc_max 同款：只读静态数组长度，任何一步失败都回退
    local function probe_item_max()
        if not T_lang then return ITEM_FALLBACK end
        local ok, f = pcall(patch.get_field, T_lang, "_itemNameCache")
        if not ok or not f then return ITEM_FALLBACK end
        local ok2, arr = pcall(patch.get_field_value, f, nil, "object")
        if not ok2 or not arr then return ITEM_FALLBACK end
        local ok3, len = pcall(patch.array_length, arr)
        if ok3 and type(len) == "number" and len > 1 then return len - 1 end
        return ITEM_FALLBACK
    end

    -- 所有内核句柄都延迟到第一次打开本页时再取，取不到就只降级不报错
    local function resolve_api()
        if not T_item then
            local ok, t = pcall(patch.get_type, "Terraria", "Item")
            if ok and t then T_item = t end
        end
        if not M_item_name and T_lang then
            local ok, m = pcall(patch.get_method, T_lang, "GetItemNameValue", 1)
            if ok then M_item_name = m end
        end
        if not M_new_item and T_item then
            local ok, m = pcall(patch.get_method, T_item, "NewItem", 9)
            if ok and m then
                M_new_item = m
            elseif patch.get_method_by_names then
                local ok2, m2 = pcall(patch.get_method_by_names, T_item, "NewItem",
                    { "X", "Y", "Width", "Height", "Type", "Stack",
                      "noBroadcast", "pfix", "ownership" })
                if ok2 and m2 then M_new_item = m2 end
            end
        end
        if not M_quick_spawn and patch.get_method_by_names then
            local ok, pt = pcall(patch.get_type, "Terraria", "Player")
            if ok and pt then
                local ok2, m = pcall(patch.get_method_by_names, pt, "QuickSpawnItem",
                    { "source", "item", "stack" })
                if ok2 then M_quick_spawn = m end
            end
        end
    end

    local function build_item_names()
        if built then return end
        built = true
        item_names, item_py, item_ini, item_ms = {}, {}, {}, {}
        resolve_api()
        if not M_item_name then
            mod.error("物品名称接口缺失（Lang.GetItemNameValue）")
            return
        end
        item_max = probe_item_max()
        local started, count = os.clock(), 0
        for id = 1, item_max do
            local name = lang_name(M_item_name, id)
            if name and name ~= "" then
                item_names[id] = name
                local p, i, s = to_keys(name)
                item_py[id], item_ini[id], item_ms[id] = p, i, s
                count = count + 1
            end
        end
        mod.info(string.format("建立物品名称索引：%d 项，用时 %.2fs", count, os.clock() - started))
    end

    local function compute_items(filter)
        local list = {}
        local needle = filter:lower()
        if needle == "" then
            for id = 1, item_max do
                if item_names[id] then list[#list + 1] = id end
            end
        else
            for id, name in pairs(item_names) do
                if matches(needle, name, item_py[id], item_ini[id], item_ms[id]) then
                    list[#list + 1] = id
                end
            end
        end
        table.sort(list)
        return list
    end

    -- 生成物品：安卓走 Item.NewItem(9 参)，桌面走 Player.QuickSpawnItem(source=nil)
    local function give_item(player, id, stack)
        if not player then return false end
        local ok = pcall(function()
            if mod.platform == "android" then
                if not M_new_item then error("no NewItem") end
                local px, py = patch.get_field_vec2(F_pos, player)
                if not px then error("no position") end
                local w = get_i32(F_width, player, 0)
                local h = get_i32(F_height, player, 0)
                patch.invoke(M_new_item, math.floor(px), math.floor(py),
                    math.floor(w), math.floor(h), id, stack, false, 0, 0)
            else
                if not M_quick_spawn then error("no QuickSpawnItem") end
                patch.invoke(M_quick_spawn, player, nil, id, stack)
            end
        end)
        return ok
    end

    local function gui_items(g)
        resolve_api()
        if not M_item_name then
            g.text("物品接口不可用：找不到 Lang.GetItemNameValue")
            return
        end
        build_item_names()
        item_filter = g.input_text("搜索", item_filter)
        item_stack = math.floor(g.slider("生成数量", item_stack, 1, 99))
        if item_filter ~= item_filter_cache then
            item_filter_cache = item_filter
            item_list_cache = compute_items(item_filter)
            item_page = 0
        end
        g.separator()
        local p = local_player_get()
        item_page = gui_pager(g, item_list_cache or {}, item_page, function(id)
            if give_item(p, id, item_stack) then
                notify("生成 " .. (item_names[id] or ("#" .. id)) .. " x" .. item_stack)
            else
                notify("生成失败")
            end
        end, item_names)
    end

    return gui_items
end)()


-- ============ 月相选择 ============
local function gui_moon(g, y0)
    -- v5.4.2：改成绝对坐标版（为了圆角按钮），必须接受 y0 并返回下一行的 y。
    --   之前只改了调用侧没改这里，wy 拿到 nil 直接中断整个 gui_world 回调，
    --   表现为面板背景没撑开、事件按钮消失。
    y0 = y0 or 0
    if not F_moon_phase and not M_set_moon then
        g.text("月相：未找到 moonPhase 接口")
        return y0 + 24
    end
    local TXT = { 235, 237, 229, 255 }
    local cap = "当前月相：" .. MOON_NAMES[(get_moon() or 0) + 1]
    local ba = _G.ms_btn_at
    if type(g.text_at) == "function" then
        g.text_at(4, y0 + 4, cap, TXT)
    elseif ba then
        if type(g.set_cursor) == "function" then g.set_cursor(0, y0 + 4) end
        g.text(cap)
    end
    local BW, GX, BH, GY = 104, 6, 36, 6
    for i = 1, 8 do
        local idx = i - 1
        local col = idx % 4
        local row = math.floor(idx / 4)
        local clicked
        if ba then
            clicked = ba(g, 4 + col * (BW + GX), y0 + 34 + row * (BH + GY), MOON_NAMES[i], BW)
        else
            if col > 0 then g.same_line() end
            clicked = g.button(MOON_NAMES[i])
        end
        if clicked then
            if set_moon(idx) then
                notify("月相改为 " .. MOON_NAMES[i])
            else
                notify("修改月相失败")
            end
        end
    end
    return y0 + 34 + 2 * (BH + GY)
end

-- ============ 改变世界（v4.6.1） ============
-- 原「切换月相」页升级为「改变世界」：保留月相，新增时间控制。
-- 时间三件套（全部是 Main 的静态字段）：
--   Main.dayTime  (bool)    true=白天 / false=夜晚
--   Main.time     (double)  白天 0=04:30 → 54000=19:30；夜晚 0=19:30 → 32400=04:30
--                           单位是「游戏秒」，1 游戏小时 = 3600
--   Main.dayRate  (int)     时间流速，原版 1
-- 关键坑：1.4.5 每帧都会调 Main.UpdateTimeRate()，把 dayRate 从
--   CreativePowerManager 的 TargetTimeRate 重算一遍 —— 直接写 dayRate 撑不过一帧。
--   必须钩 UpdateTimeRate 的 postfix，在它算完之后把我们自己的倍率写回去。
-- 同样因为主 chunk 的 local 已到 200 上限，整段包成 IIFE。
_G.ms_world = (function()
    local F_day_time, F_time, F_day_rate
    local fields_ready = false

    local target_rate = nil     -- nil = 不干预（原版行为）；0 = 暂停；1..24 = 倍率
    local rate = 1              -- 界面滑块当前值
    local last_rate = 1         -- 暂停前记住的倍率
    local time_hook = nil

    -- 白天 time: 0=4:30 → 54000=19:30（15 小时）
    -- 夜晚 time: 0=19:30 → 32400=4:30（9 小时）
    local PRESETS = {
        { "黎明 4:30",  true,  0.0 },
        { "中午 12:00", true,  27000.0 },   -- 4:30 + 7.5h
        { "黄昏 19:30", false, 0.0 },
        { "午夜 00:00", false, 16200.0 },   -- 19:30 + 4.5h
    }

    local function init_fields()
        if fields_ready then return true end
        local T = patch.get_type("Terraria", "Main")
        if not T then return false end
        F_day_time = patch.get_field(T, "dayTime")
        F_time     = patch.get_field(T, "time")
        F_day_rate = patch.get_field(T, "dayRate")
        fields_ready = (F_day_time ~= nil) and (F_time ~= nil) and (F_day_rate ~= nil)
        return fields_ready
    end

    -- 钩 Main.UpdateTimeRate()，把它算完的 dayRate 改成我们要的值
    local function install_hook()
        if time_hook then return end
        if not init_fields() then return end
        local T = patch.get_type("Terraria", "Main")
        if not T then return end
        local m = patch.get_method(T, "UpdateTimeRate", 0)
        if not m then
            mod.warn("[WORLD] Main.UpdateTimeRate not found，流速控制不可用")
            return
        end
        local ok, h = pcall(patch.install_hook, m, {
            postfix = function()
                if target_rate == nil then return end
                local okv, cur = pcall(patch.get_field_value, F_day_rate, nil, "int32")
                -- 睡觉快进时游戏强制 60，本模组不去打断它
                if okv and cur == 60 and target_rate ~= 60 then return end
                pcall(patch.set_field_value, F_day_rate, nil, target_rate, "int32")
            end,
        })
        if ok and h then
            time_hook = h
            mod.info("[WORLD] 时间流速钩子已安装（Main.UpdateTimeRate）")
        else
            mod.warn("[WORLD] 时间流速钩子安装失败")
        end
    end

    -- v4.6.2：按用户要求走原版 Main.SkipToTime(int timeToSet, bool setIsDayTime)。
    --   它会 while 循环调 UpdateTime_StartNight / UpdateTime_StartDay，
    --   直到 dayTime 与目标一致，再写 time —— 也就是游戏自己跳时间的那条路，
    --   连带原版的所有效果（陨石、随机 Boss、月亮事件、每日重置等）都会照常发生。
    --   源码位置 Main.cs:66205；StartNight 里 66385 行 dayTime=false、
    --   StartDay 里 66420 行 dayTime=true，所以 while 一定能退出。
    --   只有 SkipToTime 拿不到或调用失败，才回退到直接写 dayTime / time。
    local function apply_time(day, t)
        if not init_fields() then return false end
        local m
        local T = patch.get_type("Terraria", "Main")
        if T then
            local okm, mm = pcall(patch.get_method, T, "SkipToTime", 2)
            if okm then m = mm end
        end
        if m then
            local ok, r = pcall(patch.invoke, m, math.floor(t), day)
            if ok and r ~= false then return true end
            mod.warn("[WORLD] Main.SkipToTime 调用失败，回退直接写字段")
        else
            mod.warn("[WORLD] Main.SkipToTime 未找到，回退直接写字段")
        end
        local ok1 = pcall(patch.set_field_value, F_day_time, nil, day, "bool")
        local ok2 = pcall(patch.set_field_value, F_time, nil, t, "double")
        return ok1 and ok2
    end

    local function clock_text()
        if not init_fields() then return "未知" end
        local okd, d = pcall(patch.get_field_value, F_day_time, nil, "bool")
        local okt, t = pcall(patch.get_field_value, F_time, nil, "double")
        if not okd or not okt or type(t) ~= "number" then return "未知" end
        local base = d and 4.5 or 19.5
        local hour = (base + t / 3600.0) % 24
        local hh = math.floor(hour)
        local mm = math.floor((hour - hh) * 60)
        return string.format("%s %02d:%02d", d and "白天" or "夜晚", hh, mm)
    end

    -- 时间控制块（由 gui_world 调用）
    local function gui_time(g, y0)
        -- v5.4.3：改成绝对坐标版（流式 g.button 无法圆角），返回下一行的 y。
        y0 = y0 or 0
        install_hook()
        local SC = type(g.set_cursor) == "function"
        local ba = _G.ms_btn_at
        local TXT = { 235, 237, 229, 255 }
        if not init_fields() then
            g.text("时间控制不可用：找不到 Main.dayTime / time / dayRate")
            return y0 + 24
        end
        local flow = (rate == 0) and "暂停" or (rate .. "×")
        local cap = "当前时间：" .. clock_text() .. "　流速 " .. flow
        if type(g.text_at) == "function" then
            g.text_at(4, y0 + 4, cap, TXT)
        elseif SC then
            g.set_cursor(0, y0 + 4)
            g.text(cap)
        end
        local y = y0 + 30
        -- 暂停 / 恢复
        local plabel = (rate == 0) and "恢复时间" or "暂停时间"
        local clicked
        if ba then
            clicked = ba(g, 4, y, plabel, 160)   -- v5.4.4：与下方四个时刻按钮同宽
        else
            if SC then g.set_cursor(0, y) end
            clicked = g.button(plabel)
        end
        if clicked then
            if rate == 0 then
                rate = (last_rate > 0) and last_rate or 1
                target_rate = rate
                notify("时间恢复 " .. rate .. "×")
            else
                last_rate = rate
                rate = 0
                target_rate = 0
                notify("时间已暂停")
            end
        end
        y = y + 42
        -- 四个时刻（一行四个）
        for i = 1, #PRESETS do
            local p = PRESETS[i]
            local c
            if ba then
                c = ba(g, 4 + (i - 1) * 166, y, p[1], 160)
            else
                if SC then g.set_cursor(0, y) end
                if i > 1 then g.same_line() end
                c = g.button(p[1])
            end
            if c then
                if apply_time(p[2], p[3]) then
                    notify("时间 -> " .. p[1])
                else
                    notify("设置时间失败")
                end
            end
        end
        y = y + 42
        -- 流速滑块 0..24
        if SC then g.set_cursor(0, y) end
        local nr = math.floor(g.slider("时间流速", rate, 0, 24))
        if nr ~= rate then
            rate = nr
            if nr > 0 then last_rate = nr end
            target_rate = nr
        end
        return y + 56
    end

    -- ---------- 事件（v4.7.48）----------
    -- 全部走原版入口，不自己拼状态：
    --   派对   BirthdayParty.ManualParty = true（原版 PartyIsUp => ManualParty || GenuineParty）
    --   血月   Main.bloodMoon = true（先跳到入夜，否则白天不生效）
    --   日食   Main.eclipse = true（先跳到正午）
    --   入侵   Main.StartInvasion(int)：1 哥布林 / 2 雪人军团 / 3 海盗 / 4 火星暴乱
    --   史莱姆雨 Main.StartSlimeRain(true)
    --   南瓜月 Main.startPumpkinMoon()；霜月 Main.startSnowMoon()
    --   月亮事件 WorldGen.TriggerLunarApocalypse()
    local EV = nil
    local EVENTS = {
        { "派对", "party" }, { "血月", "blood" }, { "哥布林入侵", "goblin" }, { "史莱姆雨", "slime" },
        { "雪人军团", "snowlegion" }, { "日食", "eclipse" }, { "海盗入侵", "pirate" }, { "南瓜月", "pumpkin" },
        { "霜月", "frostmoon" }, { "火星暴乱", "martian" }, { "月亮事件", "lunar" },
    }
    local function ev_init()
        if EV then return EV end
        local e = {}
        local okm, tm = pcall(patch.get_type, "Terraria", "Main")
        if okm and tm then
            e.blood = patch.get_field(tm, "bloodMoon")
            e.eclipse = patch.get_field(tm, "eclipse")
            e.start_invasion = patch.get_method(tm, "StartInvasion", 1)
            e.start_slime = patch.get_method(tm, "StartSlimeRain", 1)
            e.pumpkin = patch.get_method(tm, "startPumpkinMoon", 0)
            e.snow = patch.get_method(tm, "startSnowMoon", 0)
        end
        local okw, wg = pcall(patch.get_type, "Terraria", "WorldGen")
        if okw and wg then
            e.lunar = patch.get_method(wg, "TriggerLunarApocalypse", 0)
        end
        local okb, bp = pcall(patch.get_type, "Terraria.GameContent.Events", "BirthdayParty")
        if okb and bp then
            e.party = patch.get_field(bp, "ManualParty")
        end
        EV = e
        return EV
    end
    local function ev_set_bool(f)
        if not f then return false end
        local ok, r = pcall(patch.set_field_value, f, nil, true, "bool")
        return (ok and r ~= false) and true or false
    end
    local function ev_call(f, ...)
        if not f then return false end
        local ok, r = pcall(patch.invoke, f, ...)
        return (ok and r ~= false) and true or false
    end
    local function ev_fire(key)
        local e = ev_init()
        if key == "party" then
            return ev_set_bool(e.party)
        elseif key == "blood" then
            -- 血月只在夜里判定，先入夜再点亮
            local ok_t = apply_time(false, 0.0)
            local ok_b = ev_set_bool(e.blood)
            return ok_b or ok_t
        elseif key == "eclipse" then
            -- 日食只在白天判定
            local ok_t = apply_time(true, 27000.0)
            local ok_b = ev_set_bool(e.eclipse)
            return ok_b or ok_t
        elseif key == "slime" then
            return ev_call(e.start_slime, true)
        elseif key == "goblin" then
            return ev_call(e.start_invasion, 1)
        elseif key == "snowlegion" then
            return ev_call(e.start_invasion, 2)
        elseif key == "pirate" then
            return ev_call(e.start_invasion, 3)
        elseif key == "martian" then
            return ev_call(e.start_invasion, 4)
        elseif key == "pumpkin" then
            return ev_call(e.pumpkin)
        elseif key == "frostmoon" then
            return ev_call(e.snow)
        elseif key == "lunar" then
            return ev_call(e.lunar)
        end
        return false
    end
    -- v5.4.0：改为绝对坐标以支持圆角按钮；返回结束 y
    local function gui_events(g, y0)
        y0 = y0 or 0
        local TXT = { 235, 237, 229, 255 }
        if type(g.text_at) == "function" then g.text_at(4, y0 + 4, "事件", TXT)
        else g.text("事件") end
        local BW, GX, BH, GY = 140, 6, 36, 6
        local ba = _G.ms_btn_at
        for i = 1, #EVENTS do
            local idx = i - 1
            local col = idx % 4
            local row = math.floor(idx / 4)
            local lbl = EVENTS[i][1]
            if ba and ba(g, 4 + col * (BW + GX), y0 + 34 + row * (BH + GY), lbl, BW) then
                if ev_fire(EVENTS[i][2]) then
                    notify(lbl .. "：已触发")
                else
                    notify(lbl .. "：触发失败")
                end
            end
        end
        return y0 + 34 + math.ceil(#EVENTS / 4) * (BH + GY)
    end

    -- ---------- 天气（v4.6.3） ----------
    -- 用到四个 Main 静态字段：
    --   windSpeedCurrent (float)  当前风速，mph = current * 50（源码 Main.cs:47703），负=东风 正=西风
    --   windSpeedTarget  (float)  目标风速，游戏会让 current 平滑靠向 target*(1 + 5/9*maxRaining)（59781）
    --   maxRaining       (float)  雨势 0..1
    --   raining          (bool)   有没有在下雨
    --   rainTime         (int)    剩余雨时长；>= 5184000 就是原版的「永久降雨」（Main.cs:3225）
    local F_wind_cur, F_wind_tgt, F_max_rain, F_raining, F_rain_time, F_cloud_alpha
    local M_start_rain, M_stop_rain
    local weather_ready = false
    local weather_inited = false
    local weather_registered = false
    local wind_mph = 0        -- -40..40（左=东风，右=西风）
    local wind_lock = false
    local rain_pct = 0        -- 0=晴天 100=最大雨
    local rain_lock = false

    local function init_weather()
        if weather_ready then return true end
        local T = patch.get_type("Terraria", "Main")
        if not T then return false end
        F_wind_cur  = patch.get_field(T, "windSpeedCurrent")
        F_wind_tgt  = patch.get_field(T, "windSpeedTarget")
        F_max_rain  = patch.get_field(T, "maxRaining")
        F_raining   = patch.get_field(T, "raining")
        F_rain_time = patch.get_field(T, "rainTime")
        F_cloud_alpha = patch.get_field(T, "cloudAlpha")
        -- 原版旅途「天气页」用的两个方法（Main.cs:65665 StopRain / 65680 StartRain）
        local ok1, m1 = pcall(patch.get_method, T, "StartRain", 3)
        if not (ok1 and m1) then
            local ok2, m2 = pcall(patch.get_method, T, "StartRain", 2)
            if ok2 then m1 = m2 end
        end
        M_start_rain = m1
        local ok3, m3 = pcall(patch.get_method, T, "StopRain", 1)
        if not (ok3 and m3) then
            local ok4, m4 = pcall(patch.get_method, T, "StopRain", 0)
            if ok4 then m3 = m4 end
        end
        M_stop_rain = m3
        weather_ready = (F_wind_cur ~= nil) and (F_wind_tgt ~= nil)
            and (F_max_rain ~= nil) and (F_raining ~= nil) and (F_rain_time ~= nil)
        return weather_ready
    end

    local function read_f(f, dft)
        if not f then return dft end
        local ok, v = pcall(patch.get_field_value, f, nil, "float")
        if ok and type(v) == "number" then return v end
        return dft
    end

    local function read_b(f, dft)
        if not f then return dft end
        local ok, v = pcall(patch.get_field_value, f, nil, "bool")
        if ok and type(v) == "boolean" then return v end
        return dft
    end

    -- 写入风速：照抄原版旅途「天气页」的 ModifyWindDirectionAndStrength
    --   （CreativePowers.cs:1194）
    --     Main.windSpeedCurrent = (Main.windSpeedTarget = MathHelper.Lerp(-0.8f, 0.8f, 滑块值));
    --   滑块 0..1 线性映射 -0.8..0.8，两边同时写同一个值，不做任何反推。
    --   （所以下雨时风速仍会被游戏按 1 + 5/9*雨势 放大，这就是原版行为）
    local function apply_wind()
        if not init_weather() then return false end
        local want = wind_mph / 50.0
        pcall(patch.set_field_value, F_wind_tgt, nil, want, "float")
        pcall(patch.set_field_value, F_wind_cur, nil, want, "float")
        return true
    end

    -- 锁定风速：对应原版 FreezeWindDirectionAndStrength —— 只冻结 target，
    --   不动 current，这样「下雨把风放大」的原版效果照样保留
    local function hold_wind()
        if not init_weather() then return end
        pcall(patch.set_field_value, F_wind_tgt, nil, wind_mph / 50.0, "float")
    end

    -- 应用雨势：完全照原版旅途「天气页」的 ModifyRainPower（CreativePowers.cs:1318）
    --   滑块 0   -> Main.StopRain(instant: true)
    --   滑块 >0  -> Main.StartRain(instant: true, 强度)   强度就是滑块值（原版滑块取的是 cloudAlpha）
    local function apply_rain()
        if not init_weather() then return false end
        local v = rain_pct / 100.0
        if v <= 0 then
            -- 先清掉原版「永久降雨」标志（rainTime >= 5184000），
            -- 否则 StopRain 里的 if (!IsRainingForever) 会把整段跳过，雨停不下来
            pcall(patch.set_field_value, F_rain_time, nil, 0, "int32")
            if M_stop_rain then
                local ok = pcall(patch.invoke, M_stop_rain, true)
                if ok then return true end
                mod.warn("[WORLD] Main.StopRain 调用失败，回退直接写字段")
            end
            pcall(patch.set_field_value, F_max_rain, nil, 0.0, "float")
            pcall(patch.set_field_value, F_raining, nil, false, "bool")
            if F_cloud_alpha then
                pcall(patch.set_field_value, F_cloud_alpha, nil, 0.0, "float")
            end
            return true
        end
        if M_start_rain then
            local ok = pcall(patch.invoke, M_start_rain, true, v)
            if ok then
                if rain_lock then
                    pcall(patch.set_field_value, F_rain_time, nil, 5184000, "int32")
                end
                return true
            end
            mod.warn("[WORLD] Main.StartRain 调用失败，回退直接写字段")
        end
        pcall(patch.set_field_value, F_max_rain, nil, v, "float")
        pcall(patch.set_field_value, F_raining, nil, true, "bool")
        if F_cloud_alpha then
            pcall(patch.set_field_value, F_cloud_alpha, nil, v, "float")
        end
        pcall(patch.set_field_value, F_rain_time, nil, rain_lock and 5184000 or 0, "int32")
        return true
    end

    local function weather_tick()
        if wind_lock then hold_wind() end
        if not rain_lock then return end
        if not init_weather() then return end
        if rain_pct <= 0 then
            -- 锁定晴天：把雨按回去。这里只写字段，不重复调 StopRain
            pcall(patch.set_field_value, F_rain_time, nil, 0, "int32")
            pcall(patch.set_field_value, F_max_rain, nil, 0.0, "float")
            pcall(patch.set_field_value, F_raining, nil, false, "bool")
        else
            -- 锁定下雨：维持强度 + 原版「永久降雨」标志。
            -- 注意绝对不能每帧调 Main.StartRain —— 它内部有 RollLuck(25) 掷金币雨，每帧调必然炸金币雨
            local v = rain_pct / 100.0
            pcall(patch.set_field_value, F_rain_time, nil, 5184000, "int32")
            pcall(patch.set_field_value, F_max_rain, nil, v, "float")
            pcall(patch.set_field_value, F_raining, nil, true, "bool")
            if F_cloud_alpha then
                pcall(patch.set_field_value, F_cloud_alpha, nil, v, "float")
            end
        end
    end

    -- 挂到合集的每帧总线（Main.Update postfix，只在世界内跑），面板关掉也照样锁
    local function ensure_weather_tick()
        if weather_registered then return end
        weather_registered = true
        if type(tb_frame) == "table" then
            tb_frame[#tb_frame + 1] = { fn = weather_tick }
        end
    end

    local function gui_weather(g, y0)
        -- v5.4.4：改成绝对坐标版，返回下一行的 y（原来按流式堆，高度算不准会和下方重叠）。
        y0 = y0 or 0
        local SC = type(g.set_cursor) == "function"
        local TXT = { 235, 237, 229, 255 }
        local y = y0
        local function at(v) if SC then g.set_cursor(0, v) end end
        ensure_weather_tick()
        if not init_weather() then
            g.text("天气控制不可用：找不到天气字段")
            return y0 + 24
        end
        -- 首次进来把滑块对齐到当前世界状态
        if not weather_inited then
            weather_inited = true
            local w = math.floor(read_f(F_wind_cur, 0) * 50 + 0.5)
            if w > 40 then w = 40 elseif w < -40 then w = -40 end
            wind_mph = w
            -- 原版旅途雨势滑块的取值就是 Main.cloudAlpha（CreativePowers.cs:1347）
            local rp = math.floor(read_f(F_cloud_alpha, read_f(F_max_rain, 0)) * 100 + 0.5)
            if rp < 0 then rp = 0 elseif rp > 100 then rp = 100 end
            if not read_b(F_raining, false) then rp = 0 end
            rain_pct = rp
        end
        -- 风
        local cur = math.floor(read_f(F_wind_cur, 0) * 50 + 0.5)
        local wtext
        if cur > 0 then
            wtext = "西风 " .. cur .. " mph"
        elseif cur < 0 then
            wtext = "东风 " .. (-cur) .. " mph"
        else
            wtext = "无风"
        end
        if type(g.text_at) == "function" then
            g.text_at(4, y + 4, "当前风速：" .. wtext, TXT)
        else
            at(y); g.text("当前风速：" .. wtext)
        end
        y = y + 30
        at(y)
        local nw = math.floor(g.slider("风速(mph)", wind_mph, -40, 40) + 0.5)
        if nw ~= wind_mph then
            wind_mph = nw
            apply_wind()
        end
        y = y + 50
        at(y)
        wind_lock = g.checkbox("锁定风速", wind_lock)
        y = y + 36
        -- 雨
        local mr = read_f(F_max_rain, 0)
        local rtext
        if not read_b(F_raining, false) then
            rtext = "晴天"
        elseif mr > 0.6 then
            rtext = "大雨"
        elseif mr >= 0.2 then
            rtext = "下雨"
        elseif mr > 0 then
            rtext = "细雨"
        else
            rtext = "阴天"
        end
        if type(g.text_at) == "function" then
            g.text_at(4, y + 4, "当前天气：" .. rtext, TXT)
        else
            at(y); g.text("当前天气：" .. rtext)
        end
        y = y + 30
        at(y)
        local np = math.floor(g.slider("雨势(%)", rain_pct, 0, 100) + 0.5)
        if np ~= rain_pct then
            rain_pct = np
            apply_rain()
        end
        y = y + 50
        at(y)
        rain_lock = g.checkbox("锁定雨势", rain_lock)
        y = y + 36
        return y
    end

    -- v5.4.5：内容高度改成动态——记上一帧算出的实际高度，本帧传给 begin_scroll。
    --   原来是写死 1520，比真实内容（约 1070）长出很多，滚到底会剩一大片空白。
    local world_h = 1100
    local function gui_world(g)
        -- v4.6.3：内容变长（月相 + 时间 + 天气），整页改成可滑动，
        --   写法跟模组设置页一致：begin_scroll(id, x, y, w, h, content_w, content_h)。
        local can_scroll = (type(g.begin_scroll) == "function" and type(g.end_scroll) == "function")
        -- v8.3.9：记住本帧的滚动偏移与内容高，end_scroll 之后补画粗滚动条
        local WP_X, WP_Y, WP_W, WP_H = 0, 54, 730, 220
        local wp_ch = world_h
        local wp_sy = 0
        if can_scroll then
            local _, sy0 = g.begin_scroll("world_page", WP_X, WP_Y, WP_W, WP_H, WP_W, wp_ch)
            wp_sy = tonumber(sy0) or 0
        end
        -- v5.5.0：本页所有板块统一为绝对坐标绘制（月相 / 事件 / 时间 / 天气 / 旅途力量），
        --   每段都是「接受 y0、返回新 y」，由这里串接；滑块与复选框仍在流式 API 上，
        --   靠 g.set_cursor(0, y) 逐行对齐。改版历史：
        --   v5.4.0 月相/事件改绝对坐标（圆角），v5.4.3 时间/旅途力量，
        --   v5.4.4 天气，v5.4.5 补事件↔分隔线 + 滚动高度动态化，v5.4.6 底部留白减半。
        local wy = 0
        wy = gui_moon(g, wy)
        wy = wy + 8
        if type(g.rect) == "function" then
            pcall(g.rect, 0, wy, 700, 1, { 60, 70, 120, 255 })
        end
        wy = wy + 8
        wy = gui_events(g, wy)
        wy = wy + 10
        if type(g.rect) == "function" then pcall(g.rect, 0, wy, 700, 1, { 60, 70, 120, 255 }) end
        wy = wy + 10
        -- v5.4.3：时间与旅途力量都改成绝对坐标，这里统一串 y
        wy = gui_time(g, wy)
        wy = wy + 10
        if type(g.rect) == "function" then pcall(g.rect, 0, wy, 700, 1, { 60, 70, 120, 255 }) end
        wy = wy + 10
        wy = gui_weather(g, wy)
        wy = wy + 10
        if type(g.rect) == "function" then pcall(g.rect, 0, wy, 700, 1, { 60, 70, 120, 255 }) end
        wy = wy + 10
        -- v4.6.8：旅途力量整页并进来（原「旅途力量」页签已删除）
        if _G.ms_powers then
            local okw, nwy = pcall(_G.ms_powers.gui, g, wy)
            if okw and type(nwy) == "number" then
                wy = nwy
            else
                wy = wy + 320
            end
        else
            if type(g.set_cursor) == "function" then g.set_cursor(0, wy) end
            g.text("旅途力量：模块未加载")
            wy = wy + 30
        end
        if type(g.set_cursor) == "function" then g.set_cursor(0, wy) end
        -- v5.4.5/5.4.6：把本帧真实内容高度记下来，下一帧给 begin_scroll 用。
        --   各段的 return 值本身略偏大（滑块行按 56 估，实际约 50），累计多出约 40；
        --   这里减 4 把底部留白压一半，又不至于把难度滑块切掉。
        world_h = wy - 4
        if can_scroll then
            g.end_scroll()
            if _G.ms_fat_scroll then pcall(_G.ms_fat_scroll, g, WP_X, WP_Y, WP_W, WP_H, wp_sy, wp_ch) end
            if type(g.set_content_height) == "function" then
                g.set_content_height(54 + 220)
            end
        end
    end

    return { gui = gui_world, install = install_hook }
end)()


-- ============ 旅途力量（v4.6.9：×0 走原版机制） ============
-- 顺序按原版旅途设置「力量」页：无敌模式 / 放置范围 / 刷怪速度 / 传染扩散 / 难度
--
-- ① 无敌模式  Player.creativeGodMode（Player.cs:1879）
-- ② 放置范围  Player.tileRangeX / tileRangeY（静态字段，基准 5 / 3）
--    ResetEffects 每帧重置（18929），原版 power 开启是 ×2+8 → 18 / 14。
-- ③ 刷怪速度  NPC.defaultSpawnRate / defaultMaxSpawns（NPC.cs:6190 / 6192）
--    ×0 用原版那条链：SpawnRateSliderPerPlayerPower.GetShouldDisableSpawnsFor(playerIndex)
--      里 playerIndex == Main.myPlayer 时读的就是 _sliderCurrentValueCache == 0（CreativePowers.cs:1595）
--      → 把该字段写 0，本地玩家就等于原版旅途把刷怪率拉到 0。
--    另一个检查点 NPC.Spawner.CanSpawnEnemiesNear(Player)（NPC.cs:345）内部会问 power，
--      但整段被 if (Main.IsJourneyMode) 包着，非旅途世界不生效 —— 所以再钩它的 prefix 兜底。
-- ④ 传染扩散  从 CreativePowerManager._powersByName 取 StopBiomeSpreadPower，调 SetPowerInfo(bool)
-- ⑤ 难度  钩 Main.Difficulty 属性 getter 的返回值（原版难度滑块 0.5x ~ 3x）
-- 同样因为主 chunk 的 local 到顶，整段包成 IIFE。
_G.ms_powers = (function()
    local T_main, T_player, T_npc
    local F_god
    -- PE(1.4.5.8) 里 tileRangeX / tileRangeY 是「静态属性」，PC 源码里才是字段
    local M_get_rx, M_set_rx, M_get_ry, M_set_ry
    local F_def_rate, F_def_max
    -- v4.7.47：PE 里 CreativePowerManager.Instance 是纯计算属性（字段列表只有 4 个实例字段、
    --   没有 _instance 也没有 <Instance>k__BackingField），唯一入口是 invoke getter，
    --   而这台机器上一 invoke 就 native 崩 —— 所以旅途滑块/倍率这条路彻底不做。
    --   刷怪率只改 NPC.defaultSpawnRate / defaultMaxSpawns 两个基数。
    local T_world                 -- Terraria.WorldGen
    local F_allowed_spread        -- WorldGen.AllowedToSpreadInfections（public static bool）
    local M_can_spawn
    local ready = false
    local inited = false
    local reset_hook = nil
    local spawn_hook = nil

    local god_on = false
    local far_on = false
    local orig_rate, orig_max
    local scale = 1
    local slider_val = 1
    local BTN = { 0, 0.5, 1, 2, 5, 10, 20, 50, 100 }
    local spread_on = true
    local diff_on = false
    local diff_val = 1.0
    local diff_slider = 10
    local diff_hook = nil

    local function read_int(f, dft)
        if not f then return dft end
        local ok, v = pcall(patch.get_field_value, f, nil, "int32")
        if ok and type(v) == "number" then return v end
        return dft
    end

    local function init_fields()
        if ready then return true end
        T_main = patch.get_type("Terraria", "Main")
        T_player = patch.get_type("Terraria", "Player")
        T_npc = patch.get_type("Terraria", "NPC")
        if not (T_main and T_player and T_npc) then return false end
        F_god = patch.get_field(T_player, "creativeGodMode")
        -- ★ 关键修复：PE 版 Player.tileRangeX / tileRangeY 是「静态属性」（带 get/set），
        --   不是字段（PC 源码 Player.cs:2479 是字段，移植到 PE 后改成了属性）。
        --   之前用 get_field 拿到的是 nil，自然一直不生效。
        local ok_px, px = pcall(patch.get_property, T_player, "tileRangeX")
        if ok_px and px then
            M_get_rx = patch.property_get_method(px)
            M_set_rx = patch.property_set_method(px)
        end
        local ok_py, py = pcall(patch.get_property, T_player, "tileRangeY")
        if ok_py and py then
            M_get_ry = patch.property_get_method(py)
            M_set_ry = patch.property_set_method(py)
        end
        -- 传染扩散开关：原版旅途「停止生物群落蔓延」就是翻这个全局 static bool
        local ok_wg, wg = pcall(patch.get_type, "Terraria", "WorldGen")
        if ok_wg and wg then
            T_world = wg
            F_allowed_spread = patch.get_field(wg, "AllowedToSpreadInfections")
        end
        F_def_rate = patch.get_field(T_npc, "defaultSpawnRate")
        F_def_max = patch.get_field(T_npc, "defaultMaxSpawns")
        -- 原版刷怪检查函数 NPC.Spawner.CanSpawnEnemiesNear(Player)
        local ok_sp, sp = pcall(patch.get_inner_type, T_npc, "Spawner")
        if ok_sp and sp then
            local ok_m, m = pcall(patch.get_method, sp, "CanSpawnEnemiesNear", 1)
            if ok_m then M_can_spawn = m end
        end
        if not M_set_rx then mod.warn("[POWER] tileRangeX 属性取不到，放置范围不可用") end
        ready = true
        return true
    end

    -- 当前世界是否旅途模式（只读 Main.GameMode 字段，3=旅途）
    local function is_journey()
        if F_game_mode then
            local ok, v = pcall(patch.get_field_value, F_game_mode, nil, "int32")
            if ok and type(v) == "number" then return v == 3 end
        end
        return false
    end
    -- 非旅途世界不会被原版那条链拦住，钩 CanSpawnEnemiesNear 兜底
    local function ensure_spawn_hook()
        if spawn_hook then return true end
        if not M_can_spawn then return false end
        local ok, h = pcall(patch.install_hook, M_can_spawn, {
            prefix = function()
                if scale <= 0 then
                    return true, false   -- 跳过原方法，直接返回 false（附近不能刷怪）
                end
                return false
            end,
        })
        if ok and h then
            spawn_hook = h
            return true
        end
        mod.warn("[POWER] CanSpawnEnemiesNear 钩子安装失败")
        return false
    end

    local function apply_spawn()
        if not init_fields() then return false end
        if not inited then
            inited = true
            orig_rate = F_def_rate and read_int(F_def_rate, 600) or 600
            orig_max = F_def_max and read_int(F_def_max, 5) or 5
            if not orig_rate or orig_rate <= 0 then orig_rate = 600 end
            if not orig_max or orig_max <= 0 then orig_max = 5 end
        end
        local function restore_base()
            if F_def_rate then pcall(patch.set_field_value, F_def_rate, nil, orig_rate, "int32") end
            if F_def_max then pcall(patch.set_field_value, F_def_max, nil, orig_max, "int32") end
        end
        if scale <= 0 then
            -- ×0：钩 CanSpawnEnemiesNear 兜底，真正关刷
            ensure_spawn_hook()
            restore_base()
            return true
        end
        -- 改基数：间隔 ÷ n；同屏 ×min(n,3)
        local n = scale
        if n < 0.1 then n = 0.1 elseif n > 100 then n = 100 end
        local rate = math.floor(orig_rate / n + 0.5)
        if rate < 1 then rate = 1 end
        local mult = n
        if mult > 3 then mult = 3 end
        local maxs = math.floor(orig_max * mult + 0.5)
        if maxs < 1 then maxs = 1 end
        if F_def_rate then pcall(patch.set_field_value, F_def_rate, nil, rate, "int32") end
        if F_def_max then pcall(patch.set_field_value, F_def_max, nil, maxs, "int32") end
        return true
    end
    -- ---------- 无敌 / 放置范围（每帧补写） ----------
    local function player_tick(inst)
        if not inst then return end
        -- 冻结蔓延时每帧兜一下：进世界/读档会把 AllowedToSpreadInfections 重置成 true
        if not spread_on and F_allowed_spread then
            pcall(patch.set_field_value, F_allowed_spread, nil, false, "bool")
        end
        if god_on and F_god then
            pcall(patch.set_field_value, F_god, inst, true, "bool")
        end
        if far_on then
            -- 原版「已增加」= 默认 5/3 各 ×2 再 +8 → 18 / 14
            if M_set_rx then pcall(patch.invoke, M_set_rx, 18) end
            if M_set_ry then pcall(patch.invoke, M_set_ry, 14) end
        end
    end

    local function ensure_hook()
        if reset_hook then return true end
        if not init_fields() then return false end
        local ok, m = pcall(patch.get_method, T_player, "ResetEffects", 0)
        if not ok or not m then
            mod.warn("[POWER] Player.ResetEffects 取不到")
            return false
        end
        local ok2, h = pcall(patch.install_hook, m, {
            postfix = function(inst)
                player_tick(inst)
            end,
        })
        if ok2 and h then
            reset_hook = h
            return true
        end
        mod.warn("[POWER] ResetEffects 钩子安装失败")
        return false
    end

    -- ---------- 传染扩散（v4.7.44：照原版旅途「停止生物群落蔓延」的做法） ----------
    -- 原版是 CreativePowers.StopBiomeSpreadPower，但它内部做的就是把
    --   WorldGen.AllowedToSpreadInfections 置 false / true。
    -- 那个 power 实例在本机拿不到（CreativePowerManager.Instance 一 invoke 就闪退），
    -- 所以直接翻这个字段 —— 效果和原版开关一致，而且只是一次 bool 写。
    local function init_spread()
        if F_allowed_spread then return true end
        if not T_world then init_fields() end
        if not T_world then return false end
        F_allowed_spread = patch.get_field(T_world, "AllowedToSpreadInfections")
        return F_allowed_spread ~= nil
    end
    local function apply_spread()
        if not init_spread() then return false end
        local ok = pcall(patch.set_field_value, F_allowed_spread, nil, spread_on and true or false, "bool")
        return ok
    end

    -- ---------- 难度 ----------
    local function install_diff_hook()
        if diff_hook then return true end
        local prop = patch.get_property(T_main, "Difficulty")
        if not prop then return false end
        local getter = patch.property_get_method(prop)
        if not getter then return false end
        local ok, h = pcall(patch.install_hook, getter, {
            postfix = function()
                if not diff_on then return nil end
                return diff_val
            end,
            override_result = true,
        })
        if ok and h then
            diff_hook = h
            return true
        end
        return false
    end

    -- ---------- 还原 ----------
    local function restore()
        if inited then
            if F_def_rate then pcall(patch.set_field_value, F_def_rate, nil, orig_rate, "int32") end
            if F_def_max then pcall(patch.set_field_value, F_def_max, nil, orig_max, "int32") end
        end
        spread_on = true
        pcall(apply_spread)
        if diff_hook and diff_hook.remove then pcall(function() diff_hook:remove() end) end
        diff_hook = nil
        if reset_hook and reset_hook.remove then pcall(function() reset_hook:remove() end) end
        reset_hook = nil
        if spawn_hook and spawn_hook.remove then pcall(function() spawn_hook:remove() end) end
        spawn_hook = nil
    end

    -- ---------- GUI ----------
        local function gui(g, y0)
        -- v5.4.3：改成绝对坐标版（倍数按钮要圆角），返回下一行的 y。
        y0 = y0 or 0
        local SC = type(g.set_cursor) == "function"
        local ba = _G.ms_btn_at
        local TXT = { 235, 237, 229, 255 }
        local y = y0
        local function at(v) if SC then g.set_cursor(0, v) end end
        if not init_fields() then
            g.text("旅途力量不可用：找不到 Main / Player / NPC 类型")
            return y0 + 24
        end
        ensure_hook()

        at(y)
        god_on = g.checkbox("无敌模式", god_on)
        y = y + 40
        -- v4.6.10：按用户要求 —— 没开只显示「放置范围」，开了显示「放置范围已增加」。
        --   但 checkbox 的 label 不能跟着变：ImGui 用 label 当控件 ID，
        --   一变下一帧就点不动了。所以 label 固定，状态文字跟在后面同一行。
        at(y)
        far_on = g.checkbox("放置范围", far_on)
        y = y + 40
        if far_on then
            -- 只有开了才 same_line，否则会把这行和下一行粘在一起
            g.same_line()
            local cur = 0
            if M_get_rx then
                local okv, v = pcall(patch.invoke, M_get_rx)
                if okv and type(v) == "number" then cur = v end
            end
            g.text("已增加（" .. cur .. " 格）")
        end

        if not inited then apply_spawn() end
        local jr = is_journey()
        local auth
        if scale <= 0 then
            auth = "· 已关闭刷怪"
        elseif jr then
            auth = "· 与旅途倍率相乘"
        else
            auth = "· 模组生效"
        end
        local sptext = string.format("刷怪速度：×%g　（间隔 %d · 同屏 %d）　%s",
            scale, F_def_rate and read_int(F_def_rate, 0) or 0,
            F_def_max and read_int(F_def_max, 0) or 0, auth)
        if type(g.text_at) == "function" then
            g.text_at(4, y + 4, sptext, TXT)
        else
            at(y); g.text(sptext)
        end
        y = y + 30
        at(y)
        local ns = math.floor(g.slider("刷怪倍率", slider_val, 0, 100) + 0.5)
        if ns ~= slider_val then
            slider_val = ns
            scale = ns
            apply_spawn()
        end
        y = y + 50
        for i = 1, #BTN do
            local v = BTN[i]
            local label = string.format("×%g", v)
            if math.abs(scale - v) < 0.001 then label = "[" .. label .. "]" end
            local hit
            if ba then
                hit = ba(g, 4 + (i - 1) * 80, y, label, 74)
            else
                if SC then g.set_cursor(0, y) end
                if i > 1 then g.same_line() end
                hit = g.button(label)
            end
            if hit then
                scale = v
                if v >= 1 then slider_val = math.floor(v + 0.5) end
                apply_spawn()
                if v <= 0 then
                    notify("刷怪速度 关闭")
                elseif is_journey() then
                    notify(string.format("刷怪速度 ×%g（与旅途倍率相乘）", v))
                else
                    notify(string.format("刷怪速度 ×%g", v))
                end
            end
        end
        y = y + 42
        local before = spread_on
        at(y)
        spread_on = g.checkbox("传染扩散", spread_on)
        y = y + 40
        if spread_on ~= before then
            if not apply_spread() then
                notify("传染扩散开关不可用")
            else
                notify(spread_on and "传染扩散 开启" or "传染扩散 关闭")
            end
        end

        install_diff_hook()
        local dtext = string.format("难度：×%.2f", diff_val)
        if type(g.text_at) == "function" then
            g.text_at(4, y + 4, dtext, TXT)
        else
            at(y); g.text(dtext)
        end
        y = y + 30
        at(y)
        local nd = math.floor(g.slider("难度倍率", diff_slider, 5, 30) + 0.5)
        if nd ~= diff_slider then
            diff_slider = nd
            diff_val = nd / 10
            diff_on = true
        end
        return y + 56
    end

    return { gui = gui, restore = restore }
end)()

-- ============ 一键建造（v4.7.0：整模块并入） ============
-- 原独立模组 liuxin.instant.housing v2.0.1 的 26 个 lua + templates/ + ui 贴图已复制到本模组 lib 下，
-- 这里只做装配（照抄原 main.lua 的 mod.init 逻辑），并把 draw 交给合集页签调用。
-- 它自己会接管面板：set_title / set_width(416) / set_pos / set_style / set_skin 都只在自己第一次 draw 时做一次，
-- 所以合集在 cur_page == 6 时会跳过自己的窗口设置，免得两边打架。
-- 退出方式：它面板底部有一个「返回模组合集」按钮（本版新加，通过 ui.on_back 回调），
-- 点它 → _G.ms_instant_back = true → 合集 on_gui 切回第 1 页。
_G.ms_instant = (function()
    local ui, workbench, adapter, controller, tick_handle
    local ready = false
    local failed = nil

    local function readableError(err)
        local message = tostring(err)
        return message:match("%.lua:%d+: (.+)$") or message
    end

    local function setup()
        if ready then return true end
        if failed then return false end
        if controller then return true end
        local ok, err = pcall(function()
            local Builder = require("builder")
            local UI = require("ui")
            controller = Builder.new({})
            ui = UI.new(mod, controller)
            if mod.platform ~= "android" or mod.arch ~= "arm64" then
                controller.disabled = true
                controller:fail("此模组仅支持 Android ARM64")
                error("unsupported platform")
            end
            local Adapter = require("adapter")
            local a, e = Adapter.new(mod.patch or {})
            if not a then error(e or "adapter init failed") end
            adapter = a
            controller.a = a
            local fok, feature = pcall(function()
                return require("workbench").new(mod, adapter, controller)
            end)
            if fok and feature then
                workbench = feature
                ui.workbench = workbench
            end
            tick_handle = a:attach(function()
                local before = controller.state
                controller:tick()
                if workbench then workbench:tick() end
                if controller.state == "error" and before ~= "error" then
                    mod.error("[一键建造] " .. tostring(controller.message))
                end
            end)
        end)
        if not ok then
            failed = readableError(err)
            mod.error("[一键建造] 初始化失败：" .. tostring(failed))
            ui = nil
            return false
        end
        ready = true
        -- 让它面板底部的「返回模组合集」能切回来
        if ui then
            ui.on_back = function() _G.ms_instant_back = true end
            -- v4.7.3：宽度交还它自己（416/320 原生布局）；host_mode 仍让图标/位置/折叠由合集说了算
            ui.host_width = nil
            ui.host_mode = true
        end
        mod.info("[一键建造] 已装载")
        return true
    end

    local function draw()
        if not setup() then
            local g = mod.gui
            g.text("一键建造初始化失败：" .. tostring(failed or "未知错误"))
            return
        end
        if ui then ui:draw() end
    end

    local function cleanup()
        if controller then pcall(function() controller:cancel() end) end
        if ui then pcall(function() ui:close() end) end
        if workbench then pcall(function() workbench:close() end) end
        if adapter then pcall(function() adapter:close() end) end
        adapter, controller, ui, workbench, tick_handle = nil, nil, nil, nil, nil
        ready = false
    end

    return { draw = draw, setup = setup, cleanup = cleanup }
end)()

-- v2.11.33：绝对定位按钮公共助手（认 x 坐标，把左上角钉到 (x,y)）。
-- v3.1.2：右列按钮改成「统一宽度」。
-- v3.2.1：文字恢复居中（button_at 原生居中，不再补全角空格）。
--   框宽由函数内 BW 控制（调小 = 按钮变短）。
-- 注：主 chunk 的 local 已到 200 上限，宽度常量写死在函数内，不再新增 local
-- v5.9.4：图片路径自适应 —— 3.0.x 的私有目录根可能是 <mod>/ 也可能是 <mod>/lib/，
--   两种都试一遍；load_image 对不存在的文件返回 nil，不会抛错。
_G.ms_load_img = function(g, name)
    if type(g.load_image) ~= "function" then return nil end
    local cands = { "lib/ui/" .. name, "ui/" .. name }
    for i = 1, #cands do
        local ok, id = pcall(g.load_image, cands[i])
        if ok and id then return id end
    end
    return nil
end
local function btn_at(g, x, y, label, w)
    local BW = w or 200   -- 右列按钮统一宽度（v4.7.26：w 可覆盖）
    -- v5.3.2：优先走圆角图按钮。button_36.png 中心色与 set_style 的 button
    --   （63,80,150）完全一致，所以换图后配色不变，只是多了圆角。
    --   半径 18 = 高度 36 的一半，即两端全圆。
    -- 注：image_button 第 7 参是九宫格 border 而非 radius；对圆角底图而言
    --     border=18 的效果就是四角 18x18 原样保留、中间拉伸，即半径 18。
    -- v5.9.3：图片可能根本没加载上（首次 on_gui 时私有目录还没就绪 / 解码失败），
    --   而 image_button 在图片无效时只画文字、不画底框 —— 表现就是「按钮只剩文字」。
    --   这里每帧自查：拿不到 ID 就重试 load_image；image_status 报 failed/invalid
    --   就永久退回直角按钮（button_at），保证一定看得见框。
    local img = _G.ms_btn_img
    if img == nil and _G.ms_load_img then
        local id = _G.ms_load_img(g, "button_36.png")
        if id then img = id; _G.ms_btn_img = id end
    end
    if img and _G.ms_btn_ok == nil and type(g.image_status) == "function" then
        local oks, st = pcall(g.image_status, img)
        if oks and type(st) == "string" then
            if st == "ready" then
                _G.ms_btn_ok = true
            elseif st:sub(1, 6) == "failed" or st == "invalid" then
                _G.ms_btn_ok = false
                pcall(mod.warn, "[GUI] 圆角按钮底图不可用（" .. st .. "），本帧起改用直角按钮")
            end
        end
    end
    if img and _G.ms_btn_ok ~= false and type(g.image_button) == "function" then
        return g.image_button(img, x, y, BW, 36, label, 18)
    end
    if type(g.button_at) == "function" then
        -- 旧路径：加载器没有 image_button 时退回直角按钮
        -- v3.2.1：按用户要求改回「白框内文字居中」（button_at 默认就是居中）
        return g.button_at(x, y, BW, 36, label)
    end
    if type(g.set_cursor) == "function" then g.set_cursor(x, y) end
    return g.button(label)
end
-- v5.4.2：btn_at 定义在 1798 行，而 gui_moon(847) / gui_events(1100) 在它之前，
--   Lua 的 local 作用域从声明处才开始，那两个函数里直接写 btn_at 会取到全局 nil。
--   这里挂到 _G，前面的函数通过 _G.ms_btn_at 访问（调用时机在模块加载完之后，安全）。
_G.ms_btn_at = btn_at
-- ============================================================================
-- v5.6.0：常开功能的统一开关表（原「默认常开、无开关」的 9 个模块）
-- ----------------------------------------------------------------------------
--   这些模块原本是 v1.4.0 ~ v3.4.1 期间按用户要求去掉开关、改常开的。
--   现在统一收回到设置页，每个一项勾选框，持久化 <key>_en.txt，默认全开。
--   门控方式：总入口 setup 里判断，关掉就【不安装钩子】—— 游戏内勾选后
--   需要重启游戏生效（卸载/安装钩子有原生崩溃风险，不做热切换）。
-- ============================================================================
_G.ms_gates = (function()
    -- key, 设置页显示名, 默认值
    local LIST = {
        { "vm", "连锁挖矿",     true },
        { "lp", "光源穿透",     true },
        { "sn", "探测（生物/宝藏/危险）", true },
        { "sn_creature", "生物探测", true, 2 },   -- 二级项（indent）
        { "sn_treasure", "宝藏探测", true, 2 },
        { "sn_danger",   "危险感知", true, 2 },
        { "py", "晶塔四改",     true },
        { "py_dist",   "无视距离",   true, 2 },   -- 二级项
        { "py_danger", "无视危险",   true, 2 },
        { "py_multi",  "同类型多座", true, 2 },
        { "py_npc",    "传送不需 NPC", true, 2 },
        { "zm", "缩放扩展",     true },

        { "cs", "召唤物不消耗（≥2个）", true },           -- v8.7.0：数量 >= 2 时不消耗
        { "dm", "每日旅商、骷髅商人", true },
        { "nh", "NPC 快速回家", true },
        { "ng", "城镇NPC无敌", true },   -- v8.9.3：城镇NPC免疫敌怪伤害
        { "lh", "残血提示",     true },
        { "rcp", "原版配方扩展", true },   -- v5.9.0：114 条原版物品配方
    }
    local V = {}
    local function file_of(k) return k .. "_en.txt" end
    for i = 1, #LIST do
        local k, _, dflt = LIST[i][1], LIST[i][2], LIST[i][3]
        local v = dflt
        local ok, raw = pcall(mod.read_file, file_of(k))
        if ok and type(raw) == "string" then
            raw = raw:gsub("%s", "")
            if raw == "0" or raw == "false" then v = false
            elseif raw == "1" or raw == "true" then v = true end
        end
        V[k] = v
    end
    -- v5.7.0：数值项（目前只有缩放扩展的最小缩放）
    local NUM = {
        { "zm_min", "最小缩放", 0.36, 0.20, 0.58 },   -- key, 名称, 默认, 最小, 最大
    }
    local NV = {}
    for i = 1, #NUM do
        local k, _, dflt, lo, hi = NUM[i][1], NUM[i][2], NUM[i][3], NUM[i][4], NUM[i][5]
        local v = dflt
        local ok, raw = pcall(mod.read_file, k .. ".txt")
        if ok and type(raw) == "string" then
            local n = tonumber((raw:gsub("%s", "")))
            if n then
                if n < lo then n = lo elseif n > hi then n = hi end
                v = n
            end
        end
        NV[k] = v
    end
    local M = {}
    M.LIST = LIST
    M.NUM = NUM
    function M.num(k) return NV[k] end
    function M.set_num(k, nv)
        for i = 1, #NUM do
            if NUM[i][1] == k then
                local lo, hi = NUM[i][4], NUM[i][5]
                nv = tonumber(nv) or NUM[i][3]
                if nv < lo then nv = lo elseif nv > hi then nv = hi end
                NV[k] = nv
                pcall(mod.write_file, k .. ".txt", string.format("%.2f", nv))
                return nv
            end
        end
        return nil
    end
    function M.indent(k)
        for i = 1, #LIST do
            if LIST[i][1] == k then return LIST[i][4] == 2 end
        end
        return false
    end
    function M.is(k)
        local v = V[k]
        if v == nil then return true end
        return v
    end
    function M.set(k, nv)
        V[k] = nv and true or false
        pcall(mod.write_file, file_of(k), V[k] and "1" or "0")
        return V[k]
    end
    function M.label(k)
        for i = 1, #LIST do
            if LIST[i][1] == k then return LIST[i][2] end
        end
        return k
    end
    return M
end)()

-- ============================================================================
-- v8.3.5：即时开关
-- 原门控方式是「setup 里判断，关掉就不装钩子 → 必须重启游戏」。
-- 现在改成「钩子/总线常驻，回调首行判开关」，勾选后下一帧就生效；
-- 不做热卸载（patchlib 卸载有原生崩溃风险），只让回调提前 return。
-- 例外：原版配方扩展（rcp）注册的是 Recipe 表项，无法撤销，仍保持重启生效。
-- ============================================================================
_G.mg_gated = function(k, fn)
    -- k 可以是单个 key，也可以是表（表内全部开启才执行）
    -- 用于「总开关 + 子开关」结构，例如 { "py", "py_dist" }
    local keys = type(k) == "table" and k or { k }
    return function(...)
        -- v8.9.17：所有走开关门控的回调，先统一过一道路世界判定。
        --   主菜单 / 世界生成期间直接返回 nil（prefix 视为不拦截，postfix 无副作用）。
        if not CHW or GENW then return nil end
        local G = _G.ms_gates
        if G then
            for i = 1, #keys do
                if not G.is(keys[i]) then return end
            end
        end
        return fn(...)
    end
end

-- ============ 模组设置 ============
local function gui_settings(g)
    if not jr_is_enabled then
        g.text("猛冲与跳跃：模块未加载")
        return
    end
    -- v2.11.33：左列勾选用 set_cursor(0,y) 逐行定位（认 y），右列按钮用 button_at(CENTER_X,y)（认 x）。
    --   两列共用同一套行 y（rowy(i)），因此严格上下配对；右列按钮左边缘全落 CENTER_X 这条竖线，
    --   与左列宽度彻底无关 => 严格对齐，绝不与开关重合。
    --   三个可调常量（改完立即生效）：
    --     CENTER_X 右列按钮左边缘的竖线（set_width(500)=>内容宽约476=>中线约238；整列左移改小、右移改大）
    --     TOP_Y    首行顶端 y（需让开上方页签栏；压到页签调大、离页签太远调小）
    --     ROW_H    行高（需 >= 按钮高 36，否则上下行重叠）
    local CENTER_X = 238
    -- v4.7.8：新增第三列（原右列 9 个按钮拆成两列：中列 5 个、右列 4 个）
    local CENTER_X2 = 458
    -- v2.15.4：按用户要求把行间距放宽（38 -> 44），不再拥挤；
    --   底边依旧贴住按钮（占位是相对 rowy(4) 的，改行高不会破环贴底效果）。
    local TOP_Y    = 46      -- v5.7.10：54 -> 46，收紧顶部抬头与页签之间的留白
    local ROW_H    = 40      -- v4.7.13：回到 40（36 时按钮上下紧贴、连成一整块块）
    -- v3.1.1：整页改成可滑动（参考「更好的体验」气候页的 begin_scroll 用法）
    --   面板高度收到「比遗忘之物开关稍高一点」：内容高 = TOP_Y + VP_H = 262
    --   遗忘之物按钮底边在 TOP_Y+4*40+36 = 250，262 刚好高出一截。
    local SCROLL = (type(g.begin_scroll) == "function" and type(g.end_scroll) == "function")
    -- v3.2.1：Dot神/DPS检测已移除，末行变成 rowy(8)（底边 356），
    --   视口 208 -> 176（面板再矮一截），内容 460 -> 360（消除底部大片留白）。
    local VP_H    = 208      -- v4.7.13：视口 208（面板高 262，与 v4.7.8 一致）
    local SCROLL_W = 720     -- v4.7.8：三列都要落在滚动区内（面板 760，内容宽约 736）
    -- v8.3.10：内容高改成「实测 + 跨帧记忆」。
    --   原来写死 1280，而实际末行 rowy(13) 的底边只有 552+36=588 —— 滚到底会剩一大片
    --   空白，滑块也被压到最短。现在由 rowy() 记录本帧画到的最大 y，收尾写回 _G，
    --   下一帧再喂给 begin_scroll。596 只是首帧兜底值，第二帧起自动校准。
    --   （本函数每帧重新进，local 留不住值，所以挂 _G。）
    local CONTENT_H = _G.ms_sp_content_h or 596
    local used_bottom = 0
    --   rowy 在滚动模式下返回「相对滚动区」的坐标（滚动区从 TOP_Y 起，内部原点归 0）
    local function rowy(i)
        -- v5.7.8：整体下移一行（i + 1），给页面最顶的「优雅永不过时」抬头腾出位置。
        --   这样所有调用方的行号都不用改，只改这一处。
        local y = TOP_Y + (i + 0.8) * ROW_H   -- v5.7.10：首行上移 8，缩小与抬头的距离
        if SCROLL then
            local ry = y - TOP_Y
            if ry + 36 > used_bottom then used_bottom = ry + 36 end   -- 记每行底边（按钮高 36）
            return ry
        end
        return y
    end
    local sp_sy = 0
    if SCROLL then
        local _, sy0 = g.begin_scroll("set_page", 0, TOP_Y, SCROLL_W, VP_H, SCROLL_W, CONTENT_H)
        sp_sy = tonumber(sy0) or 0
        if type(g.set_cursor) == "function" then g.set_cursor(0, 0) end
    end
    -- 左列：在第 i 行画一个勾选框（indent=true 时缩进一格表示二级项）
    local function lcheck(i, indent, label, value, on_change, xoff)
        -- v5.7.3：新增第 6 参 xoff（默认 0），供两列布局使用
        if type(g.set_cursor) == "function" then g.set_cursor(xoff or 0, rowy(i)) end
        -- v5.7.4：place() 里 `if(!same_line){cx=0}`，set_cursor 设的 x 会被下一句控件清掉。
        --   这里先 same_line() 把 same_line 标志立起来，place 就不会再清 cx。
        if xoff and xoff > 0 and type(g.same_line) == "function" then g.same_line() end
        if indent then g.text("　"); g.same_line() end
        local nv = g.checkbox(label, value)
        if nv ~= value then on_change(nv) end
    end
    -- 右列：在第 i 行画一个按钮（绝对定位到 CENTER_X）
    local function rbtn(i, label)
        return btn_at(g, CENTER_X, rowy(i), label)
    end

    -- ---------- v5.7.8：首块抬头「优雅永不过时」----------
    --   滚动区内部坐标 0 才是真的最顶（rowy(0) 现在 = 40），所以这里用 0。
    if type(g.set_cursor) == "function" then g.set_cursor(0, 0) end
    g.text("优雅永不过时")
    -- ---------- 行0：猛冲与跳跃 | 幸运儿 | 召神 ----------
    lcheck(0, false, "猛冲与跳跃", jr_is_enabled(), function(nv)
        jr_set_enabled(nv)
        pcall(mod.write_file, "dashroll_en.txt", nv and "1" or "0")
        notify(nv and "肉鸽瑞亚启动(^～^)" or "你只是个普通人⊙︿⊙")
    end)
    pcall(lk_gui, g, notify, CENTER_X, rowy(0))
    pcall(zs_gui, g, notify, CENTER_X2, rowy(0))

    -- ---------- 行1：翻滚无敌 | 快速放置 | 哨兵神 ----------
    lcheck(1, true, "翻滚无敌", jr_get_opt("iframe"), function(nv)
        jr_set_opt("iframe", nv)
        notify(nv and "你只是害怕了╥﹏╥" or "神不惧受伤￣へ￣")
    end)
    if ps_is_enabled then
        local pe = ps_is_enabled()
        local plabel = pe and "快速放置（已开启）" or "快速放置（已关闭）"
        if rbtn(1, plabel) then
            local npe = not pe
            pcall(mod.write_file, "ps_en.txt", npe and "1" or "0")
            ps_set_enabled(npe)
            notify(npe and "这手速，开挂了吧＼（〇_ｏ）／" or "V我50补充动力（＞ｙ＜）")
        end
    else
        g.text("快速放置：模块未加载")
    end

    -- ---------- 行2：翻滚后猛击 | 死亡回溯 | 协击神 ----------
    lcheck(2, true, "翻滚后猛击", jr_get_opt("add_buff"), function(nv)
        jr_set_opt("add_buff", nv)
        notify(nv and "翻滚是为了更好的抬头(◣_◢)" or "你这一击不够快，更不够狠(●__●)")
    end)
    if rv_is_enabled then
        local re = rv_is_enabled()
        local rlabel = re and "死亡回溯（已开启）" or "死亡回溯（已关闭）"
        if rbtn(2, rlabel) then
            local nre = not re
            pcall(mod.write_file, "rvplace_en.txt", nre and "1" or "0")
            rv_set_enabled(nre)
            notify(nre and "死亡不是终点，这一世我要(*￣︿￣)" or "回家不是害怕，家才是温暖的港湾 ( >_< )")
        end
    else
        g.text("死亡回溯：模块未加载")
    end

    -- ---------- 行3：动作优化 | 自动开袋 | 箭神 ----------
    if mp_is_enabled then
        lcheck(3, false, "动作优化", mp_is_enabled(), function(nv)
            pcall(mod.write_file, "mp_en.txt", nv and "1" or "0")
            mp_set_enabled(nv)
            notify(nv and "优雅永不过时（＾ω＾）" or "雅到极致便是俗╮(╯▽╰)╭")
        end)
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(3)) end
        g.text("动作优化：模块未加载")
    end
    pcall(EXT.sn.gui, g, notify, CENTER_X2, rowy(1))

    -- ---------- 行4：自动重铸（主开关，默认关闭）----------
    --   行5~10 是六个饰品词缀，互斥单选（切换制），选中哪个就刷哪个
    if _G.rf_is_enabled then
        lcheck(4, false, "自动重铸", _G.rf_is_enabled(), function(nv)
            _G.rf_set_enabled(nv)
            notify(nv and "你敢靠近我一步吗？o_O???" or "你已穷哭╥﹏╥")
        end)
        if _G.rf_get_acc and _G.rf_set_acc then
            local ACCS = {
                { id = 65, name = "护佑" },
                { id = 68, name = "幸运" },
                { id = 72, name = "险恶" },
                { id = 76, name = "迅捷" },
                { id = 80, name = "暴力" },
                { id = 66, name = "奥秘" },
            }
            local cur = _G.rf_get_acc()
            for i = 1, #ACCS do
                local a = ACCS[i]
                local want = (cur == a.id)
                lcheck(4 + i, true, a.name, want, function(nv)
                    -- 单选：只有勾上才算切换；取消勾选一律忽略（下一帧会画回选中态）
                    if nv and not want then
                        _G.rf_set_acc(a.id)
                        notify("已切换至" .. a.name)
                    end
                end)
            end
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(4)) end
        g.text("自动重铸：模块未加载")
    end

    -- ---------- 行11：遗忘之物 | 地图传送 | 星神 ----------
    if fi_is_enabled then
        lcheck(11, false, "遗忘之物", fi_is_enabled(), function(nv)
            pcall(mod.write_file, "fi_en.txt", nv and "1" or "0")
            fi_set_enabled(nv)
            notify(nv and "你已是完全之龙了！（＞ｙ＜）" or "你似乎遗忘了什么？o_O???")
        end)
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(4)) end
        g.text("遗忘之物：模块未加载")
    end
    -- ---------- 行12：起源重构（默认关闭）----------
    if EXT.om and EXT.om.is_enabled then
        lcheck(12, false, "起源重构", EXT.om.is_enabled(), function(nv)
            if not EXT.om.set_enabled(nv) then
                notify("起源重构：启用失败，请查看内核日志")
                return
            end
            notify(nv and "重构体来袭＼(〇_ｏ)／" or "世界恢复宁静(^～^)")
        end)
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(12)) end
        g.text("起源重构：模块未加载")
    end
    pcall(EXT.sx.gui, g, notify, CENTER_X2, rowy(2))
    if ab_is_enabled then
        local ae = ab_is_enabled()
        local alabel = ae and "自动开袋（已开启）" or "自动开袋（已关闭）"
        if rbtn(3, alabel) then
            local nae = not ae
            pcall(mod.write_file, "ab_en.txt", nae and "1" or "0")
            ab_set_enabled(nae)
            notify(nae and "袋子自己会开，你只管收割 (￣▽￣)" or "袋子又合上了 (・_・;)")
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(CENTER_X, rowy(3)) end
        g.text("自动开袋：模块未加载")
    end
    -- ---------- 行4 中列：你不准死（靠近护士自动治疗，默认关闭）----------
    --   放在「自动开袋」正下方。半径 25 格、扣钱固定走原版，不开放设置。
    if _G.nst_is_enabled then
        local ne = _G.nst_is_enabled()
        local nlabel = ne and "你不准死（已开启）" or "你不准死（已关闭）"
        if rbtn(4, nlabel) then
            local nne = not ne
            _G.nst_set_enabled(nne)
            notify(nne and "你不准死(*￣︿￣)" or "没钱还想治疗？＼(〇_ｏ)／")
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(CENTER_X, rowy(4)) end
        g.text("你不准死：模块未加载")
    end
    -- ---------- 行5 中列：自动钓鱼（10 倍浮标 + 血月不钓怪，默认关闭）----------
    if _G.fh_is_enabled then
        local fhe = _G.fh_is_enabled()
        local fhlabel = fhe and "自动钓鱼（已开启）" or "自动钓鱼（已关闭）"
        if rbtn(5, fhlabel) then
            local nfhe = not fhe
            _G.fh_set_enabled(nfhe)
            notify(nfhe and "自动钓鱼，愿者上钩(〃ω〃)"
                       or  "祝你不要空军（＾ω＾）")
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(CENTER_X, rowy(5)) end
        g.text("自动钓鱼：模块未加载")
    end
    -- v8.9.80：你不准死 → 自动钓鱼 → 地图传送 → 一键点亮
    pcall(EXT.mm.gui, g, notify, CENTER_X, rowy(6))
    pcall(ag_gui, g, notify, CENTER_X2, rowy(3))
    if star_is_enabled then
        local se = star_is_enabled()
        local slabel = se and "星神（已开启）" or "星神（已关闭）"
        if btn_at(g, CENTER_X2, rowy(4), slabel) then   -- v4.7.18：右列按钮必须用 CENTER_X2，rbtn 写死的是中列
            local nse = not se
            pcall(mod.write_file, "star_en.txt", nse and "1" or "0")
            star_set_enabled(nse)
            notify(nse and "300颗够吗？(*^▽^*)" or "星星都回去了 (￣ω￣)")
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(CENTER_X2, rowy(4)) end
        g.text("星神：模块未加载")
    end
    -- ---------- 行5 右列：Dot流（与地图传送同行）；行7 中列：一键点亮 ----------
    pcall(lm_gui, g, CENTER_X, rowy(7))
    if dot_label then
        if btn_at(g, CENTER_X2, rowy(5), dot_label()) then
            notify(dot_cycle())
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(CENTER_X2, rowy(5)) end
        g.text("Dot流：模块未加载")
    end
    -- ---------- 行13：全武器成长（默认关闭）----------
    if EXT.wg and EXT.wg.is_enabled then
        lcheck(13, false, "全武器成长", EXT.wg.is_enabled(), function(nv)
            if not EXT.wg.set_enabled(nv) then
                notify("全武器成长：启用失败，请查看内核日志")
                return
            end
            notify(nv and "你独自升级，成长世界最强(◣_◢)" or "开局就是巅峰怎么输o_O???")
        end)
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(13)) end
        g.text("全武器成长：模块未加载")
    end
    -- ---------- 行14：分隔线（v10.3.0 全武器成长占走行13，整体再下移一行）----------
    if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(14) + 6) end
    if type(g.separator) == "function" then
        g.separator()
    else
        g.text("─────────")
    end
    -- ---------- 行7 横线下方：抬头「巅峰时代」（v5.7.4：由 rowy(8)+12 上提到 rowy(7)+26，缩小留白）----------
    if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(14) + 12) end
    g.text("巅峰时代")
    -- ---------- 行8~11：巅峰时代 11 项（横线下方另起一块，三列网格，按 Info.json 顺序）----------
    -- v4.7.26：按钮框 200 -> 236（「幽灵兜帽套（已关闭）」这类长名不再出框），三列位置随之右移
    if peak_label then
        local PKEYS = { "ghost", "obsidian", "terra", "blade", "typhoon",
                        "phantasm", "holy", "unholy", "jester", "crystal", "chloro" }
        local COLS = { 0, 242, 484 }
        for i = 1, #PKEYS do
            local k = PKEYS[i]
            local col = (i - 1) % 3
            local row = 15 + math.floor((i - 1) / 3)  -- v10.3.0：再插一行，网格整体 +1
            if btn_at(g, COLS[col + 1], rowy(row), peak_label(k), 236) then
                notify(peak_toggle(k))
            end
        end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(14) + 12) end
        g.text("巅峰时代：模块未加载")
    end
    -- ---------- 行12：分隔线（v5.7.9：随网格上移一行）----------
    if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(19) + 6) end
    if type(g.separator) == "function" then
        g.separator()
    else
        g.text("─────────")
    end
    -- ---------- 行13 横线下方：抬头「更好的体验」（v5.7.6：+20 让开关组正好贴着它）----------
    if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(19) + 8) end
    g.text("更好的体验")
    -- ---------- 行15~31：15 个开关 + 1 个滑块 ----------
    --   二级项用 indent=true（lcheck 内部会先打一个全角空格再 same_line）。
    --   探测/晶塔是「总开关 + 子项」结构：总开关关掉子项不起作用，但子项状态会记住。
    if _G.ms_gates then
        local G = _G.ms_gates
        -- v5.7.5：两列改成「整组分配」——一个组（父项 + 全部子项）整体落在同一列，
        --   否则子项会被拆到另一列，看起来跟父项分家。
        --   分列策略：按组顺序走，每组放到当前较短的那一列（贪心平衡）。
        local BASE_ROW = 19     -- v10.3.0：全武器成长再插一行
        local COL_X = 360
        local GROUPS = {
            { "vm" },
            { "lp" },
            { "sn", "sn_creature", "sn_treasure", "sn_danger" },
            { "py", "py_dist", "py_danger", "py_multi", "py_npc" },
            { "zm" },
            -- v9.2.0：af / af_potion / cft 三项已移除（增益家具、药水常驻、随身制作站）
            { "cs" },
            { "dm" },
            { "nh", "ng" },   -- v8.9.3：城镇NPC无敌紧跟「NPC 快速回家」，同组保证同列相邻
            { "lh" },
            { "rcp" },
        }
        local zm_min = G.num("zm_min") or 0.36
        local function label_of(k)
            if k == "zm" then return string.format("缩放扩展（最小缩放 %.2f）", zm_min) end
            return G.label(k)
        end
        local rowL, rowR = 0, 0
        local function put(k, right, r)
            local lbl = label_of(k)
            lcheck(r, G.indent(k), lbl, G.is(k), function(nv)
                G.set(k, nv)
                -- v8.7.0：召唤物不消耗用专属播报
                if k == "cs" then
                    notify(nv and "生命不息，战斗不止⊙︿⊙"
                               or  "快速肝召唤物材料吧(·へ·)")
                    return
                end
                if k == "ng" then
                    notify(nv and "城镇的居民不会受伤了（＾ω＾）"
                               or  "城镇的居民需要你的保护 (>_<|||")
                    return
                end
                -- v8.3.5：除「原版配方扩展」外都是一改就生效
                local tail = (k == "rcp") and "（重启游戏生效）" or "（立即生效）"
                notify(lbl .. "：" .. (nv and "已开启" or "已关闭") .. tail)
            end, right and COL_X or 0)
        end
        for _, grp in ipairs(GROUPS) do
            local useRight = (rowR < rowL)      -- 右列更短就放右边
            local base = useRight and rowR or rowL
            for _, k in ipairs(grp) do
                base = base + 1
                put(k, useRight, BASE_ROW + base)
            end
            if useRight then rowR = base else rowL = base end
        end
    end
    -- 面板高度的原理：button_at 是绝对定位，不参与面板内容尺寸计算，所以必须补一个
    --   流式控件（空格文本）把面板撑起来，否则末行按钮会被下沿裁掉。
    --   v2.15.3：占位文本从 rowy(4)+40 上提到 rowy(4)+20 —— 让「空格的底边」正好压在
    --   末行按钮的底边（rowy(4)+36）上，面板下沿就紧贴按钮，不再多出一整行空白。
    --   v2.19.2：右下新增「我就是箭神」一行，一键点亮下移到 rowy(5)，占位同步跟到 rowy(5)。
    --   v2.19.3：按用户要求再向下预留两格（占位改 rowy(7)+20），给后续两个新按钮留位置，
    --            加按钮时只需接在 rowy(6)/rowy(7)，不必再动面板高度。
    --   v2.19.4：右下新增「哨兵神」；v2.19.7 按用户要求把它提到召神正下方（rowy(4)），
    --            箭神顺延到 rowy(5)，一键点亮 rowy(6)；占位仍为 rowy(7)+20，刚好贴底。
    --   v2.19.8：新增「协击神」占 rowy(5)，箭神顺延 rowy(6)、一键点亮 rowy(7)，
    --            占位跟到 rowy(8)+20（两格预留到此刚好用满）。
    --   这就是召唤生物页那种贴底的观感；纯靠调整数值，不改任何布局结构，无裁切风险。
    -- v3.1.1：滚动模式下由 end_scroll + set_content_height 决定面板高度；
    --   加载器不支持滚动时退回旧做法（占位文本撑高面板，内容平铺全部可见）。
    if SCROLL then
        g.end_scroll()
        -- v8.3.10：把本帧实测的内容底边记下来，下一帧给 begin_scroll 用（底部留 10）
        if used_bottom > 0 then _G.ms_sp_content_h = used_bottom + 10 end
        -- 注意：这里画滚动条用的仍是 CONTENT_H（本帧 begin_scroll 实际传进去的值），
        --   不能用刚更新的 used_bottom，否则滑块位置会和内核滚动状态差一帧。
        if _G.ms_fat_scroll then pcall(_G.ms_fat_scroll, g, 0, TOP_Y, SCROLL_W, VP_H, sp_sy, CONTENT_H) end
        if type(g.set_content_height) == "function" then g.set_content_height(TOP_Y + VP_H) end
    else
        if type(g.set_cursor) == "function" then g.set_cursor(0, rowy(26) + 20) end
        g.text(" ")
    end
end
-- ============================================================================
-- v8.3.9：把滚动条画粗
-- ----------------------------------------------------------------------------
-- 内核的滚动条是 C++ 里写死的（src/gui/gui_lua.inc / end_scroll）：
--     float track = std::max(3.0f, 5 * g_scale);
--     draw_rect(bounds.x + bounds.w - track, y, track, thumb, kBorder);
-- 可见宽度只有 5*scale，手机上约 5~10 像素，手指很难瞄准，这就是「点不到」的来源。
--
-- 但内核的「可拖动判定带」是另一套逻辑（l_gui_begin_scroll）：
--     m.begin(..., g_mouse_x >= bounds.x + w - 12 * g_scale)
-- 也就是右边缘 12*scale 宽的一整条带都能按下拖动，比画出来的粗 2.4 倍。
--
-- 所以不用改内核：end_scroll() 之后在同样的位置补画一条 12 宽的轨道 + 滑块。
-- 用户看到的是粗条，点它正好落进内核判定带，拖动仍由内核原生处理，
-- 一行拖动逻辑都不用自己写，也不会和内核的滚动状态打架。
-- ----------------------------------------------------------------------------
_G.ms_fat_scroll = function(g, x, y, w, h, sy, content_h)
    if type(g) ~= "table" or type(g.rect) ~= "function" then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    if type(w) ~= "number" or type(h) ~= "number" then return end
    if type(content_h) ~= "number" or type(sy) ~= "number" then return end
    if h <= 0 then return end
    if content_h <= h + 1 then return end          -- 内容没超出视口，不需要滚动条
    local maxy = content_h - h
    if maxy <= 0 then return end
    local ty = sy
    if ty < 0 then ty = 0 end
    if ty > maxy then ty = maxy end

    local TRACK_W = 12                             -- 与内核 12*scale 判定带对齐
    local tx = x + w - TRACK_W
    local thumb_h = h * h / content_h
    if thumb_h < 40 then thumb_h = 40 end          -- 太短同样难点，兜到 40
    if thumb_h > h then thumb_h = h end
    local th_y = y + (h - thumb_h) * (ty / maxy)

    pcall(g.rect, tx, y, TRACK_W, h, { 18, 22, 44, 130 })                -- 轨道
    pcall(g.rect, tx, th_y, TRACK_W, thumb_h, { 170, 182, 210, 230 })    -- 滑块
end

-- v5.9.3：皮肤加载重试用的计数（挂 _G，主 chunk 的 local 已满 200）
skin_fail_cnt = skin_fail_cnt or 0
skin_retry_tick = skin_retry_tick or 0
local collapsed_init = false
local skin_loaded = false
local cur_page = 1   -- v4.7.0：1=生成物品 2=召唤生物 3=改变世界 4=玩家属性 5=模组设置 6=一键建造

local PAGE_NAMES = { "生成物品", "召唤生物", "改变世界", "玩家属性", "模组设置", "一键建造" }

function mod.on_gui()
    local g = mod.gui
    -- v8.9.30：撤掉 v8.9.18 加的主菜单「只画一行提示」。
    --   那版是为了排查崩溃临时加的，结果主菜单看不到图标也打不开面板，
    --   和 v8.9.10 的表现不一致。现在崩溃原因已经定位到 tg 模块，这里恢复原样。
    -- v4.7.0：一键建造页 —— 整块面板交给它，合集这边一个东西都不画
    if _G.ms_instant_back then
        _G.ms_instant_back = false
        cur_page = 1
    end
    if cur_page == 6 then
        if _G.ms_instant then
            _G.ms_instant.draw()
        else
            g.text("一键建造：模块未加载")
        end
        return
    end
    -- v2.8.9 加固：窗口控制接口逐个做存在性判断。
    --   加载器版本变动导致某个接口缺失/改名时，只降级不报错，
    --   避免一句调用抛错打断整个面板绘制（控件类调用不在此列——
    --   它们真的缺失就代表加载器已不兼容，不属于“加固”能救的范围）。
    if type(g.set_title) == "function" then
        g.set_title(" ", " ") -- v2.11.20：恢复自定义皮肤（圆角图），图标位回到空格
    end
    if type(g.set_width) == "function" then
        g.set_width(760) -- v4.7.2：620 -> 760（6 个页签：一键建造被挤到面板外）
    end
    -- 配色与收起入口跟学 CreativeMenu v1.1.0（皮肤图收起入口；图片加载失败时回退纯色方块）
    if type(g.set_style) == "function" then
    g.set_style({
        -- v4.7.0：配色统一为一键建造那套（深蓝）
        panel = { 33, 43, 102, 245 },
        title = { 50, 60, 130, 255 },
        -- v9.0.5：流式按钮（页签 / 上一页下一页 / 物品名 / 召唤名）原先用
        --   63,80,150，与面板底色 33,43,102 太接近，看上去像「没有框」。
        --   模组设置页走的是圆角图按钮（button_36.png，带浅色描边），
        --   所以同一个面板里两种按钮明暗不一致。这里把流式按钮提亮，
        --   让两处的亮度对齐（形状仍受加载器限制为直角）。
        button = { 92, 118, 190, 255 },
        hover = { 116, 145, 220, 255 },
        active = { 74, 80, 90, 255 },
        border = { 14, 15, 18, 255 },
        text = { 235, 237, 229, 255 },
        -- 注：v3.1.3 试过 rounding / button_rounding / frame_rounding，加载器不认，已撤。
        --     按钮圆角受限于加载器的 ImGui::Button（直角），只能等它支持。
    })
    end
    -- v5.9.3：skin_loaded 只表示「尝试过」。若整段失败（load_image 抛错、拿不到 ID），
    --   允许再试最多 3 次（私有目录首次可能还没部署完），避免一次性失败后永久无皮肤。
    if (not skin_loaded) or (skin_fail_cnt > 0 and skin_fail_cnt < 3 and skin_retry_tick > 120) then
        if not skin_loaded then skin_loaded = true end
        skin_retry_tick = 0
        local ok = pcall(function()
            -- v4.7.3：图标用模组合集自己的 launcher.png，只共用一键建造的面板底图
            local panel = _G.ms_load_img and _G.ms_load_img(g, "panel_skin.png")
            local icon  = _G.ms_load_img and _G.ms_load_img(g, "launcher.png")
            -- v5.3.2：圆角按钮底图（中心色 63,80,150 与 set_style 的 button 一致）。
            -- 挂到 _G 而不是新增 local ——主 chunk 的 local 已满 200。
            _G.ms_btn_img = _G.ms_load_img and _G.ms_load_img(g, "button_36.png")
            -- v2.11.20：圆角用「圆角面板图 + 九宫格边距」实现（v2.11.18 已验证有效），半径 16 -> 20
            _G.ms_skin_panel = panel
            _G.ms_skin_icon  = icon
            if panel and icon and type(g.set_skin) == "function" then
                -- v5.3.3：border 12 -> 18，配合圆角面板图（四角 18x18 保留、中间拉伸）
                -- v5.3.6：edge 必须传 0！images::draw 里 target = edge>0 ? edge : b，
                --   传 8 会把圆角四角压成 8px、被中间拉伸区填平，看起来就是直角。
                g.set_skin(panel, 18, icon, 24, 0)   -- v5.3.7：圆角改回 18（edge 仍须 0）
            end
            g.set_pos(8, 92)  -- v4.7.7：再往上 3（95 -> 92）
        end)
        if not ok then
            skin_fail_cnt = skin_fail_cnt + 1
            mod.warn("皮肤加载失败，使用默认样式（第 " .. skin_fail_cnt .. " 次）")
        elseif _G.ms_btn_img == nil then
            skin_fail_cnt = skin_fail_cnt + 1   -- 没抛错但图片没拿到，也算失败
        end
    end
    if skin_fail_cnt > 0 and skin_fail_cnt < 3 and skin_retry_tick < 121 then
        skin_retry_tick = skin_retry_tick + 1
    end
    -- v9.0.4：撤销 v9.0.3 的「每帧重设 set_skin / set_pos」。
    --   实测有两个副作用：
    --   ① 每帧重设皮肤会让按钮底图每帧重新绑定，按钮框要等几帧才出现；
    --   ② 每帧 set_pos 会把玩家拖动窗口的位置按回去 —— 表现为面板不动、
    --      只有内容跟着手指走。
    --   皮肤冲突的真正来源是「别的模组也调 set_skin / load_image」，
    --   已在那两个模组侧去掉，这里不需要每帧重设。
    -- v2.8.9 加固：加载器没有 set_collapsed 时保持展开（不强行收起）
    if not collapsed_init and type(g.set_collapsed) == "function" then
        collapsed_init = true
        g.set_collapsed(true)   -- 开局默认收起，点图标展开
    end
    if not ready then
        g.text("初始化失败：缺少关键类型/字段，请查看日志。")
        return
    end
    if type(g.is_collapsed) == "function" and g.is_collapsed() then return end
    -- 页签栏（v2.7.4：按用户要求去掉方括号，直接用页签名）
    -- v9.0.7：页签改用圆角图按钮（btn_at），与物品页 / 设置页同款；绝对定位
    if _G.ms_btn_at and type(g.set_cursor) == "function" then
        for i, name in ipairs(PAGE_NAMES) do
            if _G.ms_btn_at(g, PAGER.TAB_STEP * (i - 1), PAGER.TAB_Y, name, PAGER.TAB_W) then
                cur_page = i
            end
        end
        g.set_cursor(0, PAGER.TAB_Y + PAGER.TAB_H + PAGER.TAB_GAP)
    else
        for i, name in ipairs(PAGE_NAMES) do
            if i > 1 then g.same_line() end
            if g.button(name) then cur_page = i end
        end
    end
    g.separator()
    if cur_page == 5 then
        gui_settings(g)
    elseif cur_page == 4 then
        -- v2.10.0：玩家属性页（只读展示）
        if at_gui then at_gui(g) else g.text("玩家属性：模块未加载") end
    elseif cur_page == 3 then
        -- v4.6.1：月相页升级为「改变世界」，含时间 / 天气 / 旅途力量
        if _G.ms_world then _G.ms_world.gui(g) else gui_moon(g) end
    elseif cur_page == 2 then
        gui_npcs(g)
    else
        -- v4.6.0：生成物品页（物品浏览 / 名称拼音搜索 / 生成）
        if _G.ms_gui_items then
            _G.ms_gui_items(g)
        else
            g.text("生成物品：模块未加载")
        end
    end
end

-- ============ 初始化（召唤部分） ============
local function summon_setup()
    T_main   = patch.get_type("Terraria", "Main")
    T_player = patch.get_type("Terraria", "Player")
    T_npc    = patch.get_type("Terraria", "NPC")
    T_lang   = patch.get_type("Terraria", "Lang")
    if not T_main or not T_player or not T_npc or not T_lang then
        mod.error("获取类型失败 (Main/Player/NPC/Lang)")
        return
    end

    F_main_player = find_field(T_main, "player")
    F_my_player   = find_field(T_main, "myPlayer")
    if not F_my_player then F_my_player = find_field(T_main, "<myPlayer>k__BackingField") end

    F_pos    = find_field(T_player, "position")
    F_width  = find_field(T_player, "width")
    F_height = find_field(T_player, "height")
    F_direction = find_field(T_player, "direction")
    if not F_direction then F_direction = find_field(T_player, "<direction>k__BackingField") end

    F_moon_phase = find_field(T_main, "moonPhase")
    if not F_moon_phase then F_moon_phase = find_field(T_main, "<moonPhase>k__BackingField") end

    local my_prop = patch.get_property(T_main, "myPlayer")
    if my_prop then M_get_my_player = patch.property_get_method(my_prop) end
    if not M_get_my_player then M_get_my_player = patch.get_method(T_main, "get_myPlayer", 0) end

    local moon_prop = patch.get_property(T_main, "moonPhase")
    if moon_prop then
        M_get_moon = patch.property_get_method(moon_prop)
        if patch.property_set_method then M_set_moon = patch.property_set_method(moon_prop) end
    end
    if not M_get_moon then M_get_moon = patch.get_method(T_main, "get_moonPhase", 0) end
    if not M_set_moon and patch.get_method then
        M_set_moon = patch.get_method(T_main, "set_moonPhase", 1)
    end

    M_get_npc_name = patch.get_method(T_lang, "GetNPCNameValue", 1)

    M_new_text = patch.get_method(T_main, "NewText", 5) or patch.get_method(T_main, "NewText", 4)
    -- v2.7.0 健壮性（跟学 CreativeMenu v1.1.0）：老加载器可能没有 get_method_by_names，包 pcall 兜底
    local function method_by_names(type_handle, name, param_names)
        if not patch.get_method_by_names then return nil end
        local ok, m = pcall(patch.get_method_by_names, type_handle, name, param_names)
        return ok and m or nil
    end
    M_new_npc  = patch.get_method(T_npc, "NewNPC", 10)
        or method_by_names(T_npc, "NewNPC",
            { "source", "X", "Y", "Type", "Start", "ai0", "ai1", "ai2", "ai3", "Target" })
        or patch.get_method(T_npc, "NewNPC")

    if not (F_main_player and F_pos and M_new_npc and M_get_npc_name) then
        mod.error(string.format(
            "关键句柄缺失: player=%s pos=%s newNpc=%s npcName=%s",
            tostring(F_main_player ~= nil), tostring(F_pos ~= nil),
            tostring(M_new_npc ~= nil), tostring(M_get_npc_name ~= nil)))
        return
    end

    ready = true
end

-- ============================================================================
-- 第二部分：更好的猛冲与跳跃 (Better Dash & Roll) v2.0.0（由独立模组合并）
-- 原 pkg: lua.bluefish.jumproll。翻滚/撞击无敌帧/翻滚后猛击，Player.Update hook 驱动。
-- 改造点：setup -> jr_setup、cleanup -> jr_cleanup、新增 CFG.enabled 总开关门控。
-- ============================================================================
local P = mod.patch

-- ============================================================================
-- 调试日志（v1.0.14：不再写任何文件 —— 用户要求不生成 jumproll.log）
-- 仅保留内存环形缓冲（最近 200 条），异常时随 mod.error 一起带出，平时不落盘。
-- ============================================================================
-- v6.3.10：调试日志整段移除（不记录、不落盘、热路径不做 format/date）
-- 保留同名空函数，历史调用点无需改动
local function wlog() end
local function wlogf() end
local function wlog_w() end
local function dump_dbg() return "" end

-- ============================================================================
-- 配置
-- ============================================================================
local CFG = {
    enabled      = true,   -- 总开关
    only_local   = true,   -- 只对本地玩家生效（多人时其他人不动）
    roll_frames  = 30,     -- v1.0.6: 冲刺侧滚一轮帧数（30 帧 ≈ 0.50 秒，更慢更贴合冲刺滑行；想再慢可改大）
    air_frames   = 18,     -- 跳跃空翻时长（帧，18 帧 ≈ 0.30 秒，想更慢可改大，如 30 = 0.5秒）
    dash_vx      = 11,     -- v1.0.6: 判定"真正冲刺"的 velocity.X 阈值（真冲刺≈16，跑步≈6，突增到≥11才侧滚）
    iframe       = true,   -- v1.0.8: 翻滚无敌开关（true=翻滚期间附送短暂无敌帧，false=纯翻滚不无敌）
    iframe_time  = 0.17,   -- v2.0.0: 翻滚无敌时长【固定 0.17 秒】(≈10帧@60fps)，不再可从模组界面修改
    add_buff     = true,   -- v2.0.0: 翻滚后猛击开关（true=翻滚结束给【惊人一刻】增益 ParryDamageBuff=198，false=不加）
    allow_mount  = false,  -- 坐骑/矿车上是否也翻滚（默认否，避免与坐骑旋转冲突）
    }

-- v1.0.10/v1.0.11: 模组界面设置 —— Resources/config.json (schemaVersion:1 + values)
-- 开关/数值由 TEFManager 模组设置界面写入 config.json，main.lua 启动时读取覆盖 CFG。
-- （与「武器无敌帧自定义」模组同一套机制：Info.json settings 声明 + dkjson 解析 values）
-- 兼容存储两种形式：字符串 "true"/"false" 与 布尔 true/false。
local function load_config()
    -- v1.0.12: 全程 pcall 防御 —— 任何一步出错只记日志，绝不中断 setup（确保翻滚引擎照装）
    -- 1) 读文件
    local ok1, text = pcall(function() return mod.read_file("config.json") end)
    if not ok1 then
        wlog("load_config: mod.read_file 异常: " .. tostring(text))
        return
    end
    if not text then
        wlog("config.json 不存在，使用内置默认值")
        return
    end
    -- 2) require dkjson
    local dkjson
    local ok2, j = pcall(function() return require("dkjson") end)
    if ok2 then
        dkjson = j
    else
        wlog("load_config: require(dkjson) 异常: " .. tostring(j))
        return
    end
    -- 3) 解析 JSON
    local ok3, raw = pcall(dkjson.decode, text)
    if not ok3 or type(raw) ~= "table" or type(raw.values) ~= "table" then
        wlog("config.json 解析失败(" .. tostring(raw) .. ")，使用内置默认值")
        return
    end
    local v = raw.values
    -- 4) dump 原文前 240 字符，方便诊断手机端实际内容
    wlog("config.json 原文前240: " .. tostring(text):sub(1, 240))
    -- 5) 逐字段防御解析：单个字段异常只影响该字段
    local function pick(name, parse)
        local okP, res = pcall(parse)
        if not okP then
            wlog("config.json 字段[" .. tostring(name) .. "]解析异常: " .. tostring(res) .. "，使用默认值")
            return nil
        end
        return res
    end
    -- iframe：翻滚无敌开关
    local iframe = pick("iframe", function()
        if type(v.iframe) == "string" then
            return (v.iframe == "true" or v.iframe == "1")
        elseif type(v.iframe) == "boolean" then
            return v.iframe
        end
        return nil
    end)
    if iframe ~= nil then
        CFG.iframe = iframe
        wlogf("配置[iframe] = %s (来自 config.json)", tostring(CFG.iframe))
    else
        wlog("config.json 未含 iframe，使用默认值 (iframe=true)")
    end
    -- v2.0.0: 无敌帧时长【固定 0.17 秒】，界面已删除该输入项，不再从配置读取。
    --   （CFG.iframe_time 仅在内部给 give_immune 计算免疫窗口；旧 config.json 若残留 iframe_time 也不影响）
    -- add_buff：翻滚后猛击增益开关（v2.0.0 由「翻滚附加惊人一刻」改名）
    local addb = pick("add_buff", function()
        if type(v.add_buff) == "string" then
            return (v.add_buff == "true" or v.add_buff == "1")
        elseif type(v.add_buff) == "boolean" then
            return v.add_buff
        end
        return nil
    end)
    if addb ~= nil then
        CFG.add_buff = addb
        wlogf("配置[add_buff] = %s (来自 config.json)", tostring(CFG.add_buff))
    else
        wlog("config.json 未含 add_buff，使用默认值 (add_buff=true)")
    end
end

-- ============================================================================
-- v1.0.11: 翻滚附加【惊人一刻】增益（Terraria.ID.BuffID.ParryDamageBuff = 198）
-- ============================================================================
local BUFF_PARRY = 198   -- ParryDamageBuff：近战伤害大幅提升（原版格挡成功给的增益）
local BUFF_TIME  = 300   -- 300 帧 ≈ 5 秒（与原版格挡成功给的时长一致）
-- (v1.0.12: give_parry_buff 已下移到 H/fv 工具函数定义之后，消除前向引用)
-- ============================================================================
-- 字段句柄与工具
-- ============================================================================
local H = { p = {}, m = {}, mt = {} }
local hook_handle

local function fv(field, inst, t)
    if not field then return nil end
    local ok, v = pcall(P.get_field_value, field, inst, t or "int32")
    if ok then return v end
    return nil
end
local function fbool(field, inst) return fv(field, inst, "bool") end
local function fint(field, inst) return fv(field, inst, "int32") end
local function fvec2(field, inst)
    if not field then return nil, nil end
    local ok, x, y = pcall(P.get_field_vec2, field, inst)
    if ok then return x, y end
    return nil, nil
end
local function setf(field, inst, v, t)
    if not field then return false end
    local ok, err = pcall(P.set_field_value, field, inst, v, t or "float")
    if not ok then
        wlog_w("setf 失败 field=%s err=%s", tostring(field), tostring(err))
    end
    return ok
end
local function setv2(field, inst, x, y)
    if not field then return false end
    local ok, err = pcall(P.set_field_vec2, field, inst, x, y)
    if not ok then
        wlog_w("setv2 失败 field=%s err=%s", tostring(field), tostring(err))
    end
    return ok
end
local function invM(m)
    if not m then return nil end
    local ok, r = pcall(P.invoke, m, nil)
    if ok then return r end
    wlog_w("invoke 失败 m=%s", tostring(m))
    return nil
end

-- ============================================================================
-- v1.0.11: 翻滚附加【惊人一刻】增益（Terraria.ID.BuffID.ParryDamageBuff = 198）
-- v1.0.12: 此函数定义放在 H/fv 之后，保证引用时它们已绑定（消除前向引用崩溃）
-- 优先调用原版 Player.AddBuff（处理刷新/空槽/上限等细节），失败降级直写 buffType/buffTime 数组
-- ============================================================================
local function give_parry_buff(inst)
    local ok = false
    if H.p.addbuff then
        local p_ok, r = pcall(P.invoke, H.p.addbuff, inst, BUFF_PARRY, BUFF_TIME, false)
        if p_ok and r ~= false then
            ok = true
            wlogf("已附加惊人一刻buff(198) %d帧 (AddBuff)", BUFF_TIME)
        else
            wlog_w("AddBuff 调用失败(%s)，改用数组方式", tostring(r))
        end
    else
        wlog_w("AddBuff 方法未绑定，改用数组方式")
    end
    if not ok then
        local bt  = fv(H.p.buffType, inst, "object")
        local btm = fv(H.p.buffTime, inst, "object")
        if bt and btm then
            local n = P.array_length(bt)
            if n and n > 0 then
                -- 已有该增益 → 刷新时间
                for i = 0, n - 1 do
                    local t = P.array_at(bt, i, "int32") or 0
                    if t == BUFF_PARRY then
                        local cur = P.array_at(btm, i, "int32") or 0
                        if cur < BUFF_TIME then
                            P.array_set(btm, i, BUFF_TIME, "int32")
                        end
                        ok = true
                        break
                    end
                end
                -- 没有 → 找空槽写入
                if not ok then
                    for i = 0, n - 1 do
                        local t = P.array_at(bt, i, "int32") or 0
                        if t == 0 then
                            P.array_set(bt, i, BUFF_PARRY, "int32")
                            P.array_set(btm, i, BUFF_TIME, "int32")
                            ok = true
                            break
                        end
                    end
                end
            end
        end
        if ok then
            wlogf("已附加惊人一刻buff(198) %d帧 (数组方式)", BUFF_TIME)
        else
            wlog_w("give_parry_buff: 数组方式也未成功")
        end
    end
end

-- 沿继承链向上搜索字段（武器背显同款）
local function find_field(type_handle, name)
    local t, guard = type_handle, 0
    while t and guard < 16 do
        local f = P.get_field(t, name)
        if f then return f end
        t = P.get_parent(t)
        guard = guard + 1
    end
    return nil
end

-- ============================================================================
-- 翻滚状态机
-- ============================================================================
local roll_timer = 0    -- 剩余帧数
local roll_total = 14   -- 本次翻滚总帧数（算每帧角度用）
local g_roll_angle = 0.0 -- v1.0.4: 本轮翻滚已累计角度；v1.0.7: 角度按方向走正负（右=+顺时针，左=-逆时针）
local g_roll_dir = 1     -- v1.0.7: 本次翻滚方向（1=顺时针/向右，-1=逆时针/向左；触发时记录）
local prev_dash = 0     -- 上一帧 dashTime（可为负：向左冲刺 dashTime=-15）
local g_first_frame = true -- v1.0.5: 首帧标记（dashTime 可为负，不能用负值当未初始化标记）
local prev_vy = 0.0     -- 上一帧 velocity.Y（用速度判断跳跃）
local prev_vx = 0.0     -- v1.0.6: 上一帧 velocity.X（判定冲刺速度突变）
local prev_is_dash = false -- v1.0.6: 上一帧是否真在冲刺（速度突变上升沿）
local prev_jumping = false -- 上一帧 jumping（备用信号）
local g_stat = { dash = 0, jump = 0, jumpAlt = 0, jump2 = 0 } -- 统计

local function local_player(inst)
    if not CFG.only_local then return true end
    local who = fint(H.p.whoami, inst)
    local my  = fint(H.m.myplayer, nil)
    if who == nil or my == nil then return true end -- 取不到就放行
    return who == my
end

-- 是否处于会占用旋转的状态（躺床/爬绳/骑坐骑）
-- v1.0.3: 坐骑判定改为读 Mount._type —— 空 mount 对象(type=0)不算占用，
--         之前"mount 非 nil 即占用"导致翻滚永远被跳过（玩家没坐骑时 mount 也是非 nil 对象）
local g_busy_log = 0
local function rotation_busy(inst)
    local sit    = fbool(H.p.sit, inst)
    local pulley = fbool(H.p.pulley, inst)
    local mtype  = 0
    if not CFG.allow_mount then
        local mo = fv(H.p.mount, inst, "object")
        if mo then
            mtype = fint(H.mt.mount_type, mo) or 0
        end
    end
    if sit == true then
        if g_busy_log < 20 then g_busy_log = g_busy_log + 1; wlogf("busy跳过: sit=true") end
        return true
    end
    if pulley == true then
        if g_busy_log < 20 then g_busy_log = g_busy_log + 1; wlogf("busy跳过: pulley=true") end
        return true
    end
    if not CFG.allow_mount and mtype > 0 then
        if g_busy_log < 20 then g_busy_log = g_busy_log + 1; wlogf("busy跳过: mount_type=%d", mtype) end
        return true
    end
    return false
end

-- ============================================================================
-- v1.0.14: 撞击触发式无敌 —— 仿疾旋鼬冲撞：翻滚期间撞到敌怪 → immune=true + 0.17s
-- 原版机制(Player.cs:1403 immune / Update_NPCCollision)：伤害判定只看 immune 标志，
-- immuneTime 只是计数；必须先 immune=true 才有无敌。之前只写 immuneTime 所以全无效。
-- ============================================================================
local g_hit_fallback = false -- 枚举 NPC 不可用时降级为翻滚期间全程免疫
local function give_immune(inst)
    local t = math.max(0.0, math.min(0.5, CFG.iframe_time or 0.17))
    local target = math.floor(t * 60 + 0.5)
    if target > 0 then
        if H.p.immune then setf(H.p.immune, inst, true, "bool") end
        setf(H.p.immuneTime, inst, target, "int32")
        return true
    end
    return false
end
-- 检测玩家矩形与任意敌怪矩形是否相交（枚举 Main.npc，过滤 active/非友好/damage>0）
-- 返回 true=已撞击并给出无敌；false=本轮未撞击
local function check_npc_hit(inst)
    if not (H.m.npc_arr and H.p.npc_active) then
        -- 枚举不可用 → 降级：翻滚期间直接给无敌（碰撞结算前免疫，撞怪不掉血）
        if not g_hit_fallback then
            g_hit_fallback = true
            wlog("Main.npc 枚举不可用，降级为翻滚期间全程免疫")
        end
        return give_immune(inst)
    end
    local px, py = fvec2(H.p.position, inst)
    if px == nil then return false end
    local pw = fint(H.p.width, inst) or 20
    local ph = fint(H.p.height, inst) or 42
    local ok, arr = pcall(P.get_field_value, H.m.npc_arr, nil, "object")
    if not ok or not arr then
        return give_immune(inst) -- 降级
    end
    local okL, len = pcall(P.array_length, arr)
    if not okL or type(len) ~= "number" or len < 0 or len > 2000 then
        return give_immune(inst) -- 降级
    end
    for i = 0, len - 1 do
        local okN, npc = pcall(P.array_at, arr, i, "object")
        if okN and npc then
            local active = fbool(H.p.npc_active, npc)
            if active == true then
                local friendly = fbool(H.p.npc_friendly, npc)
                local dmg = fint(H.p.npc_damage, npc) or 0
                if friendly ~= true and dmg > 0 then
                    local nx, ny = fvec2(H.p.npc_position, npc)
                    if nx ~= nil then
                        local nw = fint(H.p.npc_width, npc) or 0
                        local nh = fint(H.p.npc_height, npc) or 0
                        if px < nx + nw and px + pw > nx and py < ny + nh and py + ph > ny then
                            give_immune(inst)
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end
-- ============================================================================
-- Player.Update postfix（主逻辑）
-- ============================================================================
local g_upd_n = 0
local g_roll_log = 0 -- v1.0.3: 执行翻滚日志条数（放开诊断）
local function jroll_upd_body(inst, args)
    if type(inst) == "userdata" then attr_cache_inst = inst end -- v2.10.10 属性页实例缓存

        -- 菜单里不处理
        local gm = invM(H.m.game_menu)
        if gm == true then return end
        -- 只处理本地玩家
        if not local_player(inst) then return end

        -- 读状态（全部记录值，便于诊断）
        local dash    = fint(H.p.dashTime, inst) or 0
        local vx, vy  = fvec2(H.p.velocity, inst)
        if vx == nil then vx = 0.0 end
        if vy == nil then vy = 0.0 end
        local jumping = fbool(H.p.jumping, inst) or false
        if g_upd_n <= 3 then
            wlogf("  dash=%d vx=%.2f vy=%.2f jumping=%s prev_dash=%d prev_vx=%.2f prev_vy=%.2f",
                dash, vx, vy, tostring(jumping), prev_dash, prev_vx, prev_vy)
        end

        -- 触发①：冲刺侧滚 —— 真正冲刺 = velocity.X 突增到 ≥ CFG.dash_vx（真冲刺≈16，跑步≈6）
        -- v1.0.6 关键修复：dashTime=±15 只是"双击判定预备帧"（PC源码 dashing 尚未开始、velocity 还没加速），
        --                 旧代码在预备帧就触发翻滚 → ①走路快速拨动摇杆被判成冲刺也翻滚；②翻滚比真正冲刺提前开始。
        --                 现改为检测 velocity.X 从 <阈值 突变到 ≥阈值（真正冲刺在位移那一刻），方向取 vx 符号。
        local is_dash_now = math.abs(vx) >= CFG.dash_vx
        if g_first_frame then
            g_first_frame = false
            prev_vx = vx
            prev_is_dash = is_dash_now -- v1.0.6: 首帧同步冲刺状态，避免进图瞬间误触发翻滚
        end
        if is_dash_now and not prev_is_dash then
            roll_timer = CFG.roll_frames
            roll_total = CFG.roll_frames
            g_roll_angle = 0.0 -- v1.0.4: 重置累计角度
            g_stat.dash = g_stat.dash + 1
            local dirv = (vx >= 0) and 1 or -1
            g_roll_dir = dirv -- v1.0.7: 记录翻滚方向 = 冲刺方向（右正左负）
            wlogf(">> 冲刺触发 side-roll (vx=%.1f 方向=%s) 第%d次 一圈=%d帧", vx, (dirv == 1) and "右" or "左", g_stat.dash, CFG.roll_frames)
            local dt = fint(H.p.dashType, inst)
            wlogf("   dashType=%s dashDelay=%s", tostring(dt), tostring(fint(H.p.dashDelay, inst)))
        end
        prev_is_dash = is_dash_now
        prev_dash = dash -- v1.0.6: 仅保留诊断用（不再参与触发）

        -- 触发②：跳跃空翻
        -- 主信号：velocity.Y 明显转负（vy 突变到 < -2.0，排除走路下坡/小颠簸的小负值）——最可靠
        -- 备用信号：jumping 字段 false->true（仅当速度方式本轮未命中时使用，避免同一次跳双触发）
        local jump_trigger = false
        if vy < -2.0 and prev_vy >= -2.0 then
            jump_trigger = true
            g_stat.jumpAlt = g_stat.jumpAlt + 1
            wlogf(">> 跳跃触发 air-roll (vy=%.2f) 速度方式第%d次", vy, g_stat.jumpAlt)
        elseif jumping and not prev_jumping then
            jump_trigger = true
            g_stat.jump = g_stat.jump + 1
            wlogf(">> 跳跃触发 air-roll (jumping字段) 字段方式第%d次", g_stat.jump)
        end
        -- v1.0.4: 新增二段跳信号——上升途中再按跳（气球束等）：vy 已为负时突然更负（跳跃冲量）
        -- （之前只检测 vy 从 ≥-0.5 跳到 < -0.5 的上升沿，二段跳发生在上升途中不满足）
        if not jump_trigger and prev_vy < -2.0 and vy < prev_vy - 2.0 then
            jump_trigger = true
            g_stat.jump2 = g_stat.jump2 + 1
            wlogf(">> 跳跃触发 air-roll (vy=%.2f prev=%.2f) 二段跳第%d次", vy, prev_vy, g_stat.jump2)
        end
        if jump_trigger then
            roll_timer = CFG.air_frames
            roll_total = CFG.air_frames
            g_roll_angle = 0.0 -- v1.0.4: 重置累计角度
            local jd = fint(H.p.direction, inst) or 1
            if jd == 0 then jd = 1 end
            g_roll_dir = jd -- v1.0.7: 跳跃空翻方向 = 人物朝向（右正左负，前空翻）
        end
        prev_vy = vy
        prev_jumping = jumping

        -- 执行翻滚
        if roll_timer > 0 then
            if rotation_busy(inst) then
                -- 状态被占用：不旋转但走完倒计时（直接清零复位）
                roll_timer = 0
                setf(H.p.fullRot, inst, 0.0, "float")
                return
            end
            local dir = fint(H.p.direction, inst) or 1
            if dir == 0 then dir = 1 end
            -- v1.0.7 修复翻滚方向：角度按 g_roll_dir 走正负（右=0→2π 顺时针，左=0→-2π 逆时针）
            -- （v1.0.4 曾假设"正角度+方向镜像=向左翻滚"，实测镜像不生效 → 左冲刺也往右滚；
            --   PC源码 fullRotation 支持负值（Player.cs:4211 -fullRotation / 12594 Math.Sign），直接负角度最可靠）
            local step = (2.0 * math.pi) / roll_total
            g_roll_angle = g_roll_angle + step * g_roll_dir
            local newv = g_roll_angle
            setf(H.p.fullRot, inst, newv, "float")
            -- v1.0.4: 旋转原点改 (w/2, h/2)（身体中部），对齐蹦蹦跷翻滚中心
            -- （旧版 (w/2, h) 是脚底位置，看起来中心太靠下）
            local w = fint(H.p.width, inst) or 20
            local h = fint(H.p.height, inst) or 42
            setv2(H.p.rotOrigin, inst, w * 0.5, h * 0.5)
            -- v1.0.14: 撞击触发式无敌（仿疾旋鼬冲撞）——翻滚期间撞到敌怪才给
            --   immune=true + immuneTime(0.17s)。v1.0.13 的"每帧补 immuneTime"被实测无效的
            --   真正根因：Player.immune(Player.cs:1403) 是独立布尔标志，原版伤害判定只看它，
            --   只写 immuneTime 数值、不写 immune=true → 游戏永远不当回事，照常掉血。
            if CFG.iframe then
                check_npc_hit(inst)
            end
            -- v2.0.0: 翻滚后猛击 —— 翻滚动作【结束】(最后一帧 roll_timer<=1)时才给【惊人一刻】增益
            if CFG.add_buff and roll_timer <= 1 then
                give_parry_buff(inst)
            end
            -- 倒计时
            roll_timer = roll_timer - 1
            if roll_timer <= 0 then
                setf(H.p.fullRot, inst, 0.0, "float")
                setv2(H.p.rotOrigin, inst, 0.0, 0.0)
            end
            if g_roll_log < 100 then
                g_roll_log = g_roll_log + 1
                wlogf("  执行翻滚 left=%d newRot=%.3f dir=%d gd=%d", roll_timer, newv, dir, g_roll_dir)
            end
        end    end
local function upd_post(inst, args, result)
    g_upd_n = g_upd_n + 1
    if not inst then return false end
    if not CFG.enabled then
        if roll_timer > 0 then
            roll_timer = 0
            pcall(function()
                setf(H.p.fullRot, inst, 0.0, "float")
                setv2(H.p.rotOrigin, inst, 0.0, 0.0)
            end)
        end
        return false
    end
    if g_upd_n <= 3 then wlogf("upd_post 被调用 #%d inst=%s", g_upd_n, tostring(inst)) end
    pcall(jroll_upd_body, inst, args)
    return false
end

-- ============================================================================
-- Player.Update prefix（空实现，与动作优化一致的 install_hook 姿势）
-- ============================================================================
local function upd_pre(inst, args)
    if not CFG.enabled then return false end
    -- v1.0.14: 撞击触发式无敌必须放在碰撞结算(Update_NPCCollision)之前。
    --   游戏 Update 内部先做 NPC 碰撞结算(可能 Hurt 掉血)，pre 在它之前执行，
    --   此时若玩家正翻滚且自检到撞怪 → 先给 immune=true，碰撞结算看到 immune 就不会掉血。
    if inst and roll_timer > 0 and CFG.iframe then
        pcall(check_npc_hit, inst)
    end
    return false
end

-- ============================================================================
-- setup / cleanup
-- ============================================================================
function jr_setup()
    do
        local ok, s = pcall(function() return mod.read_file("dashroll_en.txt") end)
        if ok and type(s) == "string" and s:sub(1, 1) == "0" then CFG.enabled = false end
    end
    wlog("=== SETUP CALLED " .. os.date("%H:%M:%S") .. " jumproll v2.0.0 ===")
    -- v1.0.12: load_config 包 pcall，即便配置读取/解析抛异常也不中断 setup，翻滚引擎照装
    local ok_cfg, err_cfg = pcall(load_config)
    if not ok_cfg then
        wlog("load_config 异常（已忽略，继续装翻滚引擎）: " .. tostring(err_cfg))
    end
    -- 合并版：二级开关持久化值覆盖 config.json 默认值
    if jr_load_opts then pcall(jr_load_opts) end
    -- 卸载旧 hook（防重载叠加）
    if hook_handle and hook_handle.remove then
        pcall(function() hook_handle:remove() end)
        hook_handle = nil
    end
    local ok, err = pcall(function()
        local pt = P.get_type("Terraria", "Player")
        local mt = P.get_type("Terraria", "Main")
        if not pt then error("Player 类型获取失败") end
        -- Player/Entity 字段（用继承链搜索，保证 Entity 继承字段也能找到）
        local names = {
            whoami="whoAmI", dashTime="dashTime", dashType="dashType", dashDelay="dashDelay",
            jumping="jumping", direction="direction", width="width", height="height",
            position="position", velocity="velocity", fullRot="fullRotation",
            rotOrigin="fullRotationOrigin", immune="immune", immuneTime="immuneTime",
            sitting="sitting", pulley="pulley", mount="mount",
        }
        for k, n in pairs(names) do
            H.p[k] = find_field(pt, n)
            if not H.p[k] then wlog("字段未找到: " .. n) end
        end
        if mt then
            H.m.myplayer  = P.get_field(mt, "myPlayer")
            H.m.game_menu = P.get_method(mt, "get_gameMenu")
        end
        -- v1.0.14: 撞击触发式无敌需要 —— Main.npc 数组 + NPC 字段（枚举敌怪矩形）
        if mt then H.m.npc_arr = P.get_field(mt, "npc") end
        local NPC = P.get_type("Terraria", "NPC")
        if NPC then
            H.p.npc_active   = find_field(NPC, "active")
            H.p.npc_friendly = find_field(NPC, "friendly")
            H.p.npc_damage   = find_field(NPC, "damage")
            H.p.npc_position = find_field(NPC, "position")
            H.p.npc_width    = find_field(NPC, "width")
            H.p.npc_height   = find_field(NPC, "height")
        end
        wlog("v1.0.14 撞击绑定: immune=" .. tostring(H.p.immune)
            .. " Main.npc=" .. tostring(H.m.npc_arr)
            .. " npc.active=" .. tostring(H.p.npc_active)
            .. " npc.friendly=" .. tostring(H.p.npc_friendly)
            .. " npc.damage=" .. tostring(H.p.npc_damage)
            .. " npc.pos=" .. tostring(H.p.npc_position)
            .. " npc.w=" .. tostring(H.p.npc_width)
            .. " npc.h=" .. tostring(H.p.npc_height))
        -- v1.0.3: 绑定 Mount._type（判定是否真骑了坐骑；空坐骑对象 type=0 不算占用）
        local MNT = P.get_type("Terraria", "Mount")
        if MNT then H.mt.mount_type = P.get_field(MNT, "_type") end
        wlog("Mount类型=" .. tostring(MNT) .. " mount_type字段=" .. tostring(H.mt.mount_type))
        -- 记录各关键字段句柄（非 nil 即绑定成功）
        wlog("字段: dashTime=" .. tostring(H.p.dashTime) .. " jumping=" .. tostring(H.p.jumping)
            .. " fullRot=" .. tostring(H.p.fullRot) .. " rotOrigin=" .. tostring(H.p.rotOrigin)
            .. " pos=" .. tostring(H.p.position) .. " vel=" .. tostring(H.p.velocity)
            .. " dir=" .. tostring(H.p.direction) .. " whoami=" .. tostring(H.p.whoami)
            .. " immune=" .. tostring(H.p.immuneTime) .. " sit=" .. tostring(H.p.sitting)
            .. " pulley=" .. tostring(H.p.pulley) .. " mount=" .. tostring(H.p.mount)
            .. " dashType=" .. tostring(H.p.dashType) .. " dashDelay=" .. tostring(H.p.dashDelay))
        wlog("Main: myPlayer=" .. tostring(H.m.myplayer) .. " game_menu=" .. tostring(H.m.game_menu))
        -- v1.0.11: 绑定 Player.AddBuff 方法（唯一重载 AddBuff(int,int,bool)）与 buff 数组字段
        H.p.addbuff = P.get_method(pt, "AddBuff")
        if not H.p.buffType then H.p.buffType = P.get_field(pt, "buffType") end
        if not H.p.buffTime then H.p.buffTime = P.get_field(pt, "buffTime") end
        wlog("AddBuff方法=" .. tostring(H.p.addbuff) .. " buffType字段=" .. tostring(H.p.buffType) .. " buffTime字段=" .. tostring(H.p.buffTime))
        local mu = P.get_method(pt, "Update", 1)
        wlog("get_method(Player,Update,1) = " .. tostring(mu))
        if not mu then error("Player.Update(int) 方法获取失败") end
        -- v2.9.0：不再单独 install_hook，改注册到 Player.Update 汇合总线
        --   （与动作优化共用 1 个钩子）。开关仍由 upd_pre/upd_post 内的 CFG.enabled 门控。
        pu_reg_pre("猛冲跳跃", upd_pre)
        pu_reg_post("猛冲跳跃", upd_post)
        wlog("===> 已注册到 Player.Update 汇合总线（setup 末尾统一安装）")
    end)
    if not ok then
        wlog("=== setup 失败: " .. tostring(err))
        mod.error("[DashRoll] setup 失败: " .. tostring(err) .. " 最近日志: " .. dump_dbg())
    end
end

function jr_cleanup()
    if hook_handle and hook_handle.remove then
        pcall(function() hook_handle:remove() end)
        hook_handle = nil
    end
end

todo_list = { "setup" }
-- ===== 合并版接线：总开关（模组设置页 checkbox 控制，持久化 dashroll_en.txt）=====
function jr_set_enabled(b) CFG.enabled = (b and true or false) end
function jr_is_enabled() return CFG.enabled end
function jr_is_rolling() return roll_timer > 0 end
-- 二级开关（iframe/add_buff）：读写 CFG 并持久化 dashroll_opts.txt
function jr_get_opt(k) return CFG[k] end
function jr_set_opt(k, v)
    CFG[k] = (v and true or false)
    pcall(mod.write_file, "dashroll_opts.txt",
        string.format("iframe=%d\nadd_buff=%d", CFG.iframe and 1 or 0, CFG.add_buff and 1 or 0))
end
function jr_load_opts()
    local ok, s = pcall(function() return mod.read_file("dashroll_opts.txt") end)
    if not ok or type(s) ~= "string" then return end
    local iv = s:match("iframe=%d")
    if iv then CFG.iframe = s:match("iframe=(%d)") == "1" end
    local ab = s:match("add_buff=%d")
    if ab then CFG.add_buff = s:match("add_buff=(%d)") == "1" end
end
jr_load_opts()


-- ============================================================================
-- 第三部分：更适合陈什么的动作优化 v2.0.1（由独立模组合并）
-- 原 pkg: lua.bluemove.motionplus。头部跟随/移动倾斜/待机表情，三钩子驱动。
-- 改造点：do-end 作用域隔离；setup -> mp_setup；新增 MP_EN 总开关门控；
--          翻滚进行中让出旋转权（jr_is_rolling）。
-- ============================================================================
mp_setup, mp_cleanup, mp_set_enabled, mp_is_enabled = (function()
local MP_EN = true
    local P = patch  -- 复用合并版顶层 patch
    local f
    local function wlog(s) end -- v2.0.1: 不再写 mp16.log 文件（调试日志已停用，函数保留兼容调用点）
    local function T(x) return tostring(x) end

    -- ===== 状态 =====
    local PI = 3.14159265
    local K_TILT, K_SMOOTH, MAX_STATIC, MAX_TILT = 0.05, 0.45, 0.2618, 0.5236
    local K_RETURN = 0.05

    local g_rot, g_slime_rot, g_zomb_rot, g_zomb_tgt = 0.0, 0.0, 0.0, 0.0
    local g_lastX, g_lastY, g_inited = 0.0, 0.0, false
    local g_idle_cnt, g_move_cnt, g_using = 0, 0, 0
    local g_last_mx, g_last_my, g_mouse_inited = 0, 0, false
    local g_rope_hr, g_beyond = 0.0, 0
    local g_look_on, g_look_retarget, g_look_wait, g_look_timer = 0, 1, 0, 0
    local g_look_world, g_look_hold, g_look_rate = 0.0, 0.0, 0.0
    local g_rng = 98765
    -- emote
    local g_emote_m = nil
    local g_emote_next = 0
    local EMOTE_POOL = {0,1,2,3,15,16,17,87,88,89,91,92,93,94,134,135,136,137,138,139}
    local g_emote_rng = 24680
    local g_idle_3s, g_idle_10s, g_idle_15s = 180, 600, 900
    local g_fps_log = 0
    local g_idle_secs = 0.0
    local g_idle_since = -1
    local g_hooks = {}
    -- ===== Emote（待机随机表情）=====
    local function emote_send()
        if not g_emote_m then return end
        g_emote_rng = (g_emote_rng * 1103515245 + 12345) % 2147483648
        local idx = (math.floor(g_emote_rng / 4096) % #EMOTE_POOL) + 1
        local eid = math.floor(EMOTE_POOL[idx])
        pcall(P.invoke, g_emote_m, eid)
        wlog("EMOTE send id=" .. tostring(eid))
    end

    local g_emote_armed = 0
    local function emote_step()
        -- 未达标：清空
        if g_idle_secs < 10.0 or g_using ~= 0 then
            g_emote_armed = 0
            g_emote_next = 0
            return
        end
        if not g_emote_m then return end
        -- 刚满 10 秒：立刻发第 1 个
        if g_emote_armed == 0 then
            g_emote_armed = 1
            emote_send()
            g_emote_rng = (g_emote_rng * 1103515245 + 12345) % 2147483648
            g_emote_next = 300 + (math.floor(g_emote_rng / 65536) % 601)
            return
        end
        g_emote_next = g_emote_next - 1
        if g_emote_next > 0 then return end
        emote_send()
        g_emote_rng = (g_emote_rng * 1103515245 + 12345) % 2147483648
        g_emote_next = 300 + (math.floor(g_emote_rng / 65536) % 601)
    end


    -- ===== 句柄 =====
    local F_dp, F_hr, F_dir, F_pos, F_vel, F_fr, F_fo, F_sit, F_w, F_h, F_pulley, F_ani
    local F_mount, F_mtype
    local g_mt_log, g_mt_last = 0, -999
    local M_mx, M_my, M_sw, M_sh, M_gm, F_fps
    local F_frame
    local N_rot, N_vel, N_ai

    local function invM(m)
        if not m then return 0 end
        local r = P.invoke(m, nil)
        if r == nil then return 0 end
        return r
    end

    -- ===== NPC postfix =====
    local g_npc_n = 0
    local function npc_rot_body(inst, args)

            if not inst or not N_rot then return end
            local ai = P.get_field_value(N_ai, inst, "int32") or -1
            if ai == 1 then
                local vx = P.get_field_vec2(N_vel, inst)
                if not vx then return end
                local tgt = vx * 0.75
                if tgt > 0.5236 then tgt = 0.5236 elseif tgt < -0.5236 then tgt = -0.5236 end
                g_slime_rot = g_slime_rot + (tgt - g_slime_rot) * 0.45
                P.set_field_value(N_rot, inst, g_slime_rot, "float")
            elseif ai == 3 then
                local vx = P.get_field_vec2(N_vel, inst)
                if not vx then return end
                local tgt = vx * 0.50
                if tgt > 0.3491 then tgt = 0.3491 elseif tgt < -0.3491 then tgt = -0.3491 end
                if tgt > g_zomb_tgt + 0.06 or tgt < g_zomb_tgt - 0.06 then g_zomb_tgt = tgt end
                g_zomb_rot = g_zomb_rot + (g_zomb_tgt - g_zomb_rot) * 0.12
                P.set_field_value(N_rot, inst, g_zomb_rot, "float")
            end        end
    local function npc_post(inst, args, result)
        g_npc_n = g_npc_n + 1
        if not MP_EN then return false end
        if g_npc_n <= 3 then wlog("npc_post called #" .. g_npc_n .. " inst=" .. tostring(inst)) end
        pcall(npc_rot_body, inst, args)
    end

    -- ===== Player Update postfix（写 fullRotation）=====
    local function cart_check(inst)

                if F_mount and F_mtype then
                    local mo = P.get_field_value(F_mount, inst, "object")
                    if mo then
                        local mt = P.get_field_value(F_mtype, mo, "int32")
                        if mt then
                            if mt ~= g_mt_last and g_mt_log < 60 then
                                g_mt_log = g_mt_log + 1; g_mt_last = mt
                                wlog("MOUNT type=" .. T(mt))
                            end
                            if mt >= 7 and mt <= 40 then return true end
                        end
                    end
                end        return false
    end
    local function motion_upd_body(inst, args)

            if not inst then return end
            -- 菜单
            local gm = invM(M_gm)
            if g_upd_n <= 3 then wlog("  upd_post gm=" .. tostring(gm)) end
            if gm == true then return end
            pcall(emote_step)
            -- 躺床
            local fr = P.get_field_value(F_fr, inst, "float")
            local lying = false
            local sp = P.get_field_value(F_sit, inst, "bool")
            if sp then lying = true end
            if fr and (fr > 1.0 or fr < -1.0) then lying = true end
            -- 爬绳
            local on_rope = false
            local pu = P.get_field_value(F_pulley, inst, "bool")
            if pu then on_rope = true end
            -- 矿车
            local okc, ocv = pcall(cart_check, inst)
            local on_cart = (okc and ocv == true)

            if on_cart then lying = true end
            -- 位置/倾斜
            if not lying then
                local x, y = P.get_field_vec2(F_pos, inst)
                if x then
                    if not g_inited then g_lastX, g_lastY, g_inited = x, y, true
                    else
                        local dx = x - g_lastX
                        g_lastX, g_lastY = x, y
                        local target
                        if dx > 0.5 or dx < -0.5 then
                            target = dx * K_TILT; g_move_cnt = 10
                        elseif g_move_cnt > 0 then
                            g_move_cnt = g_move_cnt - 1; target = g_rot
                        else
                            local mx = invM(M_mx); local sw = invM(M_sw)
                            local cx = sw * 0.5
                            local r = 0.0
                            if cx > 0 then r = (mx - cx) / cx end
                            if r > 1 then r = 1 elseif r < -1 then r = -1 end
                            if g_idle_secs > 3.0 and g_using == 0 then target = 0.0
                            else target = -r * MAX_STATIC end
                        end
                        if target > MAX_TILT then target = MAX_TILT elseif target < -MAX_TILT then target = -MAX_TILT end
                        local ks = (target == 0.0) and K_RETURN or K_SMOOTH
                        g_rot = g_rot + (target - g_rot) * ks
                    end
                end
            end
            -- 写 fullRotation
            if not lying then
                if on_rope then P.set_field_value(F_fr, inst, 0.0, "float")
                else P.set_field_value(F_fr, inst, g_rot, "float") end
                local w = P.get_field_value(F_w, inst, "int32") or 20
                local h = P.get_field_value(F_h, inst, "int32") or 42
                P.set_field_vec2(F_fo, inst, w * 0.5, h)
            end
            -- direction（爬绳不碰）
            if lying or on_rope or g_look_on == 1 then return end
            local mx = invM(M_mx); local sw = invM(M_sw)
            local nd = (mx > sw * 0.5) and 1 or -1
            local cd = P.get_field_value(F_dir, inst, "int32") or 1
            if nd ~= cd then P.set_field_value(F_dir, inst, nd, "int32") end        end
    local g_upd_n = 0
    local function upd_post(inst, args, result)
        g_upd_n = g_upd_n + 1
        if not MP_EN then return false end
        -- 翻滚引擎正在执行时让出旋转权（否则写 fullRotation 会打架）
        if jr_is_rolling and jr_is_rolling() then return false end
        if g_upd_n <= 3 then wlog("upd_post called #" .. g_upd_n) end
        local okk, ee = pcall(motion_upd_body, inst, args)
        if not okk and g_upd_n <= 3 then wlog("  upd_post ERR=" .. tostring(ee)) end
        if g_upd_n <= 3 then wlog("  upd_post done") end
    end

    -- ===== Player Update prefix（idle 计数）=====
    local g_pre_calls = 0
    local g_pre_t0 = 0
    local function motion_pre_body(inst, args)

            if not inst then return false end
            local gm = invM(M_gm)
            if gm and gm ~= 0 then return false end
            if F_fps then
                local fr = P.get_field_value(F_fps, nil, "int32")
                if fr and fr > 20 and fr < 400 then
                    g_idle_3s = fr * 3
                    g_idle_10s = fr * 10
                    g_idle_15s = fr * 15
                end
            end
            local vx, vy = P.get_field_vec2(F_vel, inst)
            local moving = false
            if vx then
                if vx > 0.5 or vx < -0.5 or vy > 0.5 or vy < -0.5 then moving = true end
            end
            -- 准星移动检测：准星动也算"活跃"
            local mx0 = invM(M_mx); local my0 = invM(M_my)
            local mmoving = false
            if mx0 and mx0 > 0 then
                if not g_mouse_inited then g_last_mx, g_last_my, g_mouse_inited = mx0, my0, true
                else
                    local ddx, ddy = mx0 - g_last_mx, my0 - g_last_my
                    g_last_mx, g_last_my = mx0, my0
                    if ddx ~= 0 or ddy ~= 0 then mmoving = true end
                end
            end
            if moving or mmoving then
                g_idle_cnt = 0
                g_idle_since = -1
            else
                if g_idle_since < 0 then g_idle_since = os.clock() end
                g_idle_secs = os.clock() - g_idle_since
                g_fps_log = g_fps_log + 1
                if g_fps_log % 200 == 1 then wlog("IDLE secs=" .. string.format("%.2f", g_idle_secs)) end
            end
            local a = P.get_field_value(F_ani, inst, "int32") or 0
            g_using = (a > 0) and 1 or 0
            if g_using == 1 then g_idle_cnt = 0 end        end
    local function upd_pre(inst, args, result)
        g_pre_calls = g_pre_calls + 1
        if not MP_EN then return false end
        if g_pre_t0 == 0 then g_pre_t0 = os.clock() end
        local el = os.clock() - g_pre_t0
        if el >= 2.0 then
            wlog("PRECALLS " .. g_pre_calls .. " in " .. string.format("%.2f", el) .. "s = " .. string.format("%.0f", g_pre_calls/el) .. "/s")
            g_pre_calls = 0
            g_pre_t0 = os.clock()
        end
        pcall(motion_pre_body, inst, args)
        return false
    end

    -- ===== Head 绘制 =====
    local g_hd_n = 0
    local function head_body(inst, args)

            if not args or not args[1] then return end
            local gm = invM(M_gm)
            if gm and gm ~= 0 then return end
            local ds = args[1]
            local dp = P.get_field_value(F_dp, ds, "object")
            if not dp then return end
            -- 排除人体模型
            local inan = P.get_field_value(F_inan, dp, "bool")
            if inan then return end
            local mx = invM(M_mx); local my = invM(M_my)
            local sw = invM(M_sw); local sh = invM(M_sh)
            local dir = P.get_field_value(F_dir, dp, "int32") or 1
            local dx = mx - sw * 0.5
            local dy = my - sh * 0.5
            local ang = math.atan(dy, dx)
            if dir == -1 then
                ang = ang - PI
                if ang < -PI then ang = ang + 2 * PI end
            end
            local a = ang
            if a > PI then a = a - 2 * PI elseif a < -PI then a = a + 2 * PI end
            local aa = (a < 0) and -a or a
            local limOn = 62.0 * PI / 180.0
            local limOff = 60.0 * PI / 180.0
            if aa > limOn then g_beyond = 1 elseif aa < limOff then g_beyond = 0 end
            local tgt
            if g_idle_secs > 15.0 and g_using == 0 then
                g_look_on = 1
                if g_look_retarget == 1 then
                    g_look_retarget = 0
                    g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                    local rr = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                    if rr < 0.5 then
                        g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                        local r2 = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                        g_look_world = (r2 * 2.0 - 1.0) * 40.0 * (PI / 180.0)
                    else
                        g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                        local r2 = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                        local s = (r2 < 0.5) and 1.0 or -1.0
                        g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                        local r3 = ((math.floor(g_rng / 65536)) % 32768) / 32767.0
                        g_look_world = s * (140.0 + r3 * 40.0) * (PI / 180.0)
                    end
                    g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                    g_look_timer = 90 + (math.floor(g_rng / 256) % 91)
                    g_look_wait = 0
                    g_rng = (g_rng * 1103515245 + 12345) % 2147483648
                    g_look_rate = 1.0 / (18.0 + (math.floor(g_rng / 64) % 19))
                end
                local base = (dir == -1) and PI or 0.0
                local rel = g_look_world - base
                if rel > PI then rel = rel - 2 * PI elseif rel < -PI then rel = rel + 2 * PI end
                if g_look_wait > 0 then
                    g_look_wait = g_look_wait - 1
                    tgt = g_look_hold
                elseif math.abs(rel) > PI * 0.5 then
                    local w = g_look_world
                    if w > PI then w = w - 2 * PI elseif w < -PI then w = w + 2 * PI end
                    local nd2 = (w > -PI * 0.5 and w < PI * 0.5) and 1 or -1
                    P.set_field_value(F_dir, dp, nd2, "int32")
                    g_rope_hr = -g_rope_hr
                    g_look_hold = g_rope_hr
                    dir = nd2
                    base = (dir == -1) and PI or 0.0
                    rel = g_look_world - base
                    if rel > PI then rel = rel - 2 * PI elseif rel < -PI then rel = rel + 2 * PI end
                    g_look_wait = 18
                    tgt = g_look_hold
                else
                    g_look_hold = rel
                    tgt = rel
                end
                if g_look_timer > 0 then
                    g_look_timer = g_look_timer - 1
                    if g_look_timer == 0 then g_look_retarget = 1 end
                end
            else
                g_look_on = 0
                g_look_retarget = 1
                tgt = (g_beyond == 1) and 0.0 or a
                if g_idle_secs > 3.0 and g_idle_secs <= 15.0 and g_move_cnt == 0 then tgt = 0.0 end
            end
            -- 绳上头限制
            local rope_h = false
            local rp = P.get_field_value(F_pulley, dp, "bool")
            if rp then rope_h = true end
            if rope_h then
                local same = (dir == 1) and (dx > 0) or (dx < 0)
                if not same then tgt = 0.0 end
            end
            -- 平滑
            local d = tgt - g_rope_hr
            if g_look_on == 1 and g_look_rate > 0 and g_look_wait == 0 then
                d = d * g_look_rate
            else
                if tgt == 0.0 then d = d * 0.1 else d = d * 0.3 end
            end
            g_rope_hr = g_rope_hr + d
            local out = g_rope_hr
            -- 视线限幅：抬头最大60度、低头最大20度（按朝向镜像：dir=1时负角为抬头，dir=-1时正角为抬头）
            local lm_up = 60.0 * PI / 180.0
            local lm_down = 20.0 * PI / 180.0
            if dir == 1 then
                if out > lm_down then out = lm_down elseif out < -lm_up then out = -lm_up end
            else
                if out > lm_up then out = lm_up elseif out < -lm_down then out = -lm_down end
            end
            P.set_field_value(F_hr, dp, out, "float")
            if g_hd_n <= 3 then wlog("  head set ang=" .. string.format("%.3f", out)) end        end
    local function head_prefix(inst, args)
        g_hd_n = g_hd_n + 1
        if not MP_EN then return false end
        if g_hd_n <= 3 then wlog("head_prefix called #" .. g_hd_n .. " args1=" .. tostring(args and args[1])) end
        local okh, eh = pcall(head_body, inst, args)
        if not okh and g_hd_n <= 3 then wlog("  head ERR=" .. tostring(eh)) end
        return false
    end

    -- ===== setup =====
    function mp_setup()
        do
            local ok, s = pcall(function() return mod.read_file("mp_en.txt") end)
            if ok and type(s) == "string" and s:sub(1, 1) == "0" then MP_EN = false end
        end
        wlog("=== SETUP CALLED "..os.date("%H:%M:%S"))
        -- 卸载旧 hook（防重载叠加）
        for i, h in ipairs(g_hooks) do
            pcall(function() if h and h.remove then h:remove() end end)
        end
        g_hooks = {}
        wlog("=== motionplus lua v100 " .. os.date("%H:%M:%S") .. " plat=" .. tostring(mod.platform))
        local ok, err = pcall(function()
            local PLAYER = P.get_type("Terraria", "Player")
            local NPC = P.get_type("Terraria", "NPC")
            local M = P.get_type("Terraria", "Main")
            local DS = P.get_type("Terraria.DataStructures", "PlayerDrawSet")
            local L = P.get_type("Terraria.DataStructures", "PlayerDrawLayers")

            F_pos = P.get_field(PLAYER, "position")
            F_vel = P.get_field(PLAYER, "velocity")
            F_fr = P.get_field(PLAYER, "fullRotation")
            F_fo = P.get_field(PLAYER, "fullRotationOrigin")
            F_dir = P.get_field(PLAYER, "direction")
            F_hr = P.get_field(PLAYER, "headRotation")
            F_sit = P.get_field(PLAYER, "sitting")
            F_w = P.get_field(PLAYER, "width")
            F_h = P.get_field(PLAYER, "height")
            F_pulley = P.get_field(PLAYER, "pulley")
            F_ani = P.get_field(PLAYER, "itemAnimation")
            F_inan = P.get_field(PLAYER, "isDisplayDollOrInanimate")
            pcall(function()
                F_mount = P.get_field(PLAYER, "mount")
                local MNT = P.get_type("Terraria", "Mount")
                if MNT then F_mtype = P.get_field(MNT, "_type") end
                wlog("F_mount=" .. T(F_mount) .. " F_mtype=" .. T(F_mtype))
            end)

            N_rot = P.get_field(NPC, "rotation")
            N_vel = P.get_field(NPC, "velocity")
            N_ai = P.get_field(NPC, "aiStyle")

            M_mx = P.get_method(M, "get_mouseX")
            M_my = P.get_method(M, "get_mouseY")
            M_sw = P.get_method(M, "get_screenWidth")
            M_sh = P.get_method(M, "get_screenHeight")
            M_gm = P.get_method(M, "get_gameMenu")
            F_fps = P.get_field(M, "frameRate")
            pcall(function() F_frame = P.get_field(M, "updatesCountedForFPS") end)
            wlog("F_fps=" .. T(F_fps) .. " F_frame=" .. T(F_frame))

            F_dp = P.get_field(DS, "drawPlayer")

            local EB = P.get_type("Terraria.GameContent.UI", "EmoteBubble")
            if EB then
                g_emote_m = P.get_method(EB, "MakeLocalPlayerEmote", 1)
                wlog("emote_m=" .. T(g_emote_m))
            end

            wlog("pos=" .. T(F_pos) .. " fr=" .. T(F_fr) .. " hr=" .. T(F_hr) .. " vel=" .. T(F_vel))
            wlog("N.rot=" .. T(N_rot) .. " N.vel=" .. T(N_vel) .. " N.ai=" .. T(N_ai))
            wlog("dp=" .. T(F_dp) .. " gm=" .. T(M_gm) .. " mx=" .. T(M_mx))

            local mu = P.get_method(PLAYER, "Update", 1)
            if not mu then error("Player.Update(int) 方法获取失败") end
            -- v2.9.0：不再单独 install_hook，改注册到 Player.Update 汇合总线
            --   （与猛冲跳跃共用 1 个钩子）。开关仍由各回调内的 MP_EN 门控。
            pu_reg_pre("动作优化", upd_pre)
            pu_reg_post("动作优化", upd_post)
            wlog("hook Update=registered to pu bus")

            local mh = P.get_method(L, "DrawPlayer_21_Head", 1)
            local h2 = P.install_hook(mh, { prefix = head_prefix })
            g_hooks[#g_hooks+1] = h2
            wlog("hook Head=" .. T(h2))

            local mu2 = P.get_method(NPC, "UpdateNPC", 1)
            local h3 = P.install_hook(mu2, { postfix = npc_post })
            g_hooks[#g_hooks+1] = h3
            wlog("hook UpdateNPC=" .. T(h3))
        end)
        wlog("=== setup " .. (ok and "OK" or ("ERR " .. T(err))))
    end


    -- ===== 合并版接线：动作优化总开关（模组设置页控制，持久化 mp_en.txt）=====
    -- v2.9.0：Player.Update 已与猛冲跳跃汇合为 1 个钩子，开关改为「回调内门控」：
    --   只翻 MP_EN 标志，不再装卸钩子（卸了会连猛冲跳跃那一份一起卸掉）。
    --   mp 的四个回调（upd_pre / upd_post / head_prefix / npc_post）本就都有 MP_EN 判断。
    function mp_set_enabled(b)
        MP_EN = (b and true or false)
    end
    function mp_is_enabled() return MP_EN end
    function mp_cleanup()
        for i, h in ipairs(g_hooks) do
            pcall(function() if h and h.remove then h:remove() end end)
        end
        g_hooks = {}
    end

    return mp_setup, mp_cleanup, mp_set_enabled, mp_is_enabled
end)()


-- ============================================================================
-- 第四部分：连锁挖矿 v1.3.0（由独立模组合并，原 pkg: lzup.lua.veinminer）
-- 破坏矿石/宝石时 BFS 连锁破坏同类型相连方块（半径32/上限256），
-- Android 走 TileData 内存快通道。改造点：setup -> vm_setup；
-- safe_hook 捕获句柄；v1.4.0 起默认常开（已移除总开关）。
-- ============================================================================
vm_setup, vm_cleanup = (function()

    local dkjson = require("dkjson")
    -- patch 复用合并版顶层句柄

    -- ============ 常量 ============
    local MAX_CHAIN_TILES = 256
    local CHAIN_RADIUS = 32
    local DX = { 0, 0, -1, 1 }
    local DY = { -1, 1, 0, 0 }

    -- ============ 连锁类型集合(由 config.json 填充) ============
    local VEIN_SET = {}

    local function is_vein_type(t)
        return t ~= nil and VEIN_SET[t] == true
    end

    local function parse_id_list(s)
        if type(s) ~= "string" then return nil end
        local list = {}
        for n in s:gmatch("%d+") do list[#list + 1] = tonumber(n) end
        if #list == 0 then return nil end
        return list
    end

    local function rebuild_vein_set(ids)
        VEIN_SET = {}
        if not ids then return end
        for _, t in ipairs(ids) do VEIN_SET[t] = true end
    end

    -- ============ 句柄 (setup 中解析并缓存) ============
    local f_max_tiles_x                         -- Main.maxTilesX
    local f_max_tiles_y                         -- Main.maxTilesY
    local f_tile_type                           -- Tile.type (桌面端托管回退)
    local m_get_tile_safely                     -- Framing.GetTileSafely (桌面端托管回退)
    local m_kill_tile                           -- WorldGen.KillTile

    -- ============ Android C 快通道 ============
    local android_fast = false
    local p_max_tiles_x
    local p_max_tiles_y
    local p_tile_lookup
    local p_tile_type

    local NO_TILE = 0xFFFFFFFF
    local MAX_TILE_INDEX = 0x10000000

    -- ============ 状态 ============
    local kill_depth = 0
    local last_killed_type = 0

    -- ============ 工具 ============
    local function find_field(type_handle, name)
        local cur, guard = type_handle, 0
        while cur and guard < 16 do
            local f = patch.get_field(cur, name)
            if f then return f end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
        return nil
    end

    local function read_static_int(field)
        if not field then return 0 end
        local v = patch.get_field_value(field, nil, "int32")
        if v == nil then return 0 end
        return v
    end

    local function get_tile_type_android(x, y)
        if not android_fast then return nil end

        local max_x = patch.mem_read_values(p_max_tiles_x, 0, 1, "int32")[1]
        local max_y = patch.mem_read_values(p_max_tiles_y, 0, 1, "int32")[1]
        if not max_x or not max_y or max_x <= 0 or max_y <= 0 then return 0 end
        if x < 0 or y < 0 or x >= max_x or y >= max_y then return 0 end

        local lookup = patch.ptr_deref(p_tile_lookup, 0)
        if not lookup then return 0 end
        local idx = patch.mem_read_values(lookup, (y * max_x + x) * 4, 1, "uint32")[1]
        if idx == nil or idx == NO_TILE then return 0 end
        if idx >= MAX_TILE_INDEX then return 0 end

        local types = patch.ptr_deref(p_tile_type, 0)
        if not types then return 0 end
        local t = patch.mem_read_values(types, idx * 2, 1, "uint16")[1]
        if t == nil then return 0 end
        return t
    end

    local function get_tile_type(x, y)
        local fast_type = get_tile_type_android(x, y)
        if fast_type ~= nil then return fast_type end

        if not m_get_tile_safely or not f_tile_type then return 0 end
        local max_x = read_static_int(f_max_tiles_x)
        local max_y = read_static_int(f_max_tiles_y)
        if max_x <= 0 or max_y <= 0 then return 0 end
        if x < 0 or y < 0 or x >= max_x or y >= max_y then return 0 end

        local tile = patch.invoke(m_get_tile_safely, x, y)
        if not tile then return 0 end
        local t = patch.get_field_value(f_tile_type, tile, "uint16")
        if t == nil then return 0 end
        return t
    end

    local function call_kill_tile(i, j, fail, effect_only, no_item)
        if not m_kill_tile then return end
        patch.invoke(m_kill_tile, i, j, fail, effect_only, no_item)
    end

    local function chain_mine(ox, oy, tile_type, no_item)
        if not m_kill_tile then return end

        local queue = { { ox, oy } }
        local count = 1
        local visited = 0

        while visited < count do
            local cur = queue[visited + 1]
            visited = visited + 1

            for dir = 1, 4 do
                local nx = cur[1] + DX[dir]
                local ny = cur[2] + DY[dir]

                if nx >= ox - CHAIN_RADIUS and nx <= ox + CHAIN_RADIUS
                    and ny >= oy - CHAIN_RADIUS and ny <= oy + CHAIN_RADIUS then
                    local seen = false
                    for v = 1, count do
                        if queue[v][1] == nx and queue[v][2] == ny then
                            seen = true
                            break
                        end
                    end

                    if not seen and get_tile_type(nx, ny) == tile_type then
                        if count >= MAX_CHAIN_TILES then return end
                        count = count + 1
                        queue[count] = { nx, ny }
                        call_kill_tile(nx, ny, false, false, no_item)
                    end
                end
            end
        end
    end

    -- ============ Hook: Player.PickTile ============
    local function picktile_prefix(instance, args, result)
        local d = kill_depth
        kill_depth = kill_depth + 1

        if d == 0 and args then
            last_killed_type = get_tile_type(args[1], args[2])
        end

        return false
    end

    local function picktile_postfix(instance, args, result)
        if kill_depth <= 0 then return end

        if kill_depth == 1 and args then
            local i = args[1]
            local j = args[2]

            if get_tile_type(i, j) == 0 then
                local tile_type = last_killed_type
                if tile_type ~= 0 and tile_type < 4096 and is_vein_type(tile_type) then
                    chain_mine(i, j, tile_type, false)
                end
            end
        end

        kill_depth = kill_depth - 1
    end

    local vm_hook  -- 合并版：保存钩子句柄供总开关卸载
    local function safe_hook(method, spec, label)
        if not method then
            mod.error("安装钩子失败(" .. label .. ")：方法句柄为空")
            return false
        end
        local ok, h = pcall(patch.install_hook, method, spec)
        if not ok then
            mod.error("安装钩子失败(" .. label .. ")：" .. tostring(h))
            return false
        end
        vm_hook = h
        return true
    end

    -- ============ 加载配置 ============
    local function load_config()
        local text, err = mod.read_file("config.json")
        if not text then
            mod.error("读取 config.json 失败: " .. tostring(err))
            return
        end

        local raw, _, decode_err = dkjson.decode(text)
        if decode_err or type(raw) ~= "table" then
            mod.error("config.json 解析失败: " .. tostring(decode_err))
            return
        end

        local values = raw.values
        if type(values) ~= "table" then
            mod.error("config.json 缺少 values")
            return
        end

        local ids = parse_id_list(values.chain_types)
        if not ids then
            mod.error("config.json 的 chain_types 为空或格式错误")
            return
        end

        rebuild_vein_set(ids)

        local count = 0
        for _ in pairs(VEIN_SET) do count = count + 1 end
    end

    -- ============ 初始化 ============
    function vm_setup()
        if vm_hook and vm_hook.remove then
            pcall(function() vm_hook:remove() end)
            vm_hook = nil
        end

        load_config()

        local main_type = patch.get_type("Terraria", "Main")
        local worldgen_type = patch.get_type("Terraria", "WorldGen")
        local player_type = patch.get_type("Terraria", "Player")
        local framing_type = patch.get_type("Terraria", "Framing")
        local tile_type = patch.get_type("Terraria", "Tile")

        if not main_type or not worldgen_type or not player_type then
            mod.error("获取类型失败 (Main/WorldGen/Player)")
            return
        end

        f_max_tiles_x = find_field(main_type, "maxTilesX")
        f_max_tiles_y = find_field(main_type, "maxTilesY")
        if tile_type then
            f_tile_type = find_field(tile_type, "type")
        end
        if framing_type then
            m_get_tile_safely = patch.get_method(framing_type, "GetTileSafely", 2)
                or patch.get_method(framing_type, "GetTileSafely")
        end

        if mod.platform == "android" then
            local tiledata_type = patch.get_type("Terraria", "TileData")
            if tiledata_type then
                local f_lookup = find_field(tiledata_type, "TileLookup")
                local f_type_arr = find_field(tiledata_type, "TileType")
                if f_lookup then p_tile_lookup = patch.field_pointer(f_lookup, nil) end
                if f_type_arr then p_tile_type = patch.field_pointer(f_type_arr, nil) end
                if f_max_tiles_x then p_max_tiles_x = patch.field_pointer(f_max_tiles_x, nil) end
                if f_max_tiles_y then p_max_tiles_y = patch.field_pointer(f_max_tiles_y, nil) end

                android_fast = p_tile_lookup ~= nil and p_tile_type ~= nil
                    and p_max_tiles_x ~= nil and p_max_tiles_y ~= nil
            end
            if android_fast then
                mod.info("VeinMiner: 使用 Android TileData C 快通道 (TileLookup/TileType)")
            else
                mod.warn("VeinMiner: Android C 快通道不可用, 回退 Framing.GetTileSafely")
            end
        end

        if not android_fast and (not f_tile_type or not m_get_tile_safely) then
            mod.error("获取 Framing.GetTileSafely / Tile.type 失败, 连锁不可用")
            return
        end

        m_kill_tile = patch.get_method(worldgen_type, "KillTile", 5)
            or patch.get_method(worldgen_type, "KillTile")
        if not m_kill_tile then
            mod.error("获取 WorldGen.KillTile 方法失败")
            return
        end

        local picktile = patch.get_method(player_type, "PickTile", 4)
            or patch.get_method(player_type, "PickTile")
        if not picktile then
            mod.error("获取 Player.PickTile 方法失败")
            return
        end

        safe_hook(picktile, { prefix = _G.mg_gated("vm", picktile_prefix), postfix = _G.mg_gated("vm", picktile_postfix) }, "Player.PickTile")
    end


    function vm_cleanup()
        if vm_hook and vm_hook.remove then
            pcall(function() vm_hook:remove() end)
        end
        vm_hook = nil
    end
    return vm_setup, vm_cleanup

end)()

-- ============================================================================
-- 第五部分：Boss方向提示（liuxin.bossdirectionhint v3.0 合并改造）
-- 改造：去掉原模组 meta；setup/cleanup 改名接入总入口；默认常开（无开关）；
-- 只保留原版指针样式（pointer.png，样式2~6资源不打包）。
bd_setup, bd_cleanup = (function()
-- Boss方向提示 v3.0 / Terraria Android 1.4.5.8 + LuaLoader 1.5.0+（兼容1.6.0）
-- 仅调用 ref 参数绘制重载，不调用 DrawBuffIcon、不写玩家 buff、不激活 CombatText。
-- 按完整参数类型选择 ref Draw；不绑定版本相关的元数据 Token。
local P = patch
local H, hooks = {}, {}
local disabled, failures, frames, announced = false, 0, 0, false
local target, previous_target
local RADIUS, MAX_BUFFS = 160, 4
local distance_pointer_enabled = true
local pointer_style=1
local refresh_pointer
local POINTER_FILES={'pointer.png'} -- 合并版：只保留原版指针样式(1)
-- v2.0.1：日志 no-op —— 不写文件、不进系统日志（不再生成 Boss 运行日志文件）
local function log(s) end
local function finite(n)
    return type(n)=='number' and n==n and math.abs(n)<1e8
end
-- TEFManager将设置保存到模组private_dir/config.json；加载器read_file读取此目录。
local function refresh_config()
    if type(mod.read_file)~='function' then return end
    local ok,raw=pcall(mod.read_file,'config.json')
    if not ok or type(raw)~='string' then return end
    -- 只读取本模组的布尔及整数设置，不执行配置内容。
    local literal=raw:match('"distance_pointer_enabled"%s*:%s*([%a]+)')
    local enabled
    if literal=='true' then enabled=true elseif literal=='false' then enabled=false end
    if enabled~=nil and enabled~=distance_pointer_enabled then
        distance_pointer_enabled=enabled
        log('距离指针设置：'..(enabled and '开启' or '关闭'))
    end
    local selected=tonumber(raw:match('"pointer_style"%s*:%s*([%-]?[%d%.]+)'))
    if selected and selected%1==0 and POINTER_FILES[selected] and selected~=pointer_style then
        pointer_style=selected
        log('指针样式设置：'..selected)
        if refresh_pointer then refresh_pointer() end
    end
end
local function pointer_radius(distance)
    if not distance_pointer_enabled then return RADIUS end
    if not finite(distance) or distance<0 then return RADIUS end
    -- 0至60格（960像素）映射到48至160像素，贴近时保留角色周围空间。
    return 48+(RADIUS-48)*math.min(distance/960,1)
end
local function value(f,obj,t)
    if not f then return nil end
    return P.get_field_value(f,obj,t)
end
local function rect(x,y,w,h) return string.pack('<i4i4i4i4',x,y,w,h) end
local function release_roots()
    if H.gc_free then
        for _,root in ipairs(H.roots or {}) do pcall(P.invoke,H.gc_free,root) end
    end
    H.roots={}
    H.scratch,H.rect_scratch=nil,nil
end
local function reset()
    frames, announced, target, previous_target = 0, false, nil, nil
    H.miss = 0
end
-- v2.15.1：Boss 出生捕获（事件驱动）。
--   所有 Boss 都必须经过 NPC.NewNPC 生成，在这里判断新生成的 NPC 是不是 Boss，
--   是就把待机模式点亮、立刻恢复每 10 帧全扫。
--   成本：只在有 NPC 生成时触发（低频事件），每次 2~4 次字段读取。
--   注意：这里只读字段、不返回值，对调用方（原版及其他模组的召唤）零影响。
local function on_new_npc(inst, args, result)
    if disabled then return end
    local idx = tonumber(result)
    if not idx or idx < 0 or idx > 199 then return end
    local arr = value(H.npcs, nil, 'object')
    if not arr then return end
    local n = P.array_at(arr, idx)
    if not n then return end
    local isb = value(H.n.boss, n, 'bool') == true
    if not isb then
        -- 世吞头/体/尾在各版本的 boss 标记不一致，与 pick_boss 保持同一套判定
        local nt = value(H.n.kind, n, 'int32')
        if nt == 13 or nt == 14 or nt == 15 then isb = true end
    end
    if isb then H.seen = true; H.miss = 0 end
end
local function center(obj,fields)
    local x,y=P.get_field_vec2(fields.pos,obj)
    local w,h=value(fields.w,obj,'int32'),value(fields.h,obj,'int32')
    if not (finite(x) and finite(y) and finite(w) and finite(h)) then return end
    return x+w/2,y+h/2,x,y,w,h
end
local function pick_boss(arr,px,py)
    local best,dist=nil,math.huge
    for i=0,199 do
        local n=P.array_at(arr,i)
        if n and value(H.n.active,n,'bool')==true and value(H.n.life,n,'int32')>0
           and value(H.n.friendly,n,'bool')~=true then
            local boss=value(H.n.boss,n,'bool')==true
            -- 世吞头/体/尾在各版本的 boss 标记不一致；不把任意 realLife NPC 当 Boss。
            local nt=value(H.n.kind,n,'int32')
            if nt==13 or nt==14 or nt==15 then boss=true end
            if boss then
                local x,y=center(n,H.n)
                if x then
                    local d=(x-px)^2+(y-py)^2
                    if d<dist then best,dist=i,d end
                end
            end
        end
    end
    return best
end
local function asset_texture(asset)
    if not asset then return end
    return value(H.asset_value,asset,'object')
end
local function draw_tex(batch,texture,x,y,w,h,color)
    if not texture or not (finite(x) and finite(y)) then return false end
    -- 独立对象只是 ref 参数缓冲区，未放入游戏的 NPC / CombatText 数组。
    P.set_field_vec2(H.scratch_pos,H.scratch,x,y)
    P.set_field_raw(H.scratch_rect,H.rect_scratch,rect(0,0,w,h))
    P.set_field_raw(H.scratch_color,H.scratch,color)
    local result=P.invoke(H.draw,batch,texture,
        P.field_pointer(H.scratch_pos,H.scratch),
        P.field_pointer(H.scratch_rect,H.rect_scratch),
        P.field_pointer(H.scratch_color,H.scratch))
    if result==false then error('ref Draw 调用失败') end
    return true
end
-- 此手机版Color内存布局由上传源码确认：A B G R。
local WHITE=string.char(255,255,255,255)
local DARK=string.char(255,15,15,15)
local URGENT=string.char(255,60,140,255)
-- 图片独立保存为main.lua旁的pointer.png，尖端朝右、背景透明。
local PNG=require('pointer_png')
local pointer_image
-- 文件损坏或缺失时的简单后备箭头，避免中断Boss/Buff显示。
do
    local pixels={}
    for y=0,23 do for x=0,31 do
        local visible=(x>=8 and math.abs(y-11.5)<=(31-x)*0.5) or (x<12 and math.abs(y-11.5)<3)
        pixels[#pixels+1]=visible and {255,216,83,255} or {0,0,0,0}
    end end
    pointer_image={width=32,height=24,pixels=pixels}
end
local pointer_cache,pointer_order={},{}
local previous_png,failed_png,previous_path,failed_path
refresh_pointer=function()
    -- 这里必须用裸 io.open：指针图在模组安装目录（mod.mod_dir）下，mod.read_file 只能读
    --   mod.private_dir；pointer_png.lua 是纯 Lua 的 PNG 解码器（不是数据包），必须读原始字节。
    --   只读、仅在首次加载 / 切换指针样式时执行一次，不在钩子内。
    local path=(mod.mod_dir or '.')..'/'..POINTER_FILES[pointer_style]
    local ok,data=pcall(function()
        local f=io.open(path,'rb');if not f then return nil end
        local bytes=f:read(2097153);f:close();return bytes
    end)
    if not ok or not data then
        if failed_png~='missing' or failed_path~=path then failed_png='missing';failed_path=path;log('未能读取指针图片，保留当前指针：'..POINTER_FILES[pointer_style]) end
        return
    end
    if (path==previous_path and data==previous_png) or (path==failed_path and data==failed_png) then return end
    local decoded,img=pcall(PNG.decode,data)
    if not decoded then
        failed_png=data;failed_path=path;log('指针图片读取失败，保留当前指针：'..tostring(img));return
    end
    pointer_image=img;previous_png=data;previous_path=path;failed_png=nil;failed_path=nil
    pointer_cache,pointer_order={},{}
    log(POINTER_FILES[pointer_style]..'已加载 '..img.width..'x'..img.height)
end
local ZERO={0,0,0,0}
local function pixel_at(x,y)
    local im=pointer_image
    if x<0 or y<0 or x>=im.width or y>=im.height then return ZERO end
    return im.pixels[y*im.width+x+1]
end
local function pointer_pixels(angle,size)
    -- 指针图标保持正立，只根据 Boss 在玩家左侧/右侧做水平镜像。
    -- 旧版按角度逐帧旋转整张图片，会让人物/图案在上下方向倒转。
    size=math.max(0.5,math.min(1,size or 1))
    local size_key=math.floor(size*64+0.5)
    local mirror=math.cos(angle)<0
    local key=(mirror and 100000 or 0)+size_key
    if pointer_cache[key] then return pointer_cache[key] end
    local cells={};local im=pointer_image
    -- 大图自动缩小到60像素；小图保留原尺寸。
    local scale=math.min(1,60/math.max(im.width,im.height))*(size_key/64)
    local bound=math.ceil(math.sqrt(im.width^2+im.height^2)*scale/2)+1
    for y=-bound,bound do
        for x=-bound,bound do
            local sx=(im.width-1)/2+(mirror and -x or x)/scale
            local sy=(im.height-1)/2+y/scale
            local ix,iy=math.floor(sx),math.floor(sy)
            local fx,fy=sx-ix,sy-iy
            local p,q,r,t=pixel_at(ix,iy),pixel_at(ix+1,iy),pixel_at(ix,iy+1),pixel_at(ix+1,iy+1)
            local w1,w2,w3,w4=(1-fx)*(1-fy),fx*(1-fy),(1-fx)*fy,fx*fy
            local aa=math.floor(p[4]*w1+q[4]*w2+r[4]*w3+t[4]*w4+0.5)
            if aa>3 then
                local function channel(i) return math.min(aa,math.max(0,math.floor(p[i]*w1+q[i]*w2+r[i]*w3+t[i]*w4+0.5))) end
                cells[#cells+1]={x=x,y=y,color=string.char(aa,channel(3),channel(2),channel(1))}
            end
        end
    end
    if #pointer_order>=64 then pointer_cache[table.remove(pointer_order,1)]=nil end
    pointer_order[#pointer_order+1]=key;pointer_cache[key]=cells
    return cells
end

local function block(batch,pixel,x,y,color)
    local w,h=H.pixel_w,H.pixel_h
    w,h=math.min(2,w),math.min(2,h)
    -- 1x1贴图时平铺补齐2x2，所有源矩形都在真实贴图范围内。
    for dy=0,2-h,h do
        for dx=0,2-w,w do draw_tex(batch,pixel,x+dx,y+dy,w,h,color) end
    end
end
local function ring(batch,pixel,cx,cy,angle,distance)
    local ux,uy=math.cos(angle),math.sin(angle)
    local radius=pointer_radius(distance)
    local x,y=math.floor(cx+ux*radius+0.5),math.floor(cy+uy*radius+0.5)
    -- 与收拢半径同步：最近半尺寸，最远完整尺寸；关闭距离变化时保持原大小。
    local size=0.5+0.5*math.max(0,math.min(1,(radius-48)/(RADIUS-48)))
    for _,cell in ipairs(pointer_pixels(angle,size)) do
        draw_tex(batch,pixel,x+cell.x,y+cell.y,1,1,cell.color)
    end
end
-- 用同一个已在真机生效的ref贴图通道绘制秒数，不调用按值DrawString。
local DIGITS={
 ['0']={'111','101','101','101','111'}, ['1']={'010','110','010','010','111'},
 ['2']={'111','001','111','100','111'}, ['3']={'111','001','111','001','111'},
 ['4']={'101','101','111','001','001'}, ['5']={'111','100','111','001','111'},
 ['6']={'111','100','111','101','111'}, ['7']={'111','001','010','010','010'},
 ['8']={'111','101','111','101','111'}, ['9']={'111','101','111','001','111'},
 ['s']={'011','100','010','001','110'},
}
local function timer(batch,pixel,cx,y,seconds)
    local text=tostring(seconds)..'s'
    local x0=cx-(#text*8-2)/2
    local color=seconds<=5 and URGENT or WHITE
    for i=1,#text do
        local rows=DIGITS[text:sub(i,i)]
        if rows then
            for row=1,5 do
                for col=1,3 do
                    if rows[row]:sub(col,col)=='1' then
                        local x=x0+(i-1)*8+(col-1)*2
                        local yy=y+(row-1)*2
                        block(batch,pixel,x+1,yy+1,DARK)
                        block(batch,pixel,x,yy,color)
                    end
                end
            end
        end
    end
end
local debuff_buf={}     -- v2.1: 结果缓冲复用（同帧用完即弃，不跨帧保存）
local debuff_rows={}    -- v2.1: 行对象复用，消除每帧 table 分配
local function debuffs(npc)
    local result=debuff_buf
    for i=#result,1,-1 do result[i]=nil end
    local types=value(H.n.buff,npc,'object')
    local times=value(H.n.time,npc,'object')
    local flags=value(H.debuff,nil,'object')
    if not (types and times and flags) then return result end
    local n=P.array_length(types)
    if not finite(n) or n<=0 then n=20 end -- 此手机版 NPC 的20格；不探测越界元素
    n=math.min(n,20)
    for i=0,n-1 do
        local id=P.array_at(types,i,'int32')
        local time=P.array_at(times,i,'int32')
        if finite(id) and id>0 and id<H.buff_limit and finite(time) and time>0
           and P.array_at(flags,id,'bool')==true then
            local k=#result+1
            local row=debuff_rows[k]
            if not row then row={};debuff_rows[k]=row end
            row.id=id;row.seconds=math.ceil(time/60)
            result[k]=row
            if #result==MAX_BUFFS then break end
        end
    end
    return result
end
local function step(_,args)
    if disabled then return end
    if args and args[1]==true then return end -- 只在前景 NPC 绘制完成后画一次
    -- v2.15.1：Boss 待机模式。
    --   场上没 Boss 时，每帧只做 2 次纯 Lua 判断就返回（0 次托管调用），
    --   每 300 帧（5 秒）才做一次兜底全扫 —— 用于兜住「世界加载时场上已经有 Boss」
    --   这类 NPC.NewNPC 不会触发的情况。
    --   Boss 一出生由 on_new_npc 点亮 H.seen，立刻恢复每 10 帧全扫，手感与原来一致。
    -- v2.17.0：与 Boss 血条联动启动。
    --   血条模块的 GUIBossBar.Draw prefix 只在有 Boss 血条时被调用，每帧置 _G.g_bb_boss_seen。
    --   指针待机时每帧读一次这个全局（纯 Lua，0 托管调用），血条一亮指针就跟着高频，
    --   不必等 5 秒兜底全扫。血条被停用/失败时此标志不再出现，指针自动退回原待机逻辑。
    if not H.seen and _G.g_bb_boss_seen then
        H.seen = true; H.miss = 0; _G.g_bb_boss_seen = nil
    end
    if not H.seen then
        H.tick = (H.tick or 0) + 1
        if H.tick % 300 ~= 1 then return end
    end
    local user=value(H.active_user,nil,'object') or value(H.primary_user,nil,'object')
    local state=user and value(H.user_state,user,'object')
    if not state then
        if not H.state_warning then H.state_warning=true;log('等待本地用户GameState') end
        return
    end
    if value(H.menu,state,'bool')==true then reset(); return end
    local players=value(H.players,nil,'object')
    local idx=value(H.my_player,state,'int32')
    if not players or not finite(idx) or idx<0 or idx>254 then return end
    local player=P.array_at(players,idx)
    if not player or value(H.p.active,player,'bool')~=true then return end
    local px,py=center(player,H.p)
    if not px then return end
    local sx,sy=P.get_field_vec2(H.camera,state)
    if not (finite(sx) and finite(sy)) then return end
    frames=frames+1
    -- v2.0.1：取消每120帧轮询 config.json（合并版无Boss设置项，setup 已读一次）
    -- v2.8.1：取消每300帧的 refresh_pointer() 轮询。该调用位于绘制钩子（Main.DrawNPCs
    --   postfix）内，每次都会把 57KB 的 pointer.png 完整读一遍 —— 属于「钩子内文件 I/O」，
    --   正是当初双开闪退那类病灶。而合并版并没有任何运行时改指针样式的入口
    --   （refresh_config 只在 bd_setup 里调用一次），指针图又是包内固定文件、不会变化，
    --   所以这条轮询纯属多余。删除后本模组在游戏钩子内已无任何文件 I/O。
    if not announced and frames>=30 then
        local s=P.string_create('大肥鱼指针已启动')
        if H.chat and s and P.invoke(H.chat,s,255,210,70,false)~=false then
            announced=true; log('进入世界，聊天提示已发送')
        end
    end
    local batch=value(H.batch,nil,'object')
    if not batch or value(H.begun,batch,'bool')~=true then
        if not H.batch_warning then H.batch_warning=true;log('等待有效 SpriteBatch.Begin') end
        return
    end
    local npcs=value(H.npcs,nil,'object')
    if not npcs then return end
    if not H.seen then
        -- 待机探测帧：真扫到了才算有 Boss（扫不到就继续待机）
        local t=pick_boss(npcs,px,py)
        if not t then target=nil; return end
        target=t; H.seen=true; H.miss=0
    elseif frames%10==1 then
        target=pick_boss(npcs,px,py)
        if target==nil then
            -- 连续 30 次（约 5 秒）扫不到才真正切回待机，避免 Boss 隐身/传送时来回抖
            H.miss=(H.miss or 0)+1
            if H.miss>=30 then H.seen=false; H.miss=0 end
        else
            H.miss=0
        end
    end
    if target==nil then
        if previous_target then log('Boss消失，停止绘制');previous_target=nil end
        return
    end
    local npc=P.array_at(npcs,target)
    if not npc or value(H.n.active,npc,'bool')~=true or value(H.n.life,npc,'int32')<=0 then
        target=nil;return
    end
    local bx,by,nx,ny,nw,nh=center(npc,H.n)
    if not bx then target=nil;return end
    -- 原生指针不能作为跨帧保活引用；先通过GCHandle取出仍存活的对象。
    H.scratch=P.invoke(H.gc_target,H.scratch_root)
    H.rect_scratch=P.invoke(H.gc_target,H.rect_root)
    assert(H.scratch and H.rect_scratch,'绘制缓冲GCHandle失效')
    local pixel=asset_texture(value(H.pixel,nil,'object'))
    if not pixel then return end
    H.pixel_w,H.pixel_h=value(H.tex_w,pixel,'int32'),value(H.tex_h,pixel,'int32')
    assert(finite(H.pixel_w) and finite(H.pixel_h) and H.pixel_w>0 and H.pixel_h>0,'MagicPixel尺寸无效')
    if not H.draw_started then
        H.draw_started=true
        log('开始首轮指针绘制；缓冲GC保活已确认')
    end
    ring(batch,pixel,px-sx,py-sy,math.atan(by-py,bx-px),math.sqrt((bx-px)^2+(by-py)^2))
    if previous_target~=target then
        previous_target=target;log('锁定Boss槽位 '..target..'，指针绘制已执行')
    end
    local ids=debuffs(npc)
    if H.last_buff_count~=#ids then H.last_buff_count=#ids;log('Boss负面Buff数量 '..#ids) end
    local textures=value(H.buff_textures,nil,'object')
    if not textures then return end
    local top=ny
    local raw=P.get_field_raw(H.n.frame,npc,16)
    local _,_,_,fh=string.unpack('<i4i4i4i4',raw)
    local scale=value(H.n.scale,npc,'float')
    if finite(fh) and fh>0 and fh<4096 and finite(scale) and scale>0 and scale<20 then
        top=math.min(top,ny+nh-fh*scale,by-fh*scale/2)
    end
    for i,buff in ipairs(ids) do
        local id=buff.id
        if H.load_buff then P.invoke(H.load_buff,id) end
        local texture=asset_texture(P.array_at(textures,id))
        if texture then
            local w,h=value(H.tex_w,texture,'int32'),value(H.tex_h,texture,'int32')
            if finite(w) and finite(h) and w>0 and h>0 and w<=256 and h<=256 then
                local icon_x=bx-sx-(#ids-1)*24-w/2+(i-1)*48
                local icon_y=top-sy-h-32
                draw_tex(batch,texture,icon_x,icon_y,w,h,WHITE)
                timer(batch,pixel,icon_x+w/2,icon_y+h+4,buff.seconds)
            end
        elseif not H.missing_icons[id] then
            H.missing_icons[id]=true;log('Buff贴图未就绪 ID='..id)
        end
    end
    if not H.draw_completed then H.draw_completed=true;log('首轮指针及Buff处理结束') end
end
local function safe_step(instance,args)
    do
        local ext=_G.EXT_DH and _G.EXT_DH.draw_npcs
        if ext then pcall(ext) end
    end
    if not CHW then return end
    if disabled then return end
    local ok,e=pcall(step,instance,args)
    if ok then failures=0;return end
    failures=failures+1;log('绘制错误 '..failures..': '..tostring(e))
    if failures>=3 then disabled=true;mod.warn('Boss方向提示：连续绘制错误，已停用') end
end
local function field(t,name)
    local f=P.get_field(t,name)
    assert(f,'缺少字段 '..name)
    return f
end
function bd_setup()
    refresh_pointer()
    refresh_config()
    log('初始化 v3.0；需要 Android Terraria 1.4.5.8 / LuaLoader 1.5.0+（兼容1.6.0）')
    if type(P.get_method_by_param_types)~='function'
       or type(P.make_generic_type)~='function' or type(P.field_pointer)~='function' then
        mod.warn('Boss方向提示：加载器缺少绘制接口，请升级到 LuaLoader 1.5.0+；未挂载游戏钩子')
        return
    end
    local ok,e=pcall(function()
        local main=P.get_type('Terraria','Main')
        local nt=P.get_type('Terraria','NPC')
        local pt=P.get_type('Terraria','Player')
        local st=P.get_type('','LocalUserGameState')
        local sb=P.get_type('Microsoft.Xna.Framework.Graphics','SpriteBatch')
        local tx=P.get_type('Microsoft.Xna.Framework.Graphics','Texture2D')
        local assets=P.get_type('Terraria.GameContent','TextureAssets')
        local generic=P.get_type('ReLogic.Content','Asset`1')
        assert(main and nt and pt and st and sb and tx and assets and generic,'游戏类型不匹配')
        H.asset_value=field(P.make_generic_type(generic,{tx}),'Value')
        local vec=P.get_type('Microsoft.Xna.Framework','Vector2')
        local rectangle=P.get_type('Microsoft.Xna.Framework','Rectangle')
        local color=P.get_type('Microsoft.Xna.Framework.Graphics','Color')
        assert(vec and rectangle and color,'缺少绘制参数类型')
        -- 内核将 ref 参数解析为它对应的类；Rectangle? 为另一个类，不会匹配。
        -- 四参重载以 Color 与 VertexColors 区分，不能只按参数数量选择。
        H.draw=P.get_method_by_param_types(sb,'Draw',{tx,vec,rectangle,color})
        assert(H.draw,'找不到 Draw(Texture2D,ref Vector2,ref Rectangle,ref Color)')
        log('参数类型匹配绘制方法成功')
        H.tex_w=field(tx,'Width')
        H.tex_h=field(tx,'Height')
        assert(H.tex_w and H.tex_h,'缺少贴图尺寸接口')
        local user_t=P.get_type('','LocalUser')
        local users_t=P.get_type('','UserManagement')
        assert(user_t and users_t,'缺少本地用户类型')
        H.active_user=field(user_t,'Active')
        H.primary_user=field(users_t,'PrimaryPlayer')
        H.user_state=field(user_t,'GameState')
        -- Instance是ThreadStatic；当前加载器字段指针接口不支持，不能读取它。
        H.menu=field(st,'gameMenu');H.my_player=field(st,'myPlayer');H.camera=field(st,'screenPosition')
        H.players=field(main,'player');H.npcs=field(main,'npc');H.batch=field(main,'spriteBatch')
        H.begun=field(sb,'_beginCalled');H.debuff=field(main,'debuff')
        H.pixel=field(assets,'MagicPixel');H.buff_textures=field(assets,'Buff')
        H.buff_limit=401 -- 上传的 Terraria 1.4.5.8 BuffID.Count
        H.missing_icons={}
        H.chat=P.get_method(main,'NewText',5)
        H.load_buff=P.get_method(main,'LoadBuff',1) -- 某些版本在资源加载时已初始化全部Buff
        local function entity(t)
            return {pos=field(t,'position'),w=field(t,'width'),h=field(t,'height'),active=field(t,'active')}
        end
        H.p=entity(pt);H.n=entity(nt)
        for key,name in pairs({life='life',friendly='friendly',boss='boss',kind='type',
            buff='buffType',time='buffTime',frame='frame',scale='scale'}) do H.n[key]=field(nt,name) end
        local ct=P.get_type('Terraria','CombatText')
        local gc=P.get_type('System.Runtime.InteropServices','GCHandle')
        assert(gc,'缺少GCHandle类型')
        local gc_alloc=P.get_method(gc,'GetTargetHandle',3)
        H.gc_target=P.get_method(gc,'GetTarget',1)
        H.gc_free=P.get_method(gc,'FreeHandle',1)
        assert(gc_alloc and H.gc_target and H.gc_free,'缺少GCHandle保活接口')
        H.roots={}
        local function rooted(t)
            local obj=P.new_instance(t)
            assert(obj,'无法分配独立绘制缓冲')
            -- GetTargetHandle返回IntPtr，避开GCHandle值类型返回的ABI编组。
            -- 2=Normal强引用；Boehm GC不移动对象，不需要Pinned。
            local root=P.invoke(gc_alloc,obj,nil,2)
            assert(root and root~=false,'GCHandle保活分配失败')
            H.roots[#H.roots+1]=root
            return obj,root
        end
        H.scratch,H.scratch_root=rooted(ct)
        H.rect_scratch,H.rect_root=rooted(nt)
        H.scratch_pos=field(ct,'position');H.scratch_color=field(ct,'color');H.scratch_rect=H.n.frame
        assert(P.field_pointer(H.scratch_pos,H.scratch),'仅支持Android字段指针')
        log('两个绘制缓冲已注册GC强引用')
        -- v8.9.14 曾在这里整段停用绘制钩子（排查「创建新地图闪退」）。
        --   v8.9.56 恢复：闪退真因是 tg 模块在 WorldGen.PlaceTile 里高频跨语言
        --   读 generatingWorld（v8.9.24/25 定位，v8.9.35 已删除该跨界读），
        --   跟绘制钩子无关 —— 当时那些 "Found matching method" 日志只是巧合。
        -- ===== 原实现（v8.9.56 恢复）=====
        local method=P.get_method(main,'DrawNPCs',1)
        assert(method,'缺少 Main.DrawNPCs')
        local h=P.install_hook(method,{postfix=safe_step})
        assert(h,'钩子安装失败');hooks[#hooks+1]=h
        if _G.EXT_DH then _G.EXT_DH.draw_npcs_hosted=true end
        -- v2.15.1：Boss 出生捕获。装不上不影响主功能，只是退回「每 5 秒兜底探测」。
        local mn=P.get_method(nt,'NewNPC',10) or P.get_method(nt,'NewNPC')
        if mn then
            local okn,hn=pcall(P.install_hook,mn,{postfix=on_new_npc})
            if okn and hn then hooks[#hooks+1]=hn
            else log('NewNPC 钩子安装失败，改用纯兜底探测') end
        else log('NewNPC 方法未找到，改用纯兜底探测') end
        log('初始化成功：ref贴图绘制、真实相机、独立缓冲；没有战斗文字槽位写入')
    end)
    if not ok then disabled=true;release_roots();mod.warn('Boss方向提示初始化失败: '..tostring(e)) end
end
function bd_cleanup()
    disabled=true
    for _,h in ipairs(hooks) do pcall(function() h:remove() end) end
    hooks={};release_roots();log('已卸载，GC强引用已释放')
end

return bd_setup, bd_cleanup
end)()
-- ============================================================================
-- ============================================================================
-- 第六部分：光源穿透（lzup.lua.lightpenetration v1.2.0 合并改造）
-- 改造：去 mod.meta；setup -> lp_setup；钩子句柄捕获供清理；默认常开（无开关）。
-- 功能：Hook LightingEngine.UpdateLightDecay postfix，把光照衰减缩到原来的 30%，
--       火把等光源照明范围约扩大 3 倍（仅彩色照明模式生效）。
lp_setup, lp_cleanup = (function()
-- Copyright (C) 2026 lzup333
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- 光源穿透 (LightPenetration) —— LuaLoader (Lua) 版
-- 由 KernelLoader(C) 版 Mods/TEKernelMods/LightPenetration/main.c 移植, 功能对齐。
--
-- 功能:
--   降低光照衰减系数, 让光源照得更远。仅彩色照明模式(新光照引擎 LightingEngine)生效。
--   穿透强度由 PENETRATION_FACTOR 控制(0~1), 当前 0.3:
--     衰减降到原来的 30%, 光照范围约扩大 3 倍。
--
-- C 版实现:
--   Hook LightingEngine.UpdateLightDecay 的 Postfix;
--   该方法每帧把衰减写入 _workingLightMap (LightMap):
--     LightDecayThroughAir / LightDecayThroughSolid;
--   LightMap 传播是乘法 light *= decay, Postfix 把衰减改为
--     new = 1 - (1 - old) * PENETRATION_FACTOR
--   _workingLightMap 每帧可能被换新, 所以每帧重新取。
--
-- Lua 版差异 / 限制:
--   * 属性->访问器桥接: 已用 LuaLoader 1.3.0 的 patch.property_get_method /
--     patch.property_set_method 从属性句柄取 getter/setter 调用(与 C 版同款能力)。
--     若属性桥接取不到, 回退编译期访问器方法名:
--       get_/set_LightDecayThroughAir、get_/set_LightDecayThroughSolid;
--     再取不到回退自动属性的后备字段 <X>k__BackingField(已做判空与告警)。
--   * postfix 仅改字段/属性, 不改原方法返回值, 与 C 版语义一致。
--
-- Hook 失败不影响游戏运行。

local patch = mod.patch

-- ============ 穿透强度 (0.0 ~ 1.0, 衰减系数缩放倍数) ============
local PENETRATION_FACTOR = 0.3

-- ============ 句柄 ============
local F_working_light_map            -- LightingEngine._workingLightMap (object)
local acc_air                        -- LightMap.LightDecayThroughAir 访问器
local acc_solid                      -- LightMap.LightDecayThroughSolid 访问器

local fired = false
local lp_hook  -- 合并版：保存钩子句柄供清理卸载

-- ============ 沿父类链查找字段 ============
local function find_field(type_handle, name)
    local cur, guard = type_handle, 0
    while cur and guard < 16 do
        local field = patch.get_field(cur, name)
        if field then return field end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

-- ============ 安全安装 Hook ============
local function safe_hook(method, spec, label)
    if not method then
        mod.error("安装钩子失败(" .. label .. ")：方法句柄为空")
        return false
    end
    local ok, h = pcall(patch.install_hook, method, spec)
    if not ok then
        mod.error("安装钩子失败(" .. label .. ")：" .. tostring(h))
        return false
    end
    lp_hook = h
    return true
end

-- ============ 解析一个 float 自动属性的读写通道 ============
-- 优先用 LuaLoader 1.3.0 的属性桥接取 getter/setter; 取不到再逐级回退。
-- 返回 { kind = "method", get = m_get, set = m_set } 或
--      { kind = "field", field = f } 或 nil
local function resolve_float_accessor(type_handle, prop_name)
    -- 1) 属性 -> 访问器桥接 (LuaLoader 1.3.0)
    local prop = patch.get_property(type_handle, prop_name)
    if prop then
        local getter = patch.property_get_method(prop)
        local setter = patch.property_set_method(prop)
        if getter and setter then
            return { kind = "method", get = getter, set = setter, bridge = true }
        end
    end
    -- 2) 回退: 编译期生成的访问器方法名
    local getter = patch.get_method(type_handle, "get_" .. prop_name, 0)
    local setter = patch.get_method(type_handle, "set_" .. prop_name, 1)
    if getter and setter then
        return { kind = "method", get = getter, set = setter }
    end
    -- 3) 回退: 自动属性的后备字段
    local backing = patch.get_field(type_handle, "<" .. prop_name .. ">k__BackingField")
    if backing then
        return { kind = "field", field = backing }
    end
    return nil
end

local function read_accessor(acc, instance)
    if not acc then return nil end
    if acc.kind == "method" then
        return patch.invoke(acc.get, instance)
    end
    return patch.get_field_value(acc.field, instance, "float")
end

local function write_accessor(acc, instance, value)
    if not acc then return end
    if acc.kind == "method" then
        patch.invoke(acc.set, instance, value)
    else
        patch.set_field_value(acc.field, instance, value, "float")
    end
end

-- ============ Postfix: LightingEngine.UpdateLightDecay ============
-- LightMap 传播是乘法(light *= decay), decay 越接近 1 衰减越弱。
-- 把"每格损失 (1 - decay)"缩小为原来的 PENETRATION_FACTOR 倍:
--   new = 1 - (1 - old) * PENETRATION_FACTOR
-- 例如原 decay=0.91, factor=0.3 => new=0.973, 光照传播距离约扩大 3 倍。
-- _workingLightMap 每帧可能被换新, 所以必须每帧重新取。
local function on_update_light_decay(instance)
    if not CHW then return end
    if not instance then return end
    if not F_working_light_map then return end

    local light_map = patch.get_field_value(F_working_light_map, instance, "object")
    if not light_map then return end

    if not fired then
        fired = true
    end

    if acc_air then
        local old = read_accessor(acc_air, light_map)
        if type(old) == "number" then
            write_accessor(acc_air, light_map, 1.0 - (1.0 - old) * PENETRATION_FACTOR)
        end
    end
    if acc_solid then
        local old = read_accessor(acc_solid, light_map)
        if type(old) == "number" then
            write_accessor(acc_solid, light_map, 1.0 - (1.0 - old) * PENETRATION_FACTOR)
        end
    end
end

-- ============ 初始化 ============
function lp_setup()
    local engine_type = patch.get_type("Terraria.Graphics.Light", "LightingEngine")
    if not engine_type then
        mod.error("获取类型失败 (Terraria.Graphics.Light.LightingEngine)")
        return
    end

    F_working_light_map = patch.get_field(engine_type, "_workingLightMap")
    if not F_working_light_map then
        mod.error("获取 _workingLightMap 字段失败")
        return
    end

    local lm_type = patch.get_type("Terraria.Graphics.Light", "LightMap")
    if lm_type then
        -- 存在性自检: 属性句柄存在则 resolve_float_accessor 可经属性桥接取到访问器
        local prop_air = patch.get_property(lm_type, "LightDecayThroughAir")
        local prop_solid = patch.get_property(lm_type, "LightDecayThroughSolid")
        acc_air = resolve_float_accessor(lm_type, "LightDecayThroughAir")
        acc_solid = resolve_float_accessor(lm_type, "LightDecayThroughSolid")
        if not prop_air and not prop_solid then
            mod.warn("LightMap 未找到 LightDecayThroughAir/Solid 属性")
        end
    end

    if not acc_air or not acc_solid then
        mod.error(string.format("获取 LightMap 衰减访问器失败: air=%s solid=%s",
                  tostring(acc_air ~= nil), tostring(acc_solid ~= nil)))
        return
    end

    local method = patch.get_method(engine_type, "UpdateLightDecay", 0)
            or patch.get_method(engine_type, "UpdateLightDecay")
    if not safe_hook(method, { postfix = _G.mg_gated("lp", on_update_light_decay) }, "UpdateLightDecay") then
        return
    end

end

-- ===== 合并版接线：清理（卸钩）=====
function lp_cleanup()
    if lp_hook and lp_hook.remove then pcall(function() lp_hook:remove() end) end
    lp_hook = nil
end

return lp_setup, lp_cleanup
end)()
-- 第七部分：遗忘之物（ForgottenItem-Refresh v1.2.1 合并改造）
-- 改造：去 mod.meta；setup -> _fi_raw_setup（外层 fi_setup 包装以记录钩子句柄）；
--       默认常开（无开关）。功能：被移除物品属性回归、掉落表补全、合成配方注册、
--       ItemID.Sets/PrefixLegacy 静态集合修正。
fi_setup, fi_cleanup, fi_set_enabled, fi_is_enabled, fi_scan_slot = (function()
-- ============================================================================
-- ForgottenItem-Refresh（遗忘之物 · Lua 版）
-- ----------------------------------------------------------------------------
-- 由 EternalFuture゙ 的 ForgottenItem（C++ / EFMod）移植而来，改用 LuaLoader 的
-- mod.patch 能力（基于 LuaLoader 1.4.2）。
--
-- 目标：Terraria 1.4.5.8（Android arm/arm64）
--
-- 挂钩选择（很重要）：
--   内核的 hook 用 libffi 生成闭包，只支持标量参数；对结构体按值参数会按
--   指针处理（见 TEFKernel src/patchlib/common/method.c: il2cpp_type_to_patch_type
--   把 IL2CPP_TYPE_VALUETYPE 映射成 PATCH_POINTER）。因此这里**不挂**带结构体
--   参数的方法，也不挂高频的 Main.Update(GameTime)：
--     * 物品属性  -> Item.SetDefaults(int, ItemVariant)  postfix（都是引用/标量）
--     * 掉落表    -> ItemDropDatabase.Populate()         postfix（0 参数）
--     * 配方      -> 用 0 参数的 Player.ResetEffects 作为每帧触发点，
--                    首帧等 numRecipes > 0 后统一写入 Recipe.currentRecipe + AddRecipe。
--
-- 针对 1.4.5.8 的适配：
--   1. Item.SetDefaults 只剩 (int Type, ItemVariant variant) 两个参数。
--   2. Android/IL2CPP 下 Item.useStyle / holdStyle 是 byte -> 写 "uint8"。
--   3. PrefixLegacy.ItemSets 已把 MagicAndSummon 拆分为 Magic / Summon。
--   4. Recipe.requiredTile 由 int[] 改为 int。
--
-- 加载器要求：
--   本 Mod 基于 **LuaLoader 1.4.2**（该版本给 mod.patch 增加了 get_inner_type）。
--   ItemID.Sets / PrefixLegacy.ItemSets 是嵌套类型，只能用
--   get_inner_type(ItemID, "Sets") / get_inner_type(PrefixLegacy, "ItemSets") 获取；
--   若加载器没有 get_inner_type（1.4.1），会自动退回旧写法（Android 上取不到），
--   此时「解除禁装 / 微光嬗变 / 词缀集合」会跳过并打日志。
--
-- 说明：睡觉图标(ID:5013) 的配方无材料，被跳过。
-- ============================================================================



local P = mod.patch

-- Android/IL2CPP 下 useStyle 是 byte；桌面端是 int
local T_USE_STYLE = (mod.platform == "android") and "uint8" or "int32"

-- ============================================================================
-- 工具
-- ============================================================================

local function first_type(candidates)
    for _, c in ipairs(candidates) do
        local t = P.get_type(c[1], c[2])
        if t then return t end
    end
    return nil
end

-- ============================================================================
-- 1) Item.SetDefaults —— 补回被移除物品 / 调整已有物品
-- ============================================================================

local item_type
local item_fields = {}
local buy_price
local set_weapon_values
local default_to_food
local default_to_food_v4   -- true = 1.4.6 的四参版（没有宽高）

local ITEM_FIELD_TYPES = {
    useStyle      = T_USE_STYLE,
    useAnimation  = "int32",
    useTime       = "int32",
    width         = "int32",
    height        = "int32",
    shoot         = "int32",
    useAmmo       = "int32",
    damage        = "int32",
    shootSpeed    = "float",
    noMelee       = "bool",
    value         = "int32",
    ranged        = "bool",
    channel       = "bool",
    rare          = "int32",
    autoReuse     = "bool",
    mana          = "int32",
    magic         = "bool",
    noUseGraphic  = "bool",
}

local function iset(name, inst, value)
    local f = item_fields[name]
    if f then
        P.set_field_value(f, inst, value, ITEM_FIELD_TYPES[name])
    end
end

local function price(platinum, gold, silver, copper)
    if not buy_price then return 0 end
    local v = P.invoke(buy_price, platinum, gold, silver, copper)
    if type(v) == "number" then return v end
    return 0
end

local statics_ready = false

-- v2.11.14：需要「重算属性」的物品 ID 白名单（与下面 on_set_defaults 的各个分支一一对应）
--   这些物品在 1.4.5.8 里被官方移除/削过，靠重算一遍把属性补回来。
local FI_FIX_IDS = {
    [2881] = true,  -- 相位扭曲弹射器
    [3850] = true,  -- 埃特尼亚标枪
    [3853] = true,  -- 无趣弓
    [4058] = true,  -- 骷髅头弓
    [4722] = true,  -- 第一分形
    [4010] = true,  -- 苹果派切片
}

function on_set_defaults(inst, args)
    if not statics_ready then
        local a = apply_itemid_sets()
        local b = apply_prefix_sets()
        statics_ready = (a or b)
    end

    local t = args[1]

    if t == 2881 then
        -- 相位扭曲弹射器
        iset("useStyle", inst, 5)
        iset("useAnimation", inst, 20)
        iset("useTime", inst, 80)
        iset("shootSpeed", inst, 500.0)
        iset("width", inst, 20)
        iset("height", inst, 12)
        iset("damage", inst, 550)
        iset("shoot", inst, 79)
        iset("mana", inst, 100)
        iset("rare", inst, 8)
        iset("value", inst, price(0, 10, 0, 0))       -- 10 金
        iset("noMelee", inst, true)
        iset("channel", inst, true)
        iset("magic", inst, true)

    elseif t == 3850 then
        -- 埃特尼亚标枪
        iset("useStyle", inst, 1)
        iset("shootSpeed", inst, 55.5)
        iset("shoot", inst, 680)
        iset("damage", inst, 71)
        iset("width", inst, 0)
        iset("height", inst, 30)
        iset("useAnimation", inst, 17)
        iset("useTime", inst, 17)
        iset("noUseGraphic", inst, true)
        iset("noMelee", inst, true)
        iset("value", inst, price(0, 5, 0, 0))        -- 5 金
        iset("ranged", inst, true)
        iset("rare", inst, 6)

    elseif t == 3853 then
        -- 无趣弓
        iset("useStyle", inst, 5)
        iset("useAnimation", inst, 25)
        iset("useAmmo", inst, 40)
        iset("width", inst, 20)
        iset("height", inst, 34)
        iset("shoot", inst, 1)
        iset("damage", inst, 72)
        iset("shootSpeed", inst, 50.0)
        iset("noMelee", inst, true)
        iset("value", inst, 180000)
        iset("ranged", inst, true)
        iset("useTime", inst, 12)
        iset("channel", inst, true)
        iset("rare", inst, 6)
        iset("autoReuse", inst, true)

    elseif t == 4058 then
        -- 骷髅头弓：基础伤害 8 -> 30，击退 5.0
        iset("damage", inst, 40)
        if set_weapon_values then
            P.invoke(set_weapon_values, inst, 30, 5.0, 0)
        end

    elseif t == 4722 then
        -- 第一分形：伤害 190 -> 130
        iset("noMelee", inst, false)
        iset("damage", inst, 130)

    elseif t == 4010 then
        -- 苹果派切片：酒足饭饱 4 分钟
        if default_to_food then
            if default_to_food_v4 then
                P.invoke(default_to_food, inst, 207, 14400, false, 17)
            else
                P.invoke(default_to_food, inst, 22, 22, 207, 14400, false, 17)
            end
        end
        iset("rare", inst, 3)
        iset("value", inst, price(0, 0, 70, 5))       -- 70 银 5 铜
    end
end

-- ============================================================================
-- 2) ItemID.Sets（嵌套类型，Lua 侧取不到 -> 目前仅尝试并告警）
-- ============================================================================

local itemid_fields = {}

function apply_itemid_sets()
    local applied = false

    for _, name in ipairs({ "Deprecated", "ItemsThatShouldNotBeInInventory" }) do
        local f = itemid_fields[name]
        if f then
            local arr = P.get_field_value(f, nil, "object")
            if arr then
                P.array_fill(arr, false, "bool")
                applied = true
            end
        end
    end

    local f = itemid_fields.ShimmerTransformToItem
    if f then
        local arr = P.get_field_value(f, nil, "object")
        if arr then
            applied = true
            local pairs_to_set = {
                { 3357, 3331 }, { 3868, 3861 }, { 3862, 3867 }, { 2881, 3358 },
                { 3847, 3865 }, { 3854, 3853 }, { 2901, 2989 }, { 2990, 2902 },
                { 3404, 1649 }, { 3398, 1648 }, { 1569, 1571 },
            }
            for _, pr in ipairs(pairs_to_set) do
                P.array_set(arr, pr[1], pr[2], "int32")
                P.array_set(arr, pr[2], pr[1], "int32")
            end
        end
    end

    return applied
end

-- ============================================================================
-- 3) PrefixLegacy.ItemSets（嵌套类型，同上）
-- ============================================================================

local prefix_fields = {}

function apply_prefix_sets()
    local applied = false

    local function mark(name, id)
        local f = prefix_fields[name]
        if f then
            local arr = P.get_field_value(f, nil, "object")
            if arr then
                P.array_set(arr, id, true, "bool")
                applied = true
            end
        end
    end

    mark("SwordsHammersAxesPicks", 4722)
    mark("Magic", 2881)
    mark("GunsBows", 3850)
    mark("GunsBows", 3853)
    mark("GunsBows", 4058)

    return applied
end

-- ============================================================================
-- 4) ItemDropDatabase.Populate —— 掉落表
-- ============================================================================

local drop_common
local drop_register

local function drop_to(db, npc, item, chance)
    if not (drop_common and drop_register) then return end
    local rule = P.invoke(drop_common, item, chance, 1, 1)
    if rule then
        P.invoke(drop_register, db, npc, rule)
    end
end

function on_populate(db)
    drop_to(db, 395, 2881, 50)                                   -- 火星飞碟核心
    drop_to(db, 564, 3853, 10)
    drop_to(db, 565, 3853, 10)
    drop_to(db, 561, 3850, 10)
    drop_to(db, 562, 3850, 10)
    drop_to(db, 563, 3850, 10)
    for _, npc in ipairs({ 552, 553, 554, 555, 556, 557 }) do
        drop_to(db, npc, 3848, 10)
    end
    for _, npc in ipairs({ 555, 556, 557 }) do
        drop_to(db, npc, 3849, 10)
    end
    drop_to(db, 572, 3851, 10)
    drop_to(db, 573, 3851, 10)
end

-- ============================================================================
-- 5) 合成配方
-- ============================================================================

local RECIPES = {
    -- 夜明工具组：对应碎片 x6 + 夜明锭 x5，远古操纵机(LunarCraftingStation = 412)
    { result = 2785, ingredients = { { item = 3458, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2775, ingredients = { { item = 3456, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2780, ingredients = { { item = 3457, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 3465, ingredients = { { item = 3459, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2782, ingredients = { { item = 3458, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2772, ingredients = { { item = 3456, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2777, ingredients = { { item = 3457, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 3462, ingredients = { { item = 3459, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2783, ingredients = { { item = 3458, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2773, ingredients = { { item = 3456, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 2778, ingredients = { { item = 3457, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },
    { result = 3463, ingredients = { { item = 3459, stack = 6 }, { item = 3467, stack = 5 } }, tile = 412 },

    -- 旧礼物（无工作站）
    { result = 599, ingredients = { { item = 1869, stack = 1 } } },
    { result = 600, ingredients = { { item = 1869, stack = 1 } } },
    { result = 601, ingredients = { { item = 1869, stack = 1 } } },

    -- 骷髅头弓（工作台 = 18）
    { result = 4058, ingredients = { { item = 1274, stack = 1 }, { item = 154, stack = 50 } }, tile = 18 },
    -- 彩色染料（染缸 = 228）
    { result = 3978, ingredients = { { item = 3385, stack = 1 }, { item = 3386, stack = 1 }, { item = 3387, stack = 1 }, { item = 3388, stack = 1 } }, tile = 228 },
    -- 苹果派切片（无工作站，一次 4 个）
    { result = 4010, stack = 4, ingredients = { { item = 4011, stack = 1 } } },
    -- 苹果派（无工作站）
    { result = 4011, ingredients = { { item = 4010, stack = 4 } } },
    -- 第一分形（秘银砧 / 山铜砧 = 134）
    { result = 4722, ingredients = { { item = 757, stack = 1 }, { item = 3827, stack = 1 }, { item = 3787, stack = 1 }, { item = 1570, stack = 2 }, { item = 2880, stack = 1 } }, tile = 134 },
    -- 骨块（工作台 = 18）
    { result = 766, ingredients = { { item = 154, stack = 1 } }, tile = 18 },
    -- 假宝箱
    { result = 3705, ingredients = { { item = 3886, stack = 1 } } },
    { result = 3706, ingredients = { { item = 3887, stack = 1 } } },

    -- 睡觉图标：无材料，跳过
    -- { result = 5013, ingredients = {}, tile = 79 },
}

local function count_ingredients(r)
    local n = 0
    for _ in ipairs(r.ingredients) do n = n + 1 end
    return n
end

-- 手动注册（发布版 LuaLoader 1.4.1 没有 mod.recipe）
--   触发点用 0 参数的 Player.ResetEffects，避免 Main.Update(GameTime) 的参数编组问题。
local recipe_type
local f_current_recipe
local f_create_item
local f_required_item
local f_required_tile
local f_num_recipes
local f_item_stack
local m_add_recipe
local m_item_net_defaults
local m_create_quick
local m_update_materials

local recipes_added = false

local function recipes_ready()
    if not (f_num_recipes and m_add_recipe) then return false end
    local n = P.get_field_value(f_num_recipes, nil, "int32")
    return type(n) == "number" and n > 0
end

local function add_one(r)
    if not (f_current_recipe and f_create_item and f_required_item and m_add_recipe and m_item_net_defaults) then
        return false
    end

    local cur = P.get_field_value(f_current_recipe, nil, "object")
    if not cur then return false end

    local create = P.get_field_value(f_create_item, cur, "object")
    if not create then return false end
    P.invoke(m_item_net_defaults, create, r.result)
    if f_item_stack then
        P.set_field_value(f_item_stack, create, r.stack or 1, "int32")
    end

    local req = P.get_field_value(f_required_item, cur, "object")
    if not req then return false end
    for i, ing in ipairs(r.ingredients) do
        local slot = P.array_at(req, i - 1) -- requiredItem 是 0 基数组
        if slot then
            P.invoke(m_item_net_defaults, slot, ing.item)
            if f_item_stack then
                P.set_field_value(f_item_stack, slot, ing.stack or 1, "int32")
            end
        end
    end

    if r.tile and r.tile >= 0 and f_required_tile then
        P.set_field_value(f_required_tile, cur, r.tile, "int32")
    end

    P.invoke(m_add_recipe)
    return true
end

local function add_all_recipes()
    local ok_count = 0
    for _, r in ipairs(RECIPES) do
        if count_ingredients(r) == 0 then
            mod.warn("跳过无材料配方 result=" .. tostring(r.result))
        else
            local ok, done = pcall(add_one, r)
            if ok and done then
                ok_count = ok_count + 1
            else
                mod.warn("配方注册失败 result=" .. tostring(r.result) .. " -> " .. tostring(done))
            end
        end
    end

    if m_create_quick then P.invoke(m_create_quick) end
    if m_update_materials then P.invoke(m_update_materials) end

end

-- Player.ResetEffects()：0 参数，每帧执行，作为延迟注册的触发点
function on_player_frame(inst, args)
    if recipes_added then return end
    if not recipes_ready() then return end
    recipes_added = true
    add_all_recipes()
end

local function setup_manual_recipes()
    recipe_type = first_type({ { "Terraria", "Recipe" } })
    if not recipe_type then
        mod.warn("找不到 Terraria.Recipe，跳过配方注册")
        return
    end

    f_current_recipe = P.get_field(recipe_type, "currentRecipe")
    f_create_item = P.get_field(recipe_type, "createItem")
    f_required_item = P.get_field(recipe_type, "requiredItem")
    f_required_tile = P.get_field(recipe_type, "requiredTile")
    f_num_recipes = P.get_field(recipe_type, "numRecipes")
    m_add_recipe = P.get_method(recipe_type, "AddRecipe", 0)
    m_create_quick = P.get_method(recipe_type, "CreateRequiredItemQuickLookups", 0)
    m_update_materials = P.get_method(recipe_type, "UpdateWhichItemsAreMaterials", 0)
    f_item_stack = P.get_field(item_type, "stack")
    m_item_net_defaults = P.get_method(item_type, "netDefaults", 1)

    if f_current_recipe and m_add_recipe and m_item_net_defaults then
        -- v2.8.0：不再单独装 ResetEffects 钩子，改注册到节拍总线
        tb_reg_reset("遗忘之物", on_player_frame)
    else
        mod.warn("Recipe 符号不完整，跳过配方注册")
    end
end

-- ============================================================================
-- setup
-- ============================================================================

local function _fi_raw_setup()
    mod.info("ForgottenItem-Refresh 初始化（%s/%s）", mod.platform, mod.arch)

    -- ---- Item ----
    item_type = first_type({ { "Terraria", "Item" } })
    if not item_type then
        mod.warn("找不到 Terraria.Item，终止初始化")
        return
    end

    for name in pairs(ITEM_FIELD_TYPES) do
        item_fields[name] = P.get_field(item_type, name)
    end
    buy_price = P.get_method(item_type, "buyPrice", 4)
    set_weapon_values = P.get_method(item_type, "SetWeaponValues", 3)
    -- 1.4.6：Item 不再有 width/height，DefaultToFood 也从六参改成四参
    --   （foodbuff, duration, gulp, animTime）。1.4.5.8 仍是六参（前两位是宽高）。
    default_to_food = P.get_method(item_type, "DefaultToFood", 6)
    if not default_to_food then
        default_to_food = P.get_method(item_type, "DefaultToFood", 4)
        default_to_food_v4 = (default_to_food ~= nil)
    end

    -- v2.11.14：不再常驻挂 Item.SetDefaults 钩子。
    --   实测结论：全物品存档一进世界，物品初始化有几万次调用，钩子密度直接把进程打崩
    --   （SIGABRT / JniAbort，pcall 兜不住）。改为由增益家具的背包/仓库扫描发现目标物品时，
    --   直接对该物品实例重跑 on_set_defaults（见 fi_scan_slot，v2.19.1 起每槽位只修一次）。
    --   （item_type 仍保留，配方注册那边要用它的 stack 字段）

    -- ---- ItemID.Sets / PrefixLegacy.ItemSets（嵌套类型）----
    -- 1.4.2+：用 get_inner_type(parent, "Sets") 取；1.4.1：退回 get_type 全名（Android 上取不到）。
    local function nested(outer_candidates, inner_name, fallback_candidates)
        if type(P.get_inner_type) == "function" then
            local outer = first_type(outer_candidates)
            if outer then
                local t = P.get_inner_type(outer, inner_name)
                if t then return t end
            end
        end
        return first_type(fallback_candidates)
    end

    local sets = nested(
        { { "Terraria.ID", "ItemID" } },
        "Sets",
        { { "Terraria.ID", "ItemID.Sets" }, { "", "ItemID.Sets" } }
    )
    if sets then
        for _, name in ipairs({ "Deprecated", "ItemsThatShouldNotBeInInventory", "ShimmerTransformToItem" }) do
            itemid_fields[name] = P.get_field(sets, name)
        end
        apply_itemid_sets()
        local m = P.get_method(sets, ".cctor", 0)
        if m then P.install_hook(m, { postfix = function() apply_itemid_sets() end }) end
    else
        mod.warn("找不到 ItemID.Sets（需要 LuaLoader 1.4.2+ 的 get_inner_type；跳过禁装/微光）")
    end

    local prefix = nested(
        { { "Terraria.GameContent.Prefixes", "PrefixLegacy" } },
        "ItemSets",
        { { "Terraria.GameContent.Prefixes", "PrefixLegacy.ItemSets" }, { "", "PrefixLegacy.ItemSets" } }
    )
    if prefix then
        for _, name in ipairs({ "SwordsHammersAxesPicks", "Magic", "GunsBows" }) do
            prefix_fields[name] = P.get_field(prefix, name)
        end
        apply_prefix_sets()
        local m = P.get_method(prefix, ".cctor", 0)
        if m then P.install_hook(m, { postfix = function() apply_prefix_sets() end }) end
    else
        mod.warn("找不到 PrefixLegacy.ItemSets（需要 LuaLoader 1.4.2+ 的 get_inner_type；跳过词缀集合）")
    end

    -- ---- ItemDropDatabase ----
    local dropdb = first_type({ { "Terraria.GameContent.ItemDropRules", "ItemDropDatabase" } })
    local rule = first_type({ { "Terraria.GameContent.ItemDropRules", "ItemDropRule" } })
    if dropdb and rule then
        drop_common = P.get_method(rule, "Common", 4)
        drop_register = P.get_method(dropdb, "RegisterToNPC", 2)
        local m = P.get_method(dropdb, "Populate", 0)
        if m and drop_common and drop_register then
            P.install_hook(m, { postfix = on_populate })
        else
            mod.warn("掉落注册符号不完整，跳过掉落表")
        end
    else
        mod.warn("找不到 ItemDropDatabase / ItemDropRule")
    end

    -- ---- Recipe ----
    -- 只针对发布版 LuaLoader 1.4.1（它没有 mod.recipe），因此走手动注册路径。
    setup_manual_recipes()

end

-- ===== 合并版接线：包装 setup 以捕获钩子句柄 =====
local fi_hooks = {}
local FI_EN = false  -- 总开关（v5.7.6 起默认关闭；fi_en.txt 持久化）
local function fi_setup()
    do
        local ok, s = pcall(function() return mod.read_file("fi_en.txt") end)
        -- v7.6.3 修复：原写法只处理 "0"，读到 "1" 时不置 true，导致重启后开关失效
        --   现在：读到任意字符串即以此为准（"0" = 关，其他 = 开）；读不到保持初值 false
        if ok and type(s) == "string" and s ~= "" then
            FI_EN = (s:sub(1, 1) ~= "0")
        end
    end
    if not FI_EN then return end   -- 关闭状态：不挂钩
    if fi_hooks[1] then return end -- v7.6.3：幂等保护，避免重复点「开」时重复装钩子
    local saved = P.install_hook
    P.install_hook = function(m, opts)
        local h = saved(m, opts)
        if h then table.insert(fi_hooks, h) end
        return h
    end
    local ok, err = pcall(_fi_raw_setup)
    P.install_hook = saved
    if not ok then error(err, 0) end
end
function fi_cleanup()
    for _, h in ipairs(fi_hooks) do
        if h and h.remove then pcall(function() h:remove() end) end
    end
    fi_hooks = {}
end
-- ===== 合并版接线：遗忘之物总开关（模组设置页控制，持久化 fi_en.txt）=====
function fi_set_enabled(b)
    FI_EN = (b and true or false)
    if not FI_EN then
        fi_cleanup()
    else
        pcall(fi_setup)
    end
end
function fi_is_enabled() return FI_EN end
-- v2.19.1：搭在增益家具的扫描上，按「仓储标签 + 槽位号」去重，每槽位同一物品只修一次。
--   槽位空了（t<=0）就清记录，之后同一槽位再放进同样物品会重新修一次。
local fi_seen = {}
function fi_scan_slot(key, t, inst)
    if type(t) ~= "number" then return end
    if t <= 0 then
        if fi_seen[key] ~= nil then fi_seen[key] = nil end
        return
    end
    if not FI_EN then return end
    if not FI_FIX_IDS[t] then return end
    if not inst then return end
    if fi_seen[key] == t then return end
    fi_seen[key] = t
    pcall(on_set_defaults, inst, { t })
end
return fi_setup, fi_cleanup, fi_set_enabled, fi_is_enabled, fi_scan_slot
end)()
-- 第八部分：快速放置（参考 属性工坊 ItemForge v2.0.0 的 place_speed 精简移植）
-- 改造：单个总开关「快速放置」（ps_en.txt，默认关闭）；开 = 300% 放置速度、关 = 100%（原速）。
-- 换算（同属性工坊 speed 模式）：新 useTime/useAnimation = 原值 × 100 ÷ 300，下限 3 帧
--   （属性工坊 min_use_time=3 同款保护，1 帧会导致部分工具失效）。
-- 分类（同属性工坊优先级）：镐/斧/锤>0、近战/远程/魔法/召唤、弹药 → 排除；
--   createTile>=0 或 createWall>=0 → 放置类。
-- 所有函数均 local，避免与遗忘之物的全局函数名冲突。
ps_setup, ps_cleanup, ps_set_enabled, ps_is_enabled = (function()
local P = mod.patch
local PS_EN = false      -- 快速放置总开关（默认关闭 = 100% 原速；ps_en.txt 持久化）
local PS_FAST = 300      -- 开启时的放置速度档位（固定 300%）
local PS_MIN_TIME = 3    -- 帧下限
local ps_hook
local ps_re_hook          -- v2.0.4：ResetEffects 钩子（延迟刷新用）
local ps_dirty = false    -- v2.0.4：脏标记——GUI 点击只置位，游戏上下文执行刷新
local F_inv              -- Player.inventory 句柄
local F = {}             -- Item 字段句柄
local PS_ORIG = {}       -- 每类物品的原版基准 {ut, ua}（切档/还原用）
-- v7.6.3：方案 B —— 不再挂 Item.SetDefaults 钩子
--   病因：钩子单次约 15 次 Lua<->C 跨界（is_placeable 里就占 10 次），
--         进世界时 SetDefaults 被调用几万次（背包+仓库+所有箱子+NPC商店+合成扫描），
--         全挤在一帧 -> SIGABRT / JniAbort，pcall 兜不住。
--   解法：进图后延迟武装（避开批量期），之后靠 ResetEffects 节拍总线低频扫描背包。
--         代价：箱子里的物品不再自动加速，只处理背包（0..118 格）。
local ps_armed = false        -- 进图武装标志（武装前一律不处理）
local ps_arm_cnt = 0          -- 进图后已过帧数
local ps_sweep_cnt = 0        -- 周期扫描计数器
local PS_ARM_FRAMES = 60      -- 进图后多少帧武装（约 1 秒）
local PS_SWEEP_FRAMES = 30    -- 武装后每多少帧扫一次背包
local PS_PLACE = {}           -- type -> 是否放置类（is_placeable 结果缓存）
local ps_told = false         -- 武装日志只打一次
-- v2.0.5：安全字段获取（pcall + 继承链回退，对齐属性工坊稳定范本）
--   裸 P.get_field 直取若拿不到会抛错/返回坏句柄，后续读写原生崩 0x10（pcall 挡不住）
local function find_field_s(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local ok, f = pcall(P.get_field, cur, name)
        if ok and f then return f end
        local ok2, par = pcall(P.get_parent, cur)
        if not ok2 then return nil end
        cur = par
        guard = guard + 1
    end
    return nil
end
-- v2.0.7：闪退已确认修复（12:09/12:14/12:32 三会话 0 崩溃），移除 v2.0.5 临时诊断 ps_trace 落盘

local function read_i(name, inst)
    local f = F[name]
    if not f or not inst then return nil end
    local ok, v = pcall(P.get_field_value, f, inst, "int32")
    if ok and type(v) == "number" then return v end
    return nil
end
local function read_b(name, inst)
    local f = F[name]
    if not f or not inst then return nil end
    local ok, v = pcall(P.get_field_value, f, inst, "bool")
    if ok then
        if v == true or v == 1 then return true end
        if v == false or v == 0 then return false end
    end
    return nil
end
local function write_i(name, inst, v)
    local f = F[name]
    if not f or not inst then return false end
    local ok = pcall(P.set_field_value, f, inst, v, "int32")
    return ok
end

local function is_placeable(inst)
    if (read_i("pick", inst) or 0) > 0 then return false end
    if (read_i("axe", inst) or 0) > 0 then return false end
    if (read_i("hammer", inst) or 0) > 0 then return false end
    if read_b("melee", inst) then return false end
    if read_b("ranged", inst) then return false end
    if read_b("magic", inst) then return false end
    if read_b("summon", inst) then return false end
    if (read_i("ammo", inst) or 0) ~= 0 then return false end
    local ct = read_i("createTile", inst)
    if ct and ct >= 0 then return true end
    local cw = read_i("createWall", inst)
    if cw and cw >= 0 then return true end
    return false
end

-- v7.6.3：is_placeable 的结果只取决于物品 type（字段由 SetDefaults 决定），可缓存。
--   缓存后单件处理从 ~15 次跨界降到 ~3 次（read type + 2 次条件写）。
local function is_placeable_cached(inst, ty)
    local v = PS_PLACE[ty]
    if v ~= nil then return v end
    v = is_placeable(inst)
    PS_PLACE[ty] = v
    return v
end
local function scaled(base)
    local t = math.floor(base * 100 / PS_FAST + 0.5)
    if t < PS_MIN_TIME then t = PS_MIN_TIME end
    if t < 1 then t = 1 end
    return t
end

-- v7.6.3：on_ps_set_defaults 已删除（不再挂 Item.SetDefaults 钩子，见上方说明）
--   原本它负责「刚被重置为原版值时立刻记录基准并缩放」，现改由 ps_apply_one 首次遇到时记录。

-- v2.0.5：单格处理整块 pcall（对齐属性工坊 apply_item 模式——任一格出错只跳过该格）
local function ps_apply_one(it)
    local ty = read_i("type", it)
    if not ty or ty <= 0 then return false end
    if not is_placeable_cached(it, ty) then return false end
    local ut = read_i("useTime", it)
    local ua = read_i("useAnimation", it)
    if not ut or not ua or ut <= 0 or ua <= 0 then return false end
    local orig = PS_ORIG[ty]
    if not orig then
        orig = { ut, ua }   -- 从未被本模块改写 → 当前即原版
        PS_ORIG[ty] = orig
    else
        -- v7.6.3 基准健壮化：当前值既不是记录的基准、也不是缩放值 → 基准变了，重记。
        --   典型场景：物品换了词缀（Prefix 会改 useTime），旧基准作废。
        local f_ut, f_ua = scaled(orig[1]), scaled(orig[2])
        if (ut ~= orig[1] and ut ~= f_ut) or (ua ~= orig[2] and ua ~= f_ua) then
            orig = { ut, ua }
            PS_ORIG[ty] = orig
        end
    end
    local t_ut, t_ua
    if PS_EN then
        t_ut, t_ua = scaled(orig[1]), scaled(orig[2])
    else
        t_ut, t_ua = orig[1], orig[2]
    end
    if t_ut ~= ut then write_i("useTime", it, t_ut) end
    if t_ua ~= ua then write_i("useAnimation", it, t_ua) end
    return true
end
-- v2.0.5：玩家实例由钩子直传（不再走 local_player() 数组取用——裸 invoke/array_length/array_at 是 pcall 挡不住的崩点）
local function ps_refresh(p)
    if not p or not F_inv then return 0 end
    local ok, arr = pcall(P.get_field_value, F_inv, p, "object")
    if not ok or not arr then return 0 end
    local ok2, n = pcall(P.array_length, arr)
    if not ok2 or type(n) ~= "number" or n <= 0 then return 0 end
    if n > 120 then n = 120 end   -- 背包上限保护（属性工坊 MAX_SWEEP_SLOTS 同款）
    local cnt = 0
    for i = 0, n - 1 do
        local ok3, it = pcall(P.array_at, arr, i)
        if ok3 and it then pcall(ps_apply_one, it) end
    end
    return cnt
end

-- v2.0.4 闪退修复：GUI 回调只打脏标记；真正刷新放游戏上下文执行
-- v2.0.5：玩家实例由 ResetEffects 钩子直传（inst 即触发本轮的玩家，绝对有效引用）
local function on_ps_tick(inst)
    -- v7.6.3：进图后先等 PS_ARM_FRAMES 帧（避开世界加载时的物品初始化高峰）
    if not ps_armed then
        ps_arm_cnt = ps_arm_cnt + 1
        if ps_arm_cnt < PS_ARM_FRAMES then return false end
        ps_armed = true
        ps_sweep_cnt = 0
        ps_dirty = true          -- 武装后立刻补刷一次，不必再等一个周期
        if not ps_told then
            ps_told = true
            pcall(mod.info, "[快速放置] 已武装：进图 %d 帧后启动，每 %d 帧扫一次背包",
                PS_ARM_FRAMES, PS_SWEEP_FRAMES)
        end
    end
    if not inst then return false end
    -- 开关切换时 ps_dirty 立刻置位；否则每 PS_SWEEP_FRAMES 帧扫一次
    if ps_dirty then
        ps_dirty = false
        ps_sweep_cnt = 0
        pcall(ps_refresh, inst)
        return false
    end
    ps_sweep_cnt = ps_sweep_cnt + 1
    if ps_sweep_cnt >= PS_SWEEP_FRAMES then
        ps_sweep_cnt = 0
        pcall(ps_refresh, inst)
    end
    return false
end
-- v7.6.3：ps_install_hook 已删除，方案 B 不再挂 Item.SetDefaults 钩子
local function ps_setup()
    PS_EN = false   -- 默认关闭
    do
        local ok, s = pcall(function() return mod.read_file("ps_en.txt") end)
        if ok and type(s) == "string" and s:sub(1, 1) == "1" then PS_EN = true end
    end
    local T_ITEM = P.get_type("Terraria", "Item")
    if not T_ITEM then
        mod.warn("快速放置：找不到 Terraria.Item，跳过")
        return
    end
    for _, name in ipairs({ "type", "useTime", "useAnimation", "pick", "axe", "hammer",
                            "ammo", "createTile", "createWall",
                            "melee", "ranged", "magic", "summon" }) do
        F[name] = find_field_s(T_ITEM, name)
    end
    if not (F.useTime and F.useAnimation and F.createTile) then
        mod.warn("快速放置：Item 字段不完整，跳过")
        return
    end
    local T_PLAYER = P.get_type("Terraria", "Player")
    if T_PLAYER then F_inv = find_field_s(T_PLAYER, "inventory") end
    -- v7.6.3：不再 ps_install_hook()（方案 B）。重置扫描状态，等进图后自动武装。
    ps_armed = false
    ps_arm_cnt = 0
    ps_sweep_cnt = 0
    ps_dirty = false
    -- v2.0.4：延迟刷新——背包刷新只在游戏自身回调（每帧 ResetEffects）里执行
    -- v2.8.0：改为注册到节拍总线（不再单独装 ResetEffects 钩子）
    tb_reg_reset("快速放置", on_ps_tick)
end

function ps_cleanup()
    -- 兜底：万一还有旧版残留钩子，一并卸掉
    if ps_hook and ps_hook.remove then pcall(function() ps_hook:remove() end) end
    ps_hook = nil
    if ps_re_hook and ps_re_hook.remove then pcall(ps_re_hook.remove, ps_re_hook) end
    ps_re_hook = nil
    ps_armed = false
    ps_arm_cnt = 0
    ps_sweep_cnt = 0
    ps_dirty = false
end
-- ===== 合并版接线：快速放置（v2.0.4 闪退修复——点击只切换标志+打脏标记，
--      实际遍历背包的刷新由 on_ps_tick 在游戏上下文下一帧执行，绝不在 GUI 回调里跑）=====
function ps_set_enabled(b)
    PS_EN = (b and true or false)
    ps_dirty = true          -- 下一次 tick 立刻扫一遍（开=加速，关=还原）
    ps_sweep_cnt = 0
end
function ps_is_enabled() return PS_EN end
return ps_setup, ps_cleanup, ps_set_enabled, ps_is_enabled
end)()
-- 第二十六部分：自动开袋（v4.7.9）
--   设置页按钮「自动开袋」（ab_en.txt 持久化，默认关闭）。
--   开启后每 AB_CD 帧检查一次「手持物品」（Player.inventory[selectedItem]），
--   若该物品是宝藏袋（PC 1.4.5.8 ItemID.Sets.BossBag 全 21 个 ID），
--   先扣掉 1 个，再调 Player.OpenBossBag(type) 发放战利品。
--   ⚠ 顺序绝不能反：先 OpenBossBag 后扣数 → 每帧都能开 → 无限刷。
--   为什么用 OpenBossBag 而不是模拟右键：原版就是这条函数发包/生成掉落，
--   直接调用等价于玩家右键，且不依赖 itemAnimation / useStyle 状态机。
ab_setup, ab_cleanup, ab_set_enabled, ab_is_enabled = (function()
local P = mod.patch
local AB_EN   = false   -- 总开关（默认关闭，ab_en.txt 持久化）
local AB_CD   = 5       -- 冷却帧数：每 5 帧最多开 1 个
local ab_wait = 0
local F_inv, F_type, F_stack
local m_boss, m_crate, m_present, m_goodie, m_herb, m_legacy
local m_turntoair, m_setdef
local m_sel_getter        -- Player.selectedItem 属性 getter（PE 里是只读属性，不是字段）
local ab_hook
local T_ITEM

-- 物品分类（ID 表来自 ne.ky.autobox 1.0.3 的 switch 反汇编）
--   1 BossBag      3318~3332 15 个 + 3860/3861/3862 撒旦军团 3 个
--   2 FishingCrate 2334/2335/2336 木铁金 + 3203~3208 + 3979~3987
--   3 Present      1869
--   4 GoodieBag    1774
--   5 HerbBag      3093
--   6 LegacyPresent 599/600/601（蓝/绿/黄圣诞礼物）
local KIND = {}
local function mark(k, list)
    for i = 1, #list do KIND[list[i]] = k end
end
mark(1, { 3318, 3319, 3320, 3321, 3322, 3323, 3324, 3325, 3326, 3327,
          3328, 3329, 3330, 3331, 3332, 3860, 3861, 3862 })
mark(2, { 2334, 2335, 2336, 3203, 3204, 3205, 3206, 3207, 3208,
          3979, 3980, 3981, 3982, 3983, 3984, 3985, 3986, 3987 })
mark(3, { 1869 })
mark(4, { 1774 })
mark(5, { 3093 })
mark(6, { 599, 600, 601 })

-- 安全取字段：pcall + 继承链回退
local function find_field_s(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local ok, f = pcall(P.get_field, cur, name)
        if ok and f then return f end
        local ok2, par = pcall(P.get_parent, cur)
        if not ok2 then return nil end
        cur = par
        guard = guard + 1
    end
    return nil
end

local function get_m(t, name, argc)
    if not t then return nil end
    local ok, m = pcall(P.get_method, t, name, argc or 1)
    if ok and m then return m end
    return nil
end

-- 每帧：开「手点的那一格」inventory[selectedItem]
--   取法：Player.selectedItem 是【只读属性】（PE Player.cs:6917），
--     不能 get_field，要用 get_property + property_get_method 拿 getter，
--     再 invoke(getter, inst) 读到 int32 的格子号。
--   拿不到 getter 时退化成背包第一格（索引 0），至少不会完全不工作。
local function ab_tick(inst)
    if not AB_EN or not inst then return end
    if ab_wait > 0 then ab_wait = ab_wait - 1; return end
    if not (F_inv and F_type and F_stack) then return end
    local okA, arr = pcall(P.get_field_value, F_inv, inst, "object")
    if not okA or not arr then return end
    local sel = 0
    if m_sel_getter then
        local okS, v = pcall(P.invoke, m_sel_getter, inst)
        if okS and type(v) == "number" and v >= 0 then sel = v end
    end
    local okL, n = pcall(P.array_length, arr)
    if not okL or type(n) ~= "number" or n <= 0 then return end
    if sel >= n then sel = 0 end
    local okB, it = pcall(P.array_at, arr, sel)
    if not okB or not it then return end
    local okC, ty = pcall(P.get_field_value, F_type, it, "int32")
    if not okC or type(ty) ~= "number" then return end
    local k = KIND[ty]
    if not k then return end
    local okD, st = pcall(P.get_field_value, F_stack, it, "int32")
    if not okD or type(st) ~= "number" or st <= 0 then return end
    -- ① 先扣 1 个（顺序不能反，否则每帧都能开 = 无限刷）
    if st > 1 then
        pcall(P.set_field_value, F_stack, it, st - 1, "int32")
    elseif m_turntoair then
        pcall(P.invoke, m_turntoair, it)
    elseif m_setdef then
        pcall(P.invoke, m_setdef, it, 0)
    else
        pcall(P.set_field_value, F_stack, it, 0, "int32")
    end
    -- ② 再发战利品
    local m
    if k == 1 then m = m_boss
    elseif k == 2 then m = m_crate
    elseif k == 3 then m = m_present
    elseif k == 4 then m = m_goodie
    elseif k == 5 then m = m_herb
    else m = m_legacy end
    if m then
        local ok7, r = pcall(P.invoke, m, inst, ty)
        if not ok7 or r == false then
            mod.warn("[自动开袋] Open 调用失败 kind=" .. tostring(k) .. " type=" .. tostring(ty))
        end
    end
    ab_wait = AB_CD
end

local function ab_install_hook()
    if ab_hook then return end
    local T_PLAYER = P.get_type("Terraria", "Player")
    if not T_PLAYER then return end
    -- 首选 Player.ResetEffects（每帧一次、带玩家实例）；不行退 Player.Update
    local m = P.get_method(T_PLAYER, "ResetEffects", 0)
    if not m then m = P.get_method(T_PLAYER, "Update", 1) end
    if not m then
        mod.warn("[自动开袋] 找不到可挂载的 Player 每帧方法")
        return
    end
    local ok, h = pcall(P.install_hook, m, { postfix = ab_tick })
    if ok and h then
        ab_hook = h
    else
        mod.warn("[自动开袋] 钩子安装失败")
    end
end

function ab_setup()
    AB_EN = false
    do
        local ok, s2 = pcall(function() return mod.read_file("ab_en.txt") end)
        if ok and type(s2) == "string" and s2:sub(1, 1) == "1" then AB_EN = true end
    end
    T_ITEM = P.get_type("Terraria", "Item")
    local T_PLAYER = P.get_type("Terraria", "Player")
    if not T_ITEM or not T_PLAYER then
        mod.warn("自动开袋：找不到 Item/Player 类型，跳过")
        return
    end
    F_inv   = find_field_s(T_PLAYER, "inventory")
    F_type  = find_field_s(T_ITEM, "type")
    F_stack = find_field_s(T_ITEM, "stack")
    m_boss    = get_m(T_PLAYER, "OpenBossBag")
    m_crate   = get_m(T_PLAYER, "OpenFishingCrate")
    m_present = get_m(T_PLAYER, "OpenPresent")
    m_goodie  = get_m(T_PLAYER, "OpenGoodieBag")
    m_herb    = get_m(T_PLAYER, "OpenHerbBag")
    m_legacy  = get_m(T_PLAYER, "OpenLegacyPresent")
    do
        local okp, prop = pcall(P.get_property, T_PLAYER, "selectedItem")
        if okp and prop then
            local okg, g2 = pcall(P.property_get_method, prop)
            if okg and g2 then m_sel_getter = g2 end
        end
    end
    m_turntoair = get_m(T_ITEM, "TurnToAir", 0)
    -- 1.4.6：Item.SetDefaults(int Type, ItemVariant variant)，反射层面是两参；
    --   1.4.5.8 是单参。调用侧一直是传 (inst, 0) 两参，这里优先取两参版本。
    m_setdef    = get_m(T_ITEM, "SetDefaults", 2) or get_m(T_ITEM, "SetDefaults", 1)
    ab_install_hook()
end

function ab_cleanup()
    ab_wait = 0
    if ab_hook and ab_hook.remove then pcall(ab_hook.remove, ab_hook) end
    ab_hook = nil
end

function ab_set_enabled(b)
    AB_EN = (b and true or false)
    ab_wait = 0
    if AB_EN then ab_install_hook() else ab_cleanup() end
end

function ab_is_enabled() return AB_EN end

return ab_setup, ab_cleanup, ab_set_enabled, ab_is_enabled
end)()
-- 第二十七部分：星神（「我就是星神 v1.0.3」并入，v4.7.17）
--   星星斗篷系列受击落星：原版 3 颗 → 300 颗。
--   原版数量是局部变量 num15 = 3（PC Player.cs:38725），没有字段可改，
--   所以只能「补发」：一次受击原版会连调 3 次 NewProjectile，
--   这里每次调用补发 99 颗 → 3 × 99 + 原版 3 = 300。
--   射弹 ID：726 星星斗篷 / 724 蜜蜂斗篷 / 723 魔力斗篷 / 1133 蛇纹斗篷 / 725 星星面纱
--   ⚠ reenter 守卫必须留：补发时会再次进入 NewProjectile，不守卫会无限递归。
star_setup, star_cleanup, star_set_enabled, star_is_enabled = (function()
local P = mod.patch
local ST_EN = false            -- 总开关（默认关闭，star_en.txt 持久化）
-- v4.7.19：进图播报已删除，只留面板按钮点击时的提示
local EXTRA_PER_CALL = 99      -- 每次 NewProjectile 补发 99 颗
local CLOAK_STARS = { [726] = true, [724] = true, [723] = true, [1133] = true, [725] = true }
local m_newproj
local ready = false
local reenter = false
local star_hook

local function find_field(t, name)
    if not t then return nil end
    local ok, f = pcall(P.get_field, t, name)
    if ok and f then return f end
    return nil
end

-- Projectile.NewProjectile 的 prefix：识别是斗篷落星就补发 99 颗
local function newproj_prefix(inst, args, result)
    if reenter or not ST_EN or not ready then return false end
    if not args or not m_newproj then return false end
    if not CLOAK_STARS[args[6]] then return false end
    local sx, sy = args[2], args[3]
    local vx, vy = args[4], args[5]
    if type(sx) ~= "number" or type(sy) ~= "number" then return false end
    if type(vx) ~= "number" or type(vy) ~= "number" then return false end
    reenter = true
    for _ = 1, EXTRA_PER_CALL do
        local nx = sx + (math.random() - 0.5) * 400
        local ny = sy - math.random(500, 800)
        local nvx = vx + (math.random() - 0.5) * 3.0
        local nvy = vy + (math.random() - 0.5) * 1.5
        pcall(P.invoke, m_newproj,
            args[1], nx, ny, nvx, nvy, args[6], args[7], args[8], args[9],
            args[10], args[11], args[12], args[13])
    end
    reenter = false
    return false        -- 放行原版那一颗
end

local function star_install()
    if star_hook or not m_newproj then return end
    local ok, h = pcall(P.install_hook, m_newproj, { prefix = newproj_prefix })
    if ok and h then
        star_hook = h
    else
        mod.warn("[星神] NewProjectile 钩子安装失败")
    end
end

local function star_uninstall()
    if star_hook and star_hook.remove then pcall(star_hook.remove, star_hook) end
    star_hook = nil
    reenter = false
end

function star_setup()
    ST_EN = false
    do
        local ok, s2 = pcall(function() return mod.read_file("star_en.txt") end)
        if ok and type(s2) == "string" and s2:sub(1, 1) == "1" then ST_EN = true end
    end
    local T_Main = P.get_type("Terraria", "Main")
    local T_Proj = P.get_type("Terraria", "Projectile")
    if not (T_Main and T_Proj) then
        mod.warn("[星神] 类型获取失败，跳过")
        return
    end
    m_newproj = P.get_method(T_Proj, "NewProjectile", 13) or P.get_method(T_Proj, "NewProjectile")
    ready = (m_newproj ~= nil)
    if not ready then
        mod.error("[星神] 取不到 Projectile.NewProjectile")
        return
    end
    if ST_EN then star_install() end
    mod.info("[星神] 已加载，状态=" .. (ST_EN and "开" or "关"))
end

function star_cleanup()
    star_uninstall()
end

function star_set_enabled(b)
    ST_EN = (b and true or false)
    if ST_EN then star_install() else star_uninstall() end
end

function star_is_enabled() return ST_EN end

return star_setup, star_cleanup, star_set_enabled, star_is_enabled
end)()
-- 第二十八部分：Dot流（「dot流是对的 v1.3.7」并入，v4.7.22）
--   机制（NPC.cs 核实）：「加速痛苦」buff 398 → acceleratePoisons = true；
--   倍率写死在 NPC.UpdateNPC_BuffApplyDOTs()：
--       num2 = (L - B) + (int)(B * 2f)     ← 原版固定 2 倍
--   这里钩 NPC.GetHurtByDebuff(int)，把每次结算的 amount 按倍率放大后补差。
--   单机/开服者：本地直接调 GetHurtByDebuff(diff) 补差；
--   加入别人服务器：把差额用 MessageID 153 包上报（原版这段没有发送者校验）。
--   v1.3.7 的伤害飘字修正一并搬来：登记 CombatText.NewText 的返回下标，
--   把原本要飘的数字改写成放大后的真实值，并隐藏补差那一次的数字。
--   进图播报已按要求删除，只留面板按钮的开/关提示。
dot_setup, dot_cleanup, dot_cycle, dot_label = (function()
local P = mod.patch
local H = {}
local hooks = {}
-- 档位：0 = 关；数字 = DoT 倍率（原版固定 2，所以 2 等于不介入）
local GEARS = { 0, 5, 10, 20 }
local gear_idx = 1
local DOT_EN   = false
local DOT_MULT = 2
local ORIG_MULT = 2
-- 联机相关
local net_inited = false
local SEND_ARGC = 0
local SENT = {}              -- who -> 已上报累计伤害
local SENT_RATIO = 4         -- 每只怪最多注入 lifeMax * 4
local sent_tick = 0
local ECHO = {}              -- who -> {dmg,t} 最近一次发包的数值
local ECHO_WIN = 1.5
local WIN_START, WIN_COUNT = 0, 0
local MAX_PER_SEC = 30
local in_extra = false
-- 伤害数字修正
local ct_seq = 0
local ct_mark = -1
local ct_last = -1
-- 运行状态
local net_mode = 0
local can_send = false
local in_net = false
local last_send = {}
local pending = {}
local SEND_GAP = 0.15
local frame_budget = 0
local MAX_PER_FRAME = 2
local world_frames = 0

local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local f = P.get_field(cur, name)
        if f then return f end
        cur = P.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function rd(field, inst, ty)
    if not field then return nil end
    local ok, v = pcall(P.get_field_value, field, inst, ty)
    if ok then return v end
    return nil
end

local function wr(field, inst, v, ty)
    if not field then return false end
    local ok, r = pcall(P.set_field_value, field, inst, v, ty)
    return ok and r ~= false
end

-- ---------- 伤害数字修正（只改显示，不碰伤害） ----------
local function ct_at(idx)
    if type(idx) ~= "number" or idx < 0 or not H.f_ct_arr then return nil end
    local arr = rd(H.f_ct_arr, nil, "object")
    if not arr then return nil end
    local okn, n = pcall(P.array_length, arr)
    if not okn or type(n) ~= "number" or idx >= n then return nil end
    local okr, ct = pcall(P.array_at, arr, idx, "object")
    if okr then return ct end
    return nil
end

local function ct_set_text(idx, value)
    local ct = ct_at(idx)
    if not ct then return false end
    local str = tostring(value)
    if P.string_create then
        local okc, r = pcall(P.string_create, str)
        if okc and r then str = r end
    end
    return wr(H.f_ct_text, ct, str, "object")
end

local function ct_hide(idx)
    local ct = ct_at(idx)
    if not ct then return false end
    return wr(H.f_ct_active, ct, false, "bool")
end

local function in_world()
    local v = rd(H.f_gamemenu, nil, "bool")
    if v ~= nil then return v == false end
    if H.m_game_menu then
        local ok, r = pcall(P.invoke, H.m_game_menu)
        if ok and type(r) == "boolean" then return r == false end
    end
    return false
end

-- ---------- 联机：把差额用 153 包报给服务器 ----------
local function send_153(inst, who, dmg)
    if type(who) ~= "number" or who < 0 or who > 200 then return false end
    if not (can_send and H.m_send153) then return false end
    local lmax = rd(H.f_life_max, inst, "int32")
    if type(lmax) == "number" and lmax > 0 then
        if (SENT[who] or 0) >= lmax * SENT_RATIO then return false end
    end
    local now = os.clock()
    if now - WIN_START >= 1 then WIN_START, WIN_COUNT = now, 0 end
    if WIN_COUNT >= MAX_PER_SEC then return false end
    local total = (pending[who] or 0) + dmg
    local prev = last_send[who]
    if prev and (now - prev) < SEND_GAP then
        -- 不累积：挡下的多是「服务器广播回来又触发的同一轮」，累积会滚雪球
        return false
    end
    if frame_budget <= 0 then
        pending[who] = total
        return false
    end
    local d = math.floor(total)
    if d < 1 then pending[who] = total return false end
    if d > 32000 then d = 32000 end
    pending[who] = nil
    frame_budget = frame_budget - 1
    WIN_COUNT = WIN_COUNT + 1
    SENT[who] = (SENT[who] or 0) + d
    ECHO[who] = { dmg = d, t = now }
    last_send[who] = now
    local nt = rd(H.f_nt_empty, nil, "object")
    local ok
    if SEND_ARGC == 6 then
        ok = pcall(P.invoke, H.m_send153, 153, -1, -1, nt, who, d)
    else
        local a = { 153, -1, -1, nt, who, d }
        for i = 7, SEND_ARGC do a[i] = 0 end
        ok = pcall(P.invoke, H.m_send153, table.unpack(a))
    end
    return ok
end

-- ---------- DoT 倍率介入 ----------
local function on_hurt_prefix(inst, args, result)
    ct_mark = ct_seq
    return false
end

local function on_hurt_debuff(inst, args, result)
    if not DOT_EN then return end
    if in_extra then return end
    if DOT_MULT == ORIG_MULT then return end
    if not inst then return end
    if rd(H.f_accel, inst, "bool") ~= true then return end
    local amount = args and args[1]
    if type(amount) ~= "number" or amount <= 0 then return end
    local target = math.floor(amount * DOT_MULT / ORIG_MULT + 0.5)
    if target < 0 then target = 0 end
    local diff = target - amount
    if diff == 0 then return end
    if net_mode == 1 then
        if in_net then return end
        local who = rd(H.f_who, inst, "int32")
        local e = who and ECHO[who]
        if e and e.dmg == amount and (os.clock() - e.t) < ECHO_WIN then return end
        if diff > 0 then send_153(inst, who, diff) end
        return
    end
    -- 单机 / 开服者：本地直接补差
    if diff > 0 then
        local ct_a = (ct_seq > ct_mark) and ct_last or -1
        in_extra = true
        pcall(P.invoke, H.m_hurt, inst, diff)
        in_extra = false
        if ct_a >= 0 then
            local ct_b = ct_last
            ct_set_text(ct_a, target)
            if ct_b ~= ct_a then ct_hide(ct_b) end
        end
    else
        local life = rd(H.f_life, inst, "int32")
        local lifeMax = rd(H.f_life_max, inst, "int32")
        if type(life) == "number" and type(lifeMax) == "number" and life > 0 then
            local nl = life + (-diff)
            if nl > lifeMax then nl = lifeMax end
            wr(H.f_life, inst, nl, "int32")
        end
    end
end

-- ---------- 联机能力初始化（进世界时补装：setup 时还在主菜单，netMode 恒为 0）----------
local function init_net()
    if net_inited or net_mode ~= 1 then return end
    local t_net = P.get_type("Terraria", "NetMessage")
    local t_nt  = P.get_type("Terraria.Localization", "NetworkText")
    if not (t_net and t_nt) then return end
    H.f_nt_empty = P.get_field(t_nt, "Empty")
    local i32 = P.get_basic_type and P.get_basic_type("int32")
    local f32 = P.get_basic_type and P.get_basic_type("float")
    local cands = {}
    if i32 and f32 and P.get_method_by_param_types then
        cands[#cands + 1] = { 11, { i32, i32, i32, t_nt, i32, f32, f32, f32, i32, i32, i32 } }
        cands[#cands + 1] = { 9,  { i32, i32, i32, t_nt, i32, f32, f32, f32, i32 } }
        cands[#cands + 1] = { 6,  { i32, i32, i32, t_nt, i32, f32 } }
    end
    for _, c in ipairs(cands) do
        local ok, m = pcall(P.get_method_by_param_types, t_net, "SendData", c[2])
        if ok and m then
            H.m_send153 = m
            SEND_ARGC = c[1]
            break
        end
    end
    if not H.m_send153 then
        for _, cnt in ipairs({ 11, 10, 9, 6, 5, 3 }) do
            local ok, m = pcall(P.get_method, t_net, "SendData", cnt)
            if ok and m then
                H.m_send153 = m
                SEND_ARGC = cnt
                break
            end
        end
    end
    can_send = (H.m_send153 ~= nil)
    -- 防放大：标记「正在处理服务器网络消息」的窗口
    local hooked = false
    local t_mb = P.get_type("Terraria", "MessageBuffer")
    if t_mb then
        for cnt = 0, 15 do
            local m = P.get_method(t_mb, "GetData", cnt)
            if m then
                local okg, hg = pcall(P.install_hook, m, {
                    prefix  = function() in_net = true end,
                    postfix = function() in_net = false end,
                })
                if okg and hg then
                    hooks[#hooks + 1] = hg
                    hooked = true
                    break
                end
            end
        end
    end
    if not hooked then
        local t_np = P.get_type("Terraria", "Netplay")
        if t_np then
            for _, nm in ipairs({ "ClientFrame", "ClientUpdate", "ReadNetMessage", "UpdateClient", "ClientLoop", "DoNet" }) do
                for cnt = 0, 15 do
                    local m = P.get_method(t_np, nm, cnt)
                    if m then
                        local okg, hg = pcall(P.install_hook, m, {
                            prefix  = function() in_net = true end,
                            postfix = function() in_net = false end,
                        })
                        if okg and hg then
                            hooks[#hooks + 1] = hg
                            hooked = true
                            break
                        end
                    end
                    if hooked then break end
                end
                if hooked then break end
            end
        end
    end
    net_inited = true
end

-- ---------- 每帧（原进图播报的钩子位置，现在只做预算与联机能力补装）----------
local function on_main_update()
    frame_budget = MAX_PER_FRAME
    sent_tick = sent_tick + 1
    if sent_tick >= 1800 then sent_tick = 0; SENT = {} end
    if not in_world() then
        world_frames = 0
        return
    end
    world_frames = world_frames + 1
    if world_frames == 1 then
        net_mode = rd(H.f_netmode, nil, "int32") or 0
        pcall(init_net)
    end
end

function dot_setup()
    DOT_EN = false
    DOT_MULT = ORIG_MULT
    do
        local okf, txt = pcall(function() return mod.read_file("dot_gear.txt") end)
        if okf and type(txt) == "string" then
            local saved = tonumber(txt:match("(%d+)")) or 0
            for i = 1, #GEARS do
                if GEARS[i] == saved then gear_idx = i end
            end
        end
        local g = GEARS[gear_idx]
        if g ~= 0 then
            DOT_EN = true
            DOT_MULT = g
        end
    end
    local ok, err = pcall(function()
        local t_npc  = P.get_type("Terraria", "NPC")
        local t_main = P.get_type("Terraria", "Main")
        if not (t_npc and t_main) then error("关键类型缺失") end
        H.f_accel    = find_field(t_npc, "acceleratePoisons")
        H.f_life     = find_field(t_npc, "life")
        H.f_life_max = find_field(t_npc, "lifeMax")
        H.f_who      = find_field(t_npc, "whoAmI")
        H.f_gamemenu = P.get_field(t_main, "gameMenu")
        H.f_netmode  = P.get_field(t_main, "netMode")
        H.m_game_menu = P.get_method(t_main, "get_gameMenu", 0)
        H.m_hurt     = P.get_method(t_npc, "GetHurtByDebuff", 1)
        if not H.f_accel then error("找不到 NPC.acceleratePoisons") end
        if not H.m_hurt then error("找不到 NPC.GetHurtByDebuff(int)") end
        net_mode = rd(H.f_netmode, nil, "int32") or 0
        init_net()
        -- 伤害数字修正：常驻安装（档位可运行中切换，不能按 setup 时的倍率决定装不装）
        H.f_ct_arr = P.get_field(t_main, "combatText")
        local t_ct = P.get_type("Terraria", "CombatText")
        if t_ct then
            H.f_ct_text   = P.get_field(t_ct, "text")
            H.f_ct_active = P.get_field(t_ct, "active")
        end
        local m_nt
        local t_rect  = P.get_type("Microsoft.Xna.Framework", "Rectangle")
        local t_color = P.get_type("Microsoft.Xna.Framework", "Color")
        local i32 = P.get_basic_type and P.get_basic_type("int32")
        local blo = P.get_basic_type and P.get_basic_type("bool")
        if t_ct and t_rect and t_color and i32 and blo and P.get_method_by_param_types then
            local okm, m = pcall(P.get_method_by_param_types, t_ct, "NewText",
                                 { t_rect, t_color, i32, blo, blo })
            if okm and m then m_nt = m end
        end
        if not m_nt and t_ct then
            local okm, m = pcall(P.get_method, t_ct, "NewText", 5)
            if okm and m then m_nt = m end
        end
        if m_nt and H.f_ct_arr and H.f_ct_text and H.f_ct_active then
            local okn, hn = pcall(P.install_hook, m_nt, {
                postfix = function(inst2, args2, result)
                    if type(result) == "number" then
                        ct_seq = ct_seq + 1
                        ct_last = result
                    end
                end,
            })
            if okn and hn then
                hooks[#hooks + 1] = hn
            else
                mod.warn("[dot] 伤害数字修正挂钩失败，数字仍为原值")
            end
        else
            mod.warn("[dot] 找不到 CombatText.NewText，跳过数字修正")
        end
        local okh, h = pcall(P.install_hook, H.m_hurt, { prefix = on_hurt_prefix, postfix = on_hurt_debuff })
        if not (okh and h) then error("GetHurtByDebuff 挂钩失败") end
        hooks[#hooks + 1] = h
        local m_up = P.get_method(t_main, "Update", 1) or P.get_method(t_main, "Update", 0)
        if m_up then
            local okh2, h2 = pcall(P.install_hook, m_up, { postfix = on_main_update })
            if okh2 and h2 then
                hooks[#hooks + 1] = h2
            else
                frame_budget = 1e9
            end
        else
            frame_budget = 1e9
        end
        mod.info(string.format("[dot] 就绪 倍率=%s 网络模式=%d 发包=%s",
            tostring(GEARS[gear_idx]), net_mode, tostring(can_send)))
    end)
    if not ok then
        mod.warn("[dot] 初始化失败: " .. tostring(err))
    end
end

function dot_cleanup()
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
end

-- 点按钮：循环切档（关 → 5 → 10 → 20 → 关），返回要播报的文字
function dot_cycle()
    gear_idx = gear_idx + 1
    if gear_idx > #GEARS then gear_idx = 1 end
    local g = GEARS[gear_idx]
    if g == 0 then
        DOT_EN = false
        DOT_MULT = ORIG_MULT
    else
        DOT_EN = true
        DOT_MULT = g
    end
    pcall(mod.write_file, "dot_gear.txt", tostring(g))
    if g == 0 then return "dot的力量收回去了 (￣ω￣)" end
    return "Dot是对的￣へ￣ " .. g .. "倍"
end

function dot_label()
    local g = GEARS[gear_idx]
    if g == 0 then return "Dot流（已关闭）" end
    return "Dot流（" .. g .. "倍）"
end

return dot_setup, dot_cleanup, dot_cycle, dot_label
end)()
-- 第二十九部分：巅峰时代（「巅峰时代 v8.0.0」并入，v4.7.24）
--   11 项功能各一个按钮，默认全关，状态存 peak_en.txt（11 位 0/1，顺序同 KEYS）。
--   钩子在 setup 时一次性全装，运行时各回调按 CFG[key] 判断是否介入 ——
--   所以点按钮切换是「零成本」的，不需要装卸钩子。
--   进图播报已按要求去掉，只留面板按钮的开/关提示。
peak_setup, peak_cleanup, peak_toggle, peak_label = (function()

-- 巅峰时代 / 作者：蓝色大肥鱼
-- 力量又回来了
-- ---------------------------------------------------------------------------
-- 改动一览（对应 1.4.5.8 反编译源码）：
--   1. 幽灵兜帽套装吸血固定 10%，并取消原版「打中递减」
--      （原版 0.2 - numHits*0.05，打第 5 下就没吸血了）
--      lifeSteal 每次只扣 1%，等效额度上限 ×100
--   2. 幽灵兜帽套装：取消 40% 魔法伤害惩罚（magicDamage +0.4，每帧补）
--   3. 进图 1 秒后播报「力量又回来了(◣_◢)」
--   4. 黑曜石套（3266 帽 + 3267 长衣 + 3268 裤）套装奖励强化：
--      鞭范围 +50%（whipRangeMultiplier = 1.5）
--      鞭速度 +50%（whipUseTimeMultiplier = 0.5，使用间隔减半）
--      召唤伤害 +25%（在装备加成之上再加 0.25）
--   5. 泰拉刃（757）回归 1.4.4 之前的数值，全部走「动态覆盖」，不写任何物品数据：
--      伤害 85 → 115（钩 Player.GetWeaponDamage，按 115/85 缩放，词缀倍率天然保留）
--      使用时间 18 → 14（ItemCheck 前后临时改 useTime/useAnimation，用完立刻还原）
--      近战速度加成折扣 ×0.75 → ×1.0（ItemCheck 前把已打折的 meleeSpeed 换算回全额）
-- ---------------------------------------------------------------------------

local patch = mod.patch
local hooks = {}

-- 【测试版专用】日志落盘到项目目录；正式版这里是空的
-- 转正版：不写任何文件（日志实现留空，改回落盘只需恢复 logf 内部）
local function logf(_) end

-- ============ 模组设置 ============
-- 开关由 TEFManager「模组设置」界面写入 Resources/config.json（schemaVersion:1 + values），
-- 声明在 Info.json 的 settings 数组里。这里启动时读一次，覆盖下面的默认值。
-- 读不到 / 解析失败 / 字段缺失 → 一律回落到默认值 true（默认全开）。
local CFG = {
    ghost     = false,   -- 幽灵套：吸血固定 10% + 无上限 + 不再降 40% 魔法伤害
    obsidian  = false,   -- 黑曜石套：鞭范围/鞭速度/召唤伤害
    terra     = false,   -- 泰拉刃：伤害 115 / 使用时间 14 / 攻速不打折
    blade     = false,   -- 刃杖：取消 33% 标记伤害惩罚
    typhoon   = false,   -- 利刃台风：伤害 90 / 使用时间 20 / 双发 / 3 秒
    phantasm  = false,   -- 幻影弓：50 → 70
    holy      = false,   -- 圣箭：神圣之星 100% 伤害 + 穿透 2
    unholy    = false,   -- 邪箭：穿透后不衰减
    jester    = false,   -- 小丑之箭：穿透后不衰减
    crystal   = false,   -- 水晶子弹：3 个碎片
    chloro    = false,   -- 叶绿弹：9 → 15
}
-- ============ 面板按钮接口（v4.7.24）============
local KEYS = { "ghost", "obsidian", "terra", "blade", "typhoon", "phantasm",
               "holy", "unholy", "jester", "crystal", "chloro" }
local NAMES = {
    ghost = "幽灵兜帽套", obsidian = "黑曜石套", terra = "泰拉刃", blade = "刃杖",
    typhoon = "利刃台风", phantasm = "幻影弓", holy = "圣箭", unholy = "邪箭",
    jester = "小丑之箭", crystal = "水晶子弹", chloro = "叶绿弹",
}

local function peak_save()
    local t = {}
    for i = 1, #KEYS do t[i] = CFG[KEYS[i]] and "1" or "0" end
    pcall(mod.write_file, "peak_en.txt", table.concat(t))
end

local function peak_load()
    local ok, txt = pcall(function() return mod.read_file("peak_en.txt") end)
    if not ok or type(txt) ~= "string" or #txt < #KEYS then return end
    for i = 1, #KEYS do
        CFG[KEYS[i]] = (txt:sub(i, i) == "1")
    end
end


-- ============ 常量 ============
local GHOST_HEAL_RATE   = 0.10        -- 吸血比例固定 10%（原版 0.2 - numHits*0.05，打 5 下就没）
local GHOST_MAGIC_FIX   = 0.4
-- 抵消多少比例的幽灵套魔伤惩罚：
--   0.0 = 完全取消（伤害回到不穿幽灵套的水平）
--   0.5 = 抵消一半
--   1.0 = 完全不抵消（原版）
local GHOST_PENALTY_KEEP = 0.5
local LIFESTEAL_COST_SCALE = 0.01   -- 吸血时只消耗 1% 额度（等效上限 ×100）

-- ============ 黑曜石套（3266 帽 / 3267 长衣 / 3268 裤）============
-- 原版套装奖励：鞭范围 / 鞭速度 / 召唤伤害各有一档，这里直接顶到目标值。
-- 鞭范围：whipRangeMultiplier（乘算系数，1.0 = 原样），1.5 = 范围 +50%
-- 鞭速度：whipUseTimeMultiplier（使用间隔倍率，越小越快），0.5 = 间隔减半 = 速度 +50%
-- 召唤伤害：minionDamage 是加算系数，套装奖励部分给到 0.25
local OBSIDIAN_ARMOR = { [0] = 3266, [1] = 3267, [2] = 3268 }
-- v5.9.1：改成「在现有值上叠增量」，不再固定死目标值。
--   原版套装奖励（ArmorSetBonuses.ObsidianOutlaw）已给：
--     召唤伤害 +0.15、鞭子范围 +0.3、鞭子速度 ×(1/1.15)
--   原版饰品里能叠加到这些字段的：莫比乌斯带 accMobiusStrip（范围再 +0.1）
--   => 无饰品：范围 1.0+0.3+0.2 = 1.5（+50%）；鞭速 (1/1.15)x(1.15/1.5) = 1/1.5（+50%）
--   => 带莫比乌斯带：范围 1.6（饰品加成保留）
--   术语对照（wiki 黑曜石盔甲页）：鞭速度实际是「套装奖励」这一个因子 —— 原版 1.15（+15%），
--     我们的目标 1.50（+50%）。它与近战速度/鞭 buff 是乘算关系，所以那些来源原样保留。
--   注：近战攻速饰品走 meleeSpeed -> summonerWeaponSpeedBonus（CapAttackSpeeds 合并），
--       不经过 whipUseTimeMultiplier，天然不受本模块影响。
local OBSIDIAN_WHIP_RANGE_ADD  = 0.20           -- 在现有值上再加 0.2
local OBSIDIAN_WHIP_USE_FACTOR = 1.15 / 1.50    -- 现有值（1/1.15）再乘 0.7667 = 1/1.50
local OBSIDIAN_MINION_DMG      = 0.25

-- ============ 泰拉刃（757）回归旧版数值 ============
-- 原版 Item.cs: damage 85 / useTime 18 / useAnimation 18 / noMelee（伤害全在剑气 985）
-- 近战速度折扣：Player.Update 内 meleeSpeed = 1 + (meleeSpeed-1) × BonusMeleeSpeedMultiplier[手持物品]
-- 泰拉刃系数 0.75，即「降低 25%」；这里在 ItemCheck 之前把折扣换算还原。
local TERRA_ID          = 757
local TERRA_DAMAGE      = 115        -- 目标伤害
local TERRA_BASE_DAMAGE = 85         -- 原版伤害（缩放基准）
local TERRA_USE_TIME    = 14         -- 目标使用时间（同时用于 useAnimation）
local TERRA_SPEED_DISCOUNT = 0.75    -- 原版近战速度奖励的折扣系数（泰拉刃只吃 75%）

-- ============ 刃杖（物品 4758 / 射弹 864）：取消 33% 标记伤害惩罚 ============
-- 原版 ProjectileID.cs：
--   public static float[] SummonTagDamageMultiplier = Factory.CreateFloatSet(1f, 864f, 0.669f);
-- 全游戏只有 864（刃杖飞刀）是 0.669，其它召唤物全是 1.0。
-- Projectile.cs 的 Damage_PVE_Inner 里：
--   num15 += (int)((num18 + bonusTagDamage) * Sets.SummonTagDamageMultiplier[type]);
-- 即「鞭子 + 词缀给的标记伤害」乘 0.669 后向下取整，才加到这次伤害上。
-- 改成 1.0 后标记加成 100% 到账，且不影响任何其它召唤物，也不碰物品数据。
local BLADE_PROJ_ID  = 864
local BLADE_FIX_MUL  = 1.0     -- 目标系数（原版 0.669）

-- ============ 泰拉刃的近战速度折扣：同样走静态数组 ============
-- 原版 ItemID.cs:1168
--   public static float[] BonusMeleeSpeedMultiplier =
--       Factory.CreateFloatSet(1f, 1827f, 0.5f, 3013f, 0.25f, 3106f, 0.33f, 757f, 0.75f);
-- 原版 Player.cs:26109
--   num29 = meleeSpeed - 1f;  num29 *= Sets.BonusMeleeSpeedMultiplier[手上物品类型];  meleeSpeed = 1f + num29;
-- 把 [757] 改成 1.0，折扣从源头消失，比在 ItemCheck 里按 0.75 反推更稳。
-- 2026-11-01 实机验证：before=0.75 → after=1.0，写入成功。
local TERRA_MELEE_IDX      = 757
local TERRA_SPEED_FIX_MUL  = 1.0     -- 目标系数（原版 0.75）
local terra_speed_fixed    = false   -- 写入成功后，ItemCheck 里就不再换算（否则会双重加速）

-- ============ 利刃台风（物品 2622 / 射弹 409）============
-- 2026-11-01 实机诊断（v4.1.0-诊断版）确认移动版与 PC 1.4.5.8 完全一致：
--   item2622  dmg=85  useTime=40  useAnim=40  shoot=409
--   proj409   timeLeft=300  extraUpdates=2  pen=-1  wh=30x30  ai=71  magic=true
-- 持续时间换算：extraUpdates=2 表示每帧 AI 跑 3 次，实际秒数 = timeLeft / 3 / 60
--   原版 300 → 1.67 秒；3 秒对应 timeLeft = 3 × 3 × 60 = 540
local TYPHOON_ITEM_ID      = 2622
local TYPHOON_PROJ_ID      = 409
local TYPHOON_BASE_DAMAGE  = 85      -- 原版物品伤害（缩放基准）
local TYPHOON_DAMAGE       = 90      -- 目标伤害
local TYPHOON_USE_TIME     = 20      -- 目标使用时间（同时用于 useAnimation）
local TYPHOON_TIMELEFT     = 540     -- 目标射弹 timeLeft（= 3 秒）
local typhoon_proj_logged  = false

-- ============ 圣箭（物品 516 / 箭矢射弹 91 / 神圣之星 92）============
-- 2026-11-01 核实：移动版圣箭伤害与 PC 一致（都是 13），**伤害不需要改**。
-- 只做两项：
--   ① 星星伤害：Projectile.cs:76773-76777 在 Kill() 里
--        int num673 = damage;  if (type == 91) num673 /= 3;   ← 只有圣箭才除以 3
--      在 Kill 之前把圣箭的 damage ×3，整数除法后正好还原成原值（3d/3 = d，精确无误差）
--      Kill() 内 type==91 的分支只在这一处用到 damage（其余分支互斥），无副作用
--   ② 星星穿透：Projectile.cs:1682-1693  type 92 的 SetDefaults 里 penetrate = 1，只能打一个目标
local HOLY_ARROW_PROJ    = 91
local HOLY_STAR_PROJ     = 92
local HOLY_STAR_PEN      = 2        -- 星星穿透 1 → 2（能打第二个目标）
local holy_logged        = {}       -- 每类只记一次日志

-- ============ 句柄 ============
local T_Main, T_Player, T_Proj
local f_proj_type, f_proj_damage, f_proj_timeleft
local f_proj_magic, f_proj_ai, f_proj_alpha
local f_pl_lifesteal, f_pl_magicdmg, f_pl_statlifemax, f_pl_statlife
local f_pl_head, f_pl_body, f_pl_legs, f_pl_dead, f_pl_whoami
local f_pl_whiprange, f_pl_whipuse, f_pl_miniondmg
local f_pl_meleespeed
local f_pl_inventory, f_pl_selecteditem
local m_get_helditem      -- Player.HeldItem 属性 getter（手机上 selectedItem 是只读属性，不是字段）
local m_get_selecteditem
local f_item_usetime, f_item_useanimation
local f_pl_ghostheal   -- 幽灵兜帽套装生效标志（由套装奖励置位）
local f_pl_armor, f_item_type   -- 护甲数组（Item[20]）与物品 type 字段
local f_main_gamemenu, f_main_players, f_myplayer, f_main_proj
local m_get_myplayer
local m_get_gamemenu
local m_newproj        -- Projectile.NewProjectile（静态方法，用于一次发多枚）
local f_proj_penetrate -- 圣箭星星穿透用
local f_proj_maxpen    -- 星星的 maxPenetrate 也要同步（SetDefaults 末行会写 maxPenetrate=penetrate，postfix 改 penetrate 追不上）
local f_proj_pos       -- 水晶子弹补发碎片要读坐标
local f_proj_vel       -- 同上，读速度
local f_proj_owner     -- 同上，碎片要继承主人
local m_proj_kill      -- Projectile.Kill()，圣箭死亡时生成星星
local m_damage_pve     -- Projectile.Damage_PVE(ref Rectangle, float)，邪箭/小丑之箭穿透衰减
local m_proj_src       -- Projectile.GetProjectileSource_FromThis()，补发碎片要 IEntitySource

-- ============ 状态 ============
local ready = false
-- v5.9.1：改成增量后必须防「同帧叠加两次」（UpdateArmorSets postfix 与
--   Player.Update postfix 都会调 apply_obsidian）。这里记上次写入值，值没被重置就跳过。
local obs_last = { wr = -1, wt = -1, md = -1 }
local terra_backup = {}       -- 泰拉刃：ItemCheck 期间临时改动的 useTime/useAnimation 原值（按玩家下标）
-- 回调计数（用于确认钩子是否真的被执行）

-- ============ 工具 ============
local function find_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 12 do
        local f = patch.get_field(cur, name)
        if f then return f end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

local function get_i(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "int32")
    if ok and v ~= nil then return v end
    return dft
end

local function set_i(f, inst, v)
    if f then pcall(patch.set_field_value, f, inst, v, "int32") end
end

local function get_f(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "float")
    if ok and v ~= nil then return v end
    return dft
end

local function set_f(f, inst, v)
    if f then pcall(patch.set_field_value, f, inst, v, "float") end
end

local function get_b(f, inst, dft)
    if not f then return dft end
    local ok, v = pcall(patch.get_field_value, f, inst, "bool")
    if ok and v ~= nil then return v end
    return dft
end

--- 本地玩家下标；Android 上 myPlayer 是属性，字段读不到时回退 getter
local function my_player_index()
    local v = get_i(f_myplayer, nil, nil)
    if v ~= nil and v >= 0 then return v end
    if m_get_myplayer then
        local ok, r = pcall(patch.invoke, m_get_myplayer)
        if ok and type(r) == "number" and r >= 0 then return r end
    end
    return -1
end

--- 取本地玩家对象（用缓存的数组句柄）
local function local_player()
    local idx = my_player_index()
    if idx < 0 or not f_main_players then return nil end
    local ok, arr = pcall(patch.get_field_value, f_main_players, nil, "object")
    if not (ok and arr) then return nil end
    local ok2, pl = pcall(patch.array_at, arr, idx)
    if ok2 then return pl end
    return nil
end
--- 给玩家回血（不超过上限），返回实际增加量
local function heal_player(pl, amount)
    local life = get_i(f_pl_statlife, pl, 0)
    local maxlife = get_i(f_pl_statlifemax, pl, 0)
    if life <= 0 or maxlife <= 0 then return 0 end
    local add = math.floor(amount + 0.5)
    if add < 1 then add = 1 end
    local newlife = life + add
    if newlife > maxlife then newlife = maxlife end
    if newlife <= life then return 0 end
    set_i(f_pl_statlife, pl, newlife)
    return newlife - life
end

-- ============ Hook 2: Projectile.ghostHeal（幽灵兜帽吸血）============
-- 吸血率固定 10%（原版 0.2 - numHits*0.05，第 5 次命中起为 0）
-- lifeSteal 只扣 1%，等效额度上限 ×100，即「无限制」
local function ghost_heal_prefix(inst, args, result)
    if not ready or not inst then return false end
    if not CFG.ghost then return false end   -- 开关关闭：完全交回原版
    local dmg = args and args[1]
    if type(dmg) ~= "number" or dmg <= 1 then return true end
    if not get_b(f_proj_magic, inst, false) then return true end
    local pl = local_player()
    if not pl then return true end
    local ls = get_f(f_pl_lifesteal, pl, 0)
    if ls <= 0 then return true end

    -- 固定 10%，取消原版「命中数越多吸血越少」的递减
    local rate = GHOST_HEAL_RATE

    local amount = dmg * rate
    if amount < 1 then return true end
    local gained = heal_player(pl, amount)
    if gained > 0 then
        -- 原版每帧把 lifeSteal 硬压回 70，补上去无效；改为只扣 1%，等效额度 ×100
        set_f(f_pl_lifesteal, pl, ls - amount * LIFESTEAL_COST_SCALE)
    end
    return true
end

-- ============ Hook 5: Player.Update（额度续航 / 幽灵套装魔伤）============
-- gameMenu 在 PE 版可能是属性，字段读不到时走 getter
local upd_err_logged = false

-- ============ 套装判定与基准 ============
local md_base = -1        -- 未施加惩罚时的 magicDamage 基准
local hood_miss = 0       -- 连续多少帧判定为「没穿套装」，用于防抖

-- ============ 幽灵兜帽套装判定 ============
-- 注意：player.head / body / legs 是发型和衣服样式，不是护甲。
-- 真正的护甲在 player.armor[0]（头）/ [1]（身）/ [2]（腿）。
-- 1503 = Spectre Hood、1504 = Spectre Robe、1505 = Spectre Pants
local function is_spectre_hood(pl)
    if f_pl_armor and f_item_type then
        local ok, arr = pcall(patch.get_field_value, f_pl_armor, pl, "object")
        if ok and arr then
            local t0, t1, t2 = -1, -1, -1
            local o1, a0 = pcall(patch.array_at, arr, 0)
            if o1 and a0 then t0 = get_i(f_item_type, a0, -1) end
            local o2, a1 = pcall(patch.array_at, arr, 1)
            if o2 and a1 then t1 = get_i(f_item_type, a1, -1) end
            local o3, a2 = pcall(patch.array_at, arr, 2)
            if o3 and a2 then t2 = get_i(f_item_type, a2, -1) end
            if t0 == 1503 and t1 == 1504 and t2 == 1505 then return true end
        end
    end
    if f_pl_ghostheal and get_b(f_pl_ghostheal, pl, false) then return true end
    return false
end

-- ============ 黑曜石套：判定与强化 ============
-- 读 armor[0..2] 的 type，读不到返回 nil
local function armor_ids(pl)
    if not (f_pl_armor and f_item_type) then return nil end
    local ok, arr = pcall(patch.get_field_value, f_pl_armor, pl, "object")
    if not (ok and arr) then return nil end
    local ids = {}
    for slot = 0, 2 do
        local o, it = pcall(patch.array_at, arr, slot)
        if o and it then
            ids[slot] = get_i(f_item_type, it, -1)
        else
            ids[slot] = -1
        end
    end
    return ids
end

local function is_obsidian_set(pl)
    local ids = armor_ids(pl)
    if not ids then return false end
    return ids[0] == OBSIDIAN_ARMOR[0]
       and ids[1] == OBSIDIAN_ARMOR[1]
       and ids[2] == OBSIDIAN_ARMOR[2]
end

-- 必须在「套装奖励施加之后」调用（UpdateArmorSets 尾部 / Update 尾部）。
-- v5.9.1：全部改成「读当前值 + 增量」，这样原版套装奖励、饰品加成、其它模组的加成
--   全都能保住；旧版直接写 1.5 / 0.5，会把莫比乌斯带的 +0.1 范围吞掉。
--   同帧去重：值若还等于我们上次写的，说明本帧已经处理过，直接跳过。
local DUP_EPS = 0.0001
local function apply_obsidian(pl)
    if not is_obsidian_set(pl) then
        obs_last.wr, obs_last.wt, obs_last.md = -1, -1, -1
        return
    end
    -- 鞭子范围：现有值（含原版套装 0.3 + 饰品）再加 0.2
    local wr = get_f(f_pl_whiprange, pl, -1)
    if wr and wr > 0 and math.abs(wr - obs_last.wr) > DUP_EPS then
        local nv = wr + OBSIDIAN_WHIP_RANGE_ADD
        if set_f(f_pl_whiprange, pl, nv) then obs_last.wr = nv end
    end
    -- 鞭子速度：现有值（含原版套装 x1/1.15）再乘 0.7667 -> 1/1.50（+50%）
    local wt = get_f(f_pl_whipuse, pl, -1)
    if wt and wt > 0 and math.abs(wt - obs_last.wt) > DUP_EPS then
        local nv = wt * OBSIDIAN_WHIP_USE_FACTOR
        if set_f(f_pl_whipuse, pl, nv) then obs_last.wt = nv end
    end
    -- 召唤伤害：现有值（含原版套装 +0.15 与饰品）再加 0.25
    local md = get_f(f_pl_miniondmg, pl, -1)
    if md and md > 0 and math.abs(md - obs_last.md) > DUP_EPS then
        local nv = md + OBSIDIAN_MINION_DMG
        if set_f(f_pl_miniondmg, pl, nv) then obs_last.md = nv end
    end
end

-- ============ 泰拉刃（757）：纯动态覆盖 ============
-- 原则：绝不改动 Item 的持久字段（damage / useTime / useAnimation 都会随玩家存档保存），
-- 只在「游戏读取的那一刻」给值——要么直接改返回值，要么临时改完立刻还原。

--- 玩家当前手持的物品
--- 手机上 Player.selectedItem / HeldItem 都是只读属性（没有字段），
--- 所以优先走 HeldItem 属性的 getter，拿不到再退回 inventory + 下标。
local function held_item(pl)
    if m_get_helditem then
        local ok, it = pcall(patch.invoke, m_get_helditem, pl)
        if ok and it then return it end
    end
    if not f_pl_inventory then return nil end
    local idx = -1
    if f_pl_selecteditem then
        idx = get_i(f_pl_selecteditem, pl, -1)
    elseif m_get_selecteditem then
        local ok, v = pcall(patch.invoke, m_get_selecteditem, pl)
        if ok and type(v) == "number" then idx = v end
    end
    if idx < 0 then return nil end
    local ok, arr = pcall(patch.get_field_value, f_pl_inventory, pl, "object")
    if not (ok and arr) then return nil end
    local ok2, it = pcall(patch.array_at, arr, idx)
    if ok2 then return it end
    return nil
end

-- ============ 幻影弓（物品 3540）============
-- PC 1.4.5.8 Item.cs:31729 case 3540：damage = 50 / useTime 12 / shootSpeed 20 / shoot 630
-- 与泰拉刃、利刃台风同一套做法：钩 GetWeaponDamage 按 70/50 缩放返回値，
-- 词缀加成天然保留，不写任何物品数据。
-- 注意：弓的最终伤害 = GetWeaponDamage(弓) + 弹药伤害（PickAmmo 里相加），
-- 这里只放大「弓」的那一部分，弹药贡献不变，正是「弓的伤害 50→70」的本意。
local PHANTASM_ID          = 3540
local PHANTASM_DAMAGE      = 70      -- 目标伤害
local PHANTASM_BASE_DAMAGE = 50      -- 原版伤害（缩放基准）
local phantasm_logged      = false

-- ============ 邪箭 / 小丑之箭：取消穿透后的伤害递减 ============
-- PC 1.4.5.8 Projectile.cs:13560-13565，位置在 Damage_PVE_Inner 的 switch (type) 里：
--     case 5:  damage = (int)((double)damage * 0.9);    ← 小丑之箭，穿透后 -10%
--     case 4:  damage = (int)((double)damage * 0.95);   ← 邪箭，穿透后 -5%
-- 这段是在「本次命中结算完之后」给下一次命中留的衰减值。
--
-- 做法：钩 Projectile.Damage_PVE(ref Rectangle, float) 的 prefix + postfix。
--   prefix  —— 记下本次命中结算前的 damage（模块级标量，用完即清）
--   postfix —— 把被衰减过的 damage 还原成刚记下的那个值
-- 这样一次命中多个目标也能精确还原（d0 是整次调用的起点），
-- 且不需要按槽位存状态，没有 whoAmI 复用和内存残留的问题。
local ARROW_UNHOLY = 4
local ARROW_JESTER = 5
local pve_d0       = nil      -- 本次 Damage_PVE 调用前的伤害
local arrow_logged = {}

-- ============ 水晶子弹：碎片 2 → 3 ============
-- PC 1.4.5.8 Projectile.cs:76802-76810，在 Kill() 的 else if (type == 89) 分支里：
--     if (type == 89 && owner == Main.myPlayer)
--         for (int num677 = 0; num677 < 2; num677++)      ← 固定 2 个
--             NewProjectile(..., 90, (int)((double)damage * 0.5), 0f, owner);
-- 做法：在 Kill 的 prefix 里先自己补发 1 个碎片（90），原版随后照发 2 个 → 共 3 个。
-- 为什么放 prefix 不放 postfix：prefix 时射弹对象一定有效，能读 position / velocity / damage / owner；
-- postfix 时对象可能已被回收，读字段会拿到垃圾值。
-- 调的是 13 参重载（PC 只有 11 参与 13 参两个版本，原版这句走的就是 13 参）：
--   (spawnSource, X, Y, SpeedX, SpeedY, Type, Damage, KnockBack, Owner, ai0, ai1, ai2, modifer)
local CRYSTAL_BULLET_PROJ = 89
local CRYSTAL_SHARD_PROJ  = 90
local crystal_logged      = false
local crystal_reenter     = false

-- ============ 叶绿弹：伤害 9 → 15 ============
-- 叶绿弹是「弹药」，物品 1179 / 射弹 207，Item.cs:14482 里 damage = 9。
-- 弹药伤害在 PickAmmo 里是「加到武器伤害上」的（Player.cs:54196 Damage += ammo.damage × 倍率），
-- 所以这里不能在 SetDefaults 里改模板（背包里的存量弹药不会重新 SetDefaults），
-- 也不能在 NewProjectile 的 prefix 里改 args（args 是值拷贝，改了不生效）。
-- 做法：钩 NewProjectile 的 postfix，拿到返回的射弹下标，直接改 Main.projectile[i].damage += 6。
-- 这样「弹药贡献」正好从 9 变成 15，武器本身的伤害一点不动。
local CHLORO_PROJ   = 207
local CHLORO_ADD    = 6        -- 15 - 9
local chloro_logged = false

-- ① 伤害：钩 GetWeaponDamage 的返回值
-- 原版 = (int)(item.damage × meleeDamage)，item.damage 里已经含了词缀加成，
-- 所以乘一个固定比例 115/85，等于「词缀也按 115 这个新基准重算」，且一点数据都不动。
local function weapon_damage_postfix(inst, args, result)
    if not ready then return nil end
    local it = args and args[1]
    if not it then return nil end
    if type(result) ~= "number" or result <= 0 then return nil end
    local t = get_i(f_item_type, it, -1)
    if CFG.terra and t == TERRA_ID then
        return math.floor(result * TERRA_DAMAGE / TERRA_BASE_DAMAGE + 0.5)
    elseif CFG.typhoon and t == TYPHOON_ITEM_ID then
        -- 利刃台风 85 → 90：同样按比例缩放，词缀加成天然保留
        return math.floor(result * TYPHOON_DAMAGE / TYPHOON_BASE_DAMAGE + 0.5)
    elseif CFG.phantasm and t == PHANTASM_ID then
        -- 幻影弓 50 → 70
        local nv = math.floor(result * PHANTASM_DAMAGE / PHANTASM_BASE_DAMAGE + 0.5)
        if not phantasm_logged then
            phantasm_logged = true
            logf(string.format("[phantasm] GetWeaponDamage %s → %s", tostring(result), tostring(nv)))
        end
        return nv
    end
    return nil
end

-- ② 使用时间：ItemCheck 之前临时把 useTime/useAnimation 改成 14，
-- 游戏按 14 算完挥动节奏后立刻还原，存档里永远是原版的 18。
local function itemcheck_prefix(inst)
    if not ready or not inst then return false end
    local it = held_item(inst)
    if not it then return false end
    local itype = get_i(f_item_type, it, -1)

    -- 利刃台风：使用时间 40 → 20（同样是临时改、用完还原，不写物品数据）
    if CFG.typhoon and itype == TYPHOON_ITEM_ID then
        local idx = get_i(f_pl_whoami, inst, -1)
        if idx < 0 then return false end
        local ut2 = get_i(f_item_usetime, it, -1)
        local ua2 = get_i(f_item_useanimation, it, -1)
        if ut2 < 0 or ua2 < 0 then return false end
        if ut2 ~= TYPHOON_USE_TIME then
            terra_backup[idx] = { useTime = ut2, useAnimation = ua2 }
        end
        if terra_backup[idx] then
            set_i(f_item_usetime, it, TYPHOON_USE_TIME)
            set_i(f_item_useanimation, it, TYPHOON_USE_TIME)
        end
        return false
    end

    if not CFG.terra or itype ~= TERRA_ID then return false end
    local idx = get_i(f_pl_whoami, inst, -1)
    if idx < 0 then return false end
    local ut = get_i(f_item_usetime, it, -1)
    local ua = get_i(f_item_useanimation, it, -1)
    if ut < 0 or ua < 0 then return false end
    -- 只有读到「不是 14」的原值才刷新备份：
    -- 万一某一帧没还原成功、物品停在 14，这里也不会把 14 当成原值记下来
    if ut ~= TERRA_USE_TIME then
        terra_backup[idx] = { useTime = ut, useAnimation = ua }
    end
    if not terra_backup[idx] then return false end
    -- ③ 近战速度奖励折扣
    --    首选「源头改数组」：ItemID.Sets.BonusMeleeSpeedMultiplier[757] 改成 1.0 后，
    --    Player.Update 算出来的 meleeSpeed 本来就不打折，这里什么都不用做（再做会双重加速）。
    --    只有数组写不进去时，才退回老办法：按 1/(1+(1/ms-1)/0.75) 反推回全额攻速。
    --    必须在挥动动画计算之前做，挂在 Update 尾部是无效的。
    if f_pl_meleespeed and not terra_speed_fixed then
        local ms = get_f(f_pl_meleespeed, inst, -1)
        if ms > 0 and ms < 1 then
            local raw = 1 + (1 / ms - 1) / TERRA_SPEED_DISCOUNT
            if raw > 0 then set_f(f_pl_meleespeed, inst, 1 / raw) end
        end
    end
    set_i(f_item_usetime, it, TERRA_USE_TIME)
    set_i(f_item_useanimation, it, TERRA_USE_TIME)
    return false
end

--- 还原某位玩家手持物品的使用时间（正常结束与异常中断都走这里）
local function terra_restore(pl)
    if not pl then return end
    local idx = get_i(f_pl_whoami, pl, -1)
    if idx < 0 then return end
    local b = terra_backup[idx]
    if not b then return end
    terra_backup[idx] = nil
    local it = held_item(pl)
    if not it then return end
    if b.useTime and b.useTime > 0 then set_i(f_item_usetime, it, b.useTime) end
    if b.useAnimation and b.useAnimation > 0 then set_i(f_item_useanimation, it, b.useAnimation) end
end

local function itemcheck_postfix(inst)
    if not inst then return end
    pcall(terra_restore, inst)
end

-- ============ 刃杖：把 SummonTagDamageMultiplier[864] 写成 1.0 ============
-- 2026-11-01 实机诊断结论：
--   静态数组在手机上完全可达，get_inner_type → get_field → get_field_value → array_at 一路成功，
--   读到的原值就是 0.6690000295639，写完回读 1.0，10 秒后仍然是 1.0（没有被游戏重置）。
-- 两个坑：
--   ① setup 阶段数组还没实例化（get_field_value 返回 nil），必须等进世界后再写；
--   ② array_set 必须带类型参数 "float"，不带类型会把值写成 0（会踩成「标记伤害归零」）。
local blade_fixed = false
local blade_retry = 0

local function fix_blade_multiplier()
    if not CFG.blade then blade_fixed = true return end   -- 开关关闭：标记完成，不再重试
    if blade_fixed then return end
    local okT, T_PID = pcall(patch.get_type, "Terraria.ID", "ProjectileID")
    if not (okT and T_PID) then return end
    local okI, sets = pcall(patch.get_inner_type, T_PID, "Sets")
    if not (okI and sets) then return end
    local okF, f = pcall(patch.get_field, sets, "SummonTagDamageMultiplier")
    if not (okF and f) then return end
    local okA, arr = pcall(patch.get_field_value, f, nil, "object")
    if not (okA and arr) then return end

    local okR, cur = pcall(patch.array_at, arr, BLADE_PROJ_ID, "float")
    local c = okR and tonumber(cur) or nil
    if c and c >= BLADE_FIX_MUL - 0.01 then
        blade_fixed = true
        return
    end

    pcall(patch.array_set, arr, BLADE_PROJ_ID, BLADE_FIX_MUL, "float")
    local okV, v = pcall(patch.array_at, arr, BLADE_PROJ_ID, "float")
    local nv = okV and tonumber(v) or nil
    if nv and nv >= BLADE_FIX_MUL - 0.01 then
        blade_fixed = true
    elseif c then
        -- 写不进去就还原原值，保证不会比原版更差
        pcall(patch.array_set, arr, BLADE_PROJ_ID, c, "float")
    end
end

-- ============ 泰拉刃：把 BonusMeleeSpeedMultiplier[757] 写成 1.0 ============
-- 与刃杖同一套机制（同为 float[] 静态数组），只是换了个类型和下标。
local function fix_terra_speed()
    if not CFG.terra then terra_speed_fixed = true return end   -- 开关关闭：标记完成，不再重试
    if terra_speed_fixed then return end
    local okT, T_IID = pcall(patch.get_type, "Terraria.ID", "ItemID")
    if not (okT and T_IID) then return end
    local okI, sets = pcall(patch.get_inner_type, T_IID, "Sets")
    if not (okI and sets) then return end
    local okF, f = pcall(patch.get_field, sets, "BonusMeleeSpeedMultiplier")
    if not (okF and f) then return end
    local okA, arr = pcall(patch.get_field_value, f, nil, "object")
    if not (okA and arr) then return end

    local okR, cur = pcall(patch.array_at, arr, TERRA_MELEE_IDX, "float")
    local c = okR and tonumber(cur) or nil
    if c and c >= TERRA_SPEED_FIX_MUL - 0.01 then
        terra_speed_fixed = true
        return
    end

    pcall(patch.array_set, arr, TERRA_MELEE_IDX, TERRA_SPEED_FIX_MUL, "float")
    local okV, v = pcall(patch.array_at, arr, TERRA_MELEE_IDX, "float")
    local nv = okV and tonumber(v) or nil
    if nv and nv >= TERRA_SPEED_FIX_MUL - 0.01 then
        terra_speed_fixed = true
    elseif c then
        -- 写不进去就还原原值，ItemCheck 里的老换算继续兜底
        pcall(patch.array_set, arr, TERRA_MELEE_IDX, c, "float")
    end
end

-- 发现 magicDamage 低于基准就恢复。基准由 UpdateEquips 结束时记录。
local function restore_md(pl, tag)
    if not is_spectre_hood(pl) then return end
    local md = get_f(f_pl_magicdmg, pl, -1)
    if md < 0 then return end
    -- 目标值 = 基准 - 惩罚 × 保留比例
    local target = md_base - GHOST_MAGIC_FIX * GHOST_PENALTY_KEEP
    if md_base > 0 and md < target - 0.02 then
        set_f(f_pl_magicdmg, pl, target)
    end
end

-- 主体逻辑放在 do_update 里，外面用 pcall 包一层：
-- 任何一行出错都不会让整个回调静默失效，且会在日志里留下一条 [ERR]
local function do_update(pl)

    -- ① lifeSteal：原版每帧硬压回 70/80，这里补值无效（已改为在吸血时只扣 1%），
    --    只读取用于日志观察
    local ls = get_f(f_pl_lifesteal, pl, -1)

    -- ② 幽灵兜帽套装：补回 40% 魔法伤害
    --    优先用 player.ghostHeal（套装奖励置位的标志），拿不到再退回装备 ID：
    --    1503 = Spectre Hood（兜帽）、1504 = Spectre Robe（长袍）、1505 = Spectre Pants（护腿）
    local spectre_hood = is_spectre_hood(pl)
    if spectre_hood then
        hood_miss = 0
        if CFG.ghost then restore_md(pl, "Update") end
    else
        -- 单帧判定失败可能只是数组读取抖动，连续 30 帧才算真的没穿
        hood_miss = hood_miss + 1
        if hood_miss > 30 then md_base = -1 end
    end


    -- ③ 黑曜石套：鞭范围 / 鞭速度 / 召唤伤害（Update 末尾再兜一次，保证同帧生效）
    if CFG.obsidian then apply_obsidian(pl) end

    -- ④ 泰拉刃：万一某帧 ItemCheck 中途异常没走到还原，这里兜住，避免 14 被带进存档
    if next(terra_backup) ~= nil then
        pcall(terra_restore, pl)
    end

    -- ⑥ 静态数组修正：刃杖标记乘数 + 泰拉刃攻速折扣
    --    数组要等进世界后才实例化，所以这里每 2 秒试一次，两项都成功就不再进这个分支
    if not blade_fixed or not terra_speed_fixed then
        blade_retry = blade_retry + 1
        if blade_retry >= 120 then
            blade_retry = 0
            if CFG.blade then pcall(fix_blade_multiplier) end
            if CFG.terra then pcall(fix_terra_speed) end
        end
    end

end


-- ============ Hook: Player.UpdateEquips（魔伤补偿的正确时机）============
-- 调用顺序：ResetEffects(md=1.0) -> UpdateEquips(幽灵套 md-=0.4) -> ItemCheck(伤害结算)
-- 所以必须在 UpdateEquips 之后、ItemCheck 之前补，挂在 Update 末尾是白补。
local function equips_postfix(inst, args, result)
    if not ready or not inst then return end
    local pl = inst
    if not is_spectre_hood(pl) then return end
    -- UpdateEquips 结束时 magicDamage 还是「未惩罚」状态，记下来作为基准
    local md = get_f(f_pl_magicdmg, pl, -1)
    if md >= 0 then
        -- 只增不减：避免某一帧读到已被惩罚的值把基准拉低
        if md > md_base then md_base = md end
    end
end

-- ============ Hook: Player.UpdateArmorSets（套装奖励生效点，最可能在这里扣 0.4）============
local function armorsets_postfix(inst, args, result)
    if not ready or not inst then return end
    if CFG.ghost then pcall(restore_md, inst, "UpdateArmorSets") end
    if CFG.obsidian then pcall(apply_obsidian, inst) end
end

local function update_postfix(inst, args, result)
    if not ready or not inst then return end
    local ok, err = pcall(do_update, inst)
    if not ok and not upd_err_logged then
        upd_err_logged = true
        logf("[ERR] update_postfix: " .. tostring(err))
        mod.error("[巅峰] " .. tostring(err))
    end
end

-- ============ 射弹 SetDefaults：利刃台风持续时间 + 神圣之星穿透 ============
-- 走 Projectile.SetDefaults(int Type) 的 postfix：此时 SetDefaults 刚跑完，
-- 而 NewProjectile 后续只设 position/owner/velocity/damage，不再碰 timeLeft / penetrate，写完不会被覆盖。
local function proj_setdefaults_postfix(inst, args, result)
    if not ready or not inst then return end
    local ok, err = pcall(function()
        local t = get_i(f_proj_type, inst, -1)

        if CFG.typhoon and t == TYPHOON_PROJ_ID then
            set_i(f_proj_timeleft, inst, TYPHOON_TIMELEFT)
            if not typhoon_proj_logged then
                typhoon_proj_logged = true
                logf("[typhoon] timeLeft → " .. tostring(get_i(f_proj_timeleft, inst, -1)))
            end
            return
        end

        -- 神圣之星：penetrate 1 → 2，命中第一个目标后不消失，能打到第二个
        -- 注意：SetDefaults 的最后一行是 maxPenetrate = penetrate，所以 maxPenetrate 现在还是 1，
        -- 两个字段必须一起改，否则 maxPenetrate != penetrate 会让免疫/音效判定走偏。
        if CFG.holy and t == HOLY_STAR_PROJ then
            local old = get_i(f_proj_penetrate, inst, -1)
            local oldMax = get_i(f_proj_maxpen, inst, -1)
            set_i(f_proj_penetrate, inst, HOLY_STAR_PEN)
            set_i(f_proj_maxpen, inst, HOLY_STAR_PEN)
            if not holy_logged.pen then
                holy_logged.pen = true
                logf(string.format("[holy] star penetrate %s→%s  maxPenetrate %s→%s",
                    tostring(old), tostring(get_i(f_proj_penetrate, inst, -1)),
                    tostring(oldMax), tostring(get_i(f_proj_maxpen, inst, -1))))
            end
        end
    end)
    if not ok then logf("[typhoon] setdefaults err " .. tostring(err)) end
end

-- ============ 利刃台风：一次发 2 枚 ============
-- LuaLoader 没有生成射弹的接口，只能钩 Projectile.NewProjectile（float 版，13 个参数）：
--   args = { spawnSource, X, Y, SpeedX, SpeedY, Type, Damage, KnockBack, Owner, ai0, ai1, ai2, modifer }
-- 在 prefix 里用 patch.invoke 再调一次同一方法（速度偏转约 12°），然后放行原调用。
-- 安全设计：第一次遇到 409 只「上膛」不发射，第二次起才真正多发；
-- 重入守卫 np_reenter 必须在最前面，否则内层调用会无限递归。
local np_reenter = false
local np_armed   = false     -- 首次遇到 409 只上膛，第二次起才多发

local function newproj_prefix(inst, args, result)
    if np_reenter then return false end
    if not args or not m_newproj then return false end
    if not CFG.typhoon or args[6] ~= TYPHOON_PROJ_ID then return false end

    if not np_armed then
        np_armed = true
        return false
    end

    local sx, sy = args[4], args[5]
    if type(sx) ~= "number" or type(sy) ~= "number" then return false end
    local ang = 0.21                       -- 约 12°
    local cs, sn = math.cos(ang), math.sin(ang)
    local nsx, nsy = sx * cs - sy * sn, sx * sn + sy * cs

    np_reenter = true
    pcall(patch.invoke, m_newproj,
        args[1], args[2], args[3], nsx, nsy,
        args[6], args[7], args[8], args[9],
        args[10], args[11], args[12], args[13])
    np_reenter = false
    return false                           -- 放行原调用，原方法自己发第一枚
end

-- ============ 叶绿弹：伤害 9 → 15 ============
-- NewProjectile 的 args 是值拷贝，prefix 里改 args[7] 不会影响原方法；
-- 只能等它返回射弹下标后，从 Main.projectile[idx] 上直接改字段。
-- 注意：内核不允许同一方法装两个钩子，所以这个 postfix 必须和利刃台风的 prefix
-- 挂在同一个 hook(m_newproj, {...}) 调用里。
local function newproj_postfix(inst, args, result)
    if not ready or not f_main_proj or not f_proj_damage then return end
    if not CFG.chloro or not args or args[6] ~= CHLORO_PROJ then return end
    if type(result) ~= "number" or result < 0 then return end
    pcall(function()
        local arr = patch.get_field_value(f_main_proj, nil, "object")
        if not arr then return end
        local p = patch.array_at(arr, result)
        if not p or not patch.is_valid(p) then return end
        local d = get_i(f_proj_damage, p, -1)
        if d and d > 0 then
            set_i(f_proj_damage, p, d + CHLORO_ADD)
            if not chloro_logged then
                chloro_logged = true
                logf(string.format("[chloro] proj idx=%s damage %s → %s",
                    tostring(result), tostring(d), tostring(d + CHLORO_ADD)))
            end
        end
    end)
end

-- ============ 水晶子弹：补发第 3 个碎片 ============
-- 原版 Kill 里固定发 2 个碎片（type 90），这里在 Kill 之前先补 1 个 → 共 3 个。
-- 速度算法照抄原版：vec = -velocity * rand(40,70)*0.01 + rand(-20,21)*0.4
-- C# 的 Random.Next(min,max) 左闭右开，所以是 40~69、-20~20。
local function crystal_extra_shard(inst)
    if crystal_reenter then return end
    if not (m_newproj and m_proj_src and f_proj_pos and f_proj_vel and f_proj_owner) then return end
    crystal_reenter = true
    local ok, err = pcall(function()
        local px, py = patch.get_field_vec2(f_proj_pos, inst)
        local vx, vy = patch.get_field_vec2(f_proj_vel, inst)
        if type(px) ~= "number" or type(py) ~= "number"
            or type(vx) ~= "number" or type(vy) ~= "number" then
            logf("[crystal] vec2 read failed")
            return
        end
        local d = get_i(f_proj_damage, inst, -1)
        if d <= 0 then
            logf("[crystal] damage invalid " .. tostring(d))
            return
        end
        local ow = get_i(f_proj_owner, inst, -1)
        local src = patch.invoke(m_proj_src, inst)
        if not src then
            logf("[crystal] source is nil")
            return
        end
        local nx = -vx * (math.random(40, 69) * 0.01) + math.random(-20, 20) * 0.4
        local ny = -vy * (math.random(40, 69) * 0.01) + math.random(-20, 20) * 0.4
        local dmg = math.floor(d * 0.5)     -- 原版 (int)((double)damage * 0.5)
        local ret = patch.invoke(m_newproj, src, px + nx, py + ny, nx, ny,
            CRYSTAL_SHARD_PROJ, dmg, 0, ow, 0, 0, 0, nil)
        if not crystal_logged then
            crystal_logged = true
            logf(string.format("[crystal] extra shard ret=%s pos=%.1f,%.1f vel=%.2f,%.2f dmg=%s owner=%s",
                tostring(ret), px, py, nx, ny, tostring(dmg), tostring(ow)))
        end
    end)
    crystal_reenter = false
    if not ok then logf("[crystal] err " .. tostring(err)) end
end

-- ============ 圣箭：把「星星伤害 ÷3」还原成 100% ============
-- Projectile.Kill() 里 type==91 的分支只有这一处用到 damage：
--     int num673 = damage;  if (type == 91) { num673 /= 3; }
--     NewProjectile(..., 92, num673, ...)
-- 在 Kill 之前把圣箭的 damage ×3，整数除法后 num673 = 3d/3 = d，精确还原（无浮点误差）。
-- 该分支与其它 type 分支互斥，不会影响别的弹幕；弹幕随后即被回收，不需要还原。
local function proj_kill_prefix(inst, args, result)
    if not ready or not inst then return false end
    local ok = pcall(function()
        local t = get_i(f_proj_type, inst, -1)
        if CFG.holy and t == HOLY_ARROW_PROJ then
            local d = get_i(f_proj_damage, inst, -1)
            if d <= 0 then return end
            set_i(f_proj_damage, inst, d * 3)
            if not holy_logged.kill then
                holy_logged.kill = true
                logf("[holy] kill: arrow damage " .. tostring(d) .. " → " .. tostring(d * 3))
            end
        elseif CFG.crystal and t == CRYSTAL_BULLET_PROJ then
            crystal_extra_shard(inst)
        end
    end)
    if not ok then return false end
    return false        -- 永远放行原方法
end

-- ============ 邪箭 / 小丑之箭：穿透后不衰减 ============
local function pve_prefix(inst, args, result)
    pve_d0 = nil
    if not ready or not inst then return false end
    local ok = pcall(function()
        local t = get_i(f_proj_type, inst, -1)
        local want = (CFG.unholy and t == ARROW_UNHOLY) or (CFG.jester and t == ARROW_JESTER)
        if not want then return end
        local d = get_i(f_proj_damage, inst, -1)
        if d and d > 0 then pve_d0 = d end
    end)
    if not ok then pve_d0 = nil end
    return false        -- 永远放行原方法
end

local function pve_postfix(inst, args, result)
    if not pve_d0 then return end
    local d0 = pve_d0
    pve_d0 = nil        -- 用完即清，避免残留影响下一次
    if not ready or not inst then return end
    pcall(function()
        local d = get_i(f_proj_damage, inst, -1)
        if d and d > 0 and d ~= d0 then
            set_i(f_proj_damage, inst, d0)
            if not arrow_logged.pen then
                arrow_logged.pen = true
                logf(string.format("[arrow] pen-damage %s → restored %s", tostring(d), tostring(d0)))
            end
        end
    end)
end

-- ============ 钩子安装 ============
local function hook(method, spec, label)
    if not method then
        logf("[hook] MISSING " .. label)
        mod.error("[巅峰] 缺少方法：" .. label)
        return false
    end
    local ok, h = pcall(patch.install_hook, method, spec)
    if not ok or not h then
        logf("[hook] FAIL " .. label .. " : " .. tostring(h))
        mod.error("[巅峰] 挂钩失败 " .. label .. "：" .. tostring(h))
        return false
    end
    hooks[#hooks + 1] = h
    logf("[hook] OK " .. label)
    return true
end

function peak_setup()
    logf("=== setup " .. os.date("%H:%M:%S") .. " ===")
    logf("platform=" .. tostring(mod.platform))
    peak_load()
    T_Main   = patch.get_type("Terraria", "Main")
    T_Player = patch.get_type("Terraria", "Player")
    T_Proj   = patch.get_type("Terraria", "Projectile")
    logf(string.format("types: Main=%s Player=%s Proj=%s",
        tostring(T_Main), tostring(T_Player), tostring(T_Proj)))
    if not (T_Main and T_Player and T_Proj) then
        mod.error("[巅峰] 类型获取失败")
        return
    end

    f_proj_type     = find_field(T_Proj, "type")
    f_proj_damage   = find_field(T_Proj, "damage")
    f_proj_timeleft = find_field(T_Proj, "timeLeft")
    f_proj_magic    = find_field(T_Proj, "magic")
    f_proj_ai       = find_field(T_Proj, "ai")
    f_proj_alpha    = find_field(T_Proj, "alpha")
    f_proj_penetrate = find_field(T_Proj, "penetrate")
    f_proj_maxpen    = find_field(T_Proj, "maxPenetrate")
    f_proj_pos       = find_field(T_Proj, "position")      -- 继承自 Entity
    f_proj_vel       = find_field(T_Proj, "velocity")      -- 继承自 Entity
    f_proj_owner     = find_field(T_Proj, "owner")

    f_pl_lifesteal   = find_field(T_Player, "lifeSteal")
    f_pl_magicdmg    = find_field(T_Player, "magicDamage")
    f_pl_statlifemax = find_field(T_Player, "statLifeMax2")
    f_pl_statlife    = find_field(T_Player, "statLife")
    f_pl_head        = find_field(T_Player, "head")
    f_pl_body        = find_field(T_Player, "body")
    f_pl_legs        = find_field(T_Player, "legs")
    f_pl_dead        = find_field(T_Player, "dead")
    f_pl_whoami      = find_field(T_Player, "whoAmI")
    f_pl_ghostheal   = find_field(T_Player, "ghostHeal")
    f_pl_armor       = find_field(T_Player, "armor")
    f_pl_whiprange   = find_field(T_Player, "whipRangeMultiplier")
    f_pl_meleespeed  = find_field(T_Player, "meleeSpeed")
    f_pl_whipuse     = find_field(T_Player, "whipUseTimeMultiplier")
    f_pl_miniondmg   = find_field(T_Player, "minionDamage")
    do
        local T_Item = patch.get_type("Terraria", "Item")
        if T_Item then
            f_item_type = find_field(T_Item, "type")
            f_item_usetime = find_field(T_Item, "useTime")
            f_item_useanimation = find_field(T_Item, "useAnimation")
        end
    end
    f_pl_inventory    = find_field(T_Player, "inventory")
    f_pl_selecteditem = find_field(T_Player, "selectedItem")   -- 手机上为 nil（只读属性，不是字段）
    pcall(function()
        local ph = patch.get_property(T_Player, "HeldItem")
        if ph then m_get_helditem = patch.property_get_method(ph) end
        local ps = patch.get_property(T_Player, "selectedItem")
        if ps then m_get_selecteditem = patch.property_get_method(ps) end
    end)

    f_main_gamemenu = find_field(T_Main, "gameMenu")
    f_main_players  = find_field(T_Main, "player")
    f_main_proj     = find_field(T_Main, "projectile")   -- Projectile[]，叶绿弹改伤害用
    f_myplayer      = find_field(T_Main, "myPlayer")
    if not f_myplayer then
        m_get_myplayer = patch.get_method(T_Main, "get_myPlayer", 0)
            or patch.get_method(T_Main, "get_myPlayer")
    end

    -- 利刃台风多发用：NewProjectile 的 float 版是 13 参（Vector2 版是 11 参，内部会转调 float 版）
    m_newproj = patch.get_method(T_Proj, "NewProjectile", 13)
             or patch.get_method(T_Proj, "NewProjectile", 11)
    logf("[typhoon] NewProjectile = " .. tostring(m_newproj))

    -- 圣箭用：Projectile.Kill() 无参
    m_proj_kill = patch.get_method(T_Proj, "Kill", 0) or patch.get_method(T_Proj, "Kill")
    logf("[holy] Projectile.Kill = " .. tostring(m_proj_kill))

    -- 邪箭/小丑之箭用：Damage_PVE(ref Rectangle, float) —— 2 参（PE 源码核实）
    m_damage_pve = patch.get_method(T_Proj, "Damage_PVE", 2) or patch.get_method(T_Proj, "Damage_PVE")
    logf("[arrow] Projectile.Damage_PVE = " .. tostring(m_damage_pve))

    -- 水晶子弹补发碎片用：GetProjectileSource_FromThis() —— 0 参，返回 IEntitySource
    m_proj_src = patch.get_method(T_Proj, "GetProjectileSource_FromThis", 0)
              or patch.get_method(T_Proj, "GetProjectileSource_FromThis")
    logf("[crystal] GetProjectileSource_FromThis = " .. tostring(m_proj_src))

    -- gameMenu 在 PE 版是属性，补上 getter
    pcall(function()
        local pg = patch.get_property(T_Main, "gameMenu")
        if pg then m_get_gamemenu = patch.property_get_method(pg) end
    end)
    logf("getters: gamemenu=" .. tostring(m_get_gamemenu))

    logf(string.format("proj: type=%s dmg=%s tleft=%s magic=%s",
        tostring(f_proj_type), tostring(f_proj_damage), tostring(f_proj_timeleft),
        tostring(f_proj_magic)))
    logf(string.format("player: ls=%s md=%s life=%s max=%s head=%s who=%s",
        tostring(f_pl_lifesteal), tostring(f_pl_magicdmg), tostring(f_pl_statlife),
        tostring(f_pl_statlifemax), tostring(f_pl_head), tostring(f_pl_whoami)))
    logf(string.format("main: menu=%s players=%s myplayer=%s getmy=%s newtext=%s",
        tostring(f_main_gamemenu), tostring(f_main_players),
        tostring(f_myplayer), tostring(m_get_myplayer), tostring(m_newtext)))

    if not (f_proj_type and f_proj_damage and f_proj_timeleft) then
        mod.error("[巅峰] Projectile 关键字段缺失")
        return
    end
    local ok_all = true

    ok_all = hook(patch.get_method(T_Proj, "ghostHeal", 3),
        { prefix = ghost_heal_prefix }, "Projectile.ghostHeal") and ok_all

    ok_all = hook(
        patch.get_method(T_Player, "UpdateEquips", 1) or patch.get_method(T_Player, "UpdateEquips"),
        { postfix = equips_postfix }, "Player.UpdateEquips") and ok_all

    ok_all = hook(
        patch.get_method(T_Player, "UpdateArmorSets", 1) or patch.get_method(T_Player, "UpdateArmorSets"),
        { postfix = armorsets_postfix }, "Player.UpdateArmorSets") and ok_all

    ok_all = hook(
        patch.get_method(T_Player, "Update", 1) or patch.get_method(T_Player, "Update"),
        { postfix = update_postfix }, "Player.Update") and ok_all

    -- 利刃台风：持续时间（SetDefaults postfix）+ 多发（NewProjectile prefix）
    -- 这两个单独装，不并入 ok_all：万一装不上只能说明这一项不能用，不能拖垮已有 7 项功能
    local typhoon_a = hook(
        patch.get_method(T_Proj, "SetDefaults", 1) or patch.get_method(T_Proj, "SetDefaults"),
        { postfix = proj_setdefaults_postfix }, "Projectile.SetDefaults")
    local typhoon_b = hook(m_newproj,
        { prefix = newproj_prefix, postfix = newproj_postfix }, "Projectile.NewProjectile")
    -- 圣箭：星星伤害还原（Kill 之前把圣箭 damage ×3）
    local holy_k = hook(m_proj_kill,
        { prefix = proj_kill_prefix }, "Projectile.Kill")
    -- 邪箭 / 小丑之箭：穿透后伤害不递减
    local arrow_h = hook(m_damage_pve,
        { prefix = pve_prefix, postfix = pve_postfix }, "Projectile.Damage_PVE")
    logf(string.format("[typhoon] hooks: setdefaults=%s newproj=%s | [holy] kill=%s | [arrow] pve=%s",
        tostring(typhoon_a), tostring(typhoon_b), tostring(holy_k), tostring(arrow_h)))

    -- 泰拉刃：伤害（改返回值）+ 使用时间（临时改完还原）
    -- 两者分开判断：伤害钩子只要认得 Item.type 就能装，不依赖能不能取到手持物品
    local can_hold = (m_get_helditem ~= nil)
        or (f_pl_inventory ~= nil and (f_pl_selecteditem ~= nil or m_get_selecteditem ~= nil))

    if f_item_type then
        ok_all = hook(
            patch.get_method(T_Player, "GetWeaponDamage", 1),
            { postfix = weapon_damage_postfix, override_result = true },
            "Player.GetWeaponDamage") and ok_all
    else
        mod.error("[巅峰] 缺少 Item.type，泰拉刃伤害未启用")
    end

    if f_item_usetime and f_item_useanimation and can_hold then
        ok_all = hook(
            patch.get_method(T_Player, "ItemCheck", 0) or patch.get_method(T_Player, "ItemCheck"),
            { prefix = itemcheck_prefix, postfix = itemcheck_postfix },
            "Player.ItemCheck") and ok_all
    else
        mod.error("[巅峰] 取不到手持物品或 Item 时间字段，泰拉刃攻速未启用")
    end

    -- 自检：只在有缺失时输出一条，正常不刷屏
    do
        local miss = {}
        if not f_item_type then miss[#miss + 1] = "Item.type" end
        if not f_item_usetime then miss[#miss + 1] = "Item.useTime" end
        if not f_item_useanimation then miss[#miss + 1] = "Item.useAnimation" end
        if not m_get_helditem then miss[#miss + 1] = "HeldItem.get" end
        if not f_pl_inventory then miss[#miss + 1] = "Player.inventory" end
        if #miss > 0 then
            mod.error("[巅峰] 泰拉刃字段缺失：" .. table.concat(miss, ","))
        end
    end

    ready = ok_all
    logf("ready=" .. tostring(ready))
    if ready then
        mod.info("[巅峰] 已启用")
    else
        mod.error("[巅峰] 部分钩子未装上，功能可能不完整")
    end
end

todo_list = { "setup" }

function peak_cleanup()
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
end

function peak_toggle(key)
    if not NAMES[key] then return "巅峰时代：未知功能" end
    CFG[key] = not CFG[key]
    peak_save()
    if CFG[key] then return NAMES[key] .. "的力量回归了(◣_◢)" end
    return NAMES[key] .. "的力量已经退去 ( >_< )"
end

function peak_label(key)
    local nm = NAMES[key] or key
    if CFG[key] then return nm .. "（已开启）" end
    return nm .. "（已关闭）"
end

return peak_setup, peak_cleanup, peak_toggle, peak_label
end)()
-- 第九部分：三探测（参考 玩家工坊 PlayerForge v2.0.0 的生物探测/宝藏探测/危险感知）
-- 实现（同参考）：Hook Player.UpdateArmorSets postfix（回退 UpdateEquips → ResetEffects），
--   原版每帧在此重算装备效果并把感知字段重置回原版值，postfix 紧接着置 true——
--   天然幂等、不叠加。字段：detectCreature（生物）/ findTreasure（宝藏）/ dangerSense（危险）。
-- 默认常开、无开关；哪个字段取不到就自动跳过对应项。所有函数 local。
sn_setup, sn_cleanup = (function()
local P = mod.patch
local SENSE_FIELDS = { "detectCreature", "findTreasure", "dangerSense" }
-- v5.7.0：三项拆成独立开关，字段句柄与开关 key 一一对齐
local SENSE_KEYS   = { "sn_creature", "sn_treasure", "sn_danger" }
local F = {}          -- { f = 字段句柄, key = 开关 key }
local sn_hook

local function on_armor_sets(inst, args)
    if not CHW then return end
    if not inst then return end
    -- 总开关关掉就整块跳过；否则逐项判断（游戏内勾选即时生效）
    if not _G.ms_gates.is("sn") then return end
    for i = 1, #F do
        local e = F[i]
        if _G.ms_gates.is(e.key) then
            pcall(P.set_field_value, e.f, inst, true, "bool")
        end
    end
end

local function sn_setup()
    local okT, T_PLAYER = pcall(P.get_type, "Terraria", "Player")
    if not okT or not T_PLAYER then
        mod.warn("三探测：找不到 Terraria.Player，跳过")
        return
    end
    for idx, name in ipairs(SENSE_FIELDS) do
        local okF, f = pcall(P.get_field, T_PLAYER, name)
        if okF and f then
            F[#F + 1] = { f = f, key = SENSE_KEYS[idx] }
        else
            mod.warn("三探测：字段 " .. name .. " 取不到，跳过该项")
        end
    end
    if #F == 0 then
        mod.warn("三探测：无可用感知字段，跳过")
        return
    end
    -- 三级回退（同玩家工坊）：UpdateArmorSets → UpdateEquips → ResetEffects
    local ok1, h1 = pcall(P.get_method, T_PLAYER, "UpdateArmorSets", 1)
    local method
    if ok1 and h1 then method = h1 end
    if not method then
        local ok2, h2 = pcall(P.get_method, T_PLAYER, "UpdateEquips", 1)
        if ok2 and h2 then method = h2 end
    end
    if not method then
        local ok3, h3 = pcall(P.get_method, T_PLAYER, "ResetEffects", 0)
        if ok3 and h3 then method = h3 end
    end
    if not method then
        mod.warn("三探测：找不到可用钩子（UpdateArmorSets/UpdateEquips/ResetEffects），跳过")
        return
    end
    local okH, h = pcall(P.install_hook, method, { postfix = _G.mg_gated("sn", on_armor_sets) })
    if okH then
        sn_hook = h
    else
        mod.warn("三探测：钩子安装失败：" .. tostring(h))
    end
end

function sn_cleanup()
    if sn_hook and sn_hook.remove then pcall(function() sn_hook:remove() end) end
    sn_hook = nil
end
return sn_setup, sn_cleanup
end)()
-- 第十部分：晶塔四改（参考 世界工坊 WorldForge v7.0.0「晶塔规则」精简移植；
--   第四改参考「更好的体验分支(晶塔)v1.0.0 / lua.qing.pylon」，v2.6.3 起）
--   ① 无视距离：TeleportPylonsSystem.IsPlayerNearAPylon（静态1参）prefix 跳过原方法、恒 true
--   ② 无视危险：NPC.AnyDanger(bool,bool,bool) 3参（1.4.5.8 实际签名，参考 v5 修正）
--      prefix 跳过原方法、恒 false（"有危险"=假）
--   ③ 同类型多座：TeleportPylonsSystem.HasPylonOfType（1枚举参，枚举=标量可挂）
--      postfix + override_result 恒 false（"没有该类型晶塔"→ 可继续放置，无上限）
--   ④ 传送不需 NPC：TeleportPylonsSystem.DoesPositionHaveEnoughNPCs（2参）
--      postfix + override_result 恒 true（"附近 NPC 够了"→ 无人也能放）
--      （不碰 DoesPylonAcceptTeleportation，保留生物群系连接原规则——同参考模组）
-- 默认常开、无开关（参考 v5 教训：不设总开关，各项各管各的）。所有函数 local。
py_setup, py_cleanup = (function()
local P = mod.patch
local py_hooks = {}

-- ① 无视距离：返回 true,true = 跳过原方法并把返回值置 true（"就在晶塔旁边"）
local function on_near_pylon(inst, args)
    return true, true
end
-- ② 无视危险：返回 true,false = 跳过原方法并把返回值置 false（"没有危险"）
local function on_any_danger(inst, args)
    return true, false
end
-- ③ 同类型多座：override_result 下 postfix 返回值覆盖原返回值，恒 false
local function on_has_pylon_of_type(inst, args, result)
    return false
end
-- ④ 传送不需 NPC：override_result 下 postfix 恒 true（"附近 NPC 够了"）
local function on_enough_npcs(inst, args, result)
    return true
end

local function safe_hook(method, spec, label)
    if not method then
        mod.warn("晶塔：方法句柄为空，跳过：" .. label)
        return
    end
    local ok, h = pcall(P.install_hook, method, spec)
    if ok and h then
        py_hooks[#py_hooks + 1] = h
    else
        mod.warn("晶塔：安装钩子失败 " .. label .. "：" .. tostring(h))
    end
end

-- v13.1.9：真凶 —— HandleTeleportRequest 里遍历晶塔时有一道
--   player.InTileEntityInteractionRange(x, y, 3, 4, Pylons) ：「玩家身边必须有一座晶塔」
--   一座都找不到 → 报「NotNearAPylon」（就是你看到的那句）。
--   参考「更好的体验」的 _runningHandleTeleportRequest：只在传送期间放开，不影响别处交互。
local py_in_tp = false
local function on_handle_tp_pre(inst, args)
    py_in_tp = true
    return false
end
local function on_handle_tp_post(inst, args, result)
    py_in_tp = false
end
local function on_ent_range(inst, args)
    if py_in_tp then return true, true end
    return false
end
local function py_setup()
    -- ①/③：TeleportPylonsSystem（Terraria.GameContent）
    local okT, T_PYLON = pcall(P.get_type, "Terraria.GameContent", "TeleportPylonsSystem")
    if not okT or not T_PYLON then
        mod.warn("晶塔：找不到 TeleportPylonsSystem，跳过")
        return
    end
    local ok1, m1 = pcall(P.get_method, T_PYLON, "IsPlayerNearAPylon", 1)
    -- v8.3.6：四个钩子一律无条件安装，开关全部下沉到回调内判断。
    --   （第一版漏了这一层：关一次某个二级项，那个钩子就再也不会装上，
    --     之后无论怎么开关都不会生效。）
    safe_hook(ok1 and m1 or nil, { prefix = _G.mg_gated({ "py", "py_dist" }, on_near_pylon) }, "IsPlayerNearAPylon")
    local ok2, m2 = pcall(P.get_method, T_PYLON, "HasPylonOfType", 1)
    safe_hook(ok2 and m2 or nil, { override_result = true, postfix = _G.mg_gated({ "py", "py_multi" }, on_has_pylon_of_type) }, "HasPylonOfType")
    -- ④：DoesPositionHaveEnoughNPCs（2 参，v2.6.3 第四改）
    local ok4, m4 = pcall(P.get_method, T_PYLON, "DoesPositionHaveEnoughNPCs", 2)
    safe_hook(ok4 and m4 or nil, { override_result = true, postfix = _G.mg_gated({ "py", "py_npc" }, on_enough_npcs) }, "DoesPositionHaveEnoughNPCs")
    -- ②：NPC.AnyDanger（3 参，1.4.5.8 手机版签名）
    local okN, T_NPC = pcall(P.get_type, "Terraria", "NPC")
    if okN and T_NPC then
        local ok3, m3 = pcall(P.get_method, T_NPC, "AnyDanger", 3)
        safe_hook(ok3 and m3 or nil, { prefix = _G.mg_gated({ "py", "py_danger" }, on_any_danger) }, "NPC.AnyDanger")
    else
        mod.warn("晶塔：找不到 Terraria.NPC，无视危险跳过")
    end
    -- v13.1.7（参考「更好的体验」）：NPC 数量才是真凶 —— 万能晶塔不需要 NPC，所以它能传。
    --   ① HowManyNPCsDoesPylonNeed 恒返回 0（原版普通晶塔要 2 个）
    --   ② DoesPylonHaveEnoughNPCsAroundIt 恒返回 true（双保险）
    --   ③ DoesPylonAcceptTeleportation 恒返回 true（生物群系）
    local okn, mn = pcall(P.get_method, T_PYLON, "HowManyNPCsDoesPylonNeed", 2)
    safe_hook(okn and mn or nil, { override_result = true, postfix = _G.mg_gated({ "py", "py_npc" }, function() return 0 end) }, "HowManyNPCsDoesPylonNeed")
    local okh, mh = pcall(P.get_method, T_PYLON, "DoesPylonHaveEnoughNPCsAroundIt", 2)
    safe_hook(okh and mh or nil, { override_result = true, postfix = _G.mg_gated({ "py", "py_npc" }, function() return true end) }, "DoesPylonHaveEnoughNPCsAroundIt")
    local okb, mbb = pcall(P.get_method, T_PYLON, "DoesPylonAcceptTeleportation", 2)
    safe_hook(okb and mbb or nil, { override_result = true, postfix = _G.mg_gated({ "py", "py_dist" }, function() return true end) }, "DoesPylonAcceptTeleportation")
    -- v13.1.9：传送期间放开「身边要有晶塔」
    local oktp, mtp = pcall(P.get_method, T_PYLON, "HandleTeleportRequest", 2)
    safe_hook(oktp and mtp or nil, { prefix = _G.mg_gated({ "py", "py_dist" }, on_handle_tp_pre), postfix = on_handle_tp_post }, "HandleTeleportRequest")
    local okP9, P_PLAYER9 = pcall(P.get_type, "Terraria", "Player")
    if okP9 and P_PLAYER9 then
        local okE, mE = pcall(P.get_method, P_PLAYER9, "InTileEntityInteractionRange", 5)
        safe_hook(okE and mE or nil, { prefix = _G.mg_gated({ "py", "py_dist" }, on_ent_range) }, "InTileEntityInteractionRange")
    end
end

function py_cleanup()
    for i = 1, #py_hooks do
        local h = py_hooks[i]
        if h and h.remove then pcall(function() h:remove() end) end
    end
    py_hooks = {}
end
return py_setup, py_cleanup
end)()
-- 第十一部分：复活规则（参考 世界工坊 WorldForge v7.0.0「死亡与复活」精简移植）
--   ① 复活时间固定 5 秒：Player.KillMe(4参) postfix 把 respawnTimer 覆盖为 300 帧
--      （原版 KillMe 内部 respawnTimer = GetRespawnTime(pvp)，UpdateDead 每帧 -1 到 0 复活；
--       respawnTimerMax = 3600 帧，300 帧 = 5 秒在限内；60fps 计）
--   ② 复活不掉墓碑：Player.DropTombstone(3参) prefix 返回 true 拦掉这次掉落
--      （墓碑掉落唯一出口，参数全为标量/引用类型，prefix 可安全拦截）
--   ③ 复活地点按钮（v2.0.8，参考世界工坊「复活与死亡·复活地点」）：默认原版（出生点/床），
--      开启后原地复活。取证同世界工坊：死亡复活走 Player.Spawn(PlayerSpawnContext)，
--      不猜枚举数值——前缀读 Player.dead（死亡复活必 true，魔镜回城/进世界必 false），
--      后缀才把死亡瞬间坐标写回 position 并把 velocity 归零。
--   ★ 雷区规避：绝不读 lastDeathPostion（该字段句柄在本机是坏的，get_field_vec2 必崩 0x10，
--     pcall 挡不住）。死亡坐标改在 Player.KillMe 时用 position 句柄自行记录、复活时自行回写；
--     position/velocity 的 vec2 读写在召唤/动作优化/猛冲模块中已长期验证安全。
-- ①② 默认常开无开关；③ 带按钮、默认关闭（原版复活地点），rvplace_en.txt 持久化。
rv_setup, rv_cleanup, rv_set_enabled, rv_is_enabled = (function()
local P = mod.patch
local RV_TIME = 300   -- 5 秒 × 60 帧/秒
local rv_hooks = {}

local F_respawn   -- Player.respawnTimer 字段句柄
local F_rv_pos    -- Player.position（vec2，全模组已验证安全）
local F_rv_vel    -- Player.velocity（vec2，猛冲模块每帧读、动作优化每帧写同类句柄）
local F_rv_dead   -- Player.dead（bool 标量）
local RP_EN = false      -- 复活地点开关：false=原版（出生点/床），true=原地复活
local dead_x, dead_y     -- 死亡瞬间自记坐标（KillMe 时记录，不碰 lastDeathPostion）
local spawn_was_dead = false   -- Spawn 前缀瞬间是否处于死亡状态

-- 安全取字段：pcall + 继承链回退（对齐快速放置 find_field_s 的稳定写法）
local function rv_field(t, name)
    local cur, guard = t, 0
    while cur and guard < 16 do
        local ok, f = pcall(P.get_field, cur, name)
        if ok and f then return f end
        local ok2, par = pcall(P.get_parent, cur)
        if not ok2 then return nil end
        cur = par
        guard = guard + 1
    end
    return nil
end

-- ① 复活计时固定：postfix 覆盖 respawnTimer；同时记录死亡瞬间坐标（复活地点用）
local function on_kill_me(inst, args)
    if not inst then return end
    if F_rv_pos then
        local ok, x, y = pcall(P.get_field_vec2, F_rv_pos, inst)
        if ok and type(x) == "number" and type(y) == "number" then
            dead_x, dead_y = x, y
        end
    end
    if F_respawn then
        pcall(P.set_field_value, F_respawn, inst, RV_TIME, "int32")
    end
end
-- ② 拦掉墓碑掉落：prefix 返回 true = 跳过原方法
local function on_drop_tombstone(inst, args)
    return true
end

-- ③ 复活地点：Player.Spawn(1参) 前缀记录「这次 Spawn 是不是死亡复活」
local function on_spawn_prefix(inst, args)
    spawn_was_dead = false
    if not inst or not F_rv_dead then return end
    local ok, v = pcall(P.get_field_value, F_rv_dead, inst, "bool")
    if ok and (v == true or v == 1) then spawn_was_dead = true end
end
-- ③ 复活地点：后缀把玩家搬回死亡坐标（仅开启时；速度归零免得被死亡惯性带飞）
local function on_spawn_postfix(inst, args)
    local was = spawn_was_dead
    spawn_was_dead = false
    if not was or not RP_EN or not inst then return end
    if type(dead_x) ~= "number" or type(dead_y) ~= "number" then return end
    if dead_x < 16 or dead_y < 16 then return end   -- (0,0)≈世界外 = 没有有效死亡坐标
    if not F_rv_pos then return end
    local ok = pcall(P.set_field_vec2, F_rv_pos, inst, dead_x, dead_y)
    if ok and F_rv_vel then
        pcall(P.set_field_vec2, F_rv_vel, inst, 0, 0)
    end
end

local function safe_hook(method, spec, label)
    if not method then
        mod.warn("复活规则：方法句柄为空，跳过：" .. label)
        return
    end
    local ok, h = pcall(P.install_hook, method, spec)
    if ok and h then
        rv_hooks[#rv_hooks + 1] = h
    else
        mod.warn("复活规则：安装钩子失败 " .. label .. "：" .. tostring(h))
    end
end

local function rv_setup()
    do
        local ok, s = pcall(function() return mod.read_file("rvplace_en.txt") end)
        if ok and type(s) == "string" and s:sub(1, 1) == "1" then RP_EN = true end
    end
    local okT, T_PLAYER = pcall(P.get_type, "Terraria", "Player")
    if not okT or not T_PLAYER then
        mod.warn("复活规则：找不到 Terraria.Player，跳过")
        return
    end
    local okF, f = pcall(P.get_field, T_PLAYER, "respawnTimer")
    if okF and f then F_respawn = f end
    local ok1, m1 = pcall(P.get_method, T_PLAYER, "KillMe", 4)
    if F_respawn then
        safe_hook(ok1 and m1 or nil, { postfix = on_kill_me }, "Player.KillMe")
    else
        mod.warn("复活规则：respawnTimer 字段取不到，5 秒复活跳过")
    end
    local ok2, m2 = pcall(P.get_method, T_PLAYER, "DropTombstone", 3)
    safe_hook(ok2 and m2 or nil, { prefix = on_drop_tombstone }, "Player.DropTombstone")
    -- v2.0.8 复活地点：附加句柄 + Player.Spawn 钩子（缺句柄只停用复活地点，①②照常）
    F_rv_pos  = rv_field(T_PLAYER, "position")
    F_rv_vel  = rv_field(T_PLAYER, "velocity")
    F_rv_dead = rv_field(T_PLAYER, "dead")
    if F_rv_pos and F_rv_dead then
        local oks, ms = pcall(P.get_method, T_PLAYER, "Spawn", 1)
        safe_hook(oks and ms or nil, { prefix = on_spawn_prefix, postfix = on_spawn_postfix }, "Player.Spawn")
    else
        mod.warn("复活规则：position/dead 句柄不全，复活地点功能停用（5 秒复活/不掉墓碑照常）")
    end
end

function rv_cleanup()
    for i = 1, #rv_hooks do
        local h = rv_hooks[i]
        if h and h.remove then pcall(function() h:remove() end) end
    end
    rv_hooks = {}
end
-- ===== 合并版接线：复活地点开关（按钮点击立即生效，状态在死亡/复活钩子里读取，
--      无需遍历背包之类的游戏上下文刷新，GUI 回调里直接切换是安全的）=====
function rv_set_enabled(b)
    RP_EN = (b and true or false)
end
function rv_is_enabled() return RP_EN end
return rv_setup, rv_cleanup, rv_set_enabled, rv_is_enabled
end)()
-- ============================================================================
-- 第二十部分：玩家属性查看（参考「更好的体验 v1.2.0」属性页精简移植，v2.10.0 新增）
-- ----------------------------------------------------------------------------
-- 独立页签「玩家属性」：只读玩家身上 10 项数值并实时显示（随装备变化）。
-- 设计要点：
--   * 零钩子、零写入 —— 只在画页面那一刻读字段，不改游戏任何状态，对闪退零风险；
--     全程不碰 Vector2（遵守「死亡回溯 0x10」那条历史雷区的规避原则）。
--   * 只用老版 GUI 接口（text / same_line），不依赖 LuaLoader 2.0 的任何新 API，
--     旧加载器上照常工作。
--   * 每项独立容错：只读【真字段】（属性名的句柄是错配的，读它会崩，v2.10.1 已剔除）；
--     首选类型读不出再换类型；最后过一道取值范围，读到离谱的脏数据一律显示 "-"，绝不抛错。
-- ============================================================================
at_setup, at_cleanup, at_gui = (function()
    -- v2.10.12 正式化：分步诊断脚手架全部移除（黑匣子使命完成，根因链见 v2.10.9~v2.10.11 注释与记忆）。
    -- 保留三道实测有效的防线：
    --   1) 主菜单判定走 get_gameMenu 方法 invoke（get_field 字段路线在手机版失效）
    --   2) 实例双保险：动作优化钩子缓存 attr_cache_inst 优先，local_player_get 数组获取兜底
    --   3) 拿不到真实 userdata 实例绝不读字段（空实例读实例字段 = NULL+0x10 必崩，pcall 挡不住）
    -- v2.10.20：按用户要求删「防御」「魔力再生」两项，末行改「减伤/生命再生」，共 14 项 7 行；
    --   耀斑 20% 减伤逻辑保留；潜在速率分支及其句柄已删（无引用）
    -- v2.10.19：①「伤害减免」+耀斑套 20%：solarShields>0 时 ×0.8（Hurt 38589 乘算、不进
    --     endurance，故 v2.10.18 漏显）；挨打掉充能时 20% 暂消、3秒/层回复，数字随之波动属正常
    --   ②「魔力再生」改稳定潜在速率 = statManaMax2/3 + manaRegenBonus + 1（=站立满魔时实际值，
    --     不受施法延迟归零/移动减半干扰），星星瓶(buff158 → manaRegenBonus+10)等加成稳定可见
    -- v2.10.18：①防闪退降频：共享扫描器每帧→每15帧、属性页读值每帧→每6帧（JNI密度大降）
    --   ②「伤害减免」合并盔甲套装奖励：甲虫套 beetleDefense+beetleOrbs 层伤
    --     （甲虫减伤在 Player.Hurt 内乘算、不进 endurance 字段，故 v2.10.17 漏显）
    --     公式 1-(1-endurance)*(1-0.15*层数)；日耀套(+12%)与饰品/药水同走 endurance 已含
    --   ③生命/魔力再生去掉单位只留数值；魔力再生=manaRegen/2（原版瞬时值，受施法延迟/魔量/站桩影响会波动，非bug）
    -- v2.10.17：①「生命回复」更名「生命再生」②+魔力再生（manaRegen，同 120 tick 攒 1 点 → 魔力/秒=值÷2）
    --   ③防御改回整数直显；另设「伤害减免」= Player.endurance 百分比（加性加成、防御后生效，
    --     源码 Player.Hurt (1-endurance)×伤害；wiki 伤害减免页：蠕虫围巾17%/耐力药水10%/日耀12%/龟15%/冰屏障25%）
    --   ④重排 16 项 8 行（…生命再生/魔力再生、防御/伤害减免）；v2.10.16 的难度系数助手已删（不再需要）。
    -- v2.10.16：①攻速改倍率显示（1/ meleeSpeed，同移速风格 1.12）②防御改「减伤/击」
    --   （1.4.5 防御为每击固定减免：普通 防御x0.5 / 专家 x0.75 / 大师 x1.0，见 Main.CalculateDamagePlayersTake）
    --   ③+生命回复（lifeRegen/2 = HP/秒，120 lifeRegenCount=1HP）④按用户指定重排 14 项 7 行。
    -- v2.10.15：+召唤物上限(maxMinions)/哨兵上限(maxTurrets)——源码确认 1.4 沿用旧名 maxTurrets
    --   当哨兵上限（Player.cs:2831 public int maxTurrets = 1），int32 整数直显；13 项 = 7 行，攻速加成末行单项。
    -- v2.10.14：攻速公式修正——meleeSpeed 是【挥舞时长倍率】（越小越快；官方 Projectile.cs
    --   就是拿 1f/meleeSpeed 换算真实攻速），攻速加成改用 inv 格式 (1/值-1)*100：
    --   +12% 攻速饰品会使 meleeSpeed≈0.893，旧 bonus 公式显示 -11%（用户实测），新公式显示 +12%。
    -- v2.10.13：+5 项（近战/远程/魔法/召唤加成、攻速加成，源码确认 minionDamage/meleeSpeed，倍率默认 1f）
    --   bonus 格式 %+d%%（(值-1)*100），布局改通用奇数行循环。
    -- 字段句柄首次显示时缓存（父类链回退），数值每帧实时读取，换装备立即刷新。
    local P = mod.patch
    local gm_cached = nil
    local function gm_state()
        if gm_cached == false then return nil end
        if not gm_cached then
            local T = P.get_type("Terraria", "Main")
            local m = T and P.get_method(T, "get_gameMenu", 0)
            if not m then gm_cached = false; return nil end
            gm_cached = m
        end
        local ok, v = pcall(P.invoke, gm_cached)
        if ok then return v == true end
        return nil
    end
    local FIELDS = {
        { "近战伤害", "meleeDamage", "float", "bonus" },
        { "近战暴击", "meleeCrit", "int32", "pct" },
        { "远程伤害", "rangedDamage", "float", "bonus" },
        { "远程暴击", "rangedCrit", "int32", "pct" },
        { "魔法伤害", "magicDamage", "float", "bonus" },
        { "魔法暴击", "magicCrit", "int32", "pct" },
        { "召唤伤害", "minionDamage", "float", "bonus" },
        { "幸运",     "luck", "float", "f2" },
        { "召唤物上限", "maxMinions", "int32", "int" },
        { "哨兵上限", "maxTurrets", "int32", "int" },
        { "攻速",     "meleeSpeed", "float", "mulinv" },
        { "移速",     "moveSpeed", "float", "mul" },
        { "伤害减免", "endurance", "float", "drpct" },
        { "生命再生", "lifeRegen", "int32", "regen" },
    }

    local handles = nil
    local F_bd, F_bo = nil, nil   -- v2.10.18：甲虫套减伤字段 beetleDefense/beetleOrbs
    local F_ssh = nil   -- v2.10.19：耀斑充能 solarShields
    local function ensure_handles()
        if handles then return end
        local T = P.get_type("Terraria", "Player")
        if not T then return end
        local h = {}
        for i = 1, #FIELDS do
            local cur, guard, f = T, 0, nil
            while cur and guard < 16 do
                local ok, ff = pcall(P.get_field, cur, FIELDS[i][2])
                if ok and ff then f = ff; break end
                local ok2, par = pcall(P.get_parent, cur)
                if not ok2 then break end
                cur = par
                guard = guard + 1
            end
            h[i] = f
        end
        handles = h
        -- v2.10.18：额外取甲虫套防御套装句柄（合并到「伤害减免」显示）
        F_bd = P.get_field(T, "beetleDefense")
        F_bo = P.get_field(T, "beetleOrbs")
        F_ssh = P.get_field(T, "solarShields")          -- v2.10.19 耀斑套充能
    end
    -- v2.10.18：伤害减免 = 1-(1-endo)*(1-0.15*甲虫层数)，含盔甲套装奖励（甲虫套在 Hurt 内乘算，不进 endurance）
    local function read_dr(inst, i)
        local v = nil
        local f = handles[i]
        if f then
            local ok, val = pcall(P.get_field_value, f, inst, FIELDS[i][3])
            if ok then v = val end
        end
        if type(v) ~= "number" then return v end
        if F_ssh then
            local oks, sv = pcall(P.get_field_value, F_ssh, inst, "int32")
            if oks and type(sv) == "number" and sv > 0 then
                v = 1 - (1 - v) * 0.8
            end
        end
        if F_bd and F_bo then
            local okb, bv = pcall(P.get_field_value, F_bd, inst, "bool")
            if okb and bv == true then
                local oko, o = pcall(P.get_field_value, F_bo, inst, "int32")
                if oko and type(o) == "number" and o > 0 then
                    if o > 3 then o = 3 end
                    v = 1 - (1 - v) * (1 - 0.15 * o)
                end
            end
        end
        return v
    end
    local function fmt(v, kind)
        if type(v) ~= "number" then return "-" end
        if kind == "pct" then return string.format("%d%%", math.floor(v + 0.5)) end
        if kind == "bonus" then return string.format("%+d%%", math.floor((v - 1) * 100 + 0.5)) end
        if kind == "mulinv" then
            if v == 0 then return "-" end
            return string.format("%.2f", 1 / v)
        end
        if kind == "drpct" then
            return string.format("%.1f%%", v * 100)
        end
        if kind == "regen" then
            return string.format("%.1f", v / 2)
        end
        if kind == "f2" or kind == "mul" then return string.format("%.2f", v) end
        return string.format("%d", v)
    end
    local function readv(inst, i)
        if FIELDS[i][4] == "drpct" then return read_dr(inst, i) end
        local f = handles[i]
        if not f then return nil end
        local ok, v = pcall(P.get_field_value, f, inst, FIELDS[i][3])
        if ok then return v end
        return nil
    end
    local av_cache, av_tick = {}, 0
    local function at_setup() end
    local function at_cleanup() end
    local function at_gui(g)
        if gm_state() == true then
            g.text("请先进入世界,再查看玩家属性")
            return
        end
        local inst = (type(attr_cache_inst) == "userdata") and attr_cache_inst or nil
        if not inst then
            local ok, pl = pcall(local_player_get)
            if ok and type(pl) == "userdata" then inst = pl end
        end
        if not inst then
            g.text("未取到玩家实例(世界加载中?)")
            return
        end
        ensure_handles()
        if not handles then
            g.text("字段句柄初始化失败")
            return
        end
        -- v2.10.18：读值缓存——每 6 帧(0.1秒)刷新一轮，其余帧用缓存，JNI 读密度降 6 倍
        av_tick = av_tick + 1
        if av_tick % 6 == 1 then
            for i = 1, #FIELDS do av_cache[i] = readv(inst, i) end
        end
        for i = 1, #FIELDS, 2 do
            local a, b = i, i + 1
            if b <= #FIELDS then
                g.text(fit_label(FIELDS[a][1], 10) .. fit_label(fmt(av_cache[a], FIELDS[a][4]), 6)
                    .. fit_label(FIELDS[b][1], 10) .. fmt(av_cache[b], FIELDS[b][4]))
            else
                g.text(fit_label(FIELDS[a][1], 10) .. fmt(av_cache[a], FIELDS[a][4]))
            end
        end
    end
    return at_setup, at_cleanup, at_gui
end)()


-- ===== 第三十五部分：原版配方清理（v6.3.1）=====
-- 用户要求：第三十三部分里那批自定义配方，「去掉原来的，只保留我发给你的」。
--
-- 原版结构（PC 1.4.5.8 核实）：
--   Main.recipe = new Recipe[Recipe.maxRecipes]      Main.cs:1799
--   Recipe.numRecipes                                 Recipe.cs:60（已用条数）
--   Recipe.createItem（Item）                         Recipe.cs:66
--   Recipe.requiredItem（Item[maxRequirements]）      Recipe.cs:68
--   Recipe.SetupRecipes() 里一条条 AddRecipe()        Recipe.cs:604
--   Recipe.FindRecipes() 只把「环境满足 + 材料够」的配方收进制作列表（Recipe.cs:252）
--
-- 做法：不删数组元素（写对象数组风险大），而是把多余配方的第一个材料改成
--   一个不存在的物品 ID（9999）—— 材料永远凑不齐，这条配方就再也不会
--   出现在制作列表里，效果等同删除，且不碰任何数组结构。
--
-- 判定「哪条是我们的」：按 result + 材料 ID 集合（排序后拼接）匹配白名单。
--   哪怕游戏的配方顺序变了、或者我们自己的配方还没加入（此时白名单全部不命中，
--   原版全被废掉，随后我们的再加上），结果都只有一条。
-- 门控：跟着「原版配方扩展」开关（rcp）走，关掉就完全不介入。
-- 注：主 chunk 的 local 已到 200 上限，整段包成 IIFE 只挂 _G.ms_rcp_clean。
_G.ms_rcp_clean = (function()
    local P = patch
    local H = {}
    local hook = nil
    local ready = false
    local killed_total = 0

    -- 允许保留的配方指纹：result -> 材料 ID 排序拼接 -> true
    local KEEP = {
        ["4144"] = { ["989,4479"] = true },                        -- 泰拉魔刃（Terragrim）
        ["3368"] = { ["1225,4144"] = true },                       -- Arkhalis
        ["487"]  = { ["75,170,4930"] = true },                     -- 水晶球
        ["2177"] = { ["22,97,4930"] = true,                        -- 弹药箱（铁）
                     ["97,704,4930"] = true },                     -- 弹药箱（铅）
        ["1293"] = { ["75,170,391"] = true },                      -- 丛林蜥蜴电池
        ["1253"] = { ["664,1328,2161"] = true },                   -- 冰冻海龟壳
        ["5065"] = { ["743,3111,4934,6152"] = true },              -- 共鸣法杖
        ["6173"] = { ["530,3992,4939"] = true },                   -- 电弧涌动
    }

    local function rd(f, o, ty)
        if not f then return nil end
        local ok, v = pcall(P.get_field_value, f, o, ty)
        if ok then return v end
        return nil
    end
    local function arr_at(a, i, ty)
        local ok, v = pcall(P.array_at, a, i, ty)
        if ok then return v end
        return nil
    end
    local function arr_len(a)
        local ok, n = pcall(P.array_length, a)
        if ok and type(n) == "number" then return n end
        return 0
    end

    local function key_of(ids)
        table.sort(ids)
        return table.concat(ids, ",")
    end

    local function sweep()
        if _G.GENW then return end       -- v8.9.12：世界生成中不动配方表
        if not ready then return end
        if not (_G.ms_gates and _G.ms_gates.is("rcp")) then return end
        local arr = rd(H.f_main_recipe, nil, "object")
        if not arr then return end
        local n = rd(H.f_num_recipes, nil, "int32")
        if type(n) ~= "number" or n <= 0 then return end
        -- v8.9.11：数组实际长度可能对不上 numRecipes（世界切换时配方表正在重建），
        --   越界读取会直接 SIGSEGV，这里取较小值兜底
        local alen = arr_len(arr)
        if alen > 0 and n > alen then n = alen end
        local killed = 0
        for i = 0, n - 1 do
            local r = arr_at(arr, i)
            if r then
                local it = rd(H.f_create_item, r, "object")
                local t = it and rd(H.f_item_type, it, "int32")
                local keep = t and KEEP[tostring(t)]
                if keep then
                    local req = rd(H.f_required_item, r, "object")
                    if req then
                        local ids, cnt = {}, 0
                        local rn = arr_len(req)
                        for j = 0, rn - 1 do
                            local ri = arr_at(req, j)
                            if ri then
                                local rt = rd(H.f_item_type, ri, "int32")
                                if rt and rt > 0 then cnt = cnt + 1; ids[cnt] = rt end
                            end
                        end
                        if not keep[key_of(ids)] then
                            local ri0 = arr_at(req, 0)
                            if ri0 then
                                pcall(P.set_field_value, H.f_item_type, ri0, 9999, "int32")
                                killed = killed + 1
                            end
                        end
                    end
                end
            end
        end
        if killed > 0 then
            killed_total = killed_total + killed
            mod.info("[配方清理] 本次废掉 " .. killed .. " 条原版配方（累计 " .. killed_total .. "）")
        end
    end

    local function setup()
        if ready then return true end
        local okm, T_main = pcall(P.get_type, "Terraria", "Main")
        local okr, T_recipe = pcall(P.get_type, "Terraria", "Recipe")
        local oki, T_item = pcall(P.get_type, "Terraria", "Item")
        if not (okm and T_main and okr and T_recipe and oki and T_item) then
            mod.warn("[配方清理] 类型缺失，跳过")
            return false
        end
        H.f_main_recipe   = P.get_field(T_main, "recipe")
        H.f_create_item   = P.get_field(T_recipe, "createItem")
        H.f_required_item = P.get_field(T_recipe, "requiredItem")
        H.f_num_recipes   = P.get_field(T_recipe, "numRecipes")
        H.f_item_type     = P.get_field(T_item, "type")
        if not (H.f_main_recipe and H.f_create_item and H.f_required_item and H.f_num_recipes and H.f_item_type) then
            mod.warn("[配方清理] 关键成员缺失，跳过")
            return false
        end
        ready = true
        local m = P.get_method(T_recipe, "SetupRecipes", 0)
        if not m then
            mod.warn("[配方清理] 找不到 Recipe.SetupRecipes，跳过")
            ready = false
            return false
        end
        local okh, h = pcall(P.install_hook, m, {
            postfix = function() pcall(sweep) end,
        })
        if okh and h then
            hook = h
            mod.info("[配方清理] 已挂 Recipe.SetupRecipes")
        else
            mod.warn("[配方清理] 挂钩失败")
            ready = false
            return false
        end
        return true
    end

    local function cleanup()
        if hook and hook.remove then pcall(function() hook:remove() end) end
        hook = nil
        ready = false
    end

    return { setup = setup, cleanup = cleanup, sweep = sweep }
end)()

-- ===== 第三十三部分：原版物品配方扩展（v5.9.0 由「原版物品配方拓展 V1.1」并入）=====
-- v6.3.0：按用户要求改/加了一批配方，全部改为「徒手」（station = -1）：
--   冰冻海龟壳   海龟壳1 + 寒霜核1 + 冰雪块50
--   共鸣法杖     太阳花法杖1 + 红玉法杖1 + 粉凝胶25 + 世纪之花圣物1   (5065 / PrincessWeapon)
--   电弧涌动     狂战士手套1 + 电线999 + 火星飞碟圣物1               (6173 / ArcSurge)
--   泰拉魔刃     附魔剑1 + 强效幸运药水1                            (4144 Terragrim)
--   Arkhalis剑   泰拉魔刃1 + 神圣锭10                              (3368 Arkhalis)
--   水晶球       玻璃15 + 坠落之星8 + 血肉墙圣物1
--   弹药箱(铁)   铁锭12 + 火枪子弹100 + 血肉墙圣物1
--   弹药箱(铅)   铅锭12 + 火枪子弹100 + 血肉墙圣物1                 (2177，新增第二条)
--   丛林蜥蜴电池 玻璃10 + 坠落之星10 + 精金锭10
--   魔力水晶     生命水晶1                                        (109，新增)
-- v6.3.3 新增（工作台 18）：
--   阴森木 x50 <- 阴森钩 1829 x1
--   阴森木 x50 <- 阴森嫩枝 1831 x1
--   阴森木 x50 <- 诅咒树苗 1837 x1
-- v6.3.4 新增 19 条（铁砧16 / 秘银砧134 / 远古操纵机412）：
--   养蜂人1123 <- 金阔剑3520 或 铂金宽剑3484 + 蜂王圣物4928
--   种子弯刀3018 <- 草剑190 + 神圣锭1225x10 + 世纪之花圣物4934
--   无头骑士剑1826 <- 钛金剑1199 或 精金剑482 + 南瓜1725x10 + 南瓜王圣物4942
--   波涌之刃2880 <- 钛金剑1199 或 精金剑482 + 瓶装水126x10 + 火星飞碟圣物4939
--   狂星之怒3065 <- 彩虹猫之刃3063；彩虹猫之刃3063 <- 狂星之怒3065
--   断裂英雄剑1570 <- 蛾怪之翼2770 + 日耀碑牌碎片2766x8（或 日耀碑牌2767x1）
--   终极棱镜3541 <- 月曜3570；月曜3570 <- 终极棱镜3541
--   太空海豚机枪1553 <- 喜庆弹射器Mk2 3930；反向同理
--   七彩水晶法杖3571 <- 月亮传送门法杖3569；反向同理
--   支配之鞭5480 <- 泰拉悠悠球3389；反向同理
-- v6.3.5：星怒 65 新增「金阔剑3520 + 坠落之星75x15」（铁砧16）
-- v6.3.6：调整制作站 —— 冰冻海龟壳1253 / 共鸣法杖5065 / 电弧涌动6173 / Arkhalis3368
--   改为秘银砧/山铜砧（134）；泰拉魔刃4144 / 水晶球487 / 弹药箱2177(铁+铅)
--   改为铁砧/铅砧（16）；丛林蜥蜴电池1293 改为丛林蜥蜴熔炉（303）。魔力水晶109 仍徒手。
--   注：铁砧16 = Iron Anvil 与 Lead Anvil 共用的 tile；秘银砧134 = Mythril 与 Orichalcum 共用，
--   所以「铁砧/铅砧」「秘银砧/山铜砧」在 tile 层面本来就是同一个，配方天然通用。
--   物品 ID：圣物用 Master 圣物 WallofFleshMasterTrophy 4930 / PlanteraMasterTrophy 4934 /
--   UFOMasterTrophy 4939（火星飞碟 = UFO）。
-- 纯数据、零钩子：全部使用原版物品 ID，mod.recipe.add 登记后由内核在下一次
--   Recipe.SetupRecipes（进世界 / 加入服务器 / 换语言）时挂进配方表。
-- 数据来源：《原版配方表 1.1》（作者 竹溪寒，冥），共 114 条。
--   station 为 Tile ID，-1 = 无需合成站；常见站：16 铁砧 / 134 秘银砧 / 18 工作台。
--   特例：215 篝火（土块→沙块）、237 丛林蜥蜴祭坛（地牢钥匙→对应武器）为原表设计。
-- 全部数字 ID ==> 无待解析项，注册完不装任何钩子，运行时零开销。
-- 注：主 chunk 的 local 已到 200 上限，故整段包成 IIFE 只挂 _G.ms_rcp_setup。
_G.ms_rcp_setup = (function()
    local RCP = {
        { result = 158, count = 1, station = 114, materials = { { id = 706, count = 5 }, { id = 751, count = 10 }, { id = 75, count = 10 } } },
        { result = 158, count = 1, station = 114, materials = { { id = 19, count = 5 }, { id = 751, count = 10 }, { id = 75, count = 10 } } },
        { result = 53, count = 1, station = 114, materials = { { id = 320, count = 2 }, { id = 31, count = 1 }, { id = 751, count = 25 } } },
        { result = 987, count = 1, station = 114, materials = { { id = 320, count = 4 }, { id = 31, count = 1 }, { id = 593, count = 50 } } },
        { result = 857, count = 1, station = 114, materials = { { id = 320, count = 6 }, { id = 31, count = 1 }, { id = 169, count = 70 } } },
        { result = 211, count = 1, station = 114, materials = { { id = 225, count = 10 }, { id = 331, count = 10 } } },
        { result = 906, count = 1, station = 26, materials = { { id = 173, count = 15 }, { id = 175, count = 5 } } },
        { result = 2423, count = 1, station = 16, materials = { { id = 2121, count = 2 }, { id = 320, count = 2 } } },
        { result = 212, count = 1, station = 16, materials = { { id = 331, count = 5 }, { id = 751, count = 15 }, { id = 23, count = 20 } } },
        { result = 887, count = 1, station = 114, materials = { { id = 209, count = 15 } } },
        { result = 1323, count = 1, station = 114, materials = { { id = 208, count = 1 }, { id = 173, count = 5 }, { id = 175, count = 5 } } },
        { result = 3084, count = 1, station = 114, materials = { { id = 22, count = 5 }, { id = 530, count = 10 } } },
        { result = 3084, count = 1, station = 114, materials = { { id = 704, count = 5 }, { id = 530, count = 10 } } },
        { result = 285, count = 1, station = 16, materials = { { id = 22, count = 5 } } },
        { result = 285, count = 1, station = 16, materials = { { id = 704, count = 5 } } },
        { result = 159, count = 1, station = 220, materials = { { id = 3306, count = 1 }, { id = 23, count = 45 }, { id = 751, count = 10 }, { id = 75, count = 5 } } },
        { result = 54, count = 1, station = 86, materials = { { id = 225, count = 10 }, { id = 22, count = 5 }, { id = 290, count = 1 } } },
        { result = 54, count = 1, station = 86, materials = { { id = 225, count = 10 }, { id = 704, count = 5 }, { id = 290, count = 1 } } },
        { result = 1921, count = 1, station = 86, materials = { { id = 225, count = 8 }, { id = 2359, count = 2 } } },
        { result = 3017, count = 1, station = 86, materials = { { id = 225, count = 10 }, { id = 208, count = 1 }, { id = 195, count = 5 } } },
        { result = 863, count = 1, station = 114, materials = { { id = 225, count = 10 }, { id = 22, count = 5 }, { id = 302, count = 2 } } },
        { result = 863, count = 1, station = 114, materials = { { id = 225, count = 10 }, { id = 704, count = 5 }, { id = 302, count = 2 } } },
        { result = 950, count = 1, station = 306, materials = { { id = 664, count = 20 }, { id = 225, count = 10 }, { id = 22, count = 5 } } },
        { result = 950, count = 1, station = 306, materials = { { id = 664, count = 20 }, { id = 225, count = 10 }, { id = 704, count = 5 } } },
        { result = 2219, count = 1, station = 114, materials = { { id = 75, count = 8 }, { id = 22, count = 10 }, { id = 216, count = 1 } } },
        { result = 2219, count = 1, station = 114, materials = { { id = 75, count = 8 }, { id = 704, count = 10 }, { id = 216, count = 1 } } },
        { result = 156, count = 1, station = 114, materials = { { id = 19, count = 10 }, { id = 154, count = 20 } } },
        { result = 156, count = 1, station = 114, materials = { { id = 706, count = 10 }, { id = 154, count = 20 } } },
        { result = 885, count = 1, station = 114, materials = { { id = 225, count = 10 }, { id = 23, count = 20 }, { id = 499, count = 2 } } },
        { result = 886, count = 1, station = 114, materials = { { id = 154, count = 50 }, { id = 381, count = 6 }, { id = 2607, count = 3 } } },
        { result = 886, count = 1, station = 114, materials = { { id = 154, count = 50 }, { id = 1184, count = 6 }, { id = 2607, count = 3 } } },
        { result = 888, count = 1, station = 114, materials = { { id = 225, count = 20 }, { id = 521, count = 5 } } },
        { result = 889, count = 1, station = 114, materials = { { id = 501, count = 5 }, { id = 583, count = 1 }, { id = 381, count = 5 } } },
        { result = 934, count = 1, station = 26, materials = { { id = 225, count = 15 }, { id = 295, count = 1 } } },
        { result = 890, count = 1, station = 114, materials = { { id = 530, count = 10 }, { id = 381, count = 5 }, { id = 178, count = 3 } } },
        { result = 890, count = 1, station = 114, materials = { { id = 530, count = 10 }, { id = 1184, count = 5 }, { id = 178, count = 3 } } },
        { result = 3102, count = 1, station = 114, materials = { { id = 530, count = 10 }, { id = 296, count = 2 }, { id = 19, count = 10 } } },
        { result = 3102, count = 1, station = 114, materials = { { id = 530, count = 10 }, { id = 296, count = 2 }, { id = 706, count = 10 } } },
        { result = 891, count = 1, station = 114, materials = { { id = 38, count = 6 }, { id = 236, count = 1 } } },
        { result = 893, count = 1, station = 16, materials = { { id = 225, count = 6 }, { id = 1109, count = 1 } } },
        { result = 892, count = 1, station = 114, materials = { { id = 126, count = 1 }, { id = 313, count = 5 }, { id = 315, count = 5 }, { id = 520, count = 5 } } },
        { result = 1321, count = 1, station = 125, materials = { { id = 3103, count = 1 }, { id = 501, count = 10 }, { id = 38, count = 5 }, { id = 520, count = 5 } } },
        { result = 165, count = 1, station = 101, materials = { { id = 149, count = 1 }, { id = 148, count = 1 }, { id = 126, count = 10 } } },
        { result = 670, count = 1, station = 306, materials = { { id = 593, count = 18 }, { id = 664, count = 18 }, { id = 22, count = 5 } } },
        { result = 670, count = 1, station = 306, materials = { { id = 593, count = 18 }, { id = 664, count = 18 }, { id = 704, count = 5 } } },
        { result = 1309, count = 1, station = 26, materials = { { id = 9, count = 6 }, { id = 23, count = 40 }, { id = 3090, count = 1 } } },
        { result = 65, count = 1, station = 16, materials = { { id = 3484, count = 1 }, { id = 75, count = 10 } } },
        { result = 3069, count = 1, station = 16, materials = { { id = 9, count = 5 }, { id = 8, count = 3 }, { id = 75, count = 1 } } },
        { result = 155, count = 1, station = 16, materials = { { id = 19, count = 10 }, { id = 154, count = 20 } } },
        { result = 155, count = 1, station = 16, materials = { { id = 706, count = 10 }, { id = 154, count = 20 } } },
        { result = 989, count = 1, station = 16, materials = { { id = 3484, count = 1 }, { id = 182, count = 1 }, { id = 178, count = 1 } } },
        { result = 989, count = 1, station = 16, materials = { { id = 3520, count = 1 }, { id = 182, count = 1 }, { id = 178, count = 1 } } },
        { result = 2223, count = 1, station = 134, materials = { { id = 1006, count = 8 }, { id = 1015, count = 1 } } },
        { result = 4764, count = 1, station = 16, materials = { { id = 183, count = 25 }, { id = 22, count = 10 } } },
        { result = 4764, count = 1, station = 16, materials = { { id = 183, count = 25 }, { id = 704, count = 10 } } },
        { result = 3199, count = 1, station = 16, materials = { { id = 664, count = 50 }, { id = 170, count = 10 }, { id = 182, count = 3 } } },
        { result = 329, count = 1, station = 16, materials = { { id = 327, count = 1 }, { id = 173, count = 20 }, { id = 154, count = 10 } } },
        { result = 3213, count = 1, station = 16, materials = { { id = 87, count = 1 }, { id = 320, count = 2 } } },
        { result = 29, count = 1, station = 16, materials = { { id = 3, count = 5 }, { id = 178, count = 2 }, { id = 188, count = 2 } } },
        { result = 1291, count = 1, station = 134, materials = { { id = 331, count = 8 }, { id = 29, count = 1 }, { id = 947, count = 5 } } },
        { result = 1293, count = 1, station = 303, materials = { { id = 1006, count = 5 }, { id = 1101, count = 10 } } },
        { result = 2673, count = 1, station = 26, materials = { { id = 183, count = 15 }, { id = 2002, count = 1 }, { id = 194, count = 5 } } },
        { result = 267, count = 1, station = 77, materials = { { id = 225, count = 2 }, { id = 68, count = 10 } } },
        { result = 267, count = 1, station = 77, materials = { { id = 225, count = 2 }, { id = 1330, count = 10 } } },
        { result = 997, count = 1, station = 16, materials = { { id = 22, count = 12 }, { id = 170, count = 8 }, { id = 530, count = 6 } } },
        { result = 997, count = 1, station = 16, materials = { { id = 704, count = 12 }, { id = 170, count = 8 }, { id = 530, count = 6 } } },
        { result = 4276, count = 1, station = 16, materials = { { id = 3347, count = 25 }, { id = 154, count = 8 }, { id = 3380, count = 2 } } },
        { result = 3198, count = 1, station = 16, materials = { { id = 331, count = 10 }, { id = 22, count = 6 }, { id = 620, count = 20 } } },
        { result = 3198, count = 1, station = 16, materials = { { id = 331, count = 10 }, { id = 704, count = 6 }, { id = 620, count = 20 } } },
        { result = 2999, count = 1, station = 16, materials = { { id = 154, count = 12 }, { id = 225, count = 6 }, { id = 619, count = 15 } } },
        { result = 3750, count = 1, station = 96, materials = { { id = 4326, count = 1 }, { id = 1125, count = 1 } } },
        { result = 5532, count = 1, station = 26, materials = { { id = 61, count = 30 }, { id = 86, count = 15 } } },
        { result = 5533, count = 1, station = 26, materials = { { id = 836, count = 30 }, { id = 1329, count = 15 } } },
        { result = 4961, count = 1, station = 26, materials = { { id = 5350, count = 1 }, { id = 520, count = 5 }, { id = 501, count = 15 }, { id = 1508, count = 5 } } },
        { result = 3031, count = 1, station = 125, materials = { { id = 206, count = 49 } } },
        { result = 4820, count = 1, station = 125, materials = { { id = 207, count = 49 } } },
        { result = 5302, count = 1, station = 125, materials = { { id = 1128, count = 49 } } },
        { result = 4144, count = 1, station = 16, materials = { { id = 989, count = 1 } } },
        { result = 6173, count = 1, station = 134, materials = { { id = 3992, count = 1 }, { id = 530, count = 999 }, { id = 4939, count = 1 } } },
        { result = 5065, count = 1, station = 134, materials = { { id = 6152, count = 1 }, { id = 743, count = 1 }, { id = 3111, count = 25 } } },
        { result = 5543, count = 1, station = 114, materials = { { id = 178, count = 15 }, { id = 3989, count = 1 } } },
        { result = 2373, count = 1, station = -1, materials = { { id = 2374, count = 1 } } },
        { result = 2373, count = 1, station = -1, materials = { { id = 2375, count = 1 } } },
        { result = 2374, count = 1, station = -1, materials = { { id = 2373, count = 1 } } },
        { result = 2374, count = 1, station = -1, materials = { { id = 2375, count = 1 } } },
        { result = 2375, count = 1, station = -1, materials = { { id = 2374, count = 1 } } },
        { result = 2375, count = 1, station = -1, materials = { { id = 2373, count = 1 } } },
        { result = 3103, count = 1, station = -1, materials = { { id = 3104, count = 1 } } },
        { result = 3104, count = 1, station = -1, materials = { { id = 3103, count = 1 } } },
        -- ===== v7.0.3：祭坛系列（tile 26 = 恶魔祭坛；猩红祭坛在原版同 ID，按世界类型显示名称）=====
        { result = 3223, count = 1, station = 26, materials = { { id = 3224, count = 1 } } },                        -- 混乱之脑   <- 蠕虫围巾
        { result = 3224, count = 1, station = 26, materials = { { id = 3223, count = 1 } } },                        -- 蠕虫围巾   <- 混乱之脑
        { result = 60,   count = 5, station = 26, materials = { { id = 5, count = 1 }, { id = 59, count = 1 } } },    -- 魔菇       <- 蘑菇 + 腐化种子
        { result = 2887, count = 5, station = 26, materials = { { id = 5, count = 1 }, { id = 2171, count = 1 } } },  -- 毒蘑菇     <- 蘑菇 + 猩红种子
        { result = 59,   count = 1, station = 26, materials = { { id = 2171, count = 1 } } },                        -- 腐化种子   <- 猩红种子
        { result = 2171, count = 1, station = 26, materials = { { id = 59, count = 1 } } },                          -- 猩红种子   <- 腐化种子
        { result = 169, count = 2, station = 283, materials = { { id = 170, count = 1 } } },
        { result = 1156, count = 1, station = 303, materials = { { id = 1533, count = 1 } } },
        { result = 1571, count = 1, station = 303, materials = { { id = 1534, count = 1 } } },
        { result = 1569, count = 1, station = 303, materials = { { id = 1535, count = 1 } } },
        { result = 1260, count = 1, station = 303, materials = { { id = 1536, count = 1 } } },
        { result = 1572, count = 1, station = 303, materials = { { id = 1537, count = 1 } } },
        { result = 4607, count = 1, station = 303, materials = { { id = 4714, count = 1 } } },
        { result = 554, count = 1, station = 114, materials = { { id = 520, count = 3 }, { id = 85, count = 15 }, { id = 391, count = 5 } } },
        { result = 554, count = 1, station = 114, materials = { { id = 520, count = 3 }, { id = 85, count = 15 }, { id = 1198, count = 5 } } },
        { result = 2334, count = 1, station = 26, materials = { { id = 9, count = 20 } } },
        { result = 2335, count = 1, station = 26, materials = { { id = 2334, count = 1 }, { id = 22, count = 5 } } },
        { result = 2335, count = 1, station = 26, materials = { { id = 2334, count = 1 }, { id = 704, count = 5 } } },
        { result = 2336, count = 1, station = 26, materials = { { id = 2335, count = 1 }, { id = 19, count = 5 } } },
        { result = 2336, count = 1, station = 26, materials = { { id = 2335, count = 1 }, { id = 706, count = 5 } } },
        { result = 3979, count = 1, station = 134, materials = { { id = 2334, count = 1 }, { id = 381, count = 5 } } },
        { result = 3979, count = 1, station = 134, materials = { { id = 2334, count = 1 }, { id = 1184, count = 5 } } },
        { result = 3980, count = 1, station = 134, materials = { { id = 3979, count = 1 }, { id = 382, count = 5 } } },
        { result = 3980, count = 1, station = 134, materials = { { id = 3979, count = 1 }, { id = 1191, count = 5 } } },
        { result = 3981, count = 1, station = 134, materials = { { id = 3980, count = 1 }, { id = 391, count = 5 } } },
        { result = 3981, count = 1, station = 134, materials = { { id = 3980, count = 1 }, { id = 1198, count = 5 } } },
        { result = 1253, count = 1, station = 114, materials = { { id = 1328, count = 1 }, { id = 2161, count = 1 } } },
        { result = 195, count = 1, station = 18, materials = { { id = 194, count = 1 } } },
        { result = 194, count = 1, station = 18, materials = { { id = 195, count = 1 } } },
        { result = 195, count = 1, station = 18, materials = { { id = 62, count = 5 } } },
        { result = 194, count = 1, station = 18, materials = { { id = 62, count = 5 } } },
        { result = 62, count = 5, station = 18, materials = { { id = 194, count = 1 } } },
        { result = 62, count = 5, station = 18, materials = { { id = 195, count = 1 } } },
        { result = 3368, count = 1, station = 134, materials = { { id = 4144, count = 1 }, { id = 1225, count = 5 } } },
        { result = 109, count = 3, station = -1, materials = { { id = 29, count = 1 } } },
        { result = 1729, count = 50, station = 134, materials = { { id = 1829, count = 1 } } },  -- v6.3.3 阴森木50 <- 阴森钩1
        { result = 1729, count = 50, station = 134, materials = { { id = 1831, count = 1 } } },  -- v6.3.3 阴森木50 <- 阴森嫩枝1
        { result = 1729, count = 50, station = 134, materials = { { id = 1837, count = 1 } } },  -- v6.3.3 阴森木50 <- 诅咒树苗1
        { result = 1123, count = 1, station = 16, materials = { { id = 3520, count = 1 }, { id = 4928, count = 1 } } },  -- 养蜂人 <- 金阔剑 + 蜂王圣物（铁砧）
        { result = 1123, count = 1, station = 16, materials = { { id = 3484, count = 1 }, { id = 4928, count = 1 } } },  -- 养蜂人 <- 铂金宽剑 + 蜂王圣物（铁砧）
        { result = 3018, count = 1, station = 134, materials = { { id = 190, count = 1 }, { id = 1225, count = 10 }, { id = 4934, count = 1 } } },  -- 种子弯刀 <- 草剑 + 神圣锭x10 + 世纪之花圣物
        { result = 1826, count = 1, station = 134, materials = { { id = 1199, count = 1 }, { id = 1725, count = 10 }, { id = 4942, count = 1 } } },  -- 无头骑士剑 <- 钛金剑 + 南瓜x10 + 南瓜王圣物
        { result = 1826, count = 1, station = 134, materials = { { id = 482, count = 1 }, { id = 1725, count = 10 }, { id = 4942, count = 1 } } },  -- 无头骑士剑 <- 精金剑 + 南瓜x10 + 南瓜王圣物
        { result = 2880, count = 1, station = 134, materials = { { id = 1199, count = 1 }, { id = 126, count = 10 }, { id = 4939, count = 1 } } },  -- 波涌之刃 <- 钛金剑 + 瓶装水x10 + 火星飞碟圣物
        { result = 2880, count = 1, station = 134, materials = { { id = 482, count = 1 }, { id = 126, count = 10 }, { id = 4939, count = 1 } } },  -- 波涌之刃 <- 精金剑 + 瓶装水x10 + 火星飞碟圣物
        { result = 3065, count = 1, station = 412, materials = { { id = 3063, count = 1 } } },  -- 狂星之怒 <- 彩虹猫之刃（远古操纵机）
        { result = 3063, count = 1, station = 412, materials = { { id = 3065, count = 1 } } },  -- 彩虹猫之刃 <- 狂星之怒（远古操纵机）
        { result = 1570, count = 1, station = 134, materials = { { id = 2770, count = 1 }, { id = 2766, count = 8 } } },  -- 断裂英雄剑 <- 蛾怪之翼 + 日耀碑牌碎片x8
        { result = 1570, count = 1, station = 134, materials = { { id = 2770, count = 1 }, { id = 2767, count = 1 } } },  -- 断裂英雄剑 <- 蛾怪之翼 + 日耀碑牌x1
        { result = 3541, count = 1, station = 412, materials = { { id = 3570, count = 1 } } },  -- 终极棱镜 <- 月曜（远古操纵机）
        { result = 3570, count = 1, station = 412, materials = { { id = 3541, count = 1 } } },  -- 月曜 <- 终极棱镜（远古操纵机）
        { result = 1553, count = 1, station = 412, materials = { { id = 3930, count = 1 } } },  -- 太空海豚机枪 <- 喜庆弹射器Mk2（远古操纵机）
        { result = 3930, count = 1, station = 412, materials = { { id = 1553, count = 1 } } },  -- 喜庆弹射器Mk2 <- 太空海豚机枪（远古操纵机）
        { result = 3571, count = 1, station = 412, materials = { { id = 3569, count = 1 } } },  -- 七彩水晶法杖 <- 月亮传送门法杖（远古操纵机）
        { result = 3569, count = 1, station = 412, materials = { { id = 3571, count = 1 } } },  -- 月亮传送门法杖 <- 七彩水晶法杖（远古操纵机）
        { result = 5480, count = 1, station = 412, materials = { { id = 3389, count = 1 } } },  -- 支配之鞭 <- 泰拉悠悠球（远古操纵机）
        { result = 3389, count = 1, station = 412, materials = { { id = 5480, count = 1 } } },  -- 泰拉悠悠球 <- 支配之鞭（远古操纵机）
        { result = 65, count = 1, station = 16, materials = { { id = 3520, count = 1 }, { id = 75, count = 10 } } },  -- 星怒 <- 金阔剑 + 坠落之星x10（铁砧/铅砧）
        { result = 170, count = 1, station = 17, materials = { { id = 351, count = 1 } } },  -- v6.3.7 玻璃 <- 玻璃杯x1（熔炉）
        { result = 593, count = 1, station = 306, materials = { { id = 126, count = 1 } } },  -- v6.3.7 雪块 <- 瓶装水x1（冰雪机）
        { result = 351, count = 1, station = -1, materials = { { id = 353, count = 1 } } },  -- 玻璃杯 <- 麦芽酒x1（徒手）
        { result = 327, count = 1, station = 16, materials = { { id = 19, count = 2 }, { id = 154, count = 25 } } },
        { result = 327, count = 1, station = 16, materials = { { id = 706, count = 2 }, { id = 154, count = 25 } } },
        { result = 4263, count = 1, station = 16, materials = { { id = 3380, count = 15 }, { id = 23, count = 20 }, { id = 2625, count = 1 } } },
        { result = 4263, count = 1, station = 16, materials = { { id = 3380, count = 15 }, { id = 23, count = 20 }, { id = 4073, count = 1 } } },
        { result = 4263, count = 1, station = 16, materials = { { id = 3380, count = 15 }, { id = 23, count = 20 }, { id = 4072, count = 1 } } },
        { result = 4263, count = 1, station = 16, materials = { { id = 3380, count = 15 }, { id = 23, count = 20 }, { id = 4071, count = 1 } } },
        { result = 4819, count = 1, station = 16, materials = { { id = 175, count = 10 }, { id = 23, count = 20 }, { id = 2625, count = 1 } } },
        { result = 4819, count = 1, station = 16, materials = { { id = 175, count = 10 }, { id = 23, count = 20 }, { id = 4073, count = 1 } } },
        { result = 4819, count = 1, station = 16, materials = { { id = 175, count = 10 }, { id = 23, count = 20 }, { id = 4072, count = 1 } } },
        { result = 4819, count = 1, station = 16, materials = { { id = 175, count = 10 }, { id = 23, count = 20 }, { id = 4071, count = 1 } } },
        { result = 3118, count = 1, station = 114, materials = { { id = 3084, count = 1 } } },
        { result = 3095, count = 1, station = 114, materials = { { id = 22, count = 10 }, { id = 154, count = 10 } } },
        { result = 3095, count = 1, station = 114, materials = { { id = 704, count = 10 }, { id = 154, count = 10 } } },
        { result = 3119, count = 1, station = 114, materials = { { id = 49, count = 1 }, { id = 3202, count = 1 } } },
        { result = 3119, count = 1, station = 114, materials = { { id = 111, count = 1 }, { id = 3202, count = 1 } } },
        { result = 3099, count = 1, station = 114, materials = { { id = 15, count = 1 }, { id = 583, count = 1 } } },
        { result = 3099, count = 1, station = 114, materials = { { id = 707, count = 1 }, { id = 583, count = 1 } } },
        { result = 49, count = 1, station = 26, materials = { { id = 111, count = 1 } } },
        { result = 111, count = 1, station = 26, materials = { { id = 49, count = 1 } } },
        { result = 3120, count = 1, station = 26, materials = { { id = 149, count = 1 }, { id = 22, count = 1 }, { id = 2290, count = 1 } } },
        { result = 3120, count = 1, station = 26, materials = { { id = 149, count = 1 }, { id = 704, count = 1 }, { id = 2290, count = 1 } } },
        { result = 3037, count = 1, station = 26, materials = { { id = 22, count = 5 }, { id = 5113, count = 1 }, { id = 2290, count = 1 } } },
        { result = 3037, count = 1, station = 26, materials = { { id = 704, count = 5 }, { id = 5113, count = 1 }, { id = 2290, count = 1 } } },
        { result = 3096, count = 1, station = 26, materials = { { id = 22, count = 5 }, { id = 1485, count = 1 }, { id = 2290, count = 1 } } },
        { result = 3096, count = 1, station = 26, materials = { { id = 704, count = 5 }, { id = 1485, count = 1 }, { id = 2290, count = 1 } } },
        { result = 739, count = 1, station = 16, materials = { { id = 703, count = 7 }, { id = 181, count = 8 } } },
        { result = 740, count = 1, station = 16, materials = { { id = 20, count = 7 }, { id = 180, count = 8 } } },
        { result = 741, count = 1, station = 16, materials = { { id = 705, count = 7 }, { id = 177, count = 8 } } },
        { result = 742, count = 1, station = 16, materials = { { id = 21, count = 7 }, { id = 179, count = 8 } } },
        { result = 3380, count = 1, station = 16, materials = { { id = 3347, count = 10 }, { id = 75, count = 1 } } },
        { result = 743, count = 1, station = 16, materials = { { id = 706, count = 7 }, { id = 178, count = 8 } } },
        { result = 744, count = 1, station = 16, materials = { { id = 19, count = 7 }, { id = 182, count = 8 } } },
        { result = 18, count = 1, station = 114, materials = { { id = 22, count = 5 }, { id = 3, count = 10 }, { id = 178, count = 2 } } },
        { result = 18, count = 1, station = 114, materials = { { id = 704, count = 5 }, { id = 3, count = 10 }, { id = 178, count = 2 } } },
        { result = 393, count = 1, station = 114, materials = { { id = 22, count = 5 }, { id = 3619, count = 1 } } },
        { result = 393, count = 1, station = 114, materials = { { id = 704, count = 5 }, { id = 3619, count = 1 } } },
        { result = 3814, count = 1, station = 134, materials = { { id = 2999, count = 1 }, { id = 4946, count = 1 } } },
        { result = 3781, count = 1, station = 114, materials = { { id = 5577, count = 1 }, { id = 521, count = 5 } } },  -- 袖珍镜 <- 漂亮镜子x1 + 暗影之魂x5（秘银砧）
        { result = 2367, count = 1, station = 26, materials = { { id = 225, count = 6 }, { id = 2290, count = 1 } } },
        { result = 2368, count = 1, station = 26, materials = { { id = 225, count = 12 }, { id = 2290, count = 1 } } },
        { result = 2369, count = 1, station = 26, materials = { { id = 225, count = 10 }, { id = 2290, count = 1 } } },
        { result = 2296, count = 1, station = 16, materials = { { id = 2291, count = 1 }, { id = 4325, count = 1 } } },
        { result = 2422, count = 1, station = 16, materials = { { id = 2296, count = 1 }, { id = 906, count = 1 } } },
        { result = 2294, count = 1, station = 16, materials = { { id = 2296, count = 1 }, { id = 19, count = 10 }, { id = 2354, count = 10 }, { id = 2356, count = 10 } } },
        { result = 2294, count = 1, station = 16, materials = { { id = 2296, count = 1 }, { id = 706, count = 10 }, { id = 2354, count = 10 }, { id = 2356, count = 10 } } },
        { result = 4325, count = 1, station = 16, materials = { { id = 2291, count = 1 }, { id = 4271, count = 1 } } },
        { result = 4978, count = 1, station = 26, materials = { { id = 320, count = 10 }, { id = 751, count = 20 }, { id = 68, count = 6 } } },
        { result = 4978, count = 1, station = 26, materials = { { id = 320, count = 10 }, { id = 751, count = 20 }, { id = 1330, count = 6 } } },
        { result = 2494, count = 1, station = 26, materials = { { id = 4978, count = 1 }, { id = 575, count = 10 }, { id = 2290, count = 2 } } },
        { result = 2373, count = 1, station = 26, materials = { { id = 3306, count = 3 }, { id = 2290, count = 1 } } },
        { result = 2374, count = 1, station = 26, materials = { { id = 22, count = 2 }, { id = 2354, count = 2 }, { id = 2290, count = 2 } } },
        { result = 2374, count = 1, station = 26, materials = { { id = 704, count = 2 }, { id = 2354, count = 2 }, { id = 2290, count = 2 } } },
        { result = 2375, count = 1, station = 26, materials = { { id = 48, count = 1 }, { id = 2354, count = 5 }, { id = 2356, count = 5 }, { id = 2290, count = 3 } } },
        { result = 5139, count = 1, station = 26, materials = { { id = 22, count = 1 }, { id = 161, count = 2 }, { id = 2290, count = 1 } } },
        { result = 5139, count = 1, station = 26, materials = { { id = 704, count = 1 }, { id = 161, count = 2 }, { id = 2290, count = 1 } } },
        { result = 67, count = 1, station = 26, materials = { { id = 2886, count = 1 } } },
        { result = 2886, count = 1, station = 26, materials = { { id = 67, count = 1 } } },
        { result = 331, count = 5, station = 26, materials = { { id = 5, count = 5 }, { id = 195, count = 1 } } },
        { result = 268, count = 1, station = 26, materials = { { id = 319, count = 3 } } },
        { result = 319, count = 3, station = 26, materials = { { id = 268, count = 1 } } },
        { result = 187, count = 1, station = 26, materials = { { id = 2327, count = 2 }, { id = 225, count = 6 } } },
        { result = 485, count = 1, station = 114, materials = { { id = 5130, count = 1 }, { id = 860, count = 1 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 2625, count = 3 }, { id = 2766, count = 2 }, { id = 382, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 2625, count = 3 }, { id = 2766, count = 2 }, { id = 1191, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 4073, count = 3 }, { id = 2766, count = 2 }, { id = 382, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 4073, count = 3 }, { id = 2766, count = 2 }, { id = 1191, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 4072, count = 3 }, { id = 2766, count = 2 }, { id = 382, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 4072, count = 3 }, { id = 2766, count = 2 }, { id = 1191, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 4071, count = 3 }, { id = 2766, count = 2 }, { id = 382, count = 5 } } },
        { result = 497, count = 1, station = 114, materials = { { id = 394, count = 1 }, { id = 4071, count = 3 }, { id = 2766, count = 2 }, { id = 1191, count = 5 } } },
        { result = 1332, count = 1, station = 26, materials = { { id = 522, count = 1 } } },
        { result = 522, count = 1, station = 26, materials = { { id = 1332, count = 1 } } },
        { result = 1322, count = 1, station = 26, materials = { { id = 173, count = 15 }, { id = 175, count = 5 } } },
        { result = 938, count = 1, station = 114, materials = { { id = 1513, count = 2 } } },
        { result = 963, count = 1, station = 114, materials = { { id = 977, count = 1 } } },
        { result = 977, count = 1, station = 114, materials = { { id = 963, count = 1 } } },
        { result = 49, count = 1, station = 114, materials = { { id = 29, count = 2 }, { id = 216, count = 1 } } },
        { result = 111, count = 1, station = 114, materials = { { id = 109, count = 5 }, { id = 216, count = 1 } } },
        { result = 1328, count = 1, station = 134, materials = { { id = 4465, count = 1 }, { id = 391, count = 15 } } },
        { result = 1328, count = 1, station = 134, materials = { { id = 4465, count = 1 }, { id = 1198, count = 15 } } },
        { result = 900, count = 1, station = 114, materials = { { id = 49, count = 1 }, { id = 2349, count = 2 }, { id = 2347, count = 2 }, { id = 292, count = 2 }, { id = 2322, count = 2 }, { id = 391, count = 20 }, { id = 2766, count = 10 } } },
        { result = 900, count = 1, station = 114, materials = { { id = 49, count = 1 }, { id = 2349, count = 2 }, { id = 2347, count = 2 }, { id = 292, count = 2 }, { id = 2322, count = 2 }, { id = 1198, count = 20 }, { id = 2766, count = 10 } } },
        { result = 899, count = 1, station = 114, materials = { { id = 313, count = 10 }, { id = 2766, count = 10 }, { id = 1101, count = 10 }, { id = 1293, count = 1 }, { id = 900, count = 1 } } },
        { result = 536, count = 1, station = 114, materials = { { id = 211, count = 1 }, { id = 2326, count = 2 }, { id = 381, count = 8 } } },
        { result = 536, count = 1, station = 114, materials = { { id = 211, count = 1 }, { id = 2326, count = 2 }, { id = 1184, count = 8 } } },
        { result = 4881, count = 1, station = 77, materials = { { id = 5139, count = 1 }, { id = 175, count = 10 } } },
        { result = 4346, count = 1, station = 16, materials = { { id = 3, count = 20 }, { id = 3380, count = 12 } } },
        { result = 5574, count = 1, station = 26, materials = { { id = 4478, count = 1 }, { id = 62, count = 1 } } },
        { result = 5663, count = 1, station = 26, materials = { { id = 5664, count = 1 } } },
        { result = 5664, count = 1, station = 26, materials = { { id = 5663, count = 1 } } },
        { result = 6142, count = 1, station = 26, materials = { { id = 68, count = 20 }, { id = 2018, count = 1 } } },
        { result = 6142, count = 1, station = 26, materials = { { id = 1330, count = 20 }, { id = 2018, count = 1 } } },
        { result = 6142, count = 1, station = 26, materials = { { id = 68, count = 20 }, { id = 3563, count = 1 }, { id = 5350, count = 1 } } },
        { result = 6142, count = 1, station = 26, materials = { { id = 1330, count = 20 }, { id = 3563, count = 1 }, { id = 5350, count = 1 } } },
        { result = 5667, count = 1, station = 26, materials = { { id = 4464, count = 1 }, { id = 68, count = 10 }, { id = 3380, count = 5 } } },
        { result = 5667, count = 1, station = 26, materials = { { id = 4464, count = 1 }, { id = 1330, count = 10 }, { id = 3380, count = 5 } } },
        { result = 6157, count = 1, station = 114, materials = { { id = 49, count = 1 }, { id = 3380, count = 15 }, { id = 382, count = 15 } } },
        { result = 6157, count = 1, station = 114, materials = { { id = 49, count = 1 }, { id = 3380, count = 15 }, { id = 1191, count = 15 } } },
        { result = 6158, count = 1, station = 303, materials = { { id = 6157, count = 1 }, { id = 2218, count = 8 } } },
        { result = 6159, count = 1, station = 114, materials = { { id = 6156, count = 1 }, { id = 382, count = 10 } } },
        { result = 6159, count = 1, station = 114, materials = { { id = 6156, count = 1 }, { id = 1191, count = 10 } } },
        { result = 6167, count = 1, station = 114, materials = { { id = 3086, count = 20 }, { id = 583, count = 1 }, { id = 68, count = 5 } } },
        { result = 6167, count = 1, station = 114, materials = { { id = 3086, count = 20 }, { id = 583, count = 1 }, { id = 1330, count = 5 } } },
        { result = 6172, count = 1, station = 114, materials = { { id = 3, count = 20 }, { id = 3306, count = 1 }, { id = 382, count = 6 } } },
        { result = 6172, count = 1, station = 114, materials = { { id = 3, count = 20 }, { id = 3306, count = 1 }, { id = 1191, count = 6 } } },
        { result = 3883, count = 1, station = 134, materials = { { id = 3817, count = 50 }, { id = 4948, count = 1 } } },
        { result = 4823, count = 1, station = 134, materials = { { id = 4989, count = 1 }, { id = 4949, count = 1 } } },
        { result = 2609, count = 1, station = 134, materials = { { id = 3330, count = 1 }, { id = 4936, count = 1 } } },
    }
    -- v13.35.0：把这份表公开出去，向导补写（cr_ql.lua）直接以它为唯一事实来源，
    -- 不再靠「扫游戏配方数组 + 猜材料」。改了配方表，向导就跟着变。
    _G.ms_rcp_list = RCP
    local registered = false
    return function()
        if registered then return end
        registered = true
        if not (mod.recipe and type(mod.recipe.add) == "function") then
            pcall(mod.warn, "[配方扩展] 当前加载器不支持 mod.recipe，已跳过")
            return
        end
        local okn, failn = 0, 0
        for i = 1, #RCP do
            local r = RCP[i]
            local ok = pcall(mod.recipe.add, {
                result    = { id = r.result, count = r.count or 1 },
                station   = r.station,
                materials = r.materials,
            })
            if ok then okn = okn + 1 else failn = failn + 1 end
        end
        pcall(mod.info, string.format("[配方扩展] 注册完成：成功 %d 条，失败 %d 条", okn, failn))
    end
end)()


-- ============================================================================
-- v7.1.0：平台魔杖 / 房屋魔杖（新物品，来自 lzup 的两个独立模组，已合并进来）
-- v7.10.0：物块魔杖（灰砖版，结构照抄平台魔杖 pt_* → bw_*，铺设样式带空格与火把）
-- v7.34.0：液体魔杖（水/熔岩/蜂蜜/清除 四模式，按钮切换，四色范围预览）
--   · quickapi 两份完全相同，共用 wand_quickapi.lua 一份
--   · placement/preview/tilefield/blueprint 各自带 pt_/fw_ 前缀，互不覆盖
--   · 物品由内核 mod.item.register 分配 ID（原版最大 6195，所以从 6196 起）
-- 注：主 chunk local 已到上限，整段包 IIFE 只挂 _G.ms_wand_setup
-- ============================================================================
_G.ms_wand_setup = (function()
    local installed = false
    local PT          -- 平台魔杖模块（轻按/拖动判断需要每帧 tick）
    local BW          -- 物块魔杖模块（同上，需要每帧 tick）
    local LW          -- 液体魔杖模块（同上，还要轮询模式按钮）
    return function()
        if installed then return end
        installed = true
        local okpt, ept = pcall(function()
            local m = require('pt_wand')
            if type(m) ~= "table" then error("pt_wand 返回 " .. type(m) .. "（缺 return M）") end
            PT = m
            m.setup()
        end)
        if not okpt then
            pcall(mod.error, "[平台魔杖] 注册失败：" .. tostring(ept))
            PT = nil
        end
        local okfw, efw = pcall(function() require('fw_wand').setup() end)
        if not okfw then pcall(mod.error, "[房屋魔杖] 注册失败：" .. tostring(efw)) end
        -- v7.10.0：物块魔杖（灰砖版，完全按平台魔杖的模式做）
        local okbw, ebw = pcall(function()
            local m = require('bw_wand')
            if type(m) ~= "table" then error("bw_wand 返回 " .. type(m) .. "（缺 return M）") end
            BW = m
            m.setup()
        end)
        if not okbw then
            pcall(mod.error, "[物块魔杖] 注册失败：" .. tostring(ebw))
            BW = nil
        end
        -- v7.34.0：液体魔杖（生成水 / 熔岩 / 蜂蜜 / 清除，四色范围预览）
        local oklw, elw = pcall(function()
            local m = require('lw_wand')
            if type(m) ~= "table" then error("lw_wand 返回 " .. type(m) .. "（缺 return M）") end
            LW = m
            m.setup()
        end)
        if not oklw then
            pcall(mod.error, "[液体魔杖] 注册失败：" .. tostring(elw))
            LW = nil
        end
        -- 平台魔杖靠每帧轮询「按住/移动/松开」判断是轻按还是拖动，挂到合集总线上
        if PT and type(pu_reg_post) == "function" then
            pu_reg_post("平台魔杖", function(inst) pcall(PT.on_tick, inst) end)
        end
        if BW and type(pu_reg_post) == "function" then
            pu_reg_post("物块魔杖", function(inst) pcall(BW.on_tick, inst) end)
        end
        if LW and type(pu_reg_post) == "function" then
            pu_reg_post("液体魔杖", function(inst) pcall(LW.on_tick, inst) end)
        end
        pcall(mod.info, string.format("[魔杖] 平台魔杖=%s 房屋魔杖=%s 物块魔杖=%s 液体魔杖=%s",
            okpt and "OK" or "失败", okfw and "OK" or "失败", okbw and "OK" or "失败",
            oklw and "OK" or "失败"))
    end
end)()



-- ============================================================================
-- v7.3.0：大肥鱼的 5 件饰品（新物品，已从独立模组合并进来）
--   · dff_ring    PureLoveRing     大肥鱼的纯爱之戒
--   · dff_gem     PowerStone       大肥鱼的力量宝石
--   · dff_reverse ReverseCursed    大肥鱼的反转术式
--   · dff_spell   FatFishBlessing  大肥鱼的法术戒指
--   · dff_abyss   ChaosBlessing    大肥鱼的深渊诅咒
--   原模组是顶层直接执行（无 mod.init），故 require 即注册 + 装钩子；
--   它们没有 cleanup，卸载时钩子不会主动摘（合集整体重载会重建）。
-- 注：主 chunk local 已到上限，整段包 IIFE 只挂 _G.ms_dff_setup
-- ============================================================================
_G.ms_dff_setup = (function()
    local installed = false
    return function()
        if installed then return end
        installed = true
        local mods = { 'dff_ring', 'dff_gem', 'dff_reverse', 'dff_spell', 'dff_abyss' }
        local okn, failn = 0, 0
        for i = 1, #mods do
            local ok, err = pcall(function() require(mods[i]) end)
            if ok then okn = okn + 1 else
                failn = failn + 1
                pcall(mod.error, "[" .. mods[i] .. "] 加载失败：" .. tostring(err))
            end
        end
        pcall(mod.info, string.format("[大肥鱼饰品] 成功 %d 件，失败 %d 件", okn, failn))
    end
end)()
-- ============================================================================
-- v7.7.0：法爆魔杖（新物品，从独立模组 ai.lua.fabao_wand v1.7.2 合并进来）
--   · 物品 fabao_wand + 铁砧配方（红玉×6 + 丛林孢子×10 + 坠落之星×4）
--   · 手持后拖动框选，松手清空矩形范围；轻点不拖动为 5×5；最大 50×50
--   · 世界内画半透明红色预览框（含逐格网格线），所见即所拆
--   · 三种模式（方块+墙 / 仅方块 / 仅墙）由 mod.controls 原生触摸按钮切换
--   · 主循环不自装 Player.Update，改走合集总线 pu_reg_post
--   · 六件套互相隔离在 fbw_ 前缀下，内部 require 一律 fbw_*
-- 注：主 chunk local 已到上限，整段包 IIFE 只挂 _G.ms_fbw_setup
-- ============================================================================
_G.ms_fbw_setup, _G.ms_fbw_cleanup = (function()
    local installed = false
    local FBW = nil
    local function boot()
        if installed then return end
        installed = true
        local ok, err = pcall(function()
            local m = require("fbw_main")
            if type(m) ~= "table" then error("fbw_main 返回 " .. type(m) .. "（缺 return M）") end
            FBW = m
            m.setup()
        end)
        if not ok then
            pcall(mod.error, "[法爆魔杖] 加载失败：" .. tostring(err))
            FBW = nil
            installed = false
            return
        end
        if type(pu_reg_post) == "function" then
            pu_reg_post("法爆魔杖", function(inst) pcall(FBW.on_tick, inst) end)
        end
        pcall(mod.info, "[法爆魔杖] 已加载（总线已挂，按钮已注册）")
    end
    local function term()
        if not installed then return end
        if FBW then pcall(FBW.cleanup) end
        FBW = nil
        installed = false
    end
    return boot, term
end)()

-- ============ 总入口（合并版） ============

-- ============================================================================
-- 第三十二部分：自动重铸「榨金」
-- ----------------------------------------------------------------------------
-- 靠近哥布林工匠，自动重铸手持物品与身上已装备的饰品。
-- 参数全部写死（不开放设置，按用户要求「去掉模组设置页面」）：
--   · 刷到顶级词缀就停 —— 武器按流派白名单，饰品固定「护佑(65)」
--   · 按原版规则扣金币 —— Player.BuyItem(long, int)
--       价格 = item.value × item.stack ÷ 3，最低 1 铜；有快乐值折扣再乘 0.8
--   · 触发半径 4 格、重铸间隔 5 帧
-- 总开关：设置页按钮，默认关闭，持久化 rf_en.txt
-- 每帧算力：注册到 Player.Update 汇合总线（pu_post），不额外装钩子
-- v7.6.8 响应速度：槽位句柄一次性绑定，每个处理节拍直接读 18 次 type，
--   换任何物品（含饰品）最迟 5 帧 ≈ 0.083 秒就生效；
--   总开销 19 次跨界/节拍 ≈ 3.8 次/帧，比 v7.6.3 的 7.8 次/帧还低一半
-- v7.6.6 性能优化：候选列表全扫结果缓存若干次 tick，平时在缓存里轮换；
--   跨边界调用随候选数量线性，不再有「空槽也占轮次」的浪费；
--   CanHavePrefixes 按 item.type 缓存。
--   手持项额外核对 selectedItem：切手持后句柄会指向旧的背包格，必须重建
-- ============================================================================

_G.rf_setup, _G.rf_cleanup, _G.rf_set_enabled, _G.rf_is_enabled,
_G.rf_get_acc, _G.rf_set_acc = (function()
    pcall(require, "wand_quickapi")
    local P = mod.patch

    local RANGE    = 4      -- 触发半径（格）
    local INTERVAL = 5      -- 重铸间隔（帧）
    -- v8.9.47：一个节拍里最多重铸几件。原来一节拍只处理一件，17 个饰品槽
    --   要轮流等 17 个节拍（约 7 秒）才转过一圈，所以感觉特别慢。
    local REFRESH_PER_TICK = 4
    -- 饰品可选词缀（Tier3 优质词缀，六选一互斥）
    local ACC_LIST = {
        { id = 65, name = "护佑" },   -- Warding   +4 防御
        { id = 68, name = "幸运" },   -- Lucky     +4% 暴击率
        { id = 72, name = "险恶" },   -- Menacing  +4% 伤害
        { id = 76, name = "迅捷" },   -- Quick2    +4% 移动速度
        { id = 80, name = "暴力" },   -- Violent   +4% 击退
        { id = 66, name = "奥秘" },   -- Arcane    +20 魔力上限
    }
    local ACC_TOP  = 65        -- 当前选中的饰品词缀（从 rf_acc.txt 读）

    -- 各流派「顶级」词缀（PrefixID）
    local TOP_WEAPON = {
        [57] = true,    -- Ruthless   召唤
        [59] = true,    -- Godly      长矛 / 回旋镖 / 链球
        [81] = true,    -- Legendary  剑 / 锤 / 斧 / 镐
        [82] = true,    -- Unreal     枪 / 弓
        [83] = true,    -- Mythical   魔法
        [84] = true,    -- Legendary2 悠悠球
    }
    local NPC_GOBLIN = 107

    -- v7.6.8：槽位句柄一次性绑定
    --   依据两条事实：
    --     ① Player.cs 56709-56716：armor[i] / inventory[i] = new Item() 只在构造时执行，
    --        之后换装备一律 SetDefaults(0) 改内容，元素引用永不替换；
    --     ② l_patch_array_at 不传类型名时推回来的是裸对象指针（lightuserdata），
    --        Item 被数组强引用、不会被回收，所以句柄可以长期持有。
    --   于是把 10 个背包格 + 17 个饰品槽的句柄绑死，之后每帧只读 type，
    --   不再反复 go() / array_at() / invoke(get_selectedItem)。
    local BIND       = { player = nil, inv = nil, armor = nil }
    local CAND       = {}   -- 候选物品句柄（每节拍重填，不跨节拍用）
    local CAND_ACC   = {}   -- 是否饰品槽
    local CAND_TY    = {}   -- 收集时读到的 type，供 done / can_prefix 复用
    local CAN_CACHE  = {}   -- item.type -> CanHavePrefixes 结果

    local EN = false
    local frame, slot, slot_age, cursor = 0, -1, 0, 0
    -- v8.9.41：每件物品的重铸次数上限。
    --   如果某件物品因为目标词缀判定不对而永远「不达标」，它会把每个节拍都占掉、
    --   把钱抽干，同时让饰品永远轮不到。够 400 次就放弃它，交给下一件。
    local TRIES, MAX_TRY = {}, 400
    -- v8.9.42 诊断：记录实际重铸了哪些物品，节流输出到日志（切物品时必打一条）
    local last_log_ty = -1
    local function try_cnt(it) return TRIES[tostring(it)] or 0 end
    local function try_bump(it) TRIES[tostring(it)] = try_cnt(it) + 1 end
    local pay_block, poor = 0, false
    local failed = false
    local H = {}

    -- ---------- 读数工具 ----------
    local function gi(f, inst)
        if not f then return 0 end
        local v = P.get_field_value(f, inst, "int32")
        if type(v) ~= "number" then v = P.get_field_value(f, inst, "uint8") end
        if type(v) ~= "number" then return 0 end
        return v
    end
    local function gb(f, inst)
        if not f then return false end
        return P.get_field_value(f, inst, "bool") == true
    end
    local function go(f, inst)
        if not f then return nil end
        return P.get_field_value(f, inst, "object")
    end

    local prefix_vtype
    local function prefix_of(it)
        if not H.prefix then return -1 end
        if prefix_vtype then
            local v = P.get_field_value(H.prefix, it, prefix_vtype)
            if type(v) == "number" then return v end
            prefix_vtype = nil
        end
        for _, t in ipairs({ "uint8", "int8", "int32" }) do
            local v = P.get_field_value(H.prefix, it, t)
            if type(v) == "number" then prefix_vtype = t return v end
        end
        return -1
    end

    local function pos_of(inst)
        if not H.pos then return 0, 0 end
        local x, y = P.get_field_vec2(H.pos, inst)
        return x or 0, y or 0
    end

    -- ---------- 开关持久化 ----------
    local function write_en(v) pcall(mod.write_file, "rf_en.txt", v and "1" or "0") end
    local function read_on()
        local ok, raw = pcall(mod.read_file, "rf_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:sub(1, 1) == "1"
    end

    -- 饰品词缀持久化：非法值一律回落护佑(65)
    local function write_acc(id) pcall(mod.write_file, "rf_acc.txt", tostring(id)) end
    local function read_acc()
        local ok, raw = pcall(mod.read_file, "rf_acc.txt")
        if not ok or type(raw) ~= "string" then return 65 end
        local n = tonumber(raw:match("^%s*(%-?%d+)"))
        if not n then return 65 end
        for i = 1, #ACC_LIST do
            if ACC_LIST[i].id == n then return n end
        end
        return 65
    end

    -- ---------- 句柄 ----------
    local function bind()
        local T_Main   = P.get_type("Terraria", "Main")
        local T_Player = P.get_type("Terraria", "Player")
        local T_Item   = P.get_type("Terraria", "Item")
        local T_NPC    = P.get_type("Terraria", "NPC")
        local T_Entity = P.get_type("Terraria", "Entity")
        if not (T_Main and T_Player and T_Item and T_NPC and T_Entity) then
            mod.error("[自动重铸] 取不到 Terraria 核心类型") return false
        end
        H.npc    = P.get_field(T_Main, "npc")
        H.pos    = P.get_field(T_Entity, "position")
        H.inv    = P.get_field(T_Player, "inventory")
        H.armor  = P.get_field(T_Player, "armor")
        H.dead   = P.get_field(T_Player, "dead")
        H.disc   = P.get_field(T_Player, "discountAvailable")
        H.prefix = P.get_field(T_Item, "prefix")
        H.itype  = P.get_field(T_Item, "type")
        -- v8.9.38：按物品类别判定「最佳词缀」用的字段
        H.f_melee    = P.get_field(T_Item, "melee")
        H.f_magic    = P.get_field(T_Item, "magic")
        H.f_ranged   = P.get_field(T_Item, "ranged")
        H.f_summon   = P.get_field(T_Item, "summon")
        H.f_yoyo     = P.get_field(T_Item, "yoyo")
        H.f_usestyle = P.get_field(T_Item, "useStyle")
        H.value  = P.get_field(T_Item, "value")
        H.stack  = P.get_field(T_Item, "stack")

        -- v8.9.47：三套配装。Player.Loadouts 是 EquipmentLoadout[]，
        --   每个元素有自己的 Item[] Armor（armor[3..19] 是饰品槽），
        --   CurrentLoadoutIndex 表示当前穿的是哪一套。
        --   以前只收集 player.armor，所以只重铸「进世界时那一套」。
        local T_Loadout = P.get_type("Terraria", "EquipmentLoadout")
        if T_Loadout then
            H.loadouts = P.get_field(T_Player, "Loadouts")
            H.ld_armor = P.get_field(T_Loadout, "Armor")
        end
        H.cur_lo = P.get_field(T_Player, "CurrentLoadoutIndex")

        -- selectedItem 是属性（=> selectedItemState.Selected），不能当字段读
        local prop = P.get_property and P.get_property(T_Player, "selectedItem")
        if prop and P.property_get_method then H.m_sel = P.property_get_method(prop) end
        if not H.m_sel then H.m_sel = P.get_method(T_Player, "get_selectedItem", 0) end
        -- v8.9.41：手持物品优先用 HeldItem 属性直接取（返回 Item 对象本身），
        --   不再依赖 selectedItem 的索引。PE 上 get_selectedItem 一旦返回的不是数字，
        --   索引就会退化成 0，导致无论怎么换武器都在重铸背包第 1 格。
        local propH = P.get_property and P.get_property(T_Player, "HeldItem")
        if propH and P.property_get_method then H.m_held = P.property_get_method(propH) end
        if not H.m_held then H.m_held = P.get_method(T_Player, "get_HeldItem", 0) end

        H.m_find   = P.get_method(T_NPC, "FindFirstNPC", 1)
        H.m_reset  = P.get_method(T_Item, "ResetPrefix", 0)
        H.m_prefix = P.get_method(T_Item, "Prefix", 1)
        H.m_can    = P.get_method(T_Item, "CanHavePrefixes", 0)
        H.m_buy    = P.get_method(T_Player, "BuyItem", 2)   -- IL2CPP 只有 2 参版本

        if not (H.npc and H.pos and H.inv and H.armor and H.m_sel and
                H.m_find and H.m_reset and H.m_prefix) then
            mod.error("[自动重铸] 关键句柄缺失，功能不可用") return false
        end
        if not H.m_buy then mod.warn("[自动重铸] 取不到 Player.BuyItem，重铸将不扣钱") end
        return true
    end

    -- ---------- 扣钱 ----------
    local function price_of(player, it)
        local v = gi(H.value, it)
        local st = gi(H.stack, it)
        if v <= 0 then v = 1 end
        if st < 1 then st = 1 end
        local pr = v * st
        if gb(H.disc, player) then pr = pr * 0.8 end
        pr = math.floor(pr / 3)
        if pr < 1 then pr = 1 end
        return pr
    end

    local function pay(player, it)
        if not H.m_buy then return true end
        local ok, res = pcall(P.invoke, H.m_buy, player, price_of(player, it), -1)
        if not ok then return true end      -- 调用失败放行，避免整块功能停摆
        if res ~= true then poor = true return false end
        poor = false
        return true
    end

    -- ---------- 达标判定 ----------
    -- v8.9.43：按用户实测的最佳词缀表重写。
    --   之前那套「6 个词缀混一个集合，撞上就算达标」是错的；后来按武器大类猜
    --   也错了好几次。现在改成「每把武器一个目标表」，命中任一即达标。
    local PF_RUTHLESS   = 57    -- 无情
    local PF_GODLY      = 59    -- 神级
    local PF_DEMONIC    = 60    -- 恶魔
    local PF_LEGENDARY  = 81    -- 传奇
    local PF_UNREAL     = 82    -- 虚幻
    local PF_MYTHICAL   = 83    -- 神话
    local PF_QUICK      = 42    -- 迅速
    local PF_AGILE      = 44    -- 灵活
    local PF_BALLISTIC  = 96    -- 弹道（1.4.4 新增）
    -- 各分类的默认目标（用户没单独点名的武器走这里）
    local SET_LEGENDARY = { PF_LEGENDARY }  -- 近战 / 鞭子：传奇
    local SET_GODLY     = { PF_GODLY }      -- 悠悠球 / 回旋镖 / 连枷：神级
    local SET_UNREAL    = { PF_UNREAL }
    local SET_MYTHICAL  = { PF_MYTHICAL }
    local SET_SUMMON    = { 85 }            -- 召唤默认：传说(Fabled)
    -- v8.9.44：按用户实测修正分类目标 ——
    --   近战与鞭子一律「传奇」；只有悠悠球、回旋镖、连枷这三类是「神级」。
    --   游戏里没有现成的「回旋镖 / 连枷」集合（ItemID.Sets 只有 Yoyo），所以列名。
    local YOYO = {
        [3262]=true, [3278]=true, [3279]=true, [3280]=true, [3281]=true, [3282]=true,
        [3283]=true, [3284]=true, [3285]=true, [3286]=true, [3287]=true, [3288]=true,
        [3289]=true, [3290]=true, [3291]=true, [3316]=true, [3389]=true, [5294]=true,
    }
    local BOOMERANG_FLAIL = {
        [55]=true,   -- 附魔回旋镖
        [119]=true,  -- 烈焰回旋镖 Flamarang
        [162]=true,  -- 血之球 BallOHurt（连枷）
        [163]=true,  -- 蓝月 BlueMoon（连枷）
        [191]=true,  -- 荆棘轮 ThornChakram
        [220]=true,  -- 烈日之怒 Sunfury（连枷）
        [284]=true,  -- 木回旋镖
        [389]=true,  -- 太极连枷 DaoofPow
        [561]=true,  -- 光盘 LightDisc
        [670]=true,  -- 冰冻回旋镖
        [1122]=true, -- 附身战斧 PossessedHatchet
        [1297]=true, -- 石巨人拳 GolemFist（连枷）
        [1324]=true, -- 香蕉回旋镖
        [1325]=true, -- 链刀 ChainKnife（连枷）
        [1513]=true, -- 圣骑士锤
        [1918]=true, -- 水果轮 FruitcakeChakram
        [2424]=true, -- 铁锚 Anchor（连枷）
        [2611]=true, -- 耀斑 Flairon（连枷）
        [4272]=true, -- 滴血连枷
        [4764]=true, -- 蘑菇回旋镖 Shroomerang
        [5011]=true, -- 钉锤 Mace（连枷）
        [5012]=true, -- 燃烧钉锤
        [5298]=true, -- 三叉回旋镖 Trimarang
        [5526]=true, -- 耀斑连枷
    }
    -- v8.9.45：这些是近战，但最佳词缀是「神级」而不是传奇（用户实测）
    local MELEE_GODLY = {
        -- [757] 泰拉刃 TerraBlade 不在此列：它的最佳是传奇，走近战默认
        [4144] = true,   -- 泰拉魔刃 Terragrim
        [1569] = true,   -- 吸血鬼刀 VampireKnives
        [1571] = true,   -- 腐化者之戟 ScourgeoftheCorruptor
        [3030] = true,   -- 飞刀 FlyingKnife
        [3054] = true,   -- 暗影焰刀 ShadowFlameKnife
        [3368] = true,   -- Arkhalis 剑
        [3835] = true,   -- 瞌睡章鱼 MonkStaffT1
        [3858] = true,   -- 天龙之怒 MonkStaffT3
        [4788] = true,   -- 骑枪 JoustingLance
        [4789] = true,   -- 暗影骑枪 ShadowJoustingLance
        [4790] = true,   -- 神圣骑枪 HallowJoustingLance
    }
    -- 鞭子（1.4.5 的 Whip 系列；注意 IvyWhip 185 是抓钩，不算）
    local WHIP = {
        [4672]=true, [4678]=true, [4679]=true, [4680]=true,
        [4911]=true, [4912]=true, [4913]=true, [4914]=true,
        [5074]=true, [5473]=true, [5474]=true, [5475]=true, [5476]=true,
        [5477]=true, [5478]=true, [5479]=true, [5480]=true, [5688]=true,
    }
    -- 用户逐个点名的最佳词缀（按 ItemID）
    local SPECIAL_PREFIX = {
        [1513] = { PF_GODLY },              -- 圣骑士锤
        [3389] = { 84 },                    -- 泰拉悠悠球：悠悠球专用的「传奇」(Legendary2)
        [5462] = { PF_LEGENDARY },          -- 燧石（DeadCellsFlint）
        [3543] = { PF_RUTHLESS },           -- 破晓之光
        [3473] = { PF_RUTHLESS },           -- 日耀喷发剑
        [4956] = { PF_LEGENDARY },          -- 天顶剑
        [5669] = { PF_LEGENDARY },          -- 真铜短剑
        [98]   = { PF_AGILE, 43 },          -- 迷你鲨：灵活
        [434]  = { PF_DEMONIC },            -- 发条式突击步枪：恶魔
        [1929] = { 17 },                    -- 链式机枪：迅速(Rapid)
        [3107] = { PF_DEMONIC },            -- 钉枪：恶魔
        [64]   = { PF_RUTHLESS },           -- 魔刺：无情
        [1244] = { PF_DEMONIC },            -- 雨云法杖 NimbusRod：恶魔
        [1256] = { PF_DEMONIC },            -- 猩红魔杖：恶魔
        [3014] = { PF_RUTHLESS },           -- 爬藤怪法杖：无情
        [4758] = { PF_BALLISTIC },          -- 刃杖：弹道
    }
    local function want_prefix(it, ty)
        local sp = SPECIAL_PREFIX[ty]
        if sp then return sp end
        -- 悠悠球 / 回旋镖 / 连枷 / 上面那批特殊近战 -> 神级
        if YOYO[ty] or BOOMERANG_FLAIL[ty] or MELEE_GODLY[ty] then return SET_GODLY end
        -- 鞭子 -> 传奇
        if WHIP[ty] then return SET_LEGENDARY end
        if gb(H.f_summon, it) then return SET_SUMMON end
        if gb(H.f_magic, it)  then return SET_MYTHICAL end
        if gb(H.f_ranged, it) then return SET_UNREAL end
        if gb(H.f_melee, it)  then return SET_LEGENDARY end   -- 近战默认传奇
        return nil      -- 分类读不出来
    end
    local function done(it, is_acc, ty)
        local pf = prefix_of(it)
        if pf <= 0 then return false end
        if is_acc then return pf == ACC_TOP end
        local want = want_prefix(it, ty)
        if want then
            for i = 1, #want do
                if pf == want[i] then return true end
            end
            return false
        end
        return TOP_WEAPON[pf] == true       -- 兜底
    end
    -- ---------- 槽位绑定与候选收集 ----------
    -- 当前配装编号（0/1/2）。读不到就返回 -1，不影响其它逻辑
    local function cur_loadout(player)
        if not H.cur_lo then return -1 end
        local v = P.get_field_value(H.cur_lo, player, "int32")
        if type(v) ~= "number" then return -1 end
        return v
    end

    local function bind_slots(player)
        local inv = go(H.inv, player)
        local ar  = go(H.armor, player)
        if not (inv and ar) then return false end
        local li = {}
        for i = 0, 9 do li[i + 1] = P.array_at(inv, i) end
        local la, seen = {}, {}
        local function add(arr)
            if not arr then return end
            for i = 3, 19 do            -- armor[0..2] 头/身/腿，[3..19] 饰品槽
                local it = P.array_at(arr, i)
                if it then
                    local k = tostring(it)
                    if not seen[k] then
                        seen[k] = true
                        la[#la + 1] = it
                    end
                end
            end
        end
        add(ar)                          -- 当前穿着的
        -- v8.9.47：另外两套配装的饰品槽也纳入。切配装只是换数组引用，
        --   这些 Item 对象不会变，所以句柄可以长期持有。
        if H.loadouts and H.ld_armor then
            for i = 0, 2 do
                local lo = P.array_at(H.loadouts, i)
                if lo then add(go(H.ld_armor, lo)) end
            end
        end
        BIND.player, BIND.inv, BIND.armor = player, li, la
        BIND.loadout = cur_loadout(player)
        return true
    end
    -- 扫一遍全部已绑定槽位，收集「有物品」的候选，顺带把 type 存下来
    --   返回候选个数；CAND / CAND_ACC / CAND_TY 复用同一组表，靠返回值限定有效范围
    -- v8.9.41：手持物品获取。优先 HeldItem（对象直取），拿不到才回退索引。
    local function held_item(player)
        if H.m_held then
            local ok, hit = pcall(P.invoke, H.m_held, player)
            if ok and hit and gi(H.itype, hit) > 0 then return hit end
        end
        local oks, sel = pcall(P.invoke, H.m_sel, player)
        if oks and type(sel) == "number" and sel >= 0 and sel <= 9 then
            return BIND.inv[sel + 1]
        end
        return nil
    end
    local function collect_cand(player)
        local n = 0
        local hit = held_item(player)
        if hit then
            local ty = gi(H.itype, hit)
            if ty > 0 then
                n = n + 1
                CAND[n], CAND_ACC[n], CAND_TY[n] = hit, false, ty
            end
        end
        local la = BIND.armor
        for i = 1, #la do
            local it = la[i]
            if it then
                local ty = gi(H.itype, it)
                if ty > 0 then
                    n = n + 1
                    CAND[n], CAND_ACC[n], CAND_TY[n] = it, true, ty
                end
            end
        end
        return n
    end

    -- CanHavePrefixes 只取决于物品类型，按 type 缓存后同类物品不再跨界问
    local function can_prefix(it, ty)
        if not H.m_can then return true end
        local c = CAN_CACHE[ty]
        if c ~= nil then return c end
        local okc, can = pcall(P.invoke, H.m_can, it)
        can = (okc and can == true)
        CAN_CACHE[ty] = can
        return can
    end

    -- ---------- 每帧 ----------
    -- v8.9.47：把「扣钱 + 重铸一次」抽成 refresh，一个节拍里可以连做几件
    local function refresh(player, it, is_acc, ty)
        if not pay(player, it) then
            if pay_block <= frame then
                mod.info("[reforge] out of money")
            end
            pay_block = frame + 60
            return false
        end
        try_bump(it)
        if ty ~= last_log_ty or frame % 600 == 0 then
            last_log_ty = ty
            mod.info(string.format("[reforge] type=%d pf=%d acc=%s n=%d",
                ty, prefix_of(it), tostring(is_acc), try_cnt(it)))
        end
        pcall(P.invoke, H.m_reset, it)
        pcall(P.invoke, H.m_prefix, it, -2)
        return true
    end

    local function tick(player)
        if not EN or failed then return end
        frame = frame + 1
        if frame % INTERVAL ~= 0 then return end
        if frame < pay_block then return end
        if not player then return end
        if gb(H.dead, player) then return end
        slot_age = slot_age - INTERVAL
        if slot_age <= 0 then
            slot_age = 30
            local ok, res = pcall(P.invoke, H.m_find, NPC_GOBLIN)
            slot = (ok and type(res) == "number") and res or -1
        end
        if slot < 0 then return end
        local arr = go(H.npc, nil)
        if not arr then return end
        local npc = P.array_at(arr, slot)
        if not npc then return end
        local px, py = pos_of(player)
        local nx, ny = pos_of(npc)
        local dx, dy = nx - px, ny - py
        local lim = RANGE * 16
        if dx * dx + dy * dy > lim * lim then return end
        -- Player 对象换了（重进世界 / 换角色）或切换了配装就重新绑一次
        if BIND.player ~= player or BIND.loadout ~= cur_loadout(player) then
            if not bind_slots(player) then return end
        end
        local n = collect_cand(player)
        if n == 0 then return end
        local used, budget = {}, REFRESH_PER_TICK
        -- ① 手持武器优先：没到顶级词缀就每个节拍都重铸它
        for i = 1, n do
            if not CAND_ACC[i] then
                local c = CAND[i]
                if not done(c, false, CAND_TY[i]) and can_prefix(c, CAND_TY[i]) and try_cnt(c) < MAX_TRY then
                    if not refresh(player, c, false, CAND_TY[i]) then return end
                    used[tostring(c)] = true
                    budget = budget - 1
                    break
                end
            end
        end
        -- ② 饰品：一个节拍继续处理多件（v8.9.47 提速关键）
        while budget > 0 do
            local an = 0
            for i = 1, n do if CAND_ACC[i] then an = an + 1 end end
            if an == 0 then break end
            local pick_it, pick_ty, pick_i = nil, 0, nil
            for _ = 1, an do
                cursor = cursor % an + 1
                local cnt, idx = 0, nil
                for i = 1, n do
                    if CAND_ACC[i] then
                        cnt = cnt + 1
                        if cnt == cursor then idx = i break end
                    end
                end
                if not idx then break end
                local c = CAND[idx]
                if not used[tostring(c)] and not done(c, true, CAND_TY[idx])
                   and can_prefix(c, CAND_TY[idx]) and try_cnt(c) < MAX_TRY then
                    pick_it, pick_ty, pick_i = c, CAND_TY[idx], idx
                    break
                end
            end
            if not pick_it then break end
            if not refresh(player, pick_it, true, pick_ty) then return end
            used[tostring(pick_it)] = true
            budget = budget - 1
        end
    end
    -- ---------- 生命周期 ----------
    local function rf_setup()
        if failed then return end
        EN = read_on()
        ACC_TOP = read_acc()
        if not bind() then failed = true return end
        if type(pu_reg_post) == "function" then
            pu_reg_post("榨金", function(inst) pcall(tick, inst) end)
        else
            mod.warn("[自动重铸] 找不到 Player.Update 汇合总线，无法注册每帧任务")
        end
        local aname = "?"
        for i = 1, #ACC_LIST do
            if ACC_LIST[i].id == ACC_TOP then aname = ACC_LIST[i].name break end
        end
        mod.info(string.format("[自动重铸] 就绪（半径 %d 格 / 间隔 %d 帧 / 扣钱 开 / 饰品词缀 %s / 默认%s）",
            RANGE, INTERVAL, aname, EN and "开" or "关"))
    end

    local function rf_cleanup()
        EN = false
        frame, slot, slot_age, cursor = 0, -1, 0, 0
        pay_block, poor = 0, false
        BIND.player, BIND.inv, BIND.armor = nil, nil, nil
        TRIES = {}
    end

    local function rf_set_enabled(v)
        EN = v and true or false
        write_en(EN)
        if not EN then poor = false pay_block = 0 end
    end

    local function rf_is_enabled() return EN end

    local function rf_get_acc() return ACC_TOP end
    local function rf_set_acc(id)
        for i = 1, #ACC_LIST do
            if ACC_LIST[i].id == id then
                ACC_TOP = id
                write_acc(id)
                return true
            end
        end
        return false
    end

    return rf_setup, rf_cleanup, rf_set_enabled, rf_is_enabled, rf_get_acc, rf_set_acc
end)()

-- ============================================================================
-- 第三十四部分：你不准死（靠近护士自动治疗）
-- ----------------------------------------------------------------------------
-- 由独立模组「你不准死(*￣︿￣)」v1.0.5 并入。
-- 玩家靠近护士，只要不是满血，护士就自动给玩家治疗。
-- 参数写死（不开放设置）：
--   · 触发半径 25 格
--   · 扣钱固定走原版 —— Player.BuyItem，金币不足时原版自己拒绝治疗
--   · 检查节流 20 帧、治疗成功冷却 60 帧
-- 总开关：设置页按钮，默认关闭，持久化 nst_en.txt
-- 性能：问价 GetNurseHealCost() 放在最前面，满血返回 0 即一次跨界早退
--   （满血约 0.05 次跨界/帧，缺血约 0.45 次）
-- 坑：调 0 参静态方法必须用 patch.invoke，不能用 q.call —— 后者按
--   method_is_instance 预判再拆参数，静态方法会被误塞一个 nil 当实参，
--   参数越界异常又被 pcall 吞掉，表现为「钩子装上了但每帧静默 return」
-- ============================================================================
_G.nst_setup, _G.nst_cleanup, _G.nst_set_enabled, _G.nst_is_enabled = (function()
    local P = mod.patch
    local RANGE          = 25   -- 触发半径（格）
    local CHECK_INTERVAL = 20   -- 每 20 帧问一次价
    local HEAL_COOLDOWN  = 60   -- 治疗成功后的冷却（帧）
    local NPC_NURSE      = 18
    local EN, failed = false, false
    local frame, tickn, heal_cd = 0, 0, 0
    local H = {}

    -- ---------- 读数工具（全部带 pcall，读失败就不介入，不抛错）----------
    local function gi(f, inst)
        if not f then return 0 end
        local ok, v = pcall(P.get_field_value, f, inst, "int32")
        if ok and type(v) == "number" then return v end
        ok, v = pcall(P.get_field_value, f, inst, "uint8")
        if ok and type(v) == "number" then return v end
        return 0
    end
    local function gb(f, inst)
        if not f then return false end
        local ok, v = pcall(P.get_field_value, f, inst, "bool")
        if ok then return v == true end
        return false
    end
    local function go(f, inst)
        if not f then return nil end
        local ok, v = pcall(P.get_field_value, f, inst, "object")
        if ok then return v end
        return nil
    end
    local function pos_of(inst)
        if not H.pos then return 0, 0 end
        local ok, x, y = pcall(P.get_field_vec2, H.pos, inst)
        if ok and type(x) == "number" then return x, y end
        return 0, 0
    end

    -- ---------- 开关持久化 ----------
    local function read_on()
        local ok, raw = pcall(mod.read_file, "nst_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:sub(1, 1) == "1"
    end
    local function write_on(v) pcall(mod.write_file, "nst_en.txt", v and "1" or "0") end

    -- ---------- 句柄 ----------
    local function bind()
        local T_Main   = P.get_type("Terraria", "Main")
        local T_Player = P.get_type("Terraria", "Player")
        local T_NPC    = P.get_type("Terraria", "NPC")
        local T_Entity = P.get_type("Terraria", "Entity")
        if not (T_Main and T_Player and T_NPC and T_Entity) then
            mod.error("[你不准死] 取不到 Terraria 核心类型") return false
        end
        H.npc     = P.get_field(T_Main, "npc")
        H.menu    = P.get_field(T_Main, "gameMenu")
        H.pos     = P.get_field(T_Entity, "position")
        H.dead    = P.get_field(T_Player, "dead")
        H.who     = P.get_field(T_Player, "whoAmI")
        H.nactive = P.get_field(T_NPC, "active")
        H.ntype   = P.get_field(T_NPC, "type")
        -- 两个静态方法：0 参问价 / 1 参执行治疗
        H.m_cost = P.get_method(T_Main, "GetNurseHealCost", 0)
        H.m_heal = P.get_method(T_Main, "NPCChatText_DoNurseHeal", 1)
        H.m_find = P.get_method(T_NPC, "FindFirstNPC", 1)
        if not (H.npc and H.pos and H.m_cost and H.m_heal) then
            mod.error("[你不准死] 关键句柄缺失，功能不可用") return false
        end
        return true
    end

    -- ---------- 找护士 ----------
    -- FindFirstNPC 在世界里没护士时返回 -1，这是正常值，直接采信；
    -- 只有调用本身失败才做手动遍历兜底
    local function find_nurse(arr)
        if H.m_find then
            local ok, res = pcall(P.invoke, H.m_find, NPC_NURSE)
            if ok and type(res) == "number" then return res end
        end
        if not arr then return -1 end
        for i = 0, 199 do
            local n = P.array_at(arr, i)
            if n and gb(H.nactive, n) and gi(H.ntype, n) == NPC_NURSE then return i end
        end
        return -1
    end

    -- ---------- 每帧 ----------
    local function tick(player)
        if not EN or failed or not player then return end
        frame = frame + 1
        if heal_cd > 0 then heal_cd = heal_cd - 1 end
        tickn = tickn + 1
        if tickn % CHECK_INTERVAL ~= 0 then return end
        if heal_cd > 0 then return end

        -- ① 先问价：满血且无 debuff 返回 0，一次跨界就早退
        local okc, cost = pcall(P.invoke, H.m_cost)
        if not okc or type(cost) ~= "number" or cost <= 0 then return end
        -- ② 主菜单 / 死亡
        if gb(H.menu, nil) then return end
        if gb(H.dead, player) then return end
        -- ③ 只处理本机玩家
        if gi(H.who, player) < 0 then return end
        -- ④ 找护士
        local arr = go(H.npc, nil)
        if not arr then return end
        local slot = find_nurse(arr)
        if slot < 0 then return end
        local npc = P.array_at(arr, slot)
        if not npc then return end
        -- ⑤ 距离判定
        local px, py = pos_of(player)
        local nx, ny = pos_of(npc)
        local dx, dy = nx - px, ny - py
        local lim = RANGE * 16
        if dx * dx + dy * dy > lim * lim then return end
        -- ⑥ 交给原版治疗（内部 BuyItem 扣钱，钱不够原版自己拒绝）
        if pcall(P.invoke, H.m_heal, cost) then heal_cd = HEAL_COOLDOWN end
    end

    -- ---------- 生命周期 ----------
    local function nst_setup()
        if failed then return end
        EN = read_on()
        if not bind() then failed = true return end
        if type(pu_reg_post) == "function" then
            pu_reg_post("你不准死", function(inst) pcall(tick, inst) end)
        else
            mod.warn("[你不准死] 找不到 Player.Update 汇合总线，无法注册每帧任务")
        end
        mod.info(string.format("[你不准死] 就绪（半径 %d 格 / 扣钱 开 / 默认%s）",
            RANGE, EN and "开" or "关"))
    end
    local function nst_cleanup()
        EN = false
        frame, tickn, heal_cd = 0, 0, 0
    end
    local function nst_set_enabled(v)
        EN = v and true or false
        write_on(EN)
        if not EN then heal_cd = 0 end
    end
    local function nst_is_enabled() return EN end

    return nst_setup, nst_cleanup, nst_set_enabled, nst_is_enabled
end)()


-- ============================================================================
-- 第三十六部分：自动钓鱼 + 10 倍愿者上钩（v8.6.0 并入）
--   独立模组来源：lzup333 的 自动钓鱼(AutoFisher) v1.1.0 + 愿者上钩(VoluntaryHook) v1.1.0
--   用户要求：一个按钮同时管三件事，默认关闭
--     ① 自动抛竿 / 自动收线（全自动挂机）
--     ② 抛竿变 10 倍（原版 1 枚 → 10 枚浮标）
--     ③ 血月期间不再上钩血月钓鱼怪
--
-- ── ① 自动钓鱼的原理（不写逻辑，只按按键）────────────────────────────────────
--   只做一件事：把 Player.controlUseItem 置 true。
--   原版 Player.ItemCheck 自然会完成抛竿 / 收线 / 交鱼 / 扣鱼饵 / 算幸运与钓鱼力 /
--   记成就 / 生成任务鱼 —— 零遗漏，因为走的就是玩家按键那条路。
--   挂在 Player.ItemCheck 上而不是 Main.Update：主菜单不跑、玩家死了不跑，
--   只在真正有玩家行为时执行，天然比每帧总线安全。
--
-- ── ② 上钩判定（读原版状态机，不是猜）────────────────────────────────────────
--   ai[0] == 0 且 ai[1] < 0 且 localAI[1] != 0  →  有鱼咬钩
--   对应原版 Projectile.AI_061_FishingBobber 内部条件（aiStyle 61 = 钓鱼浮标）。
--
-- ── ③ PE 的 ai / localAI 是内联结构体，不能当数组读（重要）───────────────────
--   Projectile.cs:463  public Float_FixedArray_3 ai;   ← 定长内联，不是托管 float[]
--   array_at 拿不到，必须 get_field_raw(field, proj, 12) 取 12 字节，
--   再 string.unpack("<f", raw, idx*4+1) 按小端 float 解。
--   桌面端才是托管 float[]，走 array_at(..., "float")。
--
-- ── ④ 选择性收线：为了配合 10 倍浮标 ─────────────────────────────────────────
--   原版收线是「回收本地玩家全部 bobber」，10 枚浮标会被一次全收走。
--   做法：检测到上钩后，先把「未上钩且等待中」的浮标临时 bobber=false，
--   再按使用键 —— 原版只会回收真正上钩的那一枚；收完在 postfix 里恢复。
--
-- ── ⑤ 血月不钓怪：直接跳过敌人生成那一步 ─────────────────────────────────────
--   PC 源码 Projectile.cs:20927
--     private void FishingCheck_RollEnemySpawns(ref FishingAttempt fisher)
--     条件：!inLava && !inHoney && Main.bloodMoon && !Main.dayTime
--     结果：fisher.rolledEnemySpawn = 620/621/586/587/618（硬核另加 618，红史莱姆 682）
--   在 prefix 里 return true 跳过它 → rolledEnemySpawn 保持 0 →
--   后续 FishingCheck_RollItemDrop 正常跑 → 钓到的是正常鱼。
--   注：ref struct 参数在 Lua 侧是副本，改不动字段，所以只能「整段跳过」，
--       不能按 ID 精确筛选。效果上用户列的 587/586/618/621/622/623/620 全覆盖。
--
-- ── 与合集里已有钩子的关系 ───────────────────────────────────────────────────
--   Player.ItemCheck 已被「巅峰时代」「召神」各挂一个钩子；Projectile.NewProjectile
--   已被「星神」「泰拉刃」挂过。LuaLoader 用 hook_slots 存多钩子（push_back），
--   支持链式共存。本模块的两个回调第一行都判开关，关着时直接 return，零副作用。
-- ============================================================================
_G.fh_setup, _G.fh_cleanup, _G.fh_set_enabled, _G.fh_is_enabled = (function()
    local P     = mod.patch
    local hooks = {}

    -- ---------- 配置 ----------
    local EXTRA_COPIES    = 9      -- 额外复制 9 枚 => 固定 10 倍
    local SPREAD_STEP     = 0.10   -- 相邻副本速度夹角（弧度，约 5.7°）
    local MAX_HIDDEN      = 64     -- 最多同时隐藏多少枚浮标
    local AI_STYLE_BOBBER = 61     -- 钓鱼浮标的 aiStyle
    local CAST_CD_FRAMES  = 3      -- 抛竿冷却帧数（15 -> 3，缩短收完后的空窗期）

    local fh_on   = false          -- 总开关
    local failed  = false
    local H       = {}

    -- ---------- 运行状态 ----------
    local duplicating    = false   -- 复制防重入（#129）
    local fishing        = false   -- 是否已进入钓鱼会话（见过浮标）
    local cast_cd        = 0
    local hidden         = {}      -- 本帧被临时隐藏的浮标（retain 过的句柄，#133）
    local selective_reel = false   -- v8.9.79：拿不到 active 字段时关掉选择性收线（降级）
    -- v8.9.75：看门狗。水面还留着浮标、但长时间没有鱼咬钩时，强制收线重抛。
    --   原因：浮标可能卡在岸边/墙里、或落点水域根本没有鱼，这种浮标永远等不到咬钩，
    --   也不会自己消失。以前「只要有浮标就不收竿」，于是一卡就是永远，表现为
    --   「钓久了突然不收了」。
    -- v8.9.79：选择性收线的正确做法 —— 只「暂停」其余浮标几帧，不隐藏、不作废。
    --   原理：原版收线是「玩家按下使用键 → 所有属于他的浮标自己死」。所以想只收一枚，
    --   就必须在那一刻让其余浮标暂时不活跃（active=false），等收线动画过去再恢复。
    --   之前两种做法都不对：
    --     · bobber=false 让它 AI 走别的分支，恢复后状态已坏 → 死浮标堆积 → 卡住；
    --     · active 直接作废（v8.9.78）→ 10 枚一次全没 → 变成「一次收竿再抛 10 杆」。
    local resume_frames = 0
    local RESUME_DELAY  = 3         -- 暂停 3 帧（约 50ms）后恢复
    local idle_frames  = 0
    local IDLE_LIMIT   = 60 * 8     -- v8.9.77：8 秒没咬钩就重来一次（原 40 秒）
    local logged         = false

    -- ---------- 开关持久化 ----------
    local function read_on()
        local ok, raw = pcall(mod.read_file, "fh_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:sub(1, 1) == "1"
    end
    local function write_on(v) pcall(mod.write_file, "fh_en.txt", v and "1" or "0") end

    -- ---------- 小工具 ----------
    local function try_method(ty, name, argc)
        local ok, m = pcall(P.get_method, ty, name, argc)
        if ok then return m end
        return nil
    end
    local function try_field(ty, name)
        local ok, f = pcall(P.get_field, ty, name)
        if ok then return f end
        return nil
    end
    -- 字段查找带父类回溯（#138）
    local function find_field(ty, name)
        local cur, guard = ty, 0
        while cur and guard < 16 do
            local f = try_field(cur, name)
            if f then return f end
            local okp, parent = pcall(P.get_parent, cur)
            if not okp then return nil end
            cur = parent
            guard = guard + 1
        end
        return nil
    end

    local function gval(field, inst, ty, default)
        if not field then return default end
        local ok, v = pcall(P.get_field_value, field, inst, ty)
        if not ok or v == nil then return default end
        return v
    end
    local function gint(field, inst, default) return gval(field, inst, "int32", default) end
    local function gbool(field, inst, default) return gval(field, inst, "bool", default) end
    local function gset(field, inst, value, ty)
        if not field then return false end
        return (pcall(P.set_field_value, field, inst, value, ty))
    end

    -- 读弹幕 ai / localAI 第 idx 个 float（跨平台，#132）
    local function proj_ai(proj, field, idx)
        if not proj or not field then return nil end
        if mod.platform == "android" then
            local ok, raw = pcall(P.get_field_raw, field, proj, 12)
            if not ok or type(raw) ~= "string" or #raw < idx * 4 + 4 then return nil end
            local okf, v = pcall(string.unpack, "<f", raw, idx * 4 + 1)
            if okf and type(v) == "number" then return v end
            return nil
        end
        local ok, arr = pcall(P.get_field_value, field, proj, "object")
        if not ok or not arr then return nil end
        local oka, v = pcall(P.array_at, arr, idx, "float")
        if oka and type(v) == "number" then return v end
        return nil
    end

    local function local_player()
        if H.my_player then
            return gint(H.my_player, nil, nil)
        end
        if H.get_my_player then
            local ok, v = pcall(P.invoke, H.get_my_player)
            if ok and type(v) == "number" then return v end
        end
        return nil
    end

    local function selected_item_index(player)
        if H.get_selected_item then
            local ok, v = pcall(P.invoke, H.get_selected_item, player)
            if ok and type(v) == "number" then return v end
            return nil
        end
        if H.selected_item then
            return gint(H.selected_item, player, nil)
        end
        return nil
    end

    local function proj_array()
        if not H.projectile then return nil end
        local ok, arr = pcall(P.get_field_value, H.projectile, nil, "object")
        if ok then return arr end
        return nil
    end

    -- 血月 + 夜晚（#：Main.dayTime / Main.bloodMoon 都是 static bool 字段）
    local function blood_moon_night()
        if gbool(H.blood_moon, nil, false) ~= true then return false end
        if gbool(H.day_time, nil, false) == true then return false end
        return true
    end

    -- 浮标是否已上钩
    local function biting(proj)
        if not proj or not H.ai or not H.local_ai then return false end
        local a0 = proj_ai(proj, H.ai, 0)
        local a1 = proj_ai(proj, H.ai, 1)
        local l1 = proj_ai(proj, H.local_ai, 1)
        return a0 ~= nil and a0 == 0.0
           and a1 ~= nil and a1 < 0.0
           and l1 ~= nil and l1 ~= 0.0
    end

    -- ---------- 扫描本地玩家的浮标：返回 (数量, 是否有鱼上钩) ----------
    local function scan_bobbers(my)
        local count, bite = 0, false
        if not H.ai_style then return count, bite end
        local arr = proj_array()
        if not arr then return count, bite end
        local okn, n = pcall(P.array_length, arr)
        if not okn or type(n) ~= "number" then return count, bite end
        for i = 0, n - 1 do
            local oko, proj = pcall(P.array_at, arr, i)
            if oko and proj then
                if gint(H.ai_style, proj, -1) == AI_STYLE_BOBBER then
                    local owner_ok  = (not H.owner)  or gint(H.owner,  proj, -999) == my
                    local active_ok = (not H.active) or gbool(H.active, proj, false)
                    if owner_ok and active_ok then
                        count = count + 1
                        if biting(proj) then bite = true end
                    end
                end
            end
        end
        return count, bite
    end

    -- ---------- 隐藏 / 恢复未上钩的浮标 ----------
    local function hide_waiting(my)
        hidden = {}
        if not H.active or not H.ai_style or not H.ai then return end
        local arr = proj_array()
        if not arr then return end
        local okn, n = pcall(P.array_length, arr)
        if not okn or type(n) ~= "number" then return end
        for i = 0, n - 1 do
            local oko, proj = pcall(P.array_at, arr, i)
            if oko and proj and gint(H.ai_style, proj, -1) == AI_STYLE_BOBBER then
                local owner_ok  = (not H.owner)  or gint(H.owner,  proj, -999) == my
                local active_ok = (not H.active) or gbool(H.active, proj, false)
                if owner_ok and active_ok then
                    local a0 = proj_ai(proj, H.ai, 0)
                    if a0 ~= nil and a0 == 0.0 and not biting(proj) then
                        if gset(H.active, proj, false, "bool") then
                            if #hidden < MAX_HIDDEN then
                                local okr, kept = pcall(P.retain, proj)
                                if okr and kept then
                                    hidden[#hidden + 1] = kept
                                else
                                    gset(H.active, proj, true, "bool")
                                end
                            else
                                gset(H.active, proj, true, "bool")
                            end
                        end
                    end
                end
            end
        end
    end

    local function restore_hidden()
        if #hidden == 0 then return end
        local list = hidden
        hidden = {}
        for i = 1, #list do
            local proj = list[i]
            if proj then
                -- 弹幕槽可能已被复用，恢复前再确认还是浮标（#134）
                if (not H.ai_style) or gint(H.ai_style, proj, -1) == AI_STYLE_BOBBER then
                    gset(H.active, proj, true, "bool")
                end
            end
        end
    end

    -- ============================================================
    -- 钩 1：Player.ItemCheck（prefix 自动抛竿/收线，postfix 恢复浮标）
    -- ============================================================
    local function on_item_check_pre(inst, args, result)
        -- v8.9.79：暂停中的浮标要等收线动作走完再恢复（3 帧）。
        --   提前恢复 = 恢复后又被原版一起收走；不恢复 = 它们一直停摆。
        if resume_frames > 0 then
            resume_frames = resume_frames - 1
            if resume_frames == 0 then restore_hidden() end
        elseif #hidden > 0 then
            restore_hidden()      -- 异常遗留的兜底
        end
        if not fh_on or not inst then return false end

        local my = local_player()
        if not my or my < 0 then return false end
        if gint(H.who_am_i, inst, -1) ~= my then return false end


        local sel = selected_item_index(inst)
        if not sel or sel < 0 then return false end
        local oko, inv = pcall(P.get_field_value, H.inventory, inst, "object")
        if not oko or not inv then return false end
        local okn, invn = pcall(P.array_length, inv)
        if not okn or sel >= invn then return false end
        local oki, item = pcall(P.array_at, inv, sel)
        if not oki or not item then return false end

        if gint(H.fishing_pole, item, 0) <= 0 then
            fishing = false           -- 手上没鱼竿：结束本次自动钓鱼会话
            return false
        end

        local count, bite = scan_bobbers(my)
        count = count + #hidden     -- v8.9.79：暂停中的浮标也算在场，避免误判成「没浮标了」去重抛
        if count > 0 then
            fishing = true
            -- 有鱼上钩且当前没在挥杆：按使用键，原版自动收线交鱼
            if bite and gint(H.item_anim, inst, 0) <= 0 then
                idle_frames = 0
                if selective_reel then hide_waiting(my) end   -- 只暂停其余浮标，收完再恢复
                resume_frames = RESUME_DELAY
                gset(H.control_use, inst, true, "bool")
                return false
            end
            if bite then
                idle_frames = 0
                return false
            end
            -- v8.9.75：看门狗 —— 浮标还在，但太久没动静就强制收线。
            --   收完这一杆浮标消失，下一轮会按正常流程重新抛。
            idle_frames = idle_frames + 1
            if idle_frames >= IDLE_LIMIT and gint(H.item_anim, inst, 0) <= 0 then
                idle_frames = 0
                if selective_reel then hide_waiting(my) end
                gset(H.control_use, inst, true, "bool")
            end
            return false
        end

        idle_frames = 0
        -- 场上没浮标：只有进过钓鱼会话才自动抛竿（第一次仍需手动抛一杆）
        if not fishing then return false end
        if cast_cd > 0 then
            cast_cd = cast_cd - 1
            return false
        end
        cast_cd = CAST_CD_FRAMES
        if gint(H.item_anim, inst, 0) > 0 then return false end

        gset(H.control_use, inst, true, "bool")
        return false
    end

    local function on_item_check_post(inst, args, result)
        -- v8.9.79：正常的恢复交给 pre 里的倒计时；这里只在关闭功能时兜底恢复。
        if not fh_on then restore_hidden() end
    end

    -- ============================================================
    -- 钩 2：Projectile.NewProjectile（10 倍浮标）
    -- ============================================================
    local function dup_call(args, sx, sy)
        local n = #args
        local dup = {}
        for i = 1, n do dup[i] = args[i] end
        dup[4] = sx                     -- SpeedX
        dup[5] = sy                     -- SpeedY
        local oko, r = pcall(P.invoke, H.new_proj, table.unpack(dup, 1, n))
        if not oko then return false end
        return r
    end

    local function on_new_proj(inst, args, result)
        if not fh_on or duplicating then return end
        if not args or result == nil then return end
        local idx = result
        if type(idx) ~= "number" or idx < 0 then return end

        local arr = proj_array()
        if not arr then return end
        local oko, proj = pcall(P.array_at, arr, idx)
        if not oko or not proj then return end
        if gbool(H.bobber, proj, false) ~= true then return end      -- 只处理钓鱼浮标

        local my = local_player()
        if not my or my < 0 then return end
        if args[9] ~= my then return end                             -- 只处理本地玩家抛的

        local sx, sy = args[4], args[5]
        if type(sx) ~= "number" or type(sy) ~= "number" then return end

        duplicating = true
        local okr, err = pcall(function()
            for j = 0, EXTRA_COPIES - 1 do
                -- 对称扇形：(j - (N-1)/2) * step
                local ang = (j - (EXTRA_COPIES - 1) * 0.5) * SPREAD_STEP
                local c, s = math.cos(ang), math.sin(ang)
                local nsx = sx * c - sy * s
                local nsy = sx * s + sy * c
                if dup_call(args, nsx, nsy) == false then break end
            end
        end)
        duplicating = false

        if not okr then
            mod.warn("[自动钓鱼] 复制鱼钩失败: " .. tostring(err))
            return
        end
        if not logged then
            logged = true
            mod.info(string.format("[自动钓鱼] 10 倍鱼钩已生效 (owner=%d type=%d)",
                my, args[6] or -1))
        end
    end

    -- ============================================================
    -- 钩 3：Projectile.FishingCheck_RollEnemySpawns（血月不钓怪）
    --   方法体第一行就是 !bloodMoon || dayTime 时 return，
    --   我们只需在「血月夜晚」这一种情况下跳过它，
    --   跳过后 rolledEnemySpawn 保持 0，原版接着走正常鱼掉落。
    -- ============================================================
    local function on_roll_enemy(inst, args, result)
        if not fh_on then return end
        if not blood_moon_night() then return end
        return true
    end

    -- ---------- 绑定 ----------
    local function bind()
        local okM, T_Main = pcall(P.get_type, "Terraria", "Main")
        local okP, T_Player = pcall(P.get_type, "Terraria", "Player")
        local okI, T_Item = pcall(P.get_type, "Terraria", "Item")
        local okJ, T_Proj = pcall(P.get_type, "Terraria", "Projectile")
        local okE, T_Entity = pcall(P.get_type, "Terraria", "Entity")
        if not (okM and okP and okI and okJ) then
            mod.error("[自动钓鱼] 取不到 Terraria 核心类型")
            return false
        end

        -- 本地玩家编号
        H.my_player = try_field(T_Main, "myPlayer")
        if not H.my_player then
            H.get_my_player = try_method(T_Main, "get_myPlayer", 0)
        end

        -- Player 侧字段
        H.get_selected_item = try_method(T_Player, "get_selectedItem", 0)
        if not H.get_selected_item then
            H.selected_item = try_field(T_Player, "selectedItem")
        end
        H.who_am_i    = (okE and find_field(T_Entity, "whoAmI")) or find_field(T_Player, "whoAmI")
        H.inventory   = find_field(T_Player, "inventory")
        H.control_use = find_field(T_Player, "controlUseItem")
        H.item_anim   = find_field(T_Player, "itemAnimation")

        -- Item 侧
        H.fishing_pole = find_field(T_Item, "fishingPole")

        -- 弹幕侧
        H.projectile = try_field(T_Main, "projectile")
        H.active     = find_field(T_Proj, "active")
        H.owner      = find_field(T_Proj, "owner")
        H.ai_style   = find_field(T_Proj, "aiStyle")
        H.bobber     = find_field(T_Proj, "bobber")
        H.ai         = find_field(T_Proj, "ai")
        H.local_ai   = find_field(T_Proj, "localAI")

        -- 血月 / 昼夜（都是 static bool 字段）
        H.blood_moon = try_field(T_Main, "bloodMoon")
        H.day_time   = try_field(T_Main, "dayTime")

        -- 方法
        H.new_proj  = try_method(T_Proj, "NewProjectile", 13) or try_method(T_Proj, "NewProjectile")
        H.item_check = try_method(T_Player, "ItemCheck", 0) or try_method(T_Player, "ItemCheck")
        H.roll_enemy = try_method(T_Proj, "FishingCheck_RollEnemySpawns", 1)

        -- 关键字段缺一个就整体不启用（宁可没有，不要半坏）
        if not (H.inventory and H.fishing_pole and H.control_use and H.item_anim
                and H.projectile and H.ai_style) then
            mod.error("[自动钓鱼] 缺关键字段，功能未启用")
            return false
        end
        if not H.item_check then
            mod.error("[自动钓鱼] 取不到 Player.ItemCheck，功能未启用")
            return false
        end
        if not H.active then
            mod.warn("[自动钓鱼] 取不到 Projectile.active，选择性收线关闭（10 倍浮标会一次性被收走）")
        end
        selective_reel = (H.active ~= nil)
        return true
    end

    -- ---------- 生命周期 ----------
    local function fh_setup()
        if failed then return end
        fh_on = read_on()
        if not bind() then failed = true return end

        local function add(method, spec, label)
            if not method then
                mod.warn("[自动钓鱼] 缺方法，跳过: " .. label)
                return
            end
            local ok, h = pcall(P.install_hook, method, spec)
            if ok and h then
                hooks[#hooks + 1] = h
            else
                mod.warn("[自动钓鱼] 装钩子失败: " .. label)
            end
        end

        add(H.item_check, { prefix = on_item_check_pre, postfix = on_item_check_post }, "Player.ItemCheck")
        add(H.new_proj,   { postfix = on_new_proj },                                   "Projectile.NewProjectile")
        add(H.roll_enemy, { prefix = on_roll_enemy },                                  "FishingCheck_RollEnemySpawns")

        mod.info(string.format("[自动钓鱼] 就绪（开启=%s / 10倍 / 选择性收线=%s / 血月不钓怪=%s / 钩子 %d 个）",
            fh_on and "是" or "否",
            selective_reel and "开" or "关",
            (H.roll_enemy and H.blood_moon and H.day_time) and "开" or "关",
            #hooks))
    end

    local function fh_cleanup()
        fh_on      = false
        fishing    = false
        cast_cd    = 0
        duplicating = false
        logged     = false
        restore_hidden()
        hidden = {}
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end

    local function fh_set_enabled(v)
        fh_on = v and true or false
        write_on(fh_on)
        if not fh_on then
            fishing = false
            cast_cd = 0
            restore_hidden()
            hidden = {}
        end
    end
    local function fh_is_enabled() return fh_on end

    return fh_setup, fh_cleanup, fh_set_enabled, fh_is_enabled
end)()


-- ============================================================================
-- 第三十七部分：召唤物不消耗（v8.7.0）
--   开关名：召唤物不消耗（≥2个）　默认开启　位置在「药水常驻Buff（≥10瓶）」下面
--   播报：开「生命不息，战斗不止⊙︿⊙」 / 关「快速肝召唤物材料吧(·へ·)」
--
-- ── 覆盖范围（共 22 种，PE 1.4.5.8 全部召唤物）──────────────────────────────
--   Boss：史莱姆王冠 560、可疑眼球 43、蠕虫诱饵 70、血腥脊椎 1331、憎恶之蜂 1133、
--         鹿华 5120、明胶水晶 4988、机械蠕虫 556、机械魔眼 544、机械骷髅头 557、
--         奥库瑞姆剃刀 5334、丛林蜥蜴电池 1293、松露虫 2673、七彩草蛉 4961、
--         天界符 3601
--   事件：血泪 4271、哥布林战旗 361、海盗地图 1315、日耀碑牌 2767、
--         水晶雪球 602、南瓜月勋章 1844、调皮礼物 1958
--
--   ⚠ 奥库瑞姆剃刀（Ocram's Razor）的坑：PE 的 ItemID 常量叫 **MechdusaSummon**，
--     不叫 OcramsRazor —— 按名字搜 Razor 只会命中 Razorpine / RazorbladeTyphoon，
--     会误判成「1.4 已移除」。实际它在 Internal Item ID 5334，
--     对应用 `NPC.SpawnMechQueen`（机械美杜莎），
--     也出现在 Player.ItemCheck_UseBossSpawners 的类型白名单里。
--
-- ── 为什么不用 Hook ConsumeItem ──────────────────────────────────────────────
--   PE 的消耗有两条路：Player.ConsumeItem(int,bool,bool) 和 ItemCheck 内部的直接扣减。
--   实测 Player.cs 里 ConsumeItem 只有 4 个调用点，召唤物并不走它 ——
--   光钩 ConsumeItem 会漏掉大部分。所以改用「前后对比」这个与实现无关的办法：
--     prefix  记下当前手持槽位的 (type, stack)
--     postfix 再看这个槽位：如果 type 没变、stack 恰好少了 1，就把它写回去
--   这样不管原版走哪条路径扣的，都能补回来；而且只在「原本 >= 2」时才记，
--   数量为 1 的最后一个是正常消耗掉的，不会让玩家卡着不能收尾。
--
--   v8.8.1 修正：不能只看手持槽。松露虫（TruffleWorm 2673）不是普通召唤物，
--   它是**鱼饵** —— 手持它抛竿，鱼咬钩时由 ItemCheck_CheckFishingBobber_ConsumeBait
--   把饵扣掉，而原版是从背包里找 type == localAI[2] 的槽去扣，不一定在手持槽。
--   所以改成：扫全背包，按 type 统计总数，>= 2 的逐槽记快照，postfix 逐槽对比恢复。
-- ============================================================================
_G.cs_setup, _G.cs_cleanup = (function()
    local P      = mod.patch
    local hooks  = {}
    local H      = {}
    local failed = false

    -- ---------- 召唤物 ID 集合 ----------
    local SPAWN = {}
    do
        local ids = {
            560,   -- 史莱姆王冠     SlimeCrown
            43,    -- 可疑眼球       SuspiciousLookingEye
            70,    -- 蠕虫诱饵       WormFood
            1331,  -- 血腥脊椎       BloodySpine
            1133,  -- 憎恶之蜂       Abeemination
            5120,  -- 鹿华           DeerThing
            4988,  -- 明胶水晶       QueenSlimeCrystal
            556,   -- 机械蠕虫       MechanicalWorm
            544,   -- 机械魔眼       MechanicalEye
            557,   -- 机械骷髅头     MechanicalSkull
            1293,  -- 丛林蜥蜴电池   LihzahrdPowerCell
            2673,  -- 松露虫         TruffleWorm
            4961,  -- 七彩草蛉       EmpressButterfly
            3601,  -- 天界符         CelestialSigil
            4271,  -- 血泪           BloodMoonStarter
            361,   -- 哥布林战旗     GoblinBattleStandard
            1315,  -- 海盗地图       PirateMap
            2767,  -- 日耀碑牌       SolarTablet
            602,   -- 水晶雪球       SnowGlobe
            1844,  -- 南瓜月勋章     PumpkinMoonMedallion
            1958,  -- 调皮礼物       NaughtyPresent
            5334,  -- 奥库瑞姆剃刀   MechdusaSummon（机械美杜莎，1.4.4+ 专属种子 boss）
        }
        for i = 1, #ids do SPAWN[ids[i]] = true end
    end

    -- v8.8.1：改成全背包快照。原来只盯手持槽，漏了「鱼饵型」召唤物。
    --   松露虫（TruffleWorm 2673）不是普通召唤物，它是**鱼饵**：
    --   手持它抛竿，鱼咬钩时由 Player.ItemCheck_CheckFishingBobber_ConsumeBait 扣掉，
    --   而原版是从背包里找 type == localAI[2] 的槽去扣 -- 不一定是手持槽。
    --   所以要把背包里所有召唤物槽都记下来再对比。
    local saved = {}          -- { {slot, ty, stack}, ... }

    -- ---------- 小工具 ----------
    local function try_field(ty, name)
        local ok, f = pcall(P.get_field, ty, name)
        if ok then return f end
        return nil
    end
    local function find_field(ty, name)
        local cur, guard = ty, 0
        while cur and guard < 16 do
            local f = try_field(cur, name)
            if f then return f end
            local okp, parent = pcall(P.get_parent, cur)
            if not okp then return nil end
            cur = parent
            guard = guard + 1
        end
        return nil
    end
    local function gval(field, inst, ty, default)
        if not field then return default end
        local ok, v = pcall(P.get_field_value, field, inst, ty)
        if not ok or v == nil then return default end
        return v
    end
    local function gint(field, inst, default) return gval(field, inst, "int32", default) end
    local function gset(field, inst, value, ty)
        if not field then return false end
        return (pcall(P.set_field_value, field, inst, value, ty))
    end

    local function is_on()
        local G = _G.ms_gates
        if G then return G.is("cs") end
        return true
    end

    local function local_player()
        if H.my_player then return gint(H.my_player, nil, nil) end
        if H.get_my_player then
            local ok, v = pcall(P.invoke, H.get_my_player)
            if ok and type(v) == "number" then return v end
        end
        return nil
    end

    local function selected_index(player)
        if H.get_selected_item then
            local ok, v = pcall(P.invoke, H.get_selected_item, player)
            if ok and type(v) == "number" then return v end
            return nil
        end
        if H.selected_item then return gint(H.selected_item, player, nil) end
        return nil
    end

    local function inv_of(inst)
        if not H.inventory then return nil end
        local ok, inv = pcall(P.get_field_value, H.inventory, inst, "object")
        if ok then return inv end
        return nil
    end
    local function item_at(inv, i)
        if not inv then return nil end
        local ok, it = pcall(P.array_at, inv, i)
        if ok then return it end
        return nil
    end

    -- ---------- Hook：Player.ItemCheck ----------
    -- 前后对比法：prefix 给背包里每个「召唤物槽」拍个快照，postfix 看谁少了 1 就补回来。
    -- 与「原版走哪条路径扣的」无关，所以普通召唤物的 stack--、鱼饵型的 ConsumeBait
    -- 都能覆盖。判定门槛是「该 type 的总数 >= 2」，数量为 1 的最后一个照常消耗。
    local function on_pre(inst, args, result)
        saved = {}
        if not inst then return false end
        if not is_on() then return false end
        local my = local_player()
        if my == nil or gint(H.who_am_i, inst, -1) ~= my then return false end
        local inv = inv_of(inst)
        if not inv then return false end
        local okn, n = pcall(P.array_length, inv)
        if not okn or type(n) ~= "number" then return false end

        -- 快速预判：手持既不是召唤物、也不是鱼竿时，几乎不可能消耗召唤物
        -- （普通召唤物靠「手持使用」，鱼饵型的松露虫要靠「手持鱼竿抛竿」）。
        -- 这一步让平时手持武器/工具时的开销降到 2 次字段读，不用扫全背包。
        local sel = selected_index(inst)
        if sel and sel >= 0 and sel < n then
            local held = item_at(inv, sel)
            if held then
                local hty = gint(H.item_type, held, 0)
                local is_spawn = (hty and SPAWN[hty]) and true or false
                local is_pole = H.fishing_pole and (gint(H.fishing_pole, held, 0) > 0)
                if not is_spawn and not is_pole then return false end
            end
        end

        -- 第一遍：按 type 统计总数（同一个召唤物可能分散在多个槽里）
        local total = {}
        for i = 0, n - 1 do
            local it = item_at(inv, i)
            if it then
                local ty = gint(H.item_type, it, 0)
                if ty and SPAWN[ty] then
                    local st = gint(H.item_stack, it, 0) or 0
                    total[ty] = (total[ty] or 0) + st
                end
            end
        end

        -- 第二遍：总数 >= 2 的，逐槽记快照
        for i = 0, n - 1 do
            local it = item_at(inv, i)
            if it then
                local ty = gint(H.item_type, it, 0)
                if ty and SPAWN[ty] and (total[ty] or 0) >= 2 then
                    local st = gint(H.item_stack, it, 0) or 0
                    if st > 0 then
                        saved[#saved + 1] = { i, ty, st }
                    end
                end
            end
        end
        return false
    end

    local function on_post(inst, args, result)
        if #saved == 0 then return end
        local list = saved
        saved = {}
        if not is_on() then return end
        local inv = inv_of(inst)
        if not inv then return end
        for k = 1, #list do
            local slot, ty, st = list[k][1], list[k][2], list[k][3]
            local it = item_at(inv, slot)
            if it then
                local t2 = gint(H.item_type, it, 0)
                local now = gint(H.item_stack, it, 0)
                if t2 == ty and now and now == st - 1 then
                    gset(H.item_stack, it, st, "int32")
                end
            end
        end
    end

    -- ---------- 绑定 ----------
    local function bind()
        local okM, T_Main   = pcall(P.get_type, "Terraria", "Main")
        local okP, T_Player = pcall(P.get_type, "Terraria", "Player")
        local okI, T_Item   = pcall(P.get_type, "Terraria", "Item")
        local okE, T_Entity = pcall(P.get_type, "Terraria", "Entity")
        if not (okM and okP and okI) then
            mod.error("[召唤物不消耗] 取不到 Terraria 核心类型")
            return false
        end
        H.my_player = try_field(T_Main, "myPlayer")
        if not H.my_player then
            H.get_my_player = pcall(P.get_method, T_Main, "get_myPlayer", 0) and
                              select(2, pcall(P.get_method, T_Main, "get_myPlayer", 0)) or nil
        end
        local ok_get, m_get = pcall(P.get_method, T_Player, "get_selectedItem", 0)
        if ok_get then H.get_selected_item = m_get end
        if not H.get_selected_item then H.selected_item = try_field(T_Player, "selectedItem") end

        H.who_am_i   = (okE and find_field(T_Entity, "whoAmI")) or find_field(T_Player, "whoAmI")
        H.inventory  = find_field(T_Player, "inventory")
        H.item_type  = find_field(T_Item, "type")
        H.item_stack = find_field(T_Item, "stack")
        H.fishing_pole = find_field(T_Item, "fishingPole")   -- 快速预判用

        local ok_ic, m_ic = pcall(P.get_method, T_Player, "ItemCheck", 0)
        if not ok_ic then m_ic = nil end
        if not m_ic then
            local ok2, m2 = pcall(P.get_method, T_Player, "ItemCheck")
            if ok2 then m_ic = m2 end
        end
        H.item_check = m_ic

        if not (H.inventory and H.item_type and H.item_stack and H.item_check) then
            mod.error("[召唤物不消耗] 缺关键句柄（inventory / Item.type / Item.stack / ItemCheck）")
            return false
        end
        return true
    end

    -- ---------- 生命周期 ----------
    local function cs_setup()
        if failed then return end
        if not bind() then failed = true return end
        local ok, h = pcall(P.install_hook, H.item_check, {
            prefix = on_pre, postfix = on_post,
        })
        if not ok or not h then
            mod.warn("[召唤物不消耗] ItemCheck 钩子安装失败")
            failed = true
            return
        end
        hooks[#hooks + 1] = h
        mod.info("[召唤物不消耗] 就绪（覆盖 21 种召唤物，数量 >= 2 时不消耗）")
    end

    local function cs_cleanup()
        saved = {}
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end

    return cs_setup, cs_cleanup
end)()

function setup()
    -- ========================================================================
    -- v8.8.0：分帧启动
    -- ------------------------------------------------------------------------
    -- 以前 42 个模块在这里一口气跑完（约 320ms），全部钩子/注册/全局对象
    -- 集中在同一瞬间完成 —— 主菜单刚起来那 1~2 秒正好撞上。
    -- 现在只留「必须赶在加载期完成」的物品注册，其余排队，
    -- 由 Main.Update 每帧启动 1 个，单帧压力从 320ms 降到约 8ms。
    -- ========================================================================

    -- ① 必须第一时间完成的（这 4 类不能进队列，进了就会丢东西）
    --   · 新物品注册：内核要求加载期登记
    --   · 缩放扩展：它钩的是 XNAWorldCameraSettings.get_MaxPixelScale —— 这玩意儿
    --     在**加载画面阶段就会被调用**来算画面缩放。分帧排到第 19 帧才装的话，
    --     前面这一小段用的是原版值，表现就是「刚进游戏画面很小，进主界面才变回来」。
    if _G.ms_wand_setup then pcall(_G.ms_wand_setup) end
    if _G.ms_dff_setup  then pcall(_G.ms_dff_setup)  end
    if _G.ms_fbw_setup  then pcall(_G.ms_fbw_setup)  end
    if zm_setup         then pcall(zm_setup)         end   -- v8.8.3
    --   · 原版配方扩展：mod.recipe.add 是「加载期登记」，内核随后建配方表；
    --     分帧排到第 30 多帧才登记的话，这 114 条配方会直接丢掉（游戏里看不到）。
    if _G.ms_gates.is("rcp") then
        if _G.ms_rcp_clean and _G.ms_rcp_clean.setup then
            pcall(_G.ms_rcp_clean.setup)
        end
        if _G.ms_rcp_setup then pcall(_G.ms_rcp_setup) end
    end
    --   · 遗忘之物：它的 setup 里有三样「只跑一次」的东西，晚装就永远错过 ——
    --       ① ItemID.Sets..cctor          静态构造，启动期执行一次
    --       ② PrefixLegacy.ItemSets..cctor 同上
    --       ③ ItemDropDatabase.Populate   在 Main.Initialize() 里执行一次
    --     另外还有 setup_manual_recipes()（手动登记配方）。
    --     它默认关闭（读不到 fi_en.txt 就是 false，直接 return），所以提前几乎零成本。
    if fi_setup then pcall(fi_setup) end   -- v8.8.3

    -- ② 其余模块排进队列，顺序与原 setup 完全一致（不破坏模块间依赖）
    local B = _G.BOOT
    B.q, B.i, B.done, B.n = {}, 1, false, 0
    -- v9.2.1 转正：启动分帧的诊断区间（DIAG_LO / DIAG_HI）已移除，模块按顺序全部启动
    local function Q(name, fn)
        if type(fn) == "function" then
            B.q[#B.q + 1] = { name, fn }
        end
    end

    Q("summon_setup",  summon_setup)
    Q("jr_setup",      jr_setup)
    Q("mp_setup",      mp_setup)
    Q("vm_setup",      vm_setup)
    Q("bd_setup",      bd_setup)
    Q("lp_setup",      lp_setup)
    Q("ps_setup",      ps_setup)
    Q("ab_setup",      ab_setup)
    Q("star_setup",    star_setup)
    -- v8.9.15：dot 模块（伤害数字修正）在 v3.2.0 就宣告删除，实际一直留在启动队列里，
    --   还挂着 CombatText.NewText / GetHurtByDebuff / Main.Update 三个钩子。这里彻底摘掉。
    -- Q("dot_setup",     dot_setup)
    Q("peak_setup",    peak_setup)
    Q("sn_setup",      sn_setup)
    Q("py_setup",      py_setup)
    Q("rv_setup",      rv_setup)
    Q("lk_setup",      lk_setup)
    Q("lm_setup",      lm_setup)
    Q("zs_setup",      zs_setup)
    Q("ag_setup",      ag_setup)
    Q("EXT.sn.setup",  EXT.sn and EXT.sn.setup)
    Q("EXT.sx.setup",  EXT.sx and EXT.sx.setup)
    Q("EXT.mm.setup",  EXT.mm and EXT.mm.setup)
    Q("EXT.lh.setup",  EXT.lh and EXT.lh.setup)
    -- 起源重构（v10.1.0 并入「拟态·起源重构 v3.0.0」，默认关闭）
    Q("EXT.om", function()
        EXT.om = require("om_entry")
        if EXT.om and EXT.om.setup then EXT.om.setup() end
    end)
    -- 全武器成长（v10.3.0 并入「全武器成长 v2.1.0」，默认关闭）
    Q("EXT.wg", function()
        EXT.wg = require("wg_switch")
        if EXT.wg and EXT.wg.setup then EXT.wg.setup() end
    end)
    -- 碎晶之链：常驻内容型模组，进世界就直接注册内容 + 装钩子，没有开关也没有播报
    Q("EXT.cr", function()
        local okc, m = pcall(require, "cr_entry")
        if okc and type(m) == "table" then
            EXT.cr = m
            if m.setup then pcall(m.setup) end
            if m.hooks_on then pcall(m.hooks_on) end
        end
    end)
    Q("af_setup",      af_setup)
    Q("dm_setup",      dm_setup)
    Q("nh_setup",      nh_setup)
    Q("ng_setup",      ng_setup)
    -- Boss 血条：要 require 一个子文件再取 setup，包一层
    Q("bossbar", function()
        bb_setup, bb_cleanup = require('bossbar_entry')
        if bb_setup then bb_setup() end
    end)
    Q("rf_setup",      _G.rf_setup)
    Q("nst_setup",     _G.nst_setup)
    Q("fh_setup",      _G.fh_setup)
    Q("cs_setup",      _G.cs_setup)

    -- 自动钓鱼机（v9.1.0 并入，来源：独立模组「自动钓鱼机」v2.1.8）
    --   装配层 afm_entry.lua 只做 boot + 掉落守卫；每帧 tick 走 Player.Update 汇合总线，
    --   不再自己 install_hook（同一方法只能挂一个回调）。常开、无开关：放下机器就工作。
    Q("EXT.afm", function()
        EXT.afm = require("afm_entry")
        if EXT.afm and EXT.afm.setup then EXT.afm.setup() end
        if EXT.afm and EXT.afm.tick then
            pu_reg_post("自动钓鱼机", function(inst) pcall(EXT.afm.tick, inst) end)
        end
    end)
    -- ③ 队列末尾：装总线。必须在所有模块注册完毕之后再装
    B.q[#B.q + 1] = { "bus_install", function()
        local okTB, errTB = pcall(tb_install)
        if not okTB then mod.error("节拍总线安装异常: " .. tostring(errTB)) end
        local okPU, errPU = pcall(pu_install)
        if not okPU then mod.error("Player.Update 汇合总线安装异常: " .. tostring(errPU)) end
        mod.info(string.format("[启动] 分帧启动完成：%d 个模块 + 总线（tb=%s pu=%s）",
            B.n, tostring(okTB), tostring(okPU)))
    end }

    -- ④ v8.9.31：所有模块在加载期一次性全部启动，不再分帧排队。
    --   用户要求：进游戏就全都有，不用等。
    local tot = #B.q
    local booted = 0
    for k = 1, tot do
        local it = B.q[k]
        B.n = k
        mod.info(string.format("[BOOT] start %d/%d %s", k, tot, tostring(it[1])))
        local ok1, err1 = pcall(it[2])
        if ok1 then
            booted = booted + 1
            mod.info(string.format("[BOOT] ok %s", tostring(it[1])))
        else
            mod.error(string.format("[BOOT] FAIL %s : %s", tostring(it[1]), tostring(err1)))
        end
    end
    B.i = tot + 1
    B.done = true
    mod.info(string.format("[启动] 一次性启动完成 %d/%d", booted, tot))

    -- 照样装 Main.Update 钩子：正常情况节拍总线已占用它，这里装不上也无所谓。
    local okT, T_Main = pcall(mod.patch.get_type, "Terraria", "Main")
    local m = nil
    if okT and T_Main then
        local okm, mm = pcall(mod.patch.get_method, T_Main, "Update", 1)
        if okm then m = mm end
        if not m then
            local okm2, mm2 = pcall(mod.patch.get_method, T_Main, "Update", 0)
            if okm2 then m = mm2 end
        end
    end

    -- 这个单独的 Main.Update 钩子（v8.9.29 引入）是节拍总线的冗余备份：
    --   总线已经占用了 Main.Update，这里大概率装不上，装不上也无所谓。
    if m then
        local okH, h = pcall(mod.patch.install_hook, m, { postfix = _G.BOOT_STEP })
        if okH and h then B.hook = h
        else mod.warn("[启动] 进世界检测钩子安装失败（已有其它通道，不影响）") end
    else
        mod.warn("[启动] Main.Update 未找到（已有其它通道，不影响）")
    end
end
-- 第十三部分：幸运儿（参考 幸运调节 LuckTunerLua v1.0.2 精简改造）
--   设置页按钮「幸运儿」：开启后每帧把 Player.luck 加成 +25；关闭立即恢复原版幸运。
--   实现（同参考模组）：Hook Player.UpdateLuck()（0参，原版每帧重算幸运的唯一入口）：
--     prefix  —— 若上帧写过，先把我们加的值减回去（得到纯原版基准，幂等、防叠加）
--     postfix —— 读基准值，开启时写入 基准+25 并记录本次加值（关闭时不写）
--   全程用模块级标量记录加值（不把玩家句柄存表，遵守借用句柄不可跨帧的约束）。
lk_setup, lk_cleanup, lk_gui = (function()
    local patch = mod.patch
    local hooks = {}
    local LUCK_ON = false
    local LUCK_BONUS = 25          -- 幸运加成值
    local luck_field = nil
    local last_bonus = 0           -- 上帧实际加进去的值（0 = 没加）

    local function read_on()
        local raw = nil
        local ok, res = pcall(mod.read_file, "luck_en.txt")
        if ok then raw = res end
        if type(raw) ~= "string" or raw == "" then return false end
        return raw:match("^%s*1") ~= nil
    end

    local function write_on(v)
        pcall(mod.write_file, "luck_en.txt", v and "1" or "0")
    end

    local function get_luck(player)
        local ok, value = pcall(patch.get_field_value, luck_field, player, "float")
        if ok then return tonumber(value) end
        return nil
    end

    local function set_luck(player, value)
        return pcall(patch.set_field_value, luck_field, player, value, "float")
    end

    local function lk_prefix(player)
        if not player then return false end
        if last_bonus ~= 0 then
            local current = get_luck(player)
            if current and math.abs(current - (current - last_bonus)) > 1e-9 then
                set_luck(player, current - last_bonus)
            end
            last_bonus = 0
        end
        return false
    end

    local function lk_postfix(player)
        if not player then return false end
        if not LUCK_ON then return false end
        local base = get_luck(player)
        if not base then return false end
        local ok = set_luck(player, base + LUCK_BONUS)
        if ok then last_bonus = LUCK_BONUS else last_bonus = 0 end
        return false
    end

    local function lk_setup()
        LUCK_ON = read_on()
        local ptype = patch.get_type("Terraria", "Player")
        if not ptype then mod.warn("幸运儿：找不到 Terraria.Player") return false end
        luck_field = patch.get_field(ptype, "luck")
        if not luck_field then mod.warn("幸运儿：找不到 Player.luck 字段") return false end
        local method = patch.get_method(ptype, "UpdateLuck", 0)
        if not method then mod.warn("幸运儿：找不到 Player.UpdateLuck()") return false end
        local ok, hook = pcall(patch.install_hook, method, {
            prefix = lk_prefix,
            postfix = lk_postfix,
        })
        if not ok then mod.warn("幸运儿：钩子安装失败 ", hook) return false end
        hooks[#hooks + 1] = hook
        return true
    end

    local function lk_cleanup()
        -- 恢复原版幸运：把还在生效的加值减掉
        last_bonus = 0
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end

    -- 设置页按钮（由 gui_settings 调用）
    local function lk_gui(g, notify, bx, by)
        if not luck_field then
            g.text("幸运儿：模块未加载")
            return
        end
        local label = LUCK_ON and "幸运儿（已开启）" or "幸运儿（已关闭）"
        local clicked
        if bx then clicked = btn_at(g, bx, by, label) else clicked = g.button(label) end
        if clicked then
            LUCK_ON = not LUCK_ON
            write_on(LUCK_ON)
            if not LUCK_ON then last_bonus = 0 end
            if notify then
                -- v2.11.16：按用户指定文案（开=幸运娃 / 关=你不再幸运）
                notify(LUCK_ON and "幸运娃，享幸运人生～(^з^)-☆"
                                or "你不再幸运|(￣3￣)|")
            end
        end
    end

    return lk_setup, lk_cleanup, lk_gui
end)()
-- ============================================================================
-- 第二十三部分：召神（切鞭协同）—— v2.11.29 并入合集，默认关闭、按钮开关
-- 需求：装备蛇形手环(6157)/衔尾蛇指环(6162)/德鲁伊蛇纹斗篷(6186) 任意一件后，
--       每挥 3 次鞭子，物品栏第 2、3、4 条鞭子一起协同攻击（原版只协同第 2 条）。
-- 机制：关原版开关 accSnakeBand 让原版「协同1条」不触发，自己复用原版计数器
--       repeatWhipSwings 与「挥到动画一半」判断时机，扫描前 3 条鞭子逐条协同
--       （传 ItemCheck_Shoot 第4参 false => 伤害自动 1/3，且不递增计数器防递归）。
-- 注意：IsAWhip 等「值句柄」是借用的、不能跨帧缓存，故每次判断鞭子前现读。
-- ============================================================================
zs_setup, zs_cleanup, zs_gui = (function()
    local patch = mod.patch
    local hooks = {}
    local ZS_ON = false
    local H = {}
    local saved_snake = false

    local function read_on()
        local raw = nil
        local ok, res = pcall(mod.read_file, "zs_en.txt")
        if ok then raw = res end
        if type(raw) ~= "string" or raw == "" then return false end
        return raw:match("^%s*1") ~= nil
    end
    local function write_on(v)
        pcall(mod.write_file, "zs_en.txt", v and "1" or "0")
    end

    local function in_world()
        if not H.f_gamemenu then return true end
        local ok, v = pcall(patch.get_field_value, H.f_gamemenu, nil, "bool")
        if ok and v ~= nil then return (v == false) end
        return true
    end

    local function read_isawhip()
        if not H.f_isawhip then return nil end
        local ok, a = pcall(patch.get_field_value, H.f_isawhip, nil, "object")
        if ok then return a end
        return nil
    end

    local function on_prefix(inst)
        if not inst then return end
        if not ZS_ON or not in_world() or not H.f_snake then
            saved_snake = false
            return
        end
        local ok, v = pcall(patch.get_field_value, H.f_snake, inst, "bool")
        saved_snake = (ok and v == true)
        if saved_snake then
            pcall(patch.set_field_value, H.f_snake, inst, false, "bool")
        end
    end

    local function on_postfix(inst)
        if not inst then return end
        if saved_snake and H.f_snake then
            pcall(patch.set_field_value, H.f_snake, inst, true, "bool")
        end
        if not ZS_ON or not saved_snake then return end
        if not in_world() then return end
        if not (H.f_repeat and H.f_anim and H.f_animmax and H.f_inv
                and H.f_whoami and H.f_shoot and H.f_isawhip
                and H.m_getsel and H.m_isair
                and H.m_getdamage and H.m_shoot) then
            return
        end
        local ok_sw, swings = pcall(patch.get_field_value, H.f_repeat, inst, "int32")
        if not ok_sw or swings == nil then return end
        if (swings % 3) ~= 0 then return end
        local ok_an, anim = pcall(patch.get_field_value, H.f_anim, inst, "int32")
        local ok_am, animmax = pcall(patch.get_field_value, H.f_animmax, inst, "int32")
        if not ok_an or not ok_am or anim == nil or animmax == nil then return end
        if anim <= 0 or anim ~= math.floor(animmax * 0.5) then return end
        local whoami = nil
        do local ok_w, w = pcall(patch.get_field_value, H.f_whoami, inst, "int32")
           if ok_w then whoami = w end end
        if whoami == nil then return end
        local inv = nil
        do local ok_i, a = pcall(patch.get_field_value, H.f_inv, inst, "object")
           if ok_i then inv = a end end
        if not inv then return end
        local sel = nil
        do local ok_s, s2 = pcall(patch.invoke, H.m_getsel, inst)
           if ok_s then sel = s2 end end
        if sel == nil then return end
        local arr_whip = read_isawhip()
        local function is_whip(item)
            if not item then return false end
            local ok_a, air = pcall(patch.invoke, H.m_isair, item)
            if ok_a and air == true then return false end
            local ok_sh, shoot = pcall(patch.get_field_value, H.f_shoot, item, "int32")
            if not ok_sh or shoot == nil or shoot <= 0 then return false end
            if not arr_whip then return false end
            local ok_w2, isw = pcall(patch.array_at, arr_whip, shoot, "bool")
            return (ok_w2 and isw == true)
        end
        local held = nil
        do local ok_h, it = pcall(patch.array_at, inv, sel)
           if ok_h then held = it end end
        if not is_whip(held) then return end
        local count = 0
        local n = nil
        do local ok_n, len = pcall(patch.array_length, inv)
           if ok_n then n = len end end
        if not n then n = 50 end
        local last = n - 1
        if last > 49 then last = 49 end
        for k = sel + 1, last do
            local it = nil
            do local ok_a, v = pcall(patch.array_at, inv, k)
               if ok_a then it = v end end
            if it and is_whip(it) then
                local dmg = nil
                do local ok_d, d = pcall(patch.invoke, H.m_getdamage, inst, it)
                   if ok_d then dmg = d end end
                if dmg ~= nil then
                    pcall(patch.invoke, H.m_shoot, inst, whoami, it, dmg, false)
                    count = count + 1
                    if count >= 3 then break end
                end
            end
        end
    end

    local function zs_setup()
        ZS_ON = read_on()
        local ok, err = pcall(function()
            local t_player = patch.get_type("Terraria", "Player")
            local t_item   = patch.get_type("Terraria", "Item")
            local t_main   = patch.get_type("Terraria", "Main")
            local t_entity = patch.get_type("Terraria", "Entity")
            local t_projid = patch.get_type("Terraria.ID", "ProjectileID")
            local t_int    = patch.get_basic_type("int32")
            local t_bool   = patch.get_basic_type("bool")
            if not (t_player and t_item and t_main and t_projid and t_int and t_bool) then
                error("关键类型缺失")
            end
            H.f_snake    = patch.get_field(t_player, "accSnakeBand")
            H.f_repeat   = patch.get_field(t_player, "repeatWhipSwings")
            H.f_anim     = patch.get_field(t_player, "itemAnimation")
            H.f_animmax  = patch.get_field(t_player, "itemAnimationMax")
            H.f_inv      = patch.get_field(t_player, "inventory")
            H.f_shoot    = patch.get_field(t_item, "shoot")
            H.f_gamemenu = patch.get_field(t_main, "gameMenu")
            H.f_whoami   = (t_entity and patch.get_field(t_entity, "whoAmI"))
                       or patch.get_field(t_player, "whoAmI")
            local sets = patch.get_inner_type(t_projid, "Sets")
            if sets then
                H.f_isawhip = patch.get_field(sets, "IsAWhip")
            end
            local p_sel = patch.get_property(t_player, "selectedItem")
            if p_sel then H.m_getsel = patch.property_get_method(p_sel) end
            local p_isair = patch.get_property(t_item, "IsAir")
            if p_isair then H.m_isair = patch.property_get_method(p_isair) end
            H.m_getdamage = patch.get_method(t_player, "GetWeaponDamage", 1)
            H.m_shoot = patch.get_method_by_param_types(
                t_player, "ItemCheck_Shoot", { t_int, t_item, t_int, t_bool })
            or patch.get_method(t_player, "ItemCheck_Shoot", 4)
            local m_itemcheck = patch.get_method(t_player, "ItemCheck", 0)
            if not m_itemcheck then error("ItemCheck 方法未找到") end
            local okh, h = pcall(patch.install_hook, m_itemcheck, {
                prefix = on_prefix, postfix = on_postfix,
            })
            if not (okh and h) then error("ItemCheck 钩子安装失败: " .. tostring(h)) end
            hooks[#hooks + 1] = h
        end)
        if not ok then mod.warn("[召神] setup 失败: " .. tostring(err)) end
    end

    local function zs_cleanup()
        saved_snake = false
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
    end

    local function zs_gui(g, notify, bx, by)
        if not H.f_snake then
            g.text("召神：模块未加载")
            return
        end
        local label = ZS_ON and "召神（已开启）" or "召神（已关闭）"
        local clicked
        if bx then clicked = btn_at(g, bx, by, label) else clicked = g.button(label) end
        if clicked then
            ZS_ON = not ZS_ON
            write_on(ZS_ON)
            if notify then
                notify(ZS_ON and "以前你叫我牢召，我不挑你理，现在你该叫我什么？( ｀⌒’)メ`"
                                or "难道我真是牢召？(;︵;)")
            end
        end
    end

    return zs_setup, zs_cleanup, zs_gui
end)()
-- ============================================================================
-- 第二十五部分：我就是箭神（独立模组 v1.0.7 并入 v2.19.2）
-- 需求：鸟妖附身符(6166) / 凤凰箭袋(6181) / 炽天使项链(6180) 任意一件的
--       「箭矢引向敌人」冷却由 1.5 秒（90 帧）缩到 0.1 秒（6 帧）。
--       设置页按钮（放在召神下面），默认关闭；开/关各有播报。
-- 机制（源码 Player.cs 核实）：装备任一件即 Player.accHarpyCharm = true，
--       此后每帧走 Update_HarpyCharm() 递减 Player.accHarpyCharmCooldown，
--       归零才调 HarpyCharmEffect() 去引箭；命中一次后回填 90 帧
--       （炽天使项链 ×0.8 = 72 帧）。本模块把该计数钳到 6 帧，幂等无副作用。
-- 挂点：主 hook Player.Update_HarpyCharm(0) postfix（只对本机玩家每帧一次）；
--       取不到时退回节拍总线 tb_reg_frame，每帧对 myPlayer 钳一次。
-- 开关：按钮式，默认关闭，持久化 ag_en.txt；门控在回调内部，钩子常驻不装卸。
-- ============================================================================
ag_setup, ag_cleanup, ag_gui, ag_set_enabled, ag_is_enabled = (function()
    local P = patch
    local H = {}
    local hook = nil
    local AG_EN = false
    local CD_FRAMES = 6          -- 6 帧 = 0.1 秒（原版 90 帧 = 1.5 秒）
    local tb_registered = false

    local function read_on()
        local ok, raw = pcall(mod.read_file, "ag_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:match("^%s*1") ~= nil
    end
    local function write_on(v)
        pcall(mod.write_file, "ag_en.txt", v and "1" or "0")
    end
    local function rd(field, inst, ty)
        if not field then return nil end
        local ok, v = pcall(P.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end

    -- 幂等钳制：只在超过 6 帧时写回 6
    local function clamp(inst)
        if not inst then return end
        local cd = rd(H.f_cd, inst, "int32")
        if type(cd) ~= "number" then return end
        if cd > CD_FRAMES then
            pcall(P.set_field_value, H.f_cd, inst, CD_FRAMES, "int32")
        end
    end

    -- 主挂点回调（Player.Update_HarpyCharm postfix）
    local function on_harpy(inst)
        if not AG_EN then return end
        clamp(inst)
    end

    -- 兜底挂点：节拍总线每帧一次
    local function bus_tick()
        if not AG_EN then return end
        local idx = rd(H.f_myplayer, nil, "int32")
        if type(idx) ~= "number" or idx < 0 then return end
        local arr = rd(H.f_playerarr, nil, "object")
        if not arr then return end
        local okA, player = pcall(P.array_at, arr, idx)
        if okA and player then clamp(player) end
    end

    local function ag_setup()
        AG_EN = read_on()
        local t_player = P.get_type("Terraria", "Player")
        local t_main   = P.get_type("Terraria", "Main")
        if not (t_player and t_main) then
            mod.warn("[箭神] 类型缺失 Player/Main")
            return false
        end
        H.f_cd        = P.get_field(t_player, "accHarpyCharmCooldown")
        H.f_myplayer  = P.get_field(t_main, "myPlayer")
        H.f_playerarr = P.get_field(t_main, "player")
        if not H.f_cd then
            mod.warn("[箭神] 找不到 Player.accHarpyCharmCooldown")
            return false
        end
        local m = P.get_method(t_player, "Update_HarpyCharm", 0)
        if m then
            local okh, h = pcall(P.install_hook, m, {
                postfix = function(inst, args, result) on_harpy(inst) end,
            })
            if okh and h then hook = h end
        end
        if not hook then
            tb_reg_frame("我就是箭神", bus_tick)
            tb_registered = true
            mod.info("[箭神] 主挂点未装上，改走节拍总线")
        end
        if not (hook or tb_registered) then
            mod.warn("[箭神] 两个挂点都没装上")
            return false
        end
        mod.info("[箭神] 已加载，状态=" .. (AG_EN and "开" or "关"))
        return true
    end

    local function ag_cleanup()
        if hook then
            pcall(function() hook:remove() end)
            hook = nil
        end
        AG_EN = false
    end
    local function ag_set_enabled(b) AG_EN = (b and true or false) end
    local function ag_is_enabled() return AG_EN end

    local function ag_gui(g, notify, bx, by)
        if not H.f_cd then
            g.text("我就是箭神：模块未加载")
            return
        end
        local label = AG_EN and "箭神（已开启）" or "箭神（已关闭）"
        local clicked
        if bx then clicked = btn_at(g, bx, by, label) else clicked = g.button(label) end
        if clicked then
            AG_EN = not AG_EN
            write_on(AG_EN)
            if notify then
                notify(AG_EN and "我已经锁定你了（-_<）"
                                or "你就是人体描边大师吧（·∪·）")
            end
        end
    end

    return ag_setup, ag_cleanup, ag_gui, ag_set_enabled, ag_is_enabled
end)()
-- ============================================================================
-- 第二十六部分：我就是哨兵神（独立模组 v1.2.1 并入 v2.19.4）
-- 需求：重型投石索(6172) / 斥候投石索(6175) / 圣殿骑士投石索(6176) /
--       皇家卫队护具(6177) 这四件饰品的「携带哨兵跟随」数量由 1 放开到多个，
--       跟随位置改为玩家头顶一排微弧（刃杖式）。
--       设置页按钮（排在召神、箭神下面），默认关闭；开/关各有播报。
-- 机制（实测定位）：被携带的哨兵每帧调 SetAsSelectedSentryBackpackTarget()，
--       其实现是 Main.player[owner].accSentryBackpackGrabCooldown = 2;
--       冷却存在「玩家」身上，被携带的那只每帧把它钉回 2，于是别的哨兵
--       一查 cd > 0 就被拒 => 只能带 1 个。
--       ★ 关键坑：本机 Player 实例不能靠 Main.player[Main.myPlayer] 取
--         （手机版取不到，历史版本全栽在这），必须用
--         hook Player.Update_SentryBackpack(0) 传进来的 instance，
--         patch.retain 缓存后可跨帧复用。
-- 挂点：
--   ① Player.Update_SentryBackpack postfix —— 缓存玩家实例 + 清零抓取冷却
--   ② Projectile.CanGetPickedUpBySentryBackpack prefix/postfix —— 紧贴判定前
--      再清一次冷却；判定仍为 false 且距离够近时兜底放行
--   ③ Projectile.AI_Sentries_HeavySlingReposition postfix —— 覆盖位置排成
--      头顶一排微弧，并登记本帧存活名单
--   ④ 节拍总线 tb_reg_frame —— 每帧末整理名单，供下一帧分位次
-- 开关：按钮式，默认关闭，持久化 sg_en.txt；钩子常驻不装卸，门控在回调内部。
-- 安全：不遍历投射物数组、不按下标读游戏数组，只用钩子给的实例。
-- ============================================================================
EXT.sn.setup, EXT.sn.cleanup, EXT.sn.gui = (function()
    local P = patch
    local H = {}
    local hooks = {}
    local SN_EN = false
    local tb_registered = false

    local g_player = nil
    local cur_set, prev_list, prev_idx = {}, {}, {}

    local CARRY_BASE = 58          -- 排在头顶上方多少像素
    local CARRY_ARC  = 10          -- 弧顶额外抬高（中间比两侧高多少）
    local CARRY_GAP  = 32          -- 相邻横向间距
    local PICK_RANGE = 110         -- 兜底放行的最远距离

    local function read_on()
        local ok, raw = pcall(mod.read_file, "sg_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:match("^%s*1") ~= nil
    end
    local function write_on(v)
        pcall(mod.write_file, "sg_en.txt", v and "1" or "0")
    end
    local function rd(field, inst, ty)
        if not field then return nil end
        local ok, v = pcall(P.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end
    local function wr(field, inst, v, ty)
        if not field then return false end
        local ok, r = pcall(P.set_field_value, field, inst, v, ty)
        return ok and r ~= false
    end
    local function find_field(t, name)
        local cur, guard = t, 0
        while cur and guard < 16 do
            local f = P.get_field(cur, name)
            if f then return f end
            cur = P.get_parent(cur)
            guard = guard + 1
        end
        return nil
    end

    -- 缓存玩家实例（retain 后可跨帧用）
    local function cache_player(inst)
        if g_player or not inst then return end
        if P.retain then
            local ok, p = pcall(P.retain, inst)
            if ok and p then
                g_player = p
                return
            end
        end
        g_player = inst
    end

    -- ① 主挂点：只对本机玩家每帧一次
    local function on_sentry_bag(inst)
        if not SN_EN then return end
        if not inst then return end
        cache_player(inst)
        if rd(H.f_bag, inst, "bool") ~= true then return end
        local cd = rd(H.f_cd, inst, "int32")
        if type(cd) == "number" and cd > 0 then
            wr(H.f_cd, inst, 0, "int32")
        end
    end

    -- ② 捡起判定：prefix 贴判定前清冷却
    local function on_can_pick_pre(inst, args, result)
        if not SN_EN then return false end
        local player = g_player
        if not player then return false end
        if rd(H.f_bag, player, "bool") ~= true then return false end
        local cd = rd(H.f_cd, player, "int32")
        if type(cd) == "number" and cd > 0 then
            wr(H.f_cd, player, 0, "int32")
        end
        return false
    end

    -- ② 捡起判定：postfix 距离兜底放行
    local function on_can_pick(inst, args, result)
        if not SN_EN then return nil end
        if result == true then return nil end
        if not inst then return nil end
        local player = g_player
        if not player then return nil end
        if rd(H.f_bag, player, "bool") ~= true then return nil end

        local okA, px, py = pcall(P.get_field_vec2, H.f_player_pos, player)
        local okB, qx, qy = pcall(P.get_field_vec2, H.f_proj_pos, inst)
        if not (okA and okB) then return nil end
        if type(px) ~= "number" or type(qx) ~= "number" then return nil end

        local pwid = rd(H.f_player_w, player, "int32") or 20
        local phei = rd(H.f_player_h, player, "int32") or 42
        local qwid = rd(H.f_proj_w, inst, "int32") or 16
        local qhei = rd(H.f_proj_h, inst, "int32") or 16
        local dx = (qx + qwid * 0.5) - (px + pwid * 0.5)
        local dy = (qy + qhei * 0.5) - (py + phei * 0.5)
        if math.sqrt(dx * dx + dy * dy) <= PICK_RANGE then return true end
        return nil
    end

    -- ③ 排列：头顶一排微弧，中间高两侧低
    local function on_reposition(inst)
        if not SN_EN then return end
        if not inst then return end
        -- 只处理「哨兵本体」：月亮传送门法杖(type 641)这类武器有配套的攻击体(type 642)，
        --   那个攻击体每帧先 base.Center = 父哨兵.Center，再调一次本方法做"上移跟随"。
        --   如果我们也按它的 whoAmI 给它派位，它就会被派到别的格子上，与本体错开
        --   —— 表现出来就是"攻击从传送门旁边冒出去"。sentry=false 的一律不碰。
        --   （字段取不到时不做这项过滤，保持原行为，避免功能整体失效）
        if H.f_proj_sentry and rd(H.f_proj_sentry, inst, "bool") ~= true then return end
        local player = g_player
        if not player then return end
        local who = rd(H.f_proj_who, inst, "int32")
        if type(who) ~= "number" then return end

        if not cur_set[who] then cur_set[who] = true end

        local n = #prev_list
        local idx = prev_idx[who]
        if not idx then
            n = 1
            idx = 1
        end

        local half = (n - 1) * 0.5
        local k = idx - 1 - half
        local t = 0
        if half > 0.001 then
            t = k / half
            if t > 1 then t = 1 elseif t < -1 then t = -1 end
        end
        local off_x = k * CARRY_GAP
        local off_y = -(CARRY_BASE + CARRY_ARC * (1 - t * t))

        local okP, px, py = pcall(P.get_field_vec2, H.f_player_pos, player)
        if not okP or type(px) ~= "number" or type(py) ~= "number" then return end
        local pw = rd(H.f_player_w, player, "int32") or 20
        local ph = rd(H.f_player_h, player, "int32") or 42
        local qw = rd(H.f_proj_w, inst, "int32") or 16
        local qh = rd(H.f_proj_h, inst, "int32") or 16
        local cx = px + pw * 0.5 + off_x
        local cy = py + ph * 0.5 + off_y
        pcall(P.set_field_vec2, H.f_proj_pos, inst, cx - qw * 0.5, cy - qh * 0.5)
    end

    -- ④ 每帧末整理名单（按 whoAmI 升序，供下一帧分位次）
    local function sg_tick()
        if not SN_EN then
            cur_set, prev_list, prev_idx = {}, {}, {}
            return
        end
        local arr = {}
        for who in pairs(cur_set) do arr[#arr + 1] = who end
        table.sort(arr)
        local ix = {}
        for i = 1, #arr do ix[arr[i]] = i end
        prev_list, prev_idx = arr, ix
        cur_set = {}
    end

    local function sg_setup()
        SN_EN = read_on()
        local t_player = P.get_type("Terraria", "Player")
        local t_proj   = P.get_type("Terraria", "Projectile")
        if not (t_player and t_proj) then
            mod.warn("[哨兵神] 类型缺失 Player/Projectile")
            return false
        end
        H.f_bag        = find_field(t_player, "accSentryBackpack")
        H.f_cd         = find_field(t_player, "accSentryBackpackGrabCooldown")
        H.f_player_pos = find_field(t_player, "position")
        H.f_player_w   = find_field(t_player, "width")
        H.f_player_h   = find_field(t_player, "height")
        H.f_proj_pos   = find_field(t_proj, "position")
        H.f_proj_w     = find_field(t_proj, "width")
        H.f_proj_h     = find_field(t_proj, "height")
        H.f_proj_who   = find_field(t_proj, "whoAmI")
        H.f_proj_sentry = find_field(t_proj, "sentry")
        if not (H.f_bag and H.f_cd) then
            mod.warn("[哨兵神] 找不到 accSentryBackpack / accSentryBackpackGrabCooldown")
            return false
        end

        local function add(m, spec, tag)
            if not m then
                mod.warn("[哨兵神] 缺少方法 " .. tag)
                return
            end
            local okh, h = pcall(P.install_hook, m, spec)
            if okh and h then hooks[#hooks + 1] = h
            else mod.warn("[哨兵神] 挂钩失败 " .. tag) end
        end
        add(P.get_method(t_player, "Update_SentryBackpack", 0),
            { postfix = function(inst) on_sentry_bag(inst) end },
            "Player.Update_SentryBackpack")
        add(P.get_method(t_proj, "CanGetPickedUpBySentryBackpack", 0),
            {
                prefix  = function(inst, args, result) return on_can_pick_pre(inst, args, result) end,
                postfix = function(inst, args, result) return on_can_pick(inst, args, result) end,
                override_result = true,
            },
            "Projectile.CanGetPickedUpBySentryBackpack")
        add(P.get_method(t_proj, "AI_Sentries_HeavySlingReposition", 0),
            { postfix = function(inst) on_reposition(inst) end },
            "Projectile.AI_Sentries_HeavySlingReposition")

        tb_reg_frame("我就是哨兵神", sg_tick)
        tb_registered = true

        mod.info("[哨兵神] 已加载，状态=" .. (SN_EN and "开" or "关")
            .. "，钩子数=" .. tostring(#hooks))
        return true
    end

    local function sg_cleanup()
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
        g_player = nil
        cur_set, prev_list, prev_idx = {}, {}, {}
        SN_EN = false
    end

    local function sg_gui(g, notify, bx, by)
        if not H.f_cd then
            g.text("哨兵神：模块未加载")
            return
        end
        local label = SN_EN and "哨兵神（已开启）" or "哨兵神（已关闭）"
        local clicked
        if bx then clicked = btn_at(g, bx, by, label) else clicked = g.button(label) end
        if clicked then
            SN_EN = not SN_EN
            write_on(SN_EN)
            if notify then
                notify(SN_EN and "你说着友情啊、羁绊啊、未来啊，带着一堆的器灵过来了(っ`ヮ’c)"
                                or "散是一盘沙（’-~-`）")
            end
        end
    end

    return sg_setup, sg_cleanup, sg_gui
end)()
-- ============================================================================
-- 第二十七部分：我就是协击神（独立模组 v1.0.2 并入 v2.19.8）
-- 需求：碎裂之石(SnappingStone 6167) / 毁灭臂环(ArmletOfRuin 6179) /
--       火山碎屑石(Pyroclast 6178) 的「协同攻击」周期由 6 秒缩到 0.1 秒。
--       设置页按钮（排在哨兵神下面），默认关闭；开/关各有播报。
-- 机制（源码核实）：命中 NPC 时游戏调 Projectile.TryMakingSnappingStoneStrike，
--   开头 if (cooldown > 0) return; ，触发成功后写回 360（6 秒）；
--   三件共用同一个玩家字段 accSnappingStoneCooldown（Player.cs:1215 int），
--   Player.Update_SnappingStone() 每帧递减 1，归零时按身上那件播充能粒子。
-- 挂点：① 主 Player.Update_SnappingStone(0) postfix —— 只对本机玩家每帧一次，
--          instance 就是玩家本人，直接钳；
--       ② 备 Player.ResetEffects(0) postfix —— 主挂点装不上时用。
-- 开关：按钮式，默认关闭，持久化 sx_en.txt；钩子常驻不装卸，门控在回调内部。
-- 注：主 chunk 的 local 已到 Lua 的 200 上限，故挂到公共表 EXT 下（与哨兵神共用 1 个名额）。
-- ============================================================================
EXT.sx.setup, EXT.sx.cleanup, EXT.sx.gui = (function()
    local P = patch
    local H = {}
    local hook = nil
    local SX_EN = false

    local CD_FRAMES = 6            -- 6 帧 = 0.1 秒（原版 360 帧 = 6 秒）

    local function read_on()
        local ok, raw = pcall(mod.read_file, "sx_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:match("^%s*1") ~= nil
    end
    local function write_on(v)
        pcall(mod.write_file, "sx_en.txt", v and "1" or "0")
    end
    local function rd(field, inst, ty)
        if not field then return nil end
        local ok, v = pcall(P.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end
    local function wr(field, inst, v, ty)
        if not field then return false end
        local ok, r = pcall(P.set_field_value, field, inst, v, ty)
        return ok and r ~= false
    end
    local function find_field(t, name)
        local cur, guard = t, 0
        while cur and guard < 16 do
            local f = P.get_field(cur, name)
            if f then return f end
            cur = P.get_parent(cur)
            guard = guard + 1
        end
        return nil
    end

    -- 幂等钳制：只在比目标值大时写回，绝不往上抬
    local function clamp(inst)
        if not inst then return end
        local cd = rd(H.f_cd, inst, "int32")
        if type(cd) ~= "number" then return end
        if cd > CD_FRAMES then
            wr(H.f_cd, inst, CD_FRAMES, "int32")
        end
    end

    local function on_snapping(inst)
        if not SX_EN then return end
        clamp(inst)
    end
    local function on_reset(inst)
        if not SX_EN then return end
        clamp(inst)
    end

    local function sx_setup()
        SX_EN = read_on()
        local t_player = P.get_type("Terraria", "Player")
        if not t_player then
            mod.warn("[协击神] 类型缺失 Player")
            return false
        end
        H.f_cd = find_field(t_player, "accSnappingStoneCooldown")
        if not H.f_cd then
            mod.warn("[协击神] 找不到 Player.accSnappingStoneCooldown")
            return false
        end
        local m = P.get_method(t_player, "Update_SnappingStone", 0)
        if m then
            local okh, h = pcall(P.install_hook, m, {
                postfix = function(inst) on_snapping(inst) end,
            })
            if okh and h then hook = h end
        end
        if not hook then
            local m2 = P.get_method(t_player, "ResetEffects", 0)
            if m2 then
                local okh, h = pcall(P.install_hook, m2, {
                    postfix = function(inst) on_reset(inst) end,
                })
                if okh and h then hook = h end
            end
        end
        if not hook then
            mod.warn("[协击神] 冷却挂点没装上")
            return false
        end
        mod.info("[协击神] 已加载，状态=" .. (SX_EN and "开" or "关"))
        return true
    end

    local function sx_cleanup()
        if hook then
            pcall(function() hook:remove() end)
            hook = nil
        end
        SX_EN = false
    end

    local function sx_gui(g, notify, bx, by)
        if not H.f_cd then
            g.text("协击神：模块未加载")
            return
        end
        local label = SX_EN and "协击神（已开启）" or "协击神（已关闭）"
        local clicked
        if bx then clicked = btn_at(g, bx, by, label) else clicked = g.button(label) end
        if clicked then
            SX_EN = not SX_EN
            write_on(SX_EN)
            if notify then
                notify(SX_EN and "你这就是我们的频率啊(~_~)"
                                or "这就是散伙协奏曲（:︵:）")
            end
        end
    end

    return sx_setup, sx_cleanup, sx_gui
end)()
-- ============================================================================
-- 第十七部分：增益家具（参考「更好的体验分支(战斗) v1.1.0」合并改造）
-- 改造：去 mod.meta；setup -> af_setup；默认常开（无开关）。
-- v2.8.6 起：不再自己遍历背包——注册到第十二部分的共享扫描器，
--   v2.19.0：只扫「背包59 + 虚空保险库(bank4)40」= 99 格，每 0.5 秒一轮；
--   本模块只保留「命中 MAP -> 收 buffID」（on_item）与「写 buff」（flush）。
-- 全程只做 int32 数组标量读写（buffType/buffTime），不碰任何对象字段。
-- v2.10.23：增益范围收窄为 6 种（弹药箱 / 施法桌 / 水晶球 / 利器站 / 战争桌 / 巴斯特雕像）。
-- v2.11.15：按用户要求加回 红心灯笼 + 全部 14 种篝火（共 21 种）。
-- ============================================================================
af_setup, af_cleanup = (function()
    local P = mod.patch
    -- v2.11.17：篝火(BuffID 87) / 红心灯笼(BuffID 89) 是「区域型」增益 ——
    --   原版的生命再生加成都写在 Player.UpdateLifeRegen 里，判定读的是
    --   SceneMetrics.HasCampfire / HasHeartLantern（附近有没有那个家具），
    --   跟 buff 完全无关。所以我们只写 buffType 会出现「图标有、效果没有」。
    --   修法：在 UpdateLifeRegen 算完之后按原版公式补 lifeRegen（篝火 +1、红心灯笼 +2）。
    local AF_CAMP, AF_HEART = false, false
    local F_lifeRegen, af_lr_hook
    -- v2.11.18：站在真篝火/红心灯笼旁边时，原版自己已经加过了，不能再加一次。
    --   原版判定读的是 SceneMetrics.HasCampfire / HasHeartLantern，
    --   所以这里也读同一处：为 true 就跳过，保证「背包一个 + 地上一个」只算一次。
    local m_get_sm, m_has_camp, m_has_heart, m_set_camp, m_set_heart
    -- v2.11.20：优先「把 SceneMetrics.HasCampfire 写成 true」，让原版 UpdateLifeRegen 自己 +1/+2。
    --   这样即使玩家真的站在篝火旁，也只是原版那一次，绝不会重复计算。
    local sm_written = false
    local function sm_beacon(mgetter, msetter, sm)
        if not msetter then return false end
        local ok = pcall(P.invoke, msetter, sm, true)
        if not ok then return false end
        -- 写完必须回读确认：读到 true 说明标记确实在了（我们写的，或原版本来就有），
        -- 这时原版 UpdateLifeRegen 一定会自己加，我们不再补数值，绝不重复。
        if not mgetter then return false end
        local okv, v = pcall(P.invoke, mgetter, sm)
        return okv and (v == true)
    end
    local function sm_flag(mgetter)
        if not (mgetter and m_get_sm) then return nil end
        local oks, sm = pcall(P.invoke, m_get_sm)
        if not (oks and sm) then return nil end
        local okv, v = pcall(P.invoke, mgetter, sm)
        if not okv then return nil end
        return v == true
    end
    local function af_lr_pre(inst)
        if not CHW then return end
        if not (AF_CAMP or AF_HEART) then return end
        if not m_get_sm then return end
        local oks, sm = pcall(P.invoke, m_get_sm)
        if not (oks and sm) then return end
        local w1, w2 = false, false
        if AF_CAMP then w1 = sm_beacon(m_has_camp, m_set_camp, sm) end
        if AF_HEART then w2 = sm_beacon(m_has_heart, m_set_heart, sm) end
        sm_written = (w1 or w2)
    end
    local function af_lr_post(inst)
        if not CHW then return end
        if not (AF_CAMP or AF_HEART) then return end
        if sm_written then return end   -- v2.11.20：原版已按标记加过，不再补数值
        if not F_lifeRegen then return end
        local ok, v = pcall(P.get_field_value, F_lifeRegen, inst, "int32")
        if not ok or type(v) ~= "number" then return end
        local add = 0
        -- v2.11.18：原版已给过的（附近真有家具）不再重复加
        if AF_CAMP and sm_flag(m_has_camp) ~= true then add = add + 1 end
        if AF_HEART and sm_flag(m_has_heart) ~= true then add = add + 2 end
        if add > 0 then pcall(P.set_field_value, F_lifeRegen, inst, v + add, "int32") end
    end
    -- v2.10.23：收窄到 6 种增益站家具；v2.11.15 按用户要求加回 红心灯笼 + 篝火系
    local MAP = {
        [2177]=93,   -- 弹药箱     -> BuffID 93
        [2999]=150,  -- 施法桌     -> BuffID 150
        [487] =29,   -- 水晶球     -> BuffID 29
        [3198]=159,  -- 利器站     -> BuffID 159
        [3814]=348,  -- 战争桌     -> BuffID 348
        [4276]=215,  -- 巴斯特雕像 -> BuffID 215
        -- v2.11.15：红心灯笼 + 篝火系（ItemID/BuffID 均已对 1.4.5.8 源码核对）
        [1859]=89,   -- 红心灯笼       -> BuffID HeartLamp 89
        [966] =87,   -- 篝火           -> BuffID Campfire 87
        [3046]=87,   -- 诅咒篝火       (CursedCampfire)
        [3047]=87,   -- 恶魔篝火       (DemonCampfire)
        [3048]=87,   -- 冰冻篝火       (FrozenCampfire)
        [3049]=87,   -- 灵液篝火       (IchorCampfire)
        [3050]=87,   -- 彩虹篝火       (RainbowCampfire)
        [3723]=87,   -- 极亮篝火       (UltraBrightCampfire)
        [3724]=87,   -- 骨头篝火       (BoneCampfire)
        [4689]=87,   -- 沙漠篝火       (DesertCampfire)
        [4690]=87,   -- 珊瑚篝火       (CoralCampfire)
        [4691]=87,   -- 腐化篝火       (CorruptCampfire)
        [4692]=87,   -- 猩红篝火       (CrimsonCampfire)
        [4693]=87,   -- 神圣篝火       (HallowedCampfire)
        [4694]=87,   -- 丛林篝火       (JungleCampfire)
    }
    local MAXBUFF  = 44
    local BUFFTIME = 60     -- v2.19.0：1 秒（配套 0.5 秒扫描；取下时另有主动清零）
    -- v2.18.1：全部增益统一 3 秒（靠 2 秒一轮扫描续期）；
    --   巴斯特雕像(215) / 篝火(87) / 红心灯笼(89) 已改回原时长。
    local slotCache = {}          -- buffID -> 上次命中的槽位（0 基），命中即 O(1)
    local F_btype, F_btime
    local g_tick = 0
    -- v2.11.0：不再依赖共享扫描器，自己低频扫（每 120 帧 = 2 秒一次）
    local F_playerarr, M_getmyplayer, F_inv, F_itemtype
    local F_isitem, F_bank4   -- v2.19.0：只保留虚空保险库（猪猪/保险箱/护卫者熔炉已移除）
    -- ---- v4.3.0 药水常驻 buff ----
    -- 背包 59 格 + 虚空保险库 40 格里，同种药水 stack 累计 >= 10 瓶 -> 该药水对应的 buff 常驻。
    -- 实现只走 A 方案：靠每 0.5 秒给 buffTime 续期这一条路，
    --   不碰 Main.buffNoTimeDisplay / BuffID.Sets.TimeLeftDoesNotDecrease 两个全局静态数组，
    --   因此不会把玩家自己喝的同类药水变成永久（那两个数组是全局的，一改就污染所有实例）。
    -- 副作用（已知、可接受）：HUD 上该 buff 会显示约 1 秒读秒并循环。
    local POTION_NEED = 10
    local g_potion = {}          -- buffType -> 本轮累计瓶数
    local g_pot_act = {}         -- 本轮生效的 buffType 集合（用于给 give_buff 传 keep_long）
    local g_pot_miss = {}        -- v4.3.1：bt -> 连续未达标轮数（掉线容错，连续 3 轮才撤销）
    local F_stack, F_pbuff, F_consum, F_dmg, F_maxstack
    local g_buffs = {}
    local g_scan = 0
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
    -- v4.3.1：读 int 字段走【原始字节】。
    --   v4.3.0 用 rd(F_stack, it, "int32") 读 stack，实测会间歇性读失败，
    --   日志里 bt110 在 9993~9999 之间抖、bt3 在 5~12 之间抖 →
    --   计数偶尔跌破阈值，buff 一闪一闪。改 get_field_raw 按实际字节宽 unpack 就稳了。
    local function rd_int(field, inst)
        if not field then return nil end
        if P.get_field_raw then
            local ok, raw = pcall(P.get_field_raw, field, inst)
            if ok and type(raw) == "string" and #raw > 0 then
                local ok2, v = pcall(string.unpack, "<i" .. #raw, raw)
                if ok2 then return v end
            end
        end
        local ok3, v3 = pcall(P.get_field_value, field, inst, "int32")
        if ok3 then return v3 end
        return nil
    end
    -- v4.3.0：新增 keep_long 参数。
    --   keep_long = true（药水常驻 buff）：只补到 BUFFTIME，绝不把已有更长的时长
    --     （玩家自己喝药水给的 3600 帧）压成 60 —— 否则喝药水会变 1 秒。
    --   keep_long = nil（增益家具原路径）：行为完全不变，仍然无条件写 BUFFTIME。
    local function give_buff(me, bid, keep_long)
        local ba = rd(F_btype, me, "object")
        local bt = rd(F_btime, me, "object")
        if not (ba and bt) then return end
        local function stamp(slot)
            if keep_long then
                local cur = arr_get(bt, slot, "int32")
                if cur and cur >= BUFFTIME then return end
            end
            pcall(P.array_set, bt, slot, BUFFTIME, "int32")
        end
        -- 快速路径：上次命中的槽位仍然是这个 buff（战斗/切世界时槽位会变，读回校验自愈）
        local cached = slotCache[bid]
        if cached and arr_get(ba, cached, "int32") == bid then
            stamp(cached)
            return
        end
        local free = -1
        for i = 0, MAXBUFF - 1 do
            local cur = arr_get(ba, i, "int32")
            if cur == bid then
                slotCache[bid] = i
                stamp(i)
                return
            elseif cur == 0 and free < 0 then
                free = i
            end
        end
        if free >= 0 then
            pcall(P.array_set, ba, free, bid, "int32")
            pcall(P.array_set, bt, free, BUFFTIME, "int32")
            slotCache[bid] = free
        end
    end
    -- 命中判定（共享扫描器每读到一个物品类型号就调一次）
    local function on_item(t, acc)
        local bid = MAP[t]
        if bid then acc.buffs[bid] = true end
    end
    -- 写 buff（沿用旧版「每 2 帧一次」的节奏）
    local function flush(me, acc)
        g_tick = g_tick + 1
        if g_tick < 2 then return end
        g_tick = 0
        for bid, _ in pairs(acc.buffs) do give_buff(me, bid) end
    end
    -- ---- v2.11.0 自扫实现（替代共享扫描器）----
    -- v4.3.0：药水计数。判定规则沿用「类药水袋」：
    --   buffType > 0 是核心信号；damage > 0 拦（武器/召唤杖，召唤杖 buffType=64 会骗过第一关）；
    --   maxStack <= 1 拦（宠物/坐骑/法杖）；consumable 只有明确读到 false 才拦（读不到不拦）。
    -- v8.3.6：「增益家具」和「药水常驻」是两个互相独立的一级开关。
    --   v9.2.0：增益家具与药水常驻已移除；本模块只保留背包/仓库扫描（遗忘之物依赖）。
    --   ⚠ 这两个函数必须定义在 count_potion / scan_items 之前：
    --     Lua 的 local 作用域从声明处开始，写在后面的话 scan_items 里拿到的是全局 nil，
    --     每轮扫描都抛 "attempt to call a nil value"，被总线 pcall 吞掉 —— 两个功能会全废。
    local function af_on()
        -- v9.2.0：「增益家具」功能已移除，但背包/仓库扫描要保留 ——
        --   遗忘之物（fi_scan_slot）靠它触发，删掉扫描会让遗忘之物一起失效。
        return true
    end
    local function pot_on()
        -- v9.2.0：「药水常驻 Buff（≥10 瓶）」功能已移除
        return false
    end
    local function count_potion(it)
        if not (F_pbuff and F_stack) then return end
        local bt = rd_int(F_pbuff, it)
        if not bt or bt <= 0 then return end
        local dmg = rd_int(F_dmg, it)
        if dmg and dmg > 0 then return end
        local ms = rd_int(F_maxstack, it)
        if ms and ms <= 1 then return end
        local cons = rd(F_consum, it, "bool")
        if cons == false then return end
        local st = rd_int(F_stack, it)
        if not st or st <= 0 then return end
        g_potion[bt] = (g_potion[bt] or 0) + st
    end
    local function scan_items(arr, lim, tag)
        if not arr then return end
        local n = 0
        pcall(function() n = P.array_length(arr) end)
        if not n or n <= 0 then return end
        if lim and n > lim then n = lim end
        for i = 0, n - 1 do
            local it = arr_get(arr, i)
            if it then
                local t = rd(F_itemtype, it, "int32")
                if t then
                    local bid = MAP[t]
                    if bid and af_on() then g_buffs[bid] = true end
                    -- v5.7.1：药水常驻 buff 独立开关，关掉就不统计（已有的会在下一轮撤销）
                    if pot_on() then count_potion(it) end
                    -- v2.19.1：顺带喂给遗忘之物（每槽位同一物品只修一次）
                    if tag and fi_scan_slot then fi_scan_slot(tag .. i, t, it) end
                end
            end
        end
    end
    local function scan_bank(me, fbank, tag)
        if not (fbank and F_isitem) then return end
        local ok, st = pcall(P.get_field_value, fbank, me, "object")
        if not (ok and st) then return end
        local ok2, arr = pcall(P.get_field_value, F_isitem, st, "object")
        if ok2 and arr then scan_items(arr, 40, tag) end
    end
    local function af_tick()
        -- v9.2.0：只做背包/仓库扫描（遗忘之物依赖），给 buff 部分已删除
        g_scan = g_scan + 1
        if g_scan < 30 then return end    -- v2.19.0：0.5 秒扫一次（原来 2 秒）
        g_scan = 0
        local arr = rd(F_playerarr, nil, "object")
        if not arr then return end
        local okmi, mi = pcall(P.invoke, M_getmyplayer, nil)
        if not (okmi and type(mi) == "number") then return end
        local me = arr_get(arr, mi)
        if not me then return end
        for k in pairs(g_buffs) do g_buffs[k] = nil end
        for k in pairs(g_potion) do g_potion[k] = nil end      -- v4.3.0
        local prev_act = g_pot_act                              -- v4.3.1：上一轮生效集合
        g_pot_act = {}
        -- v2.19.0：只扫背包 59 格 + 虚空保险库（bank4）40 格 = 99 格
        scan_items(rd(F_inv, me, "object"), 59, "inv")
        scan_bank(me, F_bank4, "b4:")
        -- v9.2.0：扫描到此为止（fi_scan_slot 已跑过）。
        --   buff 续期 / 取下清理 / 篝火心灯标记全部移除，改由「多功能大背包」提供。
        do return end
        -- v4.3.0：同种药水累计 >= POTION_NEED 瓶 -> 并入 g_buffs，
        --   后续续期、槽位缓存、取下清理全部复用增益家具那一套逻辑。
        if pot_on() then
            for bt, cnt in pairs(g_potion) do
                if cnt >= POTION_NEED then g_pot_act[bt] = true end
            end
        end
        -- v4.3.1：掉线容错。单轮读数偶尔偏低不再立刻撤 buff，
        --   连续 3 轮（约 1.5 秒）都不达标才真正撤销。
        for bt in pairs(g_pot_miss) do
            if g_pot_act[bt] then g_pot_miss[bt] = nil end
        end
        for bt in pairs(prev_act) do
            if not g_pot_act[bt] then
                local m = (g_pot_miss[bt] or 0) + 1
                if m < 3 then
                    g_pot_miss[bt] = m
                    g_pot_act[bt] = true          -- 继续维持
                else
                    g_pot_miss[bt] = nil          -- 真正撤销
                end
            end
        end
        for bt in pairs(g_pot_act) do g_buffs[bt] = true end
        for bid in pairs(g_buffs) do give_buff(me, bid, g_pot_act[bid] == true) end
        -- v2.19.0：已经不在身上的增益 → 立刻把该槽位的剩余时间清零（取下即失效）
        do
            local ba = rd(F_btype, me, "object")
            local bt = rd(F_btime, me, "object")
            if ba and bt then
                local stale = nil
                for bid, slot in pairs(slotCache) do
                    if not g_buffs[bid] then
                        if arr_get(ba, slot, "int32") == bid then
                            -- v4.3.0：只清我们自己刷出来的短时长（<= BUFFTIME）。
                            --   > BUFFTIME 说明是玩家自己喝药水给的，别抹掉。
                            local cur_t = arr_get(bt, slot, "int32")
                            if not cur_t or cur_t <= BUFFTIME then
                                pcall(P.array_set, bt, slot, 0, "int32")
                            end
                        end
                        stale = stale or {}
                        stale[#stale + 1] = bid
                    end
                end
                if stale then
                    for i = 1, #stale do slotCache[stale[i]] = nil end
                end
            end
        end
        -- v2.11.17：记录背包里是否有篝火 / 红心灯笼，交给 UpdateLifeRegen 尾钩补加成
        AF_CAMP  = g_buffs[87] and true or false
        AF_HEART = g_buffs[89] and true or false
    end
    local function af_setup()
        local T_Player = P.get_type("Terraria", "Player")
        local T_Main   = P.get_type("Terraria", "Main")
        local T_Item   = P.get_type("Terraria", "Item")
        local T_IS     = P.get_type("Terraria", "InventoryStorage")
        if not (T_Player and T_Main) then
            mod.warn("增益家具：类型缺失，跳过")
            return
        end
        F_btype = P.get_field(T_Player, "buffType")
        F_btime = P.get_field(T_Player, "buffTime")
        F_inv   = P.get_field(T_Player, "inventory")
        F_bank4 = P.get_field(T_Player, "bank4")   -- v2.19.0：只保留虚空保险库
        F_playerarr   = P.get_field(T_Main, "player")
        M_getmyplayer = P.get_method(T_Main, "get_myPlayer", 0)
        F_itemtype    = T_Item and P.get_field(T_Item, "type")
        -- v4.3.0：药水判定所需字段
        F_stack    = T_Item and P.get_field(T_Item, "stack")
        F_pbuff    = T_Item and P.get_field(T_Item, "buffType")
        F_consum   = T_Item and P.get_field(T_Item, "consumable")
        F_dmg      = T_Item and P.get_field(T_Item, "damage")
        F_maxstack = T_Item and P.get_field(T_Item, "maxStack")
        if T_IS then F_isitem = P.get_field(T_IS, "item") end
        if not (F_btype and F_btime and F_inv and F_playerarr and M_getmyplayer and F_itemtype) then
            mod.warn("增益家具：关键成员缺失，跳过")
            return
        end
        -- v2.11.17：装 Player.UpdateLifeRegen 尾钩（0 参数，每帧一次，非高频重活）
        F_lifeRegen = P.get_field(T_Player, "lifeRegen")
        -- v2.11.18：解析 Main.SceneMetrics（静态属性）与它的两个 bool 属性
        do
            local prop_sm = P.get_property and P.get_property(T_Main, "SceneMetrics")
            if prop_sm and P.property_get_method then
                m_get_sm = P.property_get_method(prop_sm)
            end
            if not m_get_sm then m_get_sm = P.get_method(T_Main, "get_SceneMetrics", 0) end
            local T_SM = P.get_type("Terraria", "SceneMetrics")
            if T_SM then
                local function acc(n)
                    local p = P.get_property and P.get_property(T_SM, n)
                    if p and P.property_get_method then
                        local mm = P.property_get_method(p)
                        if mm then return mm end
                    end
                    return P.get_method(T_SM, "get_" .. n, 0)
                end
                m_has_camp  = acc("HasCampfire")
                m_has_heart = acc("HasHeartLantern")
                local function accs(n)
                    local p = P.get_property and P.get_property(T_SM, n)
                    if p and P.property_set_method then
                        local mm = P.property_set_method(p)
                        if mm then return mm end
                    end
                    return P.get_method(T_SM, "set_" .. n, 1)
                end
                m_set_camp  = accs("HasCampfire")
                m_set_heart = accs("HasHeartLantern")
            end
            if not (m_get_sm and m_has_camp and m_has_heart) then
                mod.warn("增益家具：SceneMetrics 读取句柄不完整")
            end
        end
        -- v9.2.1：增益家具已整体移除，不再安装 UpdateLifeRegen 钩子
        --   （篝火 / 红心灯笼的回血加成由「多功能大背包」提供）
        tb_reg_frame("遗忘之物扫描", af_tick)
    end
    local function af_cleanup()
        if af_lr_hook and af_lr_hook.remove then pcall(af_lr_hook.remove, af_lr_hook) end
        af_lr_hook = nil
        AF_CAMP, AF_HEART = false, false
        for k in pairs(slotCache) do slotCache[k] = nil end
        -- v4.3.0
        for k in pairs(g_potion) do g_potion[k] = nil end
        for k in pairs(g_pot_act) do g_pot_act[k] = nil end
        for k in pairs(g_pot_miss) do g_pot_miss[k] = nil end
    end
    return af_setup, af_cleanup
end)()
-- ============================================================================
-- 第十八部分：每日商人刷新（参考「旅商刷新 v1.0.0」合并改造，原 pkg lua.example.dailymechants）
-- 改造：去 mod.meta；去 config.json 轮询（沿用模组默认值硬编码：旅商开 / 骷髅开 /
--   仅洞穴层 / 半径 120 格，默认常开、无开关）；setup -> dm_setup；
--   钩子句柄捕获供 dm_cleanup；get_vec2 走 pcall（本合集死亡回溯已实测该读法稳定）。
-- 实现（同参考）：Hook Player.ResetEffects postfix（仅本地玩家），检测 Main.dayTime
--   false -> true 的黎明瞬间：
--   ① 旅行商人（NPC 368）：全场无活跃旅商则 invoke WorldGen.SpawnTravelNPC() 保底生成
--   ② 骷髅商人（NPC 453）：身处洞穴层（玩家 Y/16 > Main.rockLayer）且半径 120 格内
--      无活跃骷髅商人，则在玩家侧向 20 格、上方 20 格处 NPC.NewNPC 生成一只
-- ============================================================================
dm_setup, dm_cleanup = (function()
    local P = mod.patch

    local TRAVEL_MERCHANT_TYPE    = 368
    local SKELETON_MERCHANT_TYPE  = 453
    local SPAWN_OFFSET_TILES      = 20
    local SCAN_RADIUS_TILES       = 120   -- 原模组 config 默认值

    local F_dayTime, F_rockLayer, F_main_npc
    local F_pos, F_width, F_height
    local F_npc_active, F_npc_type, F_npc_position
    local M_spawn_travel, M_new_npc
    local dm_hook = nil
    local prev_day = nil

    -- 父类回退找字段（Entity.position 等声明在基类上）
    local function find_field(t, name)
        local cur, guard = t, 0
        while cur and guard < 16 do
            local ok, f = pcall(P.get_field, cur, name)
            if ok and f then return f end
            local okp, par = pcall(P.get_parent, cur)
            if not okp then return nil end
            cur = par
            guard = guard + 1
        end
        return nil
    end

    local function get_int(f, inst, d)
        if not f then return d end
        local ok, v = pcall(P.get_field_value, f, inst, "int32")
        if not ok or v == nil then return d end
        return v
    end

    local function get_bool(f, inst, d)
        if not f then return d end
        local ok, v = pcall(P.get_field_value, f, inst, "bool")
        if not ok or v == nil then return d end
        return v
    end

    local function get_vec2(f, inst)
        if not f then return nil, nil end
        local ok, x, y = pcall(P.get_field_vec2, f, inst)
        if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
        return x, y
    end

    local function npc_array()
        local ok, arr = pcall(P.get_field_value, F_main_npc, nil, "object")
        if not ok then return nil end
        return arr
    end

    local function traveling_merchant_exists()
        local arr = npc_array()
        if not arr then return false end
        local okl, len = pcall(P.array_length, arr)
        if not okl or not len then return false end
        for i = 0, len - 1 do
            local oko, npc = pcall(P.array_at, arr, i)
            if oko and npc and get_bool(F_npc_active, npc, false)
               and get_int(F_npc_type, npc, -1) == TRAVEL_MERCHANT_TYPE then
                return true
            end
        end
        return false
    end

    local function handle_travel_merchant()
        if not M_spawn_travel then return end
        if traveling_merchant_exists() then return end
        pcall(P.invoke, M_spawn_travel)
    end

    local function is_in_cavern(player)
        if not F_rockLayer then return true end
        local ok, rock = pcall(P.get_field_value, F_rockLayer, nil, "double")
        if not ok or type(rock) ~= "number" then return true end
        local _, py = get_vec2(F_pos, player)
        if not py then return true end
        return (py / 16.0) > rock
    end

    local function has_skeleton_merchant_nearby(px, py)
        local arr = npc_array()
        if not arr then return false end
        local okl, len = pcall(P.array_length, arr)
        if not okl or not len then return false end
        local r = SCAN_RADIUS_TILES * 16
        local r2 = r * r
        for i = 0, len - 1 do
            local oko, npc = pcall(P.array_at, arr, i)
            if oko and npc and get_bool(F_npc_active, npc, false)
               and get_int(F_npc_type, npc, -1) == SKELETON_MERCHANT_TYPE then
                local nx, ny = get_vec2(F_npc_position, npc)
                if nx then
                    local dx, dy = nx - px, ny - py
                    if dx * dx + dy * dy <= r2 then return true end
                end
            end
        end
        return false
    end

    local function spawn_skeleton_merchant(player)
        if not M_new_npc then return end
        local px, py = get_vec2(F_pos, player)
        if not px then return end
        local w = get_int(F_width, player, 20)
        local h = get_int(F_height, player, 42)
        local dir = (math.random(0, 1) == 0) and -1 or 1
        local sx = math.floor(px + w * 0.5 + dir * SPAWN_OFFSET_TILES * 16)
        local sy = math.floor(py + h * 0.5 - SPAWN_OFFSET_TILES * 16)
        pcall(P.invoke, M_new_npc, nil,
              sx, sy, SKELETON_MERCHANT_TYPE, 0,
              0.0, 0.0, 0.0, 0.0, 255)
    end

    local function handle_skeleton_merchant(player)
        if not is_in_cavern(player) then return end
        local px, py = get_vec2(F_pos, player)
        if not px then return end
        if has_skeleton_merchant_nearby(px, py) then return end
        spawn_skeleton_merchant(player)
    end

    -- 黎明瞬间（dayTime false -> true）触发两个保底检查
    local function on_reset_effects(instance)
        if not instance then return end
        local day = get_bool(F_dayTime, nil, false)
        if prev_day == nil then
            prev_day = day
            return
        end
        local is_dawn = (day == true and prev_day == false)
        prev_day = day
        if not is_dawn then return end
        pcall(handle_travel_merchant)
        pcall(handle_skeleton_merchant, instance)
    end

    local function dm_setup()
        if dm_hook then return end
        local T_Main = P.get_type("Terraria", "Main")
        local T_Player = P.get_type("Terraria", "Player")
        local T_NPC    = P.get_type("Terraria", "NPC")
        local T_Entity = P.get_type("Terraria", "Entity")
        local T_WorldGen = P.get_type("Terraria", "WorldGen")
        if not (T_Main and T_Player and T_NPC and T_Entity and T_WorldGen) then
            mod.warn("每日商人刷新：类型未找到，跳过")
            return
        end
        F_dayTime   = P.get_field(T_Main, "dayTime")
        F_rockLayer = P.get_field(T_Main, "rockLayer")
        F_main_npc  = P.get_field(T_Main, "npc")

        F_pos    = find_field(T_Entity, "position")
        F_width  = find_field(T_Entity, "width")
        F_height = find_field(T_Entity, "height")

        F_npc_active   = find_field(T_NPC, "active")
        F_npc_type     = find_field(T_NPC, "type")
        F_npc_position = find_field(T_Entity, "position")

        M_spawn_travel = P.get_method(T_WorldGen, "SpawnTravelNPC", 0)
        M_new_npc      = P.get_method(T_NPC, "NewNPC", 10)

        if not (F_dayTime and F_main_npc and F_npc_type and F_npc_active and F_pos and F_rockLayer) then
            mod.warn("每日商人刷新：关键字段缺失，跳过")
            return
        end
        if not M_spawn_travel then
            mod.warn("每日商人刷新：SpawnTravelNPC 未找到，旅行商人保底不可用")
        end
        if not M_new_npc then
            mod.warn("每日商人刷新：NPC.NewNPC(10) 未找到，骷髅商人保底不可用")
        end
        -- v2.8.0：不再单独装 ResetEffects 钩子，改注册到节拍总线
        tb_reg_reset("每日商人", _G.mg_gated("dm", on_reset_effects))
        prev_day = get_bool(F_dayTime, nil, false)
    end

    local function dm_cleanup()
        if dm_hook and dm_hook.remove then pcall(function() dm_hook:remove() end) end
        dm_hook = nil
    end

    return dm_setup, dm_cleanup
end)()

-- ============================================================================
-- 第十九部分：NPC入住（参考「npc入住相关 v1.0.0 / NPC入住 v1.0.0」合并改造，原 pkg lua.qing.npchome）
-- 改造：去 mod.meta；去 log 噪音；setup -> nh_setup；钩子句柄捕获供 nh_cleanup；
--   去 _G.g_npchome_done 守卫（合集 setup 只跑一次）；默认常开（无开关）。
-- 实现（v2.6.2 改造：降频分帧，降低 JNI 调用密度，避免与其他重钩子模块双开时抢帧）：
--   Hook Main.Update postfix 每 15 帧扫一段、每段 50 槽（游标轮转覆盖 200 槽，全圈 1 秒），
--   按 whoAmI 记录每个活跃 NPC 上一次的 homeTileX/Y：首次见到且已有合法家、
--   或家坐标发生变化时，把 NPC 直接瞬移到家中（position = 家坐标*16、
--   velocity 清零、teleporting 置 true）——分配房间后 NPC 立即入住，不用等原版走门。
--   vec2 写入走 pcall（set_field_vec2，与死亡回溯同族的标量/vec2 安全写法）。
-- ============================================================================
nh_setup, nh_cleanup = (function()
    local P = mod.patch

    local F_npcArr, F_active, F_type, F_pos, F_vel, F_h, F_hx, F_hy, F_who, F_tp
    -- v2.15.1：原来用 g_prev[whoAmI]={hx=,hy=} 存每个 NPC 上一次的家坐标，
    --   每扫到一个活着的 NPC 都要新建一个小表 + 一次 tostring —— 全游戏每秒造几十个
    --   临时对象全喂给垃圾回收。改成两个以 whoAmI 直接当下标的数组，零分配。
    local g_hx, g_hy = {}, {}
    local g_tick = 0
    local g_cursor = 0
    local SCAN_EVERY = 15   -- 每 15 帧扫一轮（v2.6.4 起；v2.6.2 为 30 帧）→ 全圈 60 帧 = 1 秒入住
    local SCAN_CHUNK = 50   -- 分帧：每轮只扫 50 槽，游标轮转覆盖 200 槽
    local nh_hook = nil

    local function rd(field, inst, ty)
        local ok, v = pcall(P.get_field_value, field, inst, ty)
        if ok then return v end
        return nil
    end

    -- 家坐标变化时把 NPC 瞬移进家
    local function move_home(npc, hx, hy)
        if hx < 0 or hy < 0 then return end
        local h = rd(F_h, npc, "int32") or 42
        local px = hx * 16
        local py = hy * 16 - h
        pcall(P.set_field_vec2, F_pos, npc, px, py)
        pcall(P.set_field_vec2, F_vel, npc, 0.0, 0.0)
        pcall(P.set_field_value, F_tp, npc, true, "bool")
    end

    local function scan()
        g_tick = g_tick + 1
        if g_tick < SCAN_EVERY then return end
        g_tick = 0
        local arr = rd(F_npcArr, nil, "object")
        if not arr then return end
        local n = 0
        pcall(function() n = P.array_length(arr) end)
        if not n or n <= 0 then return end
        if n > 200 then n = 200 end
        -- 分帧轮转：每轮只扫 SCAN_CHUNK 槽，下次从游标处继续
        local start = g_cursor
        if start >= n then start = 0 end
        local last = start + SCAN_CHUNK - 1
        if last > n - 1 then last = n - 1 end
        for i = start, last do
            local ok, npc = pcall(P.array_at, arr, i)
            if ok and npc then
                local act = rd(F_active, npc, "bool")
                if act then
                    local who = rd(F_who, npc, "int32") or i
                    local hx = rd(F_hx, npc, "int32") or -1
                    local hy = rd(F_hy, npc, "int32") or -1
                    local ox = g_hx[who]
                    if ox == nil then
                        -- 第一次见到：只要有合法家，也立刻瞬移进去
                        if hx >= 0 and hy >= 0 then move_home(npc, hx, hy) end
                        g_hx[who] = hx; g_hy[who] = hy
                    elseif ox ~= hx or g_hy[who] ~= hy then
                        move_home(npc, hx, hy)
                        g_hx[who] = hx; g_hy[who] = hy
                    end
                end
            end
        end
        g_cursor = last + 1
        if g_cursor >= n then g_cursor = 0 end
    end

    local function nh_setup()
        if nh_hook then return end
        local T_Main = P.get_type("Terraria", "Main")
        local T_NPC  = P.get_type("Terraria", "NPC")
        if not (T_Main and T_NPC) then
            mod.warn("NPC入住：Main/NPC 类型未找到，跳过")
            return
        end
        F_npcArr = P.get_field(T_Main, "npc")
        F_active = P.get_field(T_NPC, "active")
        F_type   = P.get_field(T_NPC, "type")
        F_pos    = P.get_field(T_NPC, "position")
        F_vel    = P.get_field(T_NPC, "velocity")
        F_h      = P.get_field(T_NPC, "height")
        F_hx     = P.get_field(T_NPC, "homeTileX")
        F_hy     = P.get_field(T_NPC, "homeTileY")
        F_who    = P.get_field(T_NPC, "whoAmI")
        F_tp     = P.get_field(T_NPC, "teleporting")
        if not (F_npcArr and F_active and F_pos and F_hx and F_hy and F_who) then
            mod.warn("NPC入住：关键字段缺失，跳过")
            return
        end
        -- v2.8.0：不再单独装 Main.Update 钩子，改注册到节拍总线
        tb_reg_frame("NPC入住", _G.mg_gated("nh", scan))
    end

    local function nh_cleanup()
        if nh_hook and nh_hook.remove then pcall(function() nh_hook:remove() end) end
        nh_hook = nil
        g_hx, g_hy = {}, {}
    end

    return nh_setup, nh_cleanup
end)()

-- ============================================================================
-- 城镇NPC无敌模块（v8.9.3 新增）
-- 功能：城镇 NPC 不受敌怪伤害；岩浆、玩家武器等其它伤害照常生效。
-- 机制：钩 NPC.StrikeNPC prefix，按 owner / knockBack 判源。
--   StrikeNPCNoInteraction(int Damage, float knockBack, int hitDirection)
--     内部就是 return StrikeNPC(Damage, knockBack, hitDirection, ..., owner: 255)
--     —— knockBack 原样传递，所以只钩 StrikeNPC 一处即可覆盖两条路径：
--     敌怪接触  BeHurtByOtherNPC        -> StrikeNPCNoInteraction(dmg, 6, dir)  knockBack=6
--     岩浆      Collision_LavaCollision -> StrikeNPCNoInteraction(50, 0f, 0)    knockBack=0
--     敌怪弹幕  Projectile.Damage       -> knockBack>0, owner=255
--     玩家武器  Player / Projectile     -> owner = 0~254
-- 判据：owner 在 0~254 -> 放行（玩家武器）；knockBack<=0 -> 放行（岩浆等环境）；
--       其余（owner=255 且有击退）-> 返回 true 跳过原方法，伤害为 0。
-- 开关：ms_gates 的 "ng"，默认开启。钩子常驻，回调首行由 mg_gated 判开关，
--       所以勾选后立即生效，不用重启。
-- ============================================================================
ng_setup, ng_cleanup = (function()
    local P = mod.patch
    local F_town = nil
    local ng_hook = nil

    local function is_town(npc)
        if not npc or not F_town then return false end
        local ok, v = pcall(P.get_field_value, F_town, npc, "bool")
        return ok and v == true
    end

    local function ng_setup()
        if ng_hook then return end
        local T_NPC = P.get_type("Terraria", "NPC")
        if not T_NPC then
            mod.warn("城镇NPC无敌：NPC 类型未找到，跳过")
            return
        end
        F_town = P.get_field(T_NPC, "townNPC")
        if not F_town then
            mod.warn("城镇NPC无敌：townNPC 字段缺失，跳过")
            return
        end
        local m
        for _, n in ipairs({ 6, 5, 4 }) do
            local ok, v = pcall(P.get_method, T_NPC, "StrikeNPC", n)
            if ok and v then m = v break end
        end
        if not m then
            mod.warn("城镇NPC无敌：StrikeNPC 未找到，跳过")
            return
        end
        local ok2, h = pcall(P.install_hook, m, { prefix = _G.mg_gated("ng", function(inst, args)
            if not CHW then return false end
            if not is_town(inst) then return false end
            if type(args) ~= "table" then return false end
            local kb = args[2]
            local owner = args[6]
            -- 玩家来源（玩家武器、玩家丢的炸弹）：放行
            if type(owner) == "number" and owner >= 0 and owner < 255 then return false end
            -- 无击退的环境伤害（岩浆、强制杀）：放行
            if type(kb) ~= "number" or kb <= 0 then return false end
            -- 敌怪接触 / 敌怪弹幕：免疫
            return true
        end) })
        if ok2 and h then
            ng_hook = h
        else
            mod.warn("城镇NPC无敌：StrikeNPC 钩子安装失败 " .. tostring(h))
        end
    end

    local function ng_cleanup()
        if ng_hook and ng_hook.remove then pcall(function() ng_hook:remove() end) end
        ng_hook = nil
    end

    return ng_setup, ng_cleanup
end)()


function mod.cleanup()
    -- v7.2.0：两个饰品收尾
    -- v4.6.6：把刷怪率两个字段还原成原版数值
    if _G.ms_powers and _G.ms_powers.restore then pcall(_G.ms_powers.restore) end
    -- v4.7.0：一键建造收尾
    if _G.ms_instant and _G.ms_instant.cleanup then pcall(_G.ms_instant.cleanup) end
    if _G.rf_cleanup then pcall(_G.rf_cleanup) end
    if _G.nst_cleanup then pcall(_G.nst_cleanup) end
    if _G.fh_cleanup then pcall(_G.fh_cleanup) end
    if _G.cs_cleanup then pcall(_G.cs_cleanup) end
    -- v7.7.0：法爆魔杖收尾（注销触摸按钮 + 卸内部钩子）
    if _G.ms_fbw_cleanup then pcall(_G.ms_fbw_cleanup) end
    pcall(tb_uninstall)
    pcall(pu_uninstall)
    if jr_cleanup then pcall(jr_cleanup) end
    if mp_cleanup then pcall(mp_cleanup) end
    if vm_cleanup then pcall(vm_cleanup) end
    if bd_cleanup then pcall(bd_cleanup) end
    if lp_cleanup then pcall(lp_cleanup) end
    if fi_cleanup then pcall(fi_cleanup) end
    if ps_cleanup then pcall(ps_cleanup) end
    if ab_cleanup then pcall(ab_cleanup) end
    if star_cleanup then pcall(star_cleanup) end
    if dot_cleanup then pcall(dot_cleanup) end
    if _G.ms_rcp_clean and _G.ms_rcp_clean.cleanup then pcall(_G.ms_rcp_clean.cleanup) end
    if peak_cleanup then pcall(peak_cleanup) end
    if sn_cleanup then pcall(sn_cleanup) end
    if py_cleanup then pcall(py_cleanup) end
    if rv_cleanup then pcall(rv_cleanup) end
    if lk_cleanup then pcall(lk_cleanup) end
    if zm_cleanup then pcall(zm_cleanup) end
    if lm_cleanup then pcall(lm_cleanup) end
    if zs_cleanup then pcall(zs_cleanup) end
    if ag_cleanup then pcall(ag_cleanup) end
    if EXT.sn.cleanup then pcall(EXT.sn.cleanup) end
    if EXT.sx.cleanup then pcall(EXT.sx.cleanup) end
    if EXT.mm.cleanup then pcall(EXT.mm.cleanup) end
    if EXT.lh.cleanup then pcall(EXT.lh.cleanup) end
    if EXT.om and EXT.om.cleanup then pcall(EXT.om.cleanup) end
    if EXT.wg and EXT.wg.cleanup then pcall(EXT.wg.cleanup) end
    if EXT.cr and EXT.cr.hooks_off then pcall(EXT.cr.hooks_off) end
    if EXT.afm and EXT.afm.cleanup then pcall(EXT.afm.cleanup) end
    if af_cleanup then pcall(af_cleanup) end
    if dm_cleanup then pcall(dm_cleanup) end
    if nh_cleanup then pcall(nh_cleanup) end
    if ng_cleanup then pcall(ng_cleanup) end
    if at_cleanup then pcall(at_cleanup) end
    if bb_cleanup then pcall(bb_cleanup) end
end

-- 第二十一部分：缩放扩展（v2.10.27 定稿；常开、无开关）
-- 需求：原版手机捏合缩放 0.58~2.00 → 0.36~2.00（放大上限不动，只扩小）。
-- 机制定案（v2.10.24 诊断实测）：MaxPixelScale 是捏合缩小的钳制点且单位为倒数
--   （缩小下限 = 1/MaxPixelScale；原值 1.70 → 0.588 ≈ 玩家看到的 0.58）；
--   MinPixelScale 管放大上限（1/0.50 = 2.0），不动。
-- 实测显示规律：2.7778(=1/0.36)→显示0.35，2.7027(=1/0.37)→显示0.37，
--   即显示值 = floor(1/MaxPixelScale 到两位小数)（float 略低会被截掉）。
--   故取 2.77（1/2.77≈0.36101）→ floor 后稳定显示 0.36。
-- ============================================================================
zm_setup, zm_cleanup = (function()
    local P = mod.patch
    local hook = nil
    local ZM_NEW = 2.77                 -- 1/2.77≈0.36101，向下截断后显示 0.36（默认值）
    -- v5.7.0：改成按设置里的「最小缩放」实时换算。显示值 = floor(1/MaxPixelScale, 2位)，
    --   所以要让显示为 X，需要 1/(X + 0.0011) —— 例：X=0.36 → 2.7691 → 显示 0.36。
    local function on_get_max_pixel_scale(inst, args, result)
        local G = _G.ms_gates
        if G then
            if not G.is("zm") then return nil end          -- 关掉就放行原版值
            local m = G.num("zm_min")
            if m and m > 0 then return 1.0 / (m + 0.0011) end
        end
        return ZM_NEW
    end
    local function zm_setup()
        local cam = nil
        local ok1, v1 = pcall(P.get_type, "", "XNAWorldCameraSettings")
        if ok1 then cam = v1 end
        if not cam then
            local ok2, v2 = pcall(P.get_type, nil, "XNAWorldCameraSettings")
            if ok2 then cam = v2 end
        end
        if not cam and P.get_type_by_name then
            local ok3, v3 = pcall(P.get_type_by_name, "XNAWorldCameraSettings")
            if ok3 then cam = v3 end
        end
        if not cam then
            mod.warn("缩放扩展：找不到 XNAWorldCameraSettings，跳过")
            return
        end
        local getter = nil
        local okp, prop = pcall(P.get_property, cam, "MaxPixelScale")
        if okp and prop then
            local okg, g = pcall(P.property_get_method, prop)
            if okg then getter = g end
        end
        if not getter then
            local okm, m = pcall(P.get_method, cam, "get_MaxPixelScale", 0)
            if okm then getter = m end
        end
        if not getter then
            mod.warn("缩放扩展：找不到 get_MaxPixelScale，跳过")
            return
        end
        local okh, h = pcall(P.install_hook, getter,
            { override_result = true, postfix = _G.mg_gated("zm", on_get_max_pixel_scale) })
        if okh then
            hook = h
        else
            mod.warn("缩放扩展：钩子安装失败: " .. tostring(h))
        end
    end
    local function zm_cleanup()
        if hook and hook.remove then pcall(function() hook:remove() end) end
        hook = nil
    end
    return zm_setup, zm_cleanup
end)()

-- ============================================================================
-- 第二十二部分：一键点亮地图（参考「一键点亮地图 v1.1.1」efmod 改造，v2.11.0 起）
-- 需求：模组设置页右列加「一键点亮」按钮；点击后逐步点亮整张地图。
-- 机制：调游戏原生 Main.Map.Update(x, y, 255)（按世界格子内容写入地图=已探索+满亮度），
--       逐帧批量扫描全图（借鉴原 mod 的 ProcessSlowLight 分帧思路），期间周期性置
--       Main.refreshMap=true 强制重绘。常开无开关；按钮启动/再点停止；完成自动停。
-- 适配 PE 1.4.5.8：Main.Map 为区块(chunk)化地图，Update 会按需加载区块，分帧摊薄开销。
-- ============================================================================
lm_setup, lm_cleanup, lm_gui = (function()
    local P = mod.patch
    local T_Main, T_Map
    local m_update, m_gm, m_map_get, m_refresh_set
    local f_maxw, f_maxh
    local running = false
    local cx, cy = 0, 0
    local total, done = 0, 0
    local frame = 0
    local logged = false          -- 一次性诊断
    local BATCH = 40000           -- 每帧处理格数（v2.12.7：10000→20000；v4.2.1：20000→40000，整体速度翻倍）
    local REFRESH = 15            -- 每多少帧触发一次地图重绘（v2.12.7：30→15，进度刷新更跟手）

    local function fi32(field, inst)
        if not field then return nil end
        local ok, v = pcall(P.get_field_value, field, inst, "int32")
        if ok then return v end
        return nil
    end

    local function in_world()
        if not m_gm then return true end   -- 拿不到 gameMenu 就不拦（按钮侧已拦）
        local ok, v = pcall(P.invoke, m_gm)
        return ok and v == false
    end

    local function refresh_map()
        if m_refresh_set then pcall(P.invoke, m_refresh_set, true) end
    end

    -- 取当前 WorldMap 实例（get_Map 属性 getter → retain 成 GC 副本，安全跨帧）
    local function get_map()
        if not m_map_get then return nil end
        local ok, mv = pcall(P.invoke, m_map_get)
        if not ok or not mv or mv == false then return nil end
        local okr, mr = pcall(P.retain, mv)
        if okr and mr then return mr end
        return mv
    end

    local function on_tick()
        if not running then return end
        if not m_update or not m_map_get then running = false return end
        if not in_world() then running = false return end
        local map = get_map()
        if not map then running = false return end
        local w = fi32(f_maxw, map)
        local h = fi32(f_maxh, map)
        if not w or not h or w <= 0 or h <= 0 then
            if not logged then
                logged = true
                mod.warn(string.format("一键点亮：尺寸无效 w=%s h=%s，停止", tostring(w), tostring(h)))
            end
            running = false
            return
        end
        total = w * h

        local n = 0
        while n < BATCH and cy < h do
            pcall(P.invoke, m_update, map, cx, cy, 255)
            cx = cx + 1
            if cx >= w then cx = 0 cy = cy + 1 end
            n = n + 1
            done = done + 1
        end

        frame = frame + 1
        if frame % REFRESH == 0 then refresh_map() end

        if cy >= h then
            refresh_map()
            running = false
            notify("你已看完(^～^)")
        end
    end

    local function lm_setup()
        T_Main = P.get_type("Terraria", "Main")
        T_Map  = P.get_type("Terraria.Map", "WorldMap")
        if not (T_Main and T_Map) then
            mod.warn("一键点亮：类型缺失 Main=" .. tostring(T_Main) .. " WorldMap=" .. tostring(T_Map))
            return
        end
        m_update = P.get_method(T_Map, "Update", 3)
        m_gm     = P.get_method(T_Main, "get_gameMenu", 0)
        f_maxw   = P.get_field(T_Map, "MaxWidth")
        f_maxh   = P.get_field(T_Map, "MaxHeight")
        -- PE 里 Main.Map / Main.refreshMap 是属性，用 getter/setter（回退 get_property）
        m_map_get = P.get_method(T_Main, "get_Map", 0)
        if not m_map_get then
            local okp, prop = pcall(P.get_property, T_Main, "Map")
            if okp and prop then local okg, g = pcall(P.property_get_method, prop); if okg then m_map_get = g end end
        end
        m_refresh_set = P.get_method(T_Main, "set_refreshMap", 1)
        if not m_refresh_set then
            local okp, prop = pcall(P.get_property, T_Main, "refreshMap")
            if okp and prop then local oks, s = pcall(P.property_set_method, prop); if oks then m_refresh_set = s end end
        end
        if not (m_update and m_map_get and f_maxw and f_maxh) then
            mod.warn(string.format("一键点亮：成员缺失 update=%s get_Map=%s maxw=%s maxh=%s",
                tostring(m_update), tostring(m_map_get), tostring(f_maxw), tostring(f_maxh)))
            return
        end
        tb_reg_frame("一键点亮", on_tick)
    end

    local function lm_cleanup()
        running = false
    end

    local function lm_gui(g, bx, by)
        if not m_update then
            g.text("一键点亮：模块未加载")
            return
        end
        if running and total > 0 then
            local lbl = string.format("点亮中%d%%", math.floor(done * 100 / total))
            local clicked
            if bx then clicked = btn_at(g, bx, by, lbl) else clicked = g.button(lbl) end
            if clicked then
                running = false
                notify("为何不看(·へ·)")
            end
        else
            local clicked
            if bx then clicked = btn_at(g, bx, by, "一键点亮") else clicked = g.button("一键点亮") end
            if clicked then
                if in_world() then
                    running, cx, cy, done, total, frame, logged = true, 0, 0, 0, 0, 0, false
                    notify("偷偷看一眼、两眼、三眼……(〃ω〃)")
                else
                    notify("请先进入世界-_-) zzz")
                end
            end
        end
    end

    return lm_setup, lm_cleanup, lm_gui
end)()


-- ============================================================================
-- 第二十八部分：双击地图传送（独立模组「双击地图传送（Lua）v1.0」并入 v3.1.0）
-- 需求：设置页左列「遗忘之物」下面加勾选框「地图传送」，默认关闭；
--   开/关各有一句播报。开启后双击小地图或大地图即可传送到目标格。
-- 机制（源码 + 原模组实测）：
--   钩 GUIMap.DrawMap(0) 拿地图实例，钩 PingMapLayer.Draw(2) 在其绘制时拿 GameTime 帧号，
--   同一帧内读 CursorManager 的触点数量/坐标，自己判双击（≤30 帧、同一地图、未拖动）；
--   命中则在 Player.ResetEffects 时调 Player.Teleport(Vector2, int, int) 并清零速度。
-- 差异（合入时）：
--   ① 删掉原模组全部诊断日志（钩子内文件 I/O 是老病灶）；
--   ② 钩子常驻、门控在回调里（MM_EN），关闭时零开销；
--   ③ 只跑单机（netMode != 0 直接不介入）。
-- ============================================================================
EXT.mm.setup, EXT.mm.cleanup, EXT.mm.set_enabled, EXT.mm.is_enabled, EXT.mm.gui = (function()
    local P = patch
    local H, hooks = {}, {}
    local MM_EN = false
    local failed = false
    local taps = { frame = nil, kind = nil }
    local active, last_frame, pending, map_instance = nil, -1, nil, nil
    local function read_on()
        local ok, raw = pcall(mod.read_file, "map_en.txt")
        if not ok or type(raw) ~= "string" or raw == "" then return false end
        return raw:match("^%s*1") ~= nil
    end
    local function write_on(v) pcall(mod.write_file, "map_en.txt", v and "1" or "0") end
    local function get(f, obj, ty)
        if not f then return nil end
        local ok, v = pcall(P.get_field_value, f, obj, ty)
        if ok then return v end
        return nil
    end
    local function call(m, ...)
        if not m then return nil end
        local ok, r = pcall(P.invoke, m, ...)
        if ok then return r end
        return nil
    end
    local function find_field(t, name)
        local cur, guard = t, 0
        while cur and guard < 16 do
            local f = P.get_field(cur, name)
            if f then return f end
            cur = P.get_parent(cur)
            guard = guard + 1
        end
        return nil
    end
    local function to_world(c, x, y)
        return c.mx + (x - c.ox) / c.scale, c.my + (y - c.oy) / c.scale
    end
    local function inside(r, x, y)
        return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
    end
    local function tap_reset() taps.frame = nil; taps.kind = nil end
    local function tap_add(frame, x, y, kind, radius)
        local matched = taps.frame and frame >= taps.frame and (frame - taps.frame) <= 30
            and taps.kind == kind and (x - taps.x) ^ 2 + (y - taps.y) ^ 2 <= radius * radius
        if matched then tap_reset(); return true end
        taps.frame, taps.x, taps.y, taps.kind = frame, x, y, kind
        return false
    end
    local function rect_of(ctx)
        local ok, v = pcall(P.mem_read_values, ctx, 16, 1, 'uint8')
        if not ok or not v or v[1] == 0 then return nil end
        local ok2, r = pcall(P.mem_read_values, ctx, 20, 4, 'int32')
        if not ok2 or not r or r[3] <= 0 or r[4] <= 0 then return nil end
        return { x = r[1], y = r[2], w = r[3], h = r[4] }
    end
    local function projection(ctx)
        local ok, v = pcall(P.mem_read_values, ctx, 0, 4, 'float')
        if not ok or not v then return nil end
        local ok2, s = pcall(P.mem_read_values, ctx, 36, 1, 'float')
        if not ok2 or not s then return nil end
        local scale = s[1]
        if not scale or scale ~= scale or scale < 0.01 or scale > 100 then return nil end
        for i = 1, 4 do
            if not v[i] or v[i] ~= v[i] or math.abs(v[i]) > 1e7 then return nil end
        end
        return { mx = v[1], my = v[2], ox = v[3], oy = v[4], scale = scale }
    end
    local function cursor_xy(c)
        local okp, x, y = pcall(P.get_field_vec2, H.cursor_pos, c)
        if not okp or type(x) ~= "number" then return nil end
        local runner = get(H.runner_instance, nil, 'object')
        if not runner then return nil end
        local cam = get(H.ui_camera, runner, 'object')
        if not cam then return nil end
        local sw, sh = call(H.screen_width), call(H.screen_height)
        local vw, vh = get(H.vw, cam, 'int32'), get(H.vh, cam, 'int32')
        if not sw or not sh or sw <= 0 or sh <= 0 or not vw or not vh or vw <= 0 or vh <= 0 then return nil end
        local ox, oy = get(H.vx, cam, 'int32'), get(H.vy, cam, 'int32')
        if not ox or not oy then return nil end
        return math.floor(x * vw / sw) + ox, math.floor((sh - y) * vh / sh) + oy, vw, vh
    end
    local function reset_touch() active = nil; tap_reset() end
    local function poll_map(ctx)
        if failed or not MM_EN then return end
        if not ctx or not map_instance then return end
        if call(H.game_menu) or get(H.net_mode, nil, 'int32') ~= 0 then reset_touch(); return end
        local fullscreen = call(H.fullscreen)
        local clip = rect_of(ctx)
        if (fullscreen and clip) or (not fullscreen and not clip) then return end
        local frame = get(H.frame, nil, 'int32')
        if not frame or frame == last_frame then return end
        last_frame = frame
        local camera = projection(ctx)
        local manager = get(H.cursor_manager, nil, 'object')
        if not camera or not manager then reset_touch(); return end
        local count = call(H.cursor_count, manager)
        if not count or count > 1 then reset_touch(); return end
        if count == 0 then active = nil; return end
        local c = call(H.cursor_at, manager, 0)
        if not c then reset_touch(); return end
        local x, y, vw, vh = cursor_xy(c)
        if not x or not y then reset_touch(); return end
        local down = get(H.cursor_down, c, 'bool')
        local was = get(H.cursor_was, c, 'bool')
        local id = get(H.cursor_id, c, 'int32')
        local kind = fullscreen and 'full' or 'mini'
        local within
        if fullscreen then within = x >= 0 and y >= 0 and x < vw and y < vh
        else within = inside(clip, x, y) end
        if fullscreen and within and call(H.map_controls, map_instance, c) then within = false end
        local radius = math.max(18, math.min(vw, vh) * 0.035)
        if down and not was then
            if within then active = { id = id, x = x, y = y, frame = frame, kind = kind, drag = false }
            else active = nil; tap_reset() end
        elseif active and active.id == id and active.kind == kind then
            if (x - active.x) ^ 2 + (y - active.y) ^ 2 > radius * radius then active.drag = true end
            if not down and was then
                local a = active; active = nil
                if within and not a.drag and frame >= a.frame and (frame - a.frame) <= 24 then
                    if tap_add(frame, x, y, kind, radius) then
                        local tx, ty = to_world(camera, x, y)
                        local maxx, maxy = get(H.max_x, nil, 'int32'), get(H.max_y, nil, 'int32')
                        if tx == tx and ty == ty and maxx and maxy and tx >= 2 and ty >= 2 and tx < maxx - 2 and ty < maxy - 2 then
                            pending = { x = tx * 16, y = ty * 16 }
                        end
                    end
                else tap_reset() end
            end
        elseif not down then active = nil end
    end
    local function teleport(player)
        if failed or not MM_EN then return end
        if not pending then return end
        if call(H.game_menu) or get(H.net_mode, nil, 'int32') ~= 0 then pending = nil; return end
        if get(H.who, player, 'int32') ~= call(H.my_player) then return end
        if get(H.dead, player, 'bool') then pending = nil; return end
        local dest = pending; pending = nil
        local width = get(H.width, player, 'int32')
        local height = get(H.height, player, 'int32')
        if not width or not height or width <= 0 or height <= 0 then return end
        pcall(P.invoke_value_args, H.teleport, player,
            { P.struct_arg({ 'float', 'float' }, { dest.x - width / 2, dest.y - height / 2 }), 0, 0 })
        pcall(P.set_field_vec2, H.velocity, player, 0, 0)
    end
    local function mm_setup()
        MM_EN = read_on()
        pcall(function()
            local main = P.get_type('Terraria', 'Main')
            local player = P.get_type('Terraria', 'Player')
            local map = P.get_type('', 'GUIMap')
            local layer = P.get_type('Terraria.Map', 'PingMapLayer')
            local cursor = P.get_type('', 'Cursor')
            local cm = P.get_type('', 'CursorManager')
            local runner = P.get_type('', 'XNAUnityRunner')
            local camera = P.get_type('', 'XNAUICameraSettings')
            local screen = P.get_type('UnityEngine', 'Screen')
            if not (main and player and map and layer and cursor and cm and runner and camera and screen) then
                error('地图传送类型缺失')
            end
            H.game_menu = P.get_method(main, 'get_gameMenu', 0)
            H.fullscreen = P.get_method(main, 'get_mapFullscreen', 0)
            H.my_player = P.get_method(main, 'get_myPlayer', 0)
            H.net_mode = find_field(main, 'netMode')
            H.max_x = find_field(main, 'maxTilesX')
            H.max_y = find_field(main, 'maxTilesY')
            H.frame = find_field(runner, '_frame')
            H.runner_instance = find_field(runner, '_instance')
            H.ui_camera = find_field(runner, 'UICameraSettings')
            H.vw = find_field(camera, 'realVirtualScreenWidth')
            H.vh = find_field(camera, 'realVirtualScreenHeight')
            H.vx = find_field(camera, 'realVirtualScreenOffsetX')
            H.vy = find_field(camera, 'realVirtualScreenOffsetY')
            H.screen_width = P.get_method(screen, 'get_width', 0)
            H.screen_height = P.get_method(screen, 'get_height', 0)
            H.cursor_manager = find_field(cm, 'Instance')
            H.cursor_count = P.get_method(cm, 'GetNumCursors', 0)
            H.cursor_at = P.get_method(cm, 'GetCursor', 1)
            H.cursor_pos = find_field(cursor, 'Position')
            H.cursor_down = find_field(cursor, 'Down')
            H.cursor_was = find_field(cursor, 'WasDown')
            H.cursor_id = find_field(cursor, 'Id')
            H.map_controls = P.get_method(map, 'IsCursorOverFullScreenMapControls', 1)
            H.who = find_field(player, 'whoAmI')
            H.dead = find_field(player, 'dead')
            H.width = find_field(player, 'width')
            H.height = find_field(player, 'height')
            H.velocity = find_field(player, 'velocity')
            H.teleport = P.get_method(player, 'Teleport', 3)
            if not (H.teleport and H.net_mode) then error('地图传送接口缺失') end
            local m_hook = P.install_hook(P.get_method(map, 'DrawMap', 0), {
                prefix = function(instance) map_instance = instance end,
                postfix = function() map_instance = nil end,
            })
            if m_hook then hooks[#hooks + 1] = m_hook end
            local l_hook = P.install_hook(P.get_method(layer, 'Draw', 2), {
                prefix = function(_, args) poll_map(args and args[1]) end,
            })
            if l_hook then hooks[#hooks + 1] = l_hook end
            local p_hook = P.install_hook(P.get_method(player, 'ResetEffects', 0), {
                postfix = function(pl) teleport(pl) end,
            })
            if p_hook then hooks[#hooks + 1] = p_hook end
        end)
        if #hooks == 0 then
            failed = true
            mod.error('[地图传送] 初始化失败，本模块不工作')
        else
            mod.info('[地图传送] 已加载，状态=' .. (MM_EN and '开' or '关') .. '，钩子数=' .. #hooks)
        end
    end
    local function mm_cleanup()
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
        active, pending, map_instance = nil, nil, nil
        reset_touch()
        MM_EN = false
    end
    local function mm_set_enabled(v)
        MM_EN = v and true or false
        write_on(MM_EN)
        if not MM_EN then reset_touch(); pending = nil end
    end
    local function mm_is_enabled() return MM_EN end
    local function mm_gui(g, notify, bx, by)
        if failed or not H.teleport then
            g.text("地图传送：模块未加载")
            return
        end
        local label = MM_EN and "地图传送（已开启）" or "地图传送（已关闭）"
        local clicked
        if bx then clicked = btn_at(g, bx, by, label) else clicked = g.button(label) end
        if clicked then
            local nv = not MM_EN
            mm_set_enabled(nv)
            if notify then
                notify(nv and "想去哪就去哪(＞з＜)" or "您自个儿腿着去吧（`·ω·’）")
            end
        end
    end
    return mm_setup, mm_cleanup, mm_set_enabled, mm_is_enabled, mm_gui
end)()



-- ============================================================================
-- ============================================================================
-- 残血提示模块（v3.3.0 由独立模组「残血提示 v2.1.1」bluefish.lowhpwarn 并入）
--   ① 玩家头顶显示耐药性 Buff（BuffID 21）图标 + 3×5 点阵倒计时
--   ② 血量不高于 30% 时屏幕四边红色渐变边框 + 呼吸
--   常开、无开关（v3.4.1 起去掉设置页勾选框与 lh_en.txt）
--   资源：Resources/lib/lowhp/hud.lua（头顶绘制桥）、Resources/lib/ui/border.png（边框贴图）
--   红框走 Main.Draw postfix 自开界面批次，复用 bossbar.bridge + bossbar_native.so
--   注：主 chunk 的 local 已到上限，故挂 EXT.lh
-- ============================================================================
EXT.lh.setup, EXT.lh.cleanup, EXT.lh.set_enabled, EXT.lh.is_enabled, EXT.lh.gui = (function()
    local P = patch
    local BUFF_ID     = 21
    local HP_RATIO    = 0.30
    local EDGE_PERIOD = 1.92   -- 边框呼吸周期（秒）
    local TWO_PI      = 6.283185307179586
    local PLAYER_LIFT = 26
    local DOT         = 3

    local LH_EN = true
    local hooks = {}
    local hud, br
    local tex
    local owned = {}
    local failed = false
    local failed_buff, failed_edge = false, false
    -- ---- 开关 ----
    -- v8.3.5：门控下沉到回调，勾选后立刻生效，不再需要重启
    local function lh_on()
        if not LH_EN then return false end
        local G = _G.ms_gates
        if G and not G.is("lh") then return false end
        return true
    end
    local function lh_set_enabled() end
    local function lh_is_enabled() return lh_on() end

    -- ---- 3×5 点阵数字 ----
    local DIGITS = {
        ['0'] = { '111', '101', '101', '101', '111' }, ['1'] = { '010', '110', '010', '010', '111' },
        ['2'] = { '111', '001', '111', '100', '111' }, ['3'] = { '111', '001', '111', '001', '111' },
        ['4'] = { '101', '101', '111', '001', '001' }, ['5'] = { '111', '100', '111', '001', '111' },
        ['6'] = { '111', '100', '111', '101', '111' }, ['7'] = { '111', '001', '010', '010', '010' },
        ['8'] = { '111', '101', '111', '101', '111' }, ['9'] = { '111', '101', '111', '001', '111' },
    }
    local DIGIT_SEGS = {}
    for k, rows in pairs(DIGITS) do
        local segs = {}
        for row = 1, 5 do
            local line = rows[row]
            local c = 1
            while c <= 3 do
                if line:sub(c, c) == '1' then
                    local run = 1
                    while c + run <= 3 and line:sub(c + run, c + run) == '1' do run = run + 1 end
                    segs[#segs + 1] = { (c - 1) * DOT, (row - 1) * DOT, run * DOT }
                    c = c + run
                else
                    c = c + 1
                end
            end
        end
        DIGIT_SEGS[k] = segs
    end

    local function draw_number(batch, px, cx, y, text)
        local adv = DOT * 3 + 2
        local width = #text * adv - 2
        local x0 = math.floor(cx - width / 2 + 0.5)
        for i = 1, #text do
            local segs = DIGIT_SEGS[text:sub(i, i)]
            if segs then
                local ox = x0 + (i - 1) * adv
                for q2 = 1, #segs do
                    local s = segs[q2]
                    hud:draw_tex(batch, px, ox + s[1], y + s[2], s[3], DOT, hud.WHITE)
                end
            end
        end
    end

    -- ---- 找耐药性 Buff，返回剩余帧数 ----
    local function find_buff(pl)
        local types = hud:read(hud.p_buff, pl, 'object')
        local times = hud:read(hud.p_buff_time, pl, 'object')
        if not types or not times then return nil end
        for i = 0, 21 do
            local ok, id = pcall(hud.p.array_at, types, i, 'int32')
            if ok and id == BUFF_ID then
                local ok2, left = pcall(hud.p.array_at, times, i, 'int32')
                if ok2 and type(left) == 'number' and left > 0 then return left end
                return nil
            end
            if ok and id == 0 then break end
        end
        return nil
    end

    local icon_tex, icon_w, icon_h
    local tick = 0
    local function draw_buff(batch, px, cx, top, seconds)
        if not icon_tex then
            local t0 = hud:buff_texture(BUFF_ID)
            if not t0 then return end
            local w0, h0 = hud:tex_size(t0)
            if w0 <= 0 or h0 <= 0 or w0 > 256 or h0 > 256 then return end
            icon_tex, icon_w, icon_h = t0, w0, h0
        end
        local x = math.floor(cx - icon_w / 2 + 0.5)
        local y = math.floor(top - icon_h - 8 + 0.5)
        hud:draw_tex(batch, icon_tex, x, y, icon_w, icon_h, hud.WHITE)
        local secs = math.ceil(seconds / 60)
        if secs > 99 then secs = 99 end
        -- 倒计时是整数秒，一秒才变一次；每 2 帧刷一次位置，视觉无差别但省一半绘制调用
        if tick % 2 == 0 then
            draw_number(batch, px, cx, y + icon_h + 3, tostring(secs))
        end
    end

    -- ---- 头顶 buff：状态缓存与分层节拍（30 / 2 / 6 帧）----
    local c_gs, c_pl, c_batch, c_pl_ok, c_pw = nil, nil, nil, false, 0
    local c_menu = false
    local c_life, c_life_max = 0, 0
    local c_buff
    local at_slow, at_life, at_buff = -999, -999, -999
    local pix

    local function get_pixel()
        if pix then return pix end
        local ok, v = pcall(hud.magic_pixel, hud)
        if ok and v then pix = v end
        return pix
    end

    local function refresh_slow()
        c_gs, c_pl, c_batch, c_pl_ok = nil, nil, nil, false
        local gs = hud:state()
        if not gs then return end
        c_gs = gs
        c_menu = hud:read(hud.gs_menu, gs, 'bool') == true
        if c_menu then return end
        local pl = hud:local_player(gs)
        if not pl then return end
        if hud:read(hud.p_active, pl, 'bool') == false then return end
        if hud:read(hud.p_dead, pl, 'bool') == true then return end
        c_pl, c_pl_ok = pl, true
        c_pw = hud:read(hud.p_w, pl, 'int32') or 0
        c_batch = hud:read(hud.sprite_batch, nil, 'object')
    end

    local function step()
        if failed or not hud or not lh_on() then return end
        tick = tick + 1
        if tick > 1000000 then tick = 0 end
        if tick - at_slow >= 30 then
            at_slow = tick
            refresh_slow()
        end
        local gs, pl = c_gs, c_pl
        if not gs then return end
        if tick - at_life >= 2 and pl then
            at_life = tick
            c_life = hud:read(hud.p_life, pl, 'int32') or 0
            c_life_max = hud:read(hud.p_life_max, pl, 'int32') or 0
        end
        if tick - at_buff >= 6 then
            at_buff = tick
            c_buff = (c_pl_ok and pl) and find_buff(pl) or nil
        end
        if not c_pl_ok or not pl then return end
        local buff_secs = c_buff
        if not buff_secs then return end
        local batch = c_batch
        if not batch then return end
        local px = get_pixel()
        if not px then return end
        if not hud:begin_frame() then return end
        if hud:read(hud.batch_begun, batch, 'bool') ~= true then return end
        local camx, camy = hud:vec2(hud.camera, gs)
        local ppx, ppy = hud:vec2(hud.p_pos, pl)
        if ppx then
            local cx = ppx + c_pw / 2 - (camx or 0)
            local top = ppy - (camy or 0) - PLAYER_LIFT
            draw_buff(batch, px, cx, top, buff_secs)
        end
    end

    local function safe_step()
        if failed or failed_buff or not lh_on() then return end
        local ok, err = pcall(step)
        if not ok then
            failed_buff = true
            pcall(mod.error, "[残血] 头顶buff绘制出错，已停用: " .. tostring(err))
        end
    end

    -- ---- 红框（贴图呼吸）----
    local T_screen, g_uw, g_uh, m_adjust

    local function pin(obj, unity)
        local root = br:root(obj)
        if not root then error("无法持有纹理") end
        owned[#owned + 1] = { object = obj, root = root, unity = unity }
        return obj
    end

    local function load_edge_texture()
        local path = mod.private_dir .. "/lib/ui/border.png"
        local bytes = pin(br:call(br.read_bytes, path))
        local u = pin(br:construct(br.unity_ctor, 2, 2, 4, false), true)
        assert(br:call(br.load_png, u, bytes, false) == true, "PNG 解码失败")
        br:call(br.filter, u, 1)
        br:call(br.wrap, u, 1)
        return pin(br:construct(br.xna_ctor, u))
    end

    local src_full             -- 红框源矩形（固定值，缓存一次）
    local edge_sb              -- SpriteBatch 引用缓存
    local edge_rect            -- 绘制区域缓存 {left, top, width, height}
    local edge_tick = 0

    -- 红框每帧的实际工作（提到外面定义，避免每帧新建闭包喂 GC）
    local function edge_frame()
        if c_menu then return end
        if c_life_max <= 0 or c_life <= 0 then return end
        if c_life / c_life_max > HP_RATIO then return end
        edge_tick = edge_tick + 1
        local sb = edge_sb
        local left, top, width, height
        -- 屏幕尺寸/UI 缩放基本不变：每 60 帧才重算一次，平时直接用缓存
        if edge_rect and edge_tick % 60 ~= 0 then
            left, top, width, height = edge_rect[1], edge_rect[2], edge_rect[3], edge_rect[4]
        else
            sb = P.get_field_value(br.sprite_batch, nil, 'object')
            if not sb then return end
            edge_sb = sb
            local uw = P.invoke(g_uw)
            local uh = P.invoke(g_uh)
            if type(uw) ~= 'number' or type(uh) ~= 'number' or uw <= 0 or uh <= 0 then return end
            -- v7.0.0：用 bridge 的 AdjustRealScreenForUI（纯 Lua，结构体返回值按原始字节解），
            -- 把 Unity 屏幕坐标换成 UI 坐标 —— 画在 UI 坐标系里就跟世界缩放无关。
            if m_adjust then
                local x1, y1 = br:adjust_screen(m_adjust, 0, 0)
                local x2, y2 = br:adjust_screen(m_adjust, uw, uh)
                if type(x1) == 'number' and type(y1) == 'number'
                    and type(x2) == 'number' and type(y2) == 'number' then
                    left, top = math.min(x1, x2), math.min(y1, y2)
                    width, height = math.abs(x2 - x1), math.abs(y2 - y1)
                end
            end
            if not width or width < 1 or height < 1 then
                left, top, width, height = 0, 0, uw, uh
            end
            edge_rect = { left, top, width, height }
        end
        if not sb then return end
        local now = br:call(br.time) or 0
        local intensity = 0.48 + 0.52 * (0.5 - 0.5 * math.cos(now * TWO_PI / EDGE_PERIOD))
        local alpha = math.floor(255 * intensity + 0.5)
        if not tex then tex = load_edge_texture() end
        if not src_full then src_full = br:source(0, 0, 1920, 1080) end
        local col = br:color(alpha, alpha, alpha, alpha)
        br:begin_hud(sb)
        local ok2, err2 = pcall(br.draw_sprite, br, sb, tex, left, top, width, height, src_full, col)
        if not ok2 then
            pcall(br.end_hud, br, sb)
            error(err2)
        end
        br:end_hud(sb)
    end
    local function edge_draw()
        if failed or failed_edge or not br or not lh_on() then return end
        local ok, err = pcall(edge_frame)
        if not ok then
            failed_edge = true
            pcall(mod.error, "[残血] 边框绘制出错，已停用: " .. tostring(err))
        end
    end
    -- ---- setup / cleanup ----
    local function lh_init()
        LH_EN = true
        failed = false
        failed_buff, failed_edge = false, false
        -- v7.0.0：先建纯 Lua bridge（头顶 buff 与红框共用）
        local okB, errB = pcall(function() br = require('bossbar.bridge').new(P) end)
        if not okB then
            br = nil
            pcall(mod.error, "[残血] bridge 初始化失败: " .. tostring(errB))
        end
        -- 头顶 buff（Main.DrawNPCs postfix）
        local okH, errH = pcall(function()
            local H = assert(require('lowhp.hud'), "require 返回空")
            hud = H.new(P, br)
            local dh = _G.EXT_DH
            if dh then dh.draw_npcs = safe_step end
        end)
        if not okH then
            hud = nil
            pcall(mod.error, "[残血] 头顶buff初始化失败: " .. tostring(errH))
        end
        -- 红框（Main.Draw postfix，自开界面批次）
        local okE, errE = pcall(function()
            assert(br, "bridge 未就绪")
            T_screen = assert(P.get_type('UnityEngine', 'Screen'), "缺少 UnityEngine.Screen")
            g_uw = assert(P.property_get_method(P.get_property(T_screen, 'width')), "缺少 Screen.width")
            g_uh = assert(P.property_get_method(P.get_property(T_screen, 'height')), "缺少 Screen.height")
            -- 坐标换算走软依赖：拿不到就靠 edge_frame 的全屏兜底（位置可能偏，但不会整个消失）
            local runner = P.get_type('', 'XNAUnityRunner')
            m_adjust = runner and P.get_method(runner, 'AdjustRealScreenForUI', 1) or nil
            local dh = _G.EXT_DH
            if dh then dh.main_draw = edge_draw end
        end)
        if not okE then
            br = nil
            pcall(mod.error, "[残血] 红框初始化失败: " .. tostring(errE))
        end
    end
    -- 初始化必须在模组装载阶段同步跑完（和独立版一致）。
    -- 挪到帧回调里等于在渲染循环中做大量反射解析，实测直接 SIGABRT。
    local function lh_setup()
        LH_EN = true
        failed = false
        local okI, errI = pcall(lh_init)
        if not okI then pcall(mod.error, "[残血] 初始化异常: " .. tostring(errI)) end
    end

    local function lh_cleanup()
        failed = true
        do
            local dh = _G.EXT_DH
            if dh then
                if dh.draw_npcs == safe_step then dh.draw_npcs = nil end
                if dh.main_draw == edge_draw then dh.main_draw = nil end
            end
        end
        for i = #hooks, 1, -1 do
            pcall(function() hooks[i]:remove() end)
            hooks[i] = nil
        end
        if br then
            for i = #owned, 1, -1 do
                local o = owned[i]
                if o.unity then pcall(br.call, br, br.destroy, o.object) end
                pcall(br.call, br, br.unroot, o.root)
            end
        end
        owned = {}
        tex = nil
        icon_tex = nil
        pix = nil
        edge_sb, edge_rect, src_full = nil, nil, nil
        if hud then pcall(hud.cleanup, hud) end
        hud, br = nil, nil
    end

    local function lh_gui() end

    return lh_setup, lh_cleanup, lh_set_enabled, lh_is_enabled, lh_gui
end)()


todo_list = { "setup" }
