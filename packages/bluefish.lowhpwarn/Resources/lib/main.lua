-- ============================================================================
-- 残血提示 v1.10.0
--   ① 玩家头顶显示「耐药性」Buff（BuffID 21）的图标与剩余秒数
--   ② 血量低于阈值时，屏幕四边绘制红色渐隐框，血量越低越浓、呼吸闪烁
--
--   依赖面与「Buff显示 v1.2.4」一致：只用 MagicPixel + Buff[] 图标，
--   不创建 Unity 对象、不读模组资源、不用 get_method_by_names / construct。
--
--   v1.5.0 加了 diag 埋点：setup 每一步都追加写入
--   /storage/emulated/0/Download/残血提示_diag.txt
--   崩溃后看这个文件最后一行，就知道炸在哪一步。
-- ============================================================================
-- 注意：LuaLoader 用全局 mod，绝不可写成 local mod = ...（chunk 无参数，... 为 nil）
mod.meta = { pkg_id = "bluefish.lowhpwarn", version = "2.0.0", version_code = 26, api_version = 1 }

-- 诊断文件优先写到项目文件夹，目录不存在时回退 Download 根目录
local DIAG_PATHS = {
    '/storage/emulated/0/Download/模组加工厂/项目-残血提示/残血提示_diag.txt',
    '/storage/emulated/0/Download/残血提示_diag.txt',
}
local diag_path
local diag_started = false
local function diag(msg)
    pcall(function()
        local f
        if diag_path then
            f = io.open(diag_path, diag_started and 'a' or 'w')
        else
            for _, p in ipairs(DIAG_PATHS) do
                f = io.open(p, diag_started and 'a' or 'w')
                if f then diag_path = p break end
            end
        end
        if not f then return end
        if not diag_started then
            diag_started = true
            f:write('=== 残血提示 诊断 ' .. tostring(os.time()) .. ' ===\n')
        end
        f:write(tostring(msg) .. '\n')
        f:close()
    end)
end

diag('main.lua 开始执行')

local hud
local tex = {}
local hooks = {}
local disabled = false
local failures = 0
local announced = false

-- ---------------- 可调参数 ----------------
local BUFF_ID    = 21
local HP_RATIO   = 0.30
local EDGE_PCT   = 0.014  -- 红框厚度占屏幕短边的比例
local EDGE_MIN   = 8      -- 最小厚度（px）
local BANDS      = 14     -- 逐格扫描的格数（按实际厚度自动封顶）
local ALPHA_CUT  = 4      -- alpha 低于此值就不再画
local GB_NEAR    = 18     -- 贴边处的 G/B（越小越纯红）
local GB_FAR     = 40     -- 内缘的 G/B（淡红但更红，不发白）
local A_FAR      = 0.42   -- 内缘保留的 alpha 比例
local PEAK_MIN   = 140    -- 刚触发时的峰值 alpha
local PEAK_MAX   = 255    -- 血量见底时的峰值 alpha
local PULSE_OMEGA = 1.8   -- 扫掠角速度（rad/s）：2*pi/1.8 ≈ 3.5 秒一轮
local TWO_PI     = 6.283185307179586
local PLAYER_LIFT = 26
local DOT        = 3

local function note(s)
    pcall(mod.info, '[残血提示] ' .. tostring(s))
end

-- 播报到聊天栏：只能在绘制阶段调用（setup 阶段调托管接口不安全）
local root_chat
local function say(text)
    local ok, m = pcall(function()
        if root_chat then return root_chat end
        local main = mod.patch.get_type('Terraria', 'Main')
        return main and mod.patch.get_method(main, 'NewText', 5)
    end)
    if not ok or not m then return false end
    root_chat = m
    local s = text
    -- 带全角符号/颜文字的文案走 string_create，避免转码成乱码
    if mod.patch.string_create then
        local okc, r = pcall(mod.patch.string_create, text)
        if okc and r then s = r end
    end
    local okc, r = pcall(mod.patch.invoke, m, s, 255, 170, 190, false)
    return okc and r ~= false
end

-- 进世界欢迎语：进世界满 1 秒（60 帧）播报一次，回主菜单后重置
local GREET_TEXT   = '别慌我会提醒你的(∠·ω< )⌒☆'
local GREET_FRAMES = 60
local greet_frames = 0


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

local function stop(reason)
    if disabled then return end
    disabled = true
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
    note('已停用: ' .. tostring(reason))
    diag('已停用: ' .. tostring(reason))
end

local function get_pixel()
    if tex.pixel then return tex.pixel end
    local ok, v = pcall(hud.magic_pixel, hud)
    if ok and v then tex.pixel = v end
    return tex.pixel
end

local function draw_number(batch, pixel, cx, y, text)
    local adv = DOT * 3 + 2
    local width = #text * adv - 2
    local x0 = math.floor(cx - width / 2 + 0.5)
    for i = 1, #text do
        local segs = DIGIT_SEGS[text:sub(i, i)]
        if segs then
            local ox = x0 + (i - 1) * adv
            for q = 1, #segs do
                local g = segs[q]
                hud:draw_tex(batch, pixel, ox + g[1], y + g[2], g[3], DOT, hud.WHITE)
            end
        end
    end
end

local edge_phase = 0
local edge_last_t

-- 红色渐隐边框：厚度按屏幕短边算，四边一致；闪烁由真实时间驱动，频率恒定
local function draw_edge(batch, pixel, w, h, ratio)
    local k = 1 - ratio / HP_RATIO
    if k < 0 then k = 0 elseif k > 1 then k = 1 end
    -- 相位用真实时间推进，频率固定：帧率高低、血量波动都不改变扫掠快慢
    local now = hud:now()
    if edge_last_t then
        local dt = now - edge_last_t
        if dt > 0 and dt < 0.5 then edge_phase = edge_phase + dt * PULSE_OMEGA end
    end
    edge_last_t = now
    local peak = PEAK_MIN + (PEAK_MAX - PEAK_MIN) * k
    -- 三角波 0 -> 1 -> 0：前半从边缘向内逐格亮起，后半从内向外逐格熄灭
    local cyc = (edge_phase % TWO_PI) / TWO_PI
    local tri = 1 - math.abs(2 * cyc - 1)
    local short = w < h and w or h
    local th = math.floor(short * EDGE_PCT)
    if th < EDGE_MIN then th = EDGE_MIN end
    -- 格数不能超过厚度（每格至少 1px），否则小屏上会多格叠到同一行
    local bands = BANDS
    if bands > th then bands = th end
    if bands < 1 then bands = 1 end
    local nlit = tri * bands       -- 已亮的格数（带小数，用于过渡格）
    for i = 1, bands do
        local t0 = (i - 1) / bands
        local t1 = i / bands
        -- lit：该格当前亮度。fi 越小越靠屏幕边缘；nlit 0->bands 是「由外向内亮起」，
        -- 再从 bands->0 就是「由内向外熄灭」，正在过渡的那一格取小数部分做渐变
        local lit = nlit - (i - 1)
        if lit > 1 then lit = 1 elseif lit < 0 then lit = 0 end
        if lit > 0 then
            -- 颜色：贴边浓红 -> 内缘淡红（G/B 升高），alpha 同步降到 A_FAR
            local gb = math.floor(GB_NEAR + (GB_FAR - GB_NEAR) * t0 + 0.5)
            local a = math.floor(peak * (1 - t0 * (1 - A_FAR)) * lit)
            if a < ALPHA_CUT then a = 0 end
            if a > 255 then a = 255 end
            if a > 0 then
                local col = string.char(a, gb, gb, 255)   -- ABGR: A,B,G,R；R 恒为 255
                -- 边界取整对齐，避免相邻段之间出现 1px 缝
                local p0 = math.floor(th * t0 + 0.5)
                local p1 = math.floor(th * t1 + 0.5)
                local thick = p1 - p0
                if thick < 1 then thick = 1 end
                -- 竖条：y 从 0 到 h
                hud:draw_tex(batch, pixel, p0, 0, thick, h, col)
                hud:draw_tex(batch, pixel, w - p0 - thick, 0, thick, h, col)
                -- 横条：铺满整个屏幕宽度，四角和竖条重叠也没关系
                hud:draw_tex(batch, pixel, 0, p0, w, thick, col)
                hud:draw_tex(batch, pixel, 0, h - p0 - thick, w, thick, col)
            end
        end
    end
end

-- 找耐药性 Buff，返回剩余秒数（找不到返回 nil）
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
        if ok and id == 0 then break end   -- 空槽即结束（buff 数组前半段紧凑排列）
    end
    return nil
end

local icon_tex, icon_w, icon_h
local function draw_buff(batch, pixel, cx, top, seconds)
    -- 图标纹理和尺寸在游戏运行期是稳定的，取一次就缓存，省掉每帧 5 次反射读
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
    draw_number(batch, pixel, cx, y + icon_h + 3, tostring(secs))
end

-- ---- 缓存与刷新节拍 ----
-- 每帧都去读托管字段很贵（一次读 = 一次反射调用）。这里按变化快慢分层刷新：
--   玩家 / 批次 / 菜单 30 帧（0.5 秒）   屏幕尺寸 60 帧（1 秒）
--   血量 2 帧（0.03 秒）   耐药性 buff 6 帧（0.1 秒）
-- 只有相机位置每帧读——它决定头顶图标的屏幕坐标，掉帧会看到拖影。
local tick = 0
local c_gs, c_pl, c_batch, c_pl_ok, c_pw = nil, nil, nil, false, 0
local c_menu = false
local c_w, c_h = 0, 0
local c_life, c_life_max = 0, 0
local c_buff
local at_slow, at_dim, at_life, at_buff = -999, -999, -999, -999

-- 慢变状态：GameState、玩家、玩家宽度、SpriteBatch
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
    if disabled then return end
    tick = tick + 1
    if tick > 1000000 then tick = 0 end

    if tick - at_slow >= 30 then
        at_slow = tick
        refresh_slow()
    end
    local gs, pl = c_gs, c_pl
    if not gs then return end

    -- 进世界满 GREET_FRAMES 帧播报一次欢迎语；回主菜单或还没进世界就清零
    if c_menu or not c_pl_ok then
        greet_frames = 0
    elseif greet_frames >= 0 then
        greet_frames = greet_frames + 1
        if greet_frames >= GREET_FRAMES then
            greet_frames = -1
            say(GREET_TEXT)
        end
    end

    if not c_pl_ok or not pl then return end

    if tick - at_life >= 2 then
        at_life = tick
        c_life = hud:read(hud.p_life, pl, 'int32') or 0
        c_life_max = hud:read(hud.p_life_max, pl, 'int32') or 0
    end
    local life, life_max = c_life, c_life_max
    local low = life_max > 0 and life > 0 and (life / life_max) < HP_RATIO

    if tick - at_buff >= 6 then
        at_buff = tick
        c_buff = find_buff(pl)
    end
    local buff_secs = c_buff

    -- 这帧有没有东西要画，没有就直接退出（不取批次、不取句柄）
    if not low and not buff_secs then return end
    local batch = c_batch
    if not batch then return end

    local pixel = get_pixel()
    if not pixel then return end
    if not hud:begin_frame() then return end
    if hud:read(hud.batch_begun, batch, 'bool') ~= true then return end

    if tick - at_dim >= 60 then
        at_dim = tick
        c_w, c_h = hud:dimensions(gs)
    end
    local w, h = c_w, c_h
    if w <= 0 or h <= 0 then return end

    if not announced then
        announced = true
        diag(string.format('首帧绘制已生效 缓冲=%s 屏幕=%dx%d', tostring(hud.rect_how), w, h))
    end

    if low then
        draw_edge(batch, pixel, w, h, life / life_max)
    end

    if buff_secs then
        local camx, camy = hud:vec2(hud.camera, gs)
        local px, py = hud:vec2(hud.p_pos, pl)
        if px then
            local cx = px + c_pw / 2 - (camx or 0)
            local top = py - (camy or 0) - PLAYER_LIFT
            draw_buff(batch, pixel, cx, top, buff_secs)
        end
    end
end

local function safe_step()
    if disabled then return end
    local ok, err = pcall(step)
    if ok then
        failures = 0
        return
    end
    failures = failures + 1
    if failures <= 2 then
        note('绘制错误 ' .. failures .. ': ' .. tostring(err))
        diag('绘制错误 ' .. failures .. ': ' .. tostring(err))
    end
    if failures >= 120 then stop(err) end
end

local function do_setup()
    diag('setup 开始 platform=' .. tostring(mod.platform) .. ' patch=' .. tostring(mod.patch ~= nil))
    if mod.platform ~= 'android' then
        note('仅支持 Android，跳过')
        return
    end
    local ok, err = pcall(function()
        local p = assert(mod.patch, '缺少 patch 接口')
        for _, name in ipairs({ 'get_method_by_param_types', 'make_generic_type', 'field_pointer', 'mem_write_values' }) do
            assert(type(p[name]) == 'function', '加载器缺少 ' .. name)
        end
        diag('接口检查通过，require hud')
        local H = require('hud')
        diag('require hud 成功，开始初始化')
        hud = H.new(p, diag)
        diag('hud 初始化完成，准备挂钩子')
        local hook = assert(p.install_hook(hud.draw_npcs, { postfix = safe_step }), '钩子安装失败')
        hooks[#hooks + 1] = hook
        diag('钩子安装成功 setup 完成')
        note('已挂钩子 矩形缓冲=' .. tostring(hud.rect_how))
    end)
    if not ok then
        diag('setup 失败: ' .. tostring(err))
        stop(err)
    end
end

local function do_cleanup()
    disabled = true
    for i = #hooks, 1, -1 do
        pcall(function() hooks[i]:remove() end)
        hooks[i] = nil
    end
    if hud then pcall(hud.cleanup, hud) end
    hud = nil
    tex = {}
end

function setup() pcall(do_setup) end
todo_list = { "setup" }

function mod.cleanup() pcall(do_cleanup) end

diag('main.lua 执行完毕 setup 已注册')