-- ============================================================================
-- 更好的猛冲与跳跃 (Better Dash & Roll) —— LuaLoader 版  v2.0.0
-- pkg: lua.bluefish.jumproll   author: 蓝色大肥鱼
-- 功能：猛冲、跳跃时翻滚，翻滚期间无敌，翻滚结束获得一次猛击
-- v2.0.0 改动（用户第11轮反馈：①设置界面删无敌帧时间输入 ②惊人一刻改翻滚后猛击 ③版本2.0.0 ④新文案）：
--   1) 模组设置界面【删除】「无敌帧时间（秒）」输入项（iframe_time），只保留 翻滚无敌 / 翻滚后猛击
--      两个开关；无敌时长【固定 0.17 秒】（≈10帧@60fps），不再可从界面修改。
--   2) 【翻滚附加惊人一刻】改为【翻滚后猛击】：触发时机从翻滚【开始】(roll_timer==roll_total)
--      改为翻滚【结束】(翻滚动作最后一帧 roll_timer<=1 时)给角色附加【惊人一刻】(ParryDamageBuff=198)增益。
--   3) 版本号 2.0.0 / versionCode 200；介绍文案更新；打包名「更好的猛冲与跳跃v2.0.0正式版.zip」。
-- v1.0.14 改动（用户第10轮反馈：①无敌帧还是没生效 ②不要再生成 jumproll.log）：
--   1) 【真正的根因】v1.0.8~v1.0.13 无敌全没生效：Player.immune（无敌标志）是独立字段
--      (Player.cs:1403 public bool immune)，原版伤害判定只看 immune；
--      之前只写了 immuneTime 数值、从未设 immune=true → 游戏根本不当回事，翻滚撞怪照常掉血。
--   2) 无敌帧改为【撞击触发式·仿疾旋鼬(物品5665/冲撞)】：翻滚期间逐帧检测玩家矩形是否
--      与敌怪矩形相交（枚举 Main.npc，过滤 active/非友好/damage>0），撞到的瞬间给
--      immune=true + immuneTime(默认0.17s≈10帧)；0.17秒免疫窗口结束后若仍贴着怪会再次
--      触发 → 贴怪不掉血、撞完离开后免疫自然耗尽，手感贴近疾旋鼬冲撞。
--   3) 彻底移除 jumproll.log 文件日志（删除 open_log/文件句柄写入，wlog 仅保留内存环形
--      缓冲，不再生成任何文件）。
-- v1.0.13 改动（用户第9轮反馈：①改名 更好的猛冲与跳跃 ②翻滚无敌帧没生效）：
--   1) 模组名称改为【更好的猛冲与跳跃】（Info.json name / 打包文件名同步）。
--   2) 无敌帧改为【翻滚全程维持】：v1.0.8 只在校准帧(roll_timer==roll_total)设置一次
--      immuneTime=10帧(0.17s)，但侧滚共30帧(0.5s)、空翻18帧(0.3s)，后半段无敌已耗尽
--      → 实测"翻滚被怪打没无敌"。现改为执行翻滚期间每帧都把 immuneTime 补到 target，
--      翻滚全程保持无敌（时长仍受 iframe_time 控制，0~0.5s）。
--   3) 日志多路径备选（/sdcard/Download、/storage/emulated/0/Download、/data/local/tmp
--      等4个候选路径，任一可写即可），避免单路径权限/占用导致诊断日志丢失。
-- v1.0.12 改动（修复用户第8轮反馈：翻滚完全消失）：
--   1) Bug1 修复：load_config() 全程 pcall 防御 + setup 调用处包 pcall，
--      配置读取/解析任何异常都只记日志不中断 setup —— 翻滚引擎(hook)必装，翻滚必恢复。
--   2) Bug2 修复：give_parry_buff 函数下移到 H/fv 定义之后，消除前向引用（此前一旦翻滚触发必崩）。
--   3) 动作参数与 v1.0.8 完全一致（roll_frames=30 / air_frames=18 / 触发条件 / 角度），手感不变。
-- v1.0.11 改动（用户第7轮反馈）：
--   1) 无敌帧时间自定义：模组设置界面新增【无敌帧时间（秒）】输入（0~0.5，默认 0.17）。
--   2) 翻滚附加【惊人一刻】增益（Terraria.ID.BuffID.ParryDamageBuff = 198，近战伤害大幅提升）：
--      每次翻滚（跳跃空翻/冲刺侧滚）触发时给本地玩家附加该 buff（300 帧 ≈ 5 秒），
--      并新增模组设置界面开关【翻滚附加惊人一刻】（默认开启）。
-- v1.0.10 改动（用户第6轮反馈：要模组界面里的开关，不要文件管理器改）：
--   1) 模组介绍改为：跳跃、冲刺时角色会翻滚，支持翻滚期间附带无敌。
--   2) 翻滚无敌开关改为【模组设置界面】方式 —— Info.json settings（CHOICE 开关）
--      + Resources/config.json 存储（schemaVersion:1 + values.iframe）+ main.lua
--      load_config() 用 dkjson 读取（与「武器无敌帧自定义」模组完全一致）。
--   3) 移除 v1.0.9 的外部 txt 配置文件方式（jumproll_config.txt 不再读取/生成）。
-- v1.0.9 改动（用户第5轮需求补全：外部配置文件）：
--   1) 新增外部配置文件 /sdcard/Download/jumproll_config.txt：
--      启动时若存在则逐行 key=value 覆盖配置（iframe/iframe_time/roll_frames/air_frames 等），
--      不存在则自动生成带中文注释的默认模板 —— 用手机文件管理器直接改，重启游戏即生效
--      （加载器开调试模式后，还可游戏聊天框内输 /reload 热生效，不用重进）。
-- v1.0.8 改动（用户第5轮需求）：
--   1) 模组介绍精简为一句；无敌帧改为可配置时长（0~1秒，默认0.17秒≈10帧），并保留翻滚无敌总开关。
-- v1.0.7 改动（用户实测第4轮反馈）：
--   1) 翻滚方向只往右（左冲刺也往右翻）——v1.0.4 的"正角度+镜像"假设不成立，
--      现触发时记录方向 g_roll_dir（侧滚=冲刺方向、空翻=人物朝向），执行时角度按方向走正负。
-- v1.0.6 改动（用户实测第3轮反馈2项）：
--   1) 误触发（只碰方向键走路/小跳也翻滚）——
--      冲刺侧滚改为检测 velocity.X 突变到冲刺速度（≥CFG.dash_vx≈11，真冲刺≈16，跑步≈6 不误触发），
--      且起始点对准"真正冲刺加速"那一刻（旧 dashTime=±15 只是双击预备帧，翻滚提前开始）。
--      跳跃空翻 vy 阈值从 -0.5 收紧到 -2.0（排除走下坡/小颠簸），并消除"速度方式+字段方式"双触发。
--   2) 翻滚太快、先翻滚再冲刺出去 —— 侧滚 roll_frames 14→30（约0.5秒转一圈，更慢更贴合冲刺滑行）。
-- v1.0.5 改动（用户实测第2轮反馈2项）：
--   1) 往左不翻滚的真正根因 —— PC源码 dashTime 向左冲刺 = -15（负值，向右=+15），
--      旧触发条件 dash>0 只认正值，向左冲刺从未进入翻滚逻辑（v1.0.4 只改了角度符号，没碰触发，所以还是不行）。
--      现改为 dash~=0 且 prev_dash==0 即触发（正负都行），方向照旧交给 direction 的 sprite 镜像呈现。
--   2) 翻滚太快 —— 冲刺侧滚一圈改为 = 整个冲刺周期（取 |dashTime|，15帧→0 与 -15帧→0 都是15帧），
--      翻滚与冲刺动作同步结束；跳跃空翻保持 CFG.air_frames 可调。
-- v1.0.4 改动（用户实测反馈4项修复）：
--   1) 向左翻滚没动作 —— 旧版 dir=-1 时 fullRotation 走负角度(0→-2π)，PE 渲染不认负角度整圈 → 左翻无动画。
--      现改为角度永远走正（g_roll_angle 0→+2π），方向交给 direction=-1 的 sprite 水平镜像自动呈现。
--   2) 气球束第二段跳不触发 —— 旧版只检测 vy 从 ≥-0.5 跳到 < -0.5 的上升沿；二段跳发生在上升途中（vy 已为负再变负）。
--      新增二段跳信号：not jump_trigger 且 prev_vy < -0.5 且 vy < prev_vy - 2.0 时也触发。
--   3) 翻滚中心太靠下 —— 旋转原点 (width/2, height)（脚底）改为 (width/2, height/2)（身体中部），对齐蹦蹦跷。
--   4) 坐骑误判 —— v1.0.3 已修复（Mount._type>0 才算占用），本轮保留并回归验证。
-- v1.0.3 改动：修复"触发正常但翻滚不显示"：
--   1) rotation_busy 坐骑判定 bug —— 之前 mount 对象非 nil 即视为占用（但玩家没坐骑时 mount 也是非 nil 的空对象，
--      type=0），导致每次翻滚触发后都被静默跳过。现改为读取 Mount._type，仅 type>0（真骑了东西）才算占用。
--   2) 旋转原点 fullRotationOrigin 改局部坐标 (width/2, height)（对齐动作优化姿势；PE 上它是相对 sprite 的局部偏移，
--      之前写成世界坐标 px+w/2,py+h/2 会让旋转中心错乱）。
--   3) 诊断日志扩容：busy 判定/执行翻滚段都记录（前100条），一次运行即可看清全链路。
-- v1.0.2 改动：修复 wlogf/wlog_w 中 '...' 在匿名函数内的语法错误（此前导致整个脚本无法编译加载）
--   1) 增加 wlog 文件日志（/sdcard/Download/jumproll.log），
--      因为 mod.info 不会出现在 TEFKernel runtime 日志中（已确认），
--      必须像参考模组(动作优化/mp16.log)一样自己写文件才能看到执行轨迹
--   2) 跳跃检测从 jumping 字段改为 velocity.Y < 0（上升沿），
--      因为 jumping 字段在 PE 上存在性存疑（动作优化参考模组从不使用它）
--   3) 字段绑定改用继承链搜索(find_field)，更健壮
--   4) setup 逐项记录绑定结果，任何失败都能在日志里看到
-- 参考：动作优化(mp16) 的 Player.Update hook + wlog 调试法
--       武器背显(WeaponOutBack) 的 find_field 继承链字段搜索
-- ============================================================================
mod.meta = { pkg_id = "lua.bluefish.jumproll", version = "2.2.0", version_code = 202, api_version = 1 }
local P = mod.patch

-- ============================================================================
-- 调试日志（v1.0.14：不再写任何文件 —— 用户要求不生成 jumproll.log）
-- 仅保留内存环形缓冲（最近 200 条），异常时随 mod.error 一起带出，平时不落盘。
-- ============================================================================
local g_dbg = {}     -- 内存环形缓冲
local g_dbg_n = 0
local function wlog(s)
    g_dbg_n = g_dbg_n + 1
    g_dbg[g_dbg_n % 200] = os.date("%H:%M:%S") .. " " .. tostring(s)
end
local function wlogf(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if ok then wlog(msg) end
end
-- W 前缀 = 总会打（前300条）—— v1.0.14 起仅内存，不写文件
local g_wcount = 0
local function wlog_w(fmt, ...)
    g_wcount = g_wcount + 1
    if g_wcount > 300 then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if ok then wlog(msg) end
end
-- 取出最近日志（供 setup 异常时随 mod.error 输出）
local function dump_dbg()
    local lines = {}
    for i = 0, 199 do
        local s = g_dbg[(g_dbg_n - i) % 200]
        if s then lines[#lines + 1] = s end
        if #lines >= 40 then break end
    end
    return table.concat(lines, " | ")
end

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
    trail        = true,   -- v2.1.0: 翻滚残影（true=翻滚期间冒烟粒子拖尾，false=无残影）
    dash_roll    = true,   -- v2.2.0: 冲刺翻滚（true=冲刺时侧滚，false=冲刺不翻滚）
    jump_roll    = true,   -- v2.2.0: 跳跃翻滚（true=跳跃/二段跳时空翻，false=跳跃不翻滚）
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
    -- v2.1.0: trail —— 翻滚残影开关（与合集 v2.16.0 残影同步）
    local tr = pick("trail", function()
        if type(v.trail) == "string" then
            return (v.trail == "true" or v.trail == "1")
        elseif type(v.trail) == "boolean" then
            return v.trail
        end
        return nil
    end)
    if tr ~= nil then
        CFG.trail = tr
        wlogf("配置[trail] = %s (来自 config.json)", tostring(CFG.trail))
    else
        wlog("config.json 未含 trail，使用默认值 (trail=true)")
    end
    -- v2.2.0: dash_roll —— 冲刺翻滚开关
    local dr = pick("dash_roll", function()
        if type(v.dash_roll) == "string" then
            return (v.dash_roll == "true" or v.dash_roll == "1")
        elseif type(v.dash_roll) == "boolean" then
            return v.dash_roll
        end
        return nil
    end)
    if dr ~= nil then
        CFG.dash_roll = dr
        wlogf("配置[dash_roll] = %s (来自 config.json)", tostring(CFG.dash_roll))
    else
        wlog("config.json 未含 dash_roll，使用默认值 (dash_roll=true)")
    end
    -- v2.2.0: jump_roll —— 跳跃翻滚开关
    local jr2 = pick("jump_roll", function()
        if type(v.jump_roll) == "string" then
            return (v.jump_roll == "true" or v.jump_roll == "1")
        elseif type(v.jump_roll) == "boolean" then
            return v.jump_roll
        end
        return nil
    end)
    if jr2 ~= nil then
        CFG.jump_roll = jr2
        wlogf("配置[jump_roll] = %s (来自 config.json)", tostring(CFG.jump_roll))
    else
        wlog("config.json 未含 jump_roll，使用默认值 (jump_roll=true)")
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
local function ffloat(field, inst) return fv(field, inst, "float") end
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

-- ============================================================================
-- v2.1.0: 翻滚残影（自模组合集 v2.16.0 定稿同步）—— 翻滚执行期间每 2 帧在玩家位置
-- 发烟尘粒子（Dust.NewDust type=31），存续 2 秒、体积 1.6 倍。
-- 用游戏原生粒子系统，零额外钩子/零文件IO；句柄获取失败自动静默关闭。
-- 收进单张 trail 表：节省主 chunk local 寄存器（上限 200）
-- ============================================================================
local trail = { ready = false, fail = false, frame = 0, m = nil, v2 = nil }

function trail.init()
    if trail.ready or trail.fail then return end
    local ok, err = pcall(function()
        local V2 = P.get_type("Terraria", "Vector2") or P.get_type("System", "Vector2") or P.get_type("Microsoft.Xna.Framework", "Vector2")
        local DUST = P.get_type("Terraria", "Dust")
        if not (V2 and DUST) then error("类型缺失 V2=" .. tostring(V2) .. " Dust=" .. tostring(DUST)) end
        trail.v2 = V2
        trail.m = P.get_method(DUST, "NewDust", 7)
            or P.get_method(DUST, "NewDust", 6)
            or P.get_method(DUST, "NewDust", 5)
        if not trail.m then error("Dust.NewDust 方法未找到") end
    end)
    if ok then
        trail.ready = true
        wlog("trail_init OK NewDust=" .. tostring(trail.m))
    else
        trail.fail = true
        wlog("trail_init 失败(残影关闭): " .. tostring(err))
    end
end

function trail.emit(inst)
    if not CFG.trail or trail.fail then return end
    if not trail.ready then trail.init() end
    if not trail.ready then return end
    trail.frame = trail.frame + 1
    if trail.frame % 2 ~= 0 then return end -- 每 2 帧 1 次
    local ok, err = pcall(function()
        local px, py = fvec2(H.p.position, inst)
        if px == nil then return end
        local w = fint(H.p.width, inst) or 20
        local h = fint(H.p.height, inst) or 42
        local v2 = P.new_instance(trail.v2, nil)
        pcall(P.set_field_value, v2, "X", px, "float")
        pcall(P.set_field_value, v2, "Y", py, "float")
        -- v2.16.x 定稿参数：存续 2 秒（120 帧）、体积 1.6 倍；NewDust 初速传 0
        local d = P.invoke(trail.m, nil, v2, w, h, 31, 0.0, 0.0, 0) -- type=31 烟雾 DustID.smoke
        if d then
            pcall(P.set_field_value, d, "activeTime", 120, "int32") -- 存续 2 秒
            pcall(P.set_field_value, d, "scale", 1.6, "float")      -- 放大，残影更清晰
        end
    end)
    if not ok then
        trail.fail = true
        wlog("emit_trail 异常(残影关闭): " .. tostring(err))
    end
end

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
local function upd_post(inst, args, result)
    g_upd_n = g_upd_n + 1
    if not inst then return false end
    if g_upd_n <= 3 then wlogf("upd_post 被调用 #%d inst=%s", g_upd_n, tostring(inst)) end
    pcall(function()
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
            -- v2.2.0: 冲刺翻滚开关（关闭时只记录状态，不触发翻滚）
            if CFG.dash_roll then
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
            -- v2.2.0: 跳跃翻滚开关（关闭时跳跃/二段跳都不空翻）
            if CFG.jump_roll then
                roll_timer = CFG.air_frames
                roll_total = CFG.air_frames
                g_roll_angle = 0.0 -- v1.0.4: 重置累计角度
                local jd = fint(H.p.direction, inst) or 1
                if jd == 0 then jd = 1 end
                g_roll_dir = jd -- v1.0.7: 跳跃空翻方向 = 人物朝向（右正左负，前空翻）
            end
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
            -- v2.1.0: 翻滚残影 —— 翻滚期间沿运动轨迹冒烟粒子
            trail.emit(inst)
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
        end
    end)
    return false
end

-- ============================================================================
-- Player.Update prefix（空实现，与动作优化一致的 install_hook 姿势）
-- ============================================================================
local function upd_pre(inst, args)
    -- v1.0.14: 撞击触发式无敌必须放在碰撞结算(Update_NPCCollision)之前。
    --   游戏 Update 内部先做 NPC 碰撞结算(可能 Hurt 掉血)，pre 在它之前执行，
    --   此时若玩家正翻滚且自检到撞怪 → 先给 immune=true，碰撞结算看到 immune 就不会掉血。
    if inst and roll_timer > 0 and CFG.iframe then
        pcall(function() check_npc_hit(inst) end)
    end
    return false
end

-- ============================================================================
-- setup / cleanup
-- ============================================================================
function setup()
    wlog("=== SETUP CALLED " .. os.date("%H:%M:%S") .. " jumproll v2.0.0 ===")
    -- v1.0.12: load_config 包 pcall，即便配置读取/解析抛异常也不中断 setup，翻滚引擎照装
    local ok_cfg, err_cfg = pcall(load_config)
    if not ok_cfg then
        wlog("load_config 异常（已忽略，继续装翻滚引擎）: " .. tostring(err_cfg))
    end
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
        local h = P.install_hook(mu, { prefix = upd_pre, postfix = upd_post })
        wlog("install_hook 返回 = " .. tostring(h))
        if not h then error("install_hook 返回空") end
        hook_handle = h
        wlog("===> 模组已启用，等待游戏内测试")
    end)
    if not ok then
        wlog("=== setup 失败: " .. tostring(err))
        mod.error("[DashRoll] setup 失败: " .. tostring(err) .. " 最近日志: " .. dump_dbg())
    end
end

function mod.cleanup()
    if hook_handle and hook_handle.remove then
        pcall(function() hook_handle:remove() end)
        hook_handle = nil
    end
    mod.info("[DashRoll] 已卸载")
end

todo_list = { "setup" }