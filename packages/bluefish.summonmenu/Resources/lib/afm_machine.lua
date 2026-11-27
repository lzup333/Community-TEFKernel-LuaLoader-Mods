-- afm_machine.lua
-- 钓鱼机列表、放置、每帧循环。只有一种上鱼方式：存档模式。
--
--   存档模式：库存存在模组自己的存档里，靠「靠近 + 按使用键」手动存取
--       · 手持钓竿/鱼饵点一下机器 → 装进去（走近也会自动吸入）
--       · 空手点一下机器 → 把渔获取走
--       · 上鱼间隔 8~16 帧（0.13~0.27 秒）
--
--   机器本身仍然是一个箱子图格（CHEST_TILE），只当标记用；
--   箱子里的物品与钓鱼机无关，不会被读写。
local U = require("afm_util")
local F = require("afm_fish")

local M = {}
local SD, B
local MACHINES = {}          -- ["x,y"] = machine
local SAVE_FILE = "afm_machines.txt"

local CHEST_TILE = 21
-- v2.1.4：水域判定 = 以钓鱼机为圆心、半径 35 的「下半圆」（含水平线）。
--   钓鱼机不会放在水下，上半圆永远是空气，没必要扫。
local WATER_RADIUS = 35

-- v2.0.8：存档模式原先 120~240 帧（2~4 秒一条），现在和箱子模式同样 8~16 帧。
--   存档模式钓一次鱼是纯 Lua 计算（不碰内存/反射），提速不增加性能负担。
local TICK_MIN = 8
local TICK_MAX = 16
-- v2.1.4：每 600 帧（10 秒）重扫一遍下半圆，分帧进行（每帧一行，共 36 行）。
--   扫完才更新水量，平时零开销；加水、抽水、挖渠都会在 10 秒内体现。
local WATER_SWEEP = 600
-- v2.0.7：没按屏幕时，走近自动存取每 3 帧跑一次就够（原来每帧都读手持物品）
local INTERACT_EVERY = 3
local SAY_GAP = 900
-- v2.1.5：状态播报改成 20 秒一次（原来 15 秒），且必须先判距离再算，
--   不靠近就不播。距离用 tick 里已缓存的玩家坐标，不再单独反射读一次。
local STATUS_GAP = 1200
local REACH_STATUS = 12
local REACH_ACT = 5

function M.setup(ctx, bind)
    SD = ctx
    B = bind
    SD.machines = MACHINES
    M.load()
    -- 只保留存档模式：老存档里记的 chest 一律刷回 lua
    for _, mm in pairs(MACHINES) do
        mm.mode = "lua"
    end
end

-- v2.1.6：给掉落守卫用——判断「这个坐标是不是某台钓鱼机」
function M.near_machine(x, y, r)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    r = r or 2
    for _, mm in pairs(MACHINES) do
        if math.abs(mm.x - x) <= r and math.abs(mm.y - y) <= r then return true end
    end
    return false
end
local function key_of(x, y)
    return string.format("%d,%d", math.floor(x), math.floor(y))
end

-- ==================== 存档 ====================
--   M x y mode rodType rodCount baitType baitCount
--   C itemType count          （仅 lua 模式）
local function serialize()
    local out = { "#AFM3" }
    local keys = {}
    for k in pairs(MACHINES) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local m = MACHINES[k]
        if m then
            out[#out + 1] = string.format("M %d %d %s %d %d %d %d",
                math.floor(m.x), math.floor(m.y), "lua",
                (m.rod and m.rod.t) or 0, (m.rod and m.rod.n) or 0,
                (m.bait and m.bait.t) or 0, (m.bait and m.bait.n) or 0)
            if (m.potion or 0) > 0 or (m.chum or 0) > 0 then
                out[#out + 1] = string.format("T %d %d", m.potion or 0, m.chum or 0)
            end
            for _, g in ipairs(m.gears or {}) do
                out[#out + 1] = string.format("G %d", g)
            end
            for _, c in ipairs(m.catches or {}) do
                out[#out + 1] = string.format("C %d %d", c.t, c.n)
            end
        end
    end
    return table.concat(out, "\n") .. "\n"
end

function M.save()
    pcall(mod.write_file, SAVE_FILE, serialize())
end

function M.load()
    MACHINES = {}
    SD.machines = MACHINES
    local ok, txt = pcall(mod.read_file, SAVE_FILE)
    if not ok or type(txt) ~= "string" then return 0 end
    local cur, n = nil, 0
    for line in txt:gmatch("[^\r\n]+") do
        local tag = line:sub(1, 1)
        if tag == "M" then
            local x, y, mode, rt, rn, bt, bn =
                line:match("^M%s+(%-?%d+)%s+(%-?%d+)%s+(%a+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
            if x then
                cur = {
                    x = tonumber(x), y = tonumber(y),
                    mode = "lua",
                    cd = 60, water = 0, water_frames = 0,
                    say = {}, catches = {}, gears = {},
                }
                local a, b = tonumber(rt), tonumber(rn)
                if a and a > 0 and b and b > 0 then cur.rod = { t = a, n = b } end
                local c, d = tonumber(bt), tonumber(bn)
                if c and c > 0 and d and d > 0 then cur.bait = { t = c, n = d } end
                MACHINES[key_of(cur.x, cur.y)] = cur
                n = n + 1
            end
        elseif tag == "C" and cur then
            local t, c = line:match("^C%s+(%-?%d+)%s+(%-?%d+)")
            if t then cur.catches[#cur.catches + 1] = { t = tonumber(t), n = tonumber(c) } end
        elseif tag == "G" and cur then
            local t = line:match("^G%s+(%-?%d+)")
            if t then
                cur.gears = cur.gears or {}
                cur.gears[#cur.gears + 1] = tonumber(t)
            end
        elseif tag == "T" and cur then
            local a, bb = line:match("^T%s+(%-?%d+)%s+(%-?%d+)")
            if a then
                cur.potion = tonumber(a)
                cur.chum = tonumber(bb)
            end
        end
    end
    U.log_info(string.format("[AFM] 载入 %d 台钓鱼机", n))
    return n
end

-- ==================== 放置 ====================
local function new_machine(x, y)
    local m = {
        x = x, y = y, mode = "lua",
        cd = 30, alive_cd = 0, water = 0, water_frames = 0,
        say = {}, catches = {}, gears = {},
    }
    MACHINES[key_of(x, y)] = m
    return m
end

function M.try_place(player, pressed_edge)
    if not player then return false end
    if not pressed_edge then return false end
    if not B.holding_machine(player) then return false end

    local x, y = B.aim(player)
    if not x then return false end

    local tries = { { x, y }, { x, y - 1 }, { x - 1, y }, { x, y - 2 } }
    local idx, err, okx, oky
    for _, t in ipairs(tries) do
        idx, err = B.place_chest(t[1], t[2])
        if idx then okx, oky = t[1], t[2] break end
    end

    if not idx then
        B.notify("这里放不下钓鱼机 (>_<)", 255, 140, 140)
        U.log_warn("[AFM] 放置失败: " .. tostring(err))
        return false
    end

    new_machine(okx, oky)
    local held = B.item_at(B.inventory(player), B.selected(player))
    if held then
        local n = B.item_stack(held)
        if n and n > 0 then B.set_stack(held, n - 1) end
    end
    M.save()
    B.notify(string.format("自动钓鱼机已放下 (%d,%d)：打开这个箱子放进钓竿和鱼饵", okx, oky),
        150, 230, 255)
    U.log_info(string.format("[AFM] 放置成功 (%d,%d) chest=%d", okx, oky, idx))
    return true
end

-- ==================== 辅助 ====================
local function say(m, k, text, r, g, b)
    local now = SD.S.frame or 0
    if now - (m.say[k] or -99999) < SAY_GAP then return end
    m.say[k] = now
    B.notify(text, r, g, b)
end

local function alive(m)
    local t = B.tile_type(m.x, m.y)
    if t == nil then return true end
    return t == CHEST_TILE
end


local function catch_add(m, itype, count)
    m.catches = m.catches or {}
    for _, c in ipairs(m.catches) do
        if c.t == itype then
            if c.n + count > 999 then return false end
            c.n = c.n + count
            return true
        end
    end
    if #m.catches >= 30 then return false end
    m.catches[#m.catches + 1] = { t = itype, n = count }
    return true
end

local function catch_count(m)
    local n = 0
    for _, c in ipairs(m.catches or {}) do n = n + c.n end
    return n
end

-- 把机器里的东西全部返还给玩家：竿、饵、渔具、渔获
local function dump_all(m, player)
    local got, parts = 0, {}
    local function give(t, n, label)
        if not t or not n or n <= 0 then return end
        local g = B.inv_add(player, t, n)
        got = got + g
        if g > 0 then
            parts[#parts + 1] = string.format("%s×%d", label or F.name_of(t), g)
        end
    end
    if m.rod then give(m.rod.t, m.rod.n) m.rod = nil end
    if m.bait then give(m.bait.t, m.bait.n) m.bait = nil end
    for _, g in ipairs(m.gears or {}) do give(g, 1, F.extra_name(g)) end
    m.gears = {}
    for _, c in ipairs(m.catches or {}) do give(c.t, c.n) end
    m.catches = {}
    return got, table.concat(parts, " ")
end

-- ==================== lua 模式：手动存取 ====================
local function take_from_hand(held, want)
    if not held then return 0 end
    local cur = B.item_stack(held)
    if type(cur) ~= "number" or cur <= 0 then return 0 end
    local n = math.min(cur, want)
    if n <= 0 then return 0 end
    local left = cur - n
    if not B.set_stack(held, left) then return 0 end
    if B.item_stack(held) == left then return n end
    B.set_stack(held, cur)
    return 0
end

local function lua_interact(m, player, pressed_edge, d0)
    -- d0 由 tick 里的距离预判算出（用缓存坐标），这里不再重复读玩家位置
    local d = d0
    if not d or d > REACH_ACT then return end

    local held = B.item_at(B.inventory(player), B.selected(player))
    local itype = held and B.item_type(held) or 0
    local istack = held and B.item_stack(held) or 0

    -- 空手点一下机器 → 把机器里的东西全部取回（含钓竿、鱼饵、渔具）
    -- 这条不受冷却限制，随时可以点
    if pressed_edge and (itype == 0 or istack <= 0) then
        local got, detail = dump_all(m, player)
        if got > 0 then
            B.notify("已取回：" .. detail, 150, 255, 180)
            M.save()
        else
            B.notify("这台钓鱼机是空的", 255, 200, 120)
        end
        return
    end

    -- 自动存取（走近触发）。冷却压到 0.17 秒
    m.cdi = (m.cdi or 0) - 1
    if m.cdi > 0 then return end
    m.cdi = 10

    -- 手持竿/饵/渔具/药水 → 装进去
    -- 一帧内最多连续装 40 次：鱼饵一次吸光、钓鱼药水连喝都不用等
    for _ = 1, 40 do
        local hp = B.item_at(B.inventory(player), B.selected(player))
        local it = hp and B.item_type(hp) or 0
        local st = hp and B.item_stack(hp) or 0
        if it <= 0 or st <= 0 then break end

        local pole, bait = B.probe_item(it)
        if pole > 0 then
            if m.rod then
                say(m, "hasrod", "这台钓鱼机里已经有钓竿了", 255, 200, 120)
                break
            end
            if take_from_hand(hp, 1) <= 0 then
                B.notify("钓竿取不出来（读取异常）", 255, 150, 150)
                break
            end
            m.rod = { t = it, n = 1 }
            B.notify(string.format("已装进钓竿，渔力 %d", pole), 150, 230, 255)
            M.save()
            break

        elseif bait > 0 then
            local have = (m.bait and m.bait.n) or 0
            if m.bait and m.bait.t ~= it then
                say(m, "bmix", "先取走机器里原有的鱼饵再换种类", 255, 200, 120)
                break
            end
            local room = 999 - have
            if room <= 0 then
                say(m, "bfull", "这台钓鱼机的鱼饵已经满了", 255, 200, 120)
                break
            end
            local got = take_from_hand(hp, math.min(room, st))
            if got <= 0 then
                B.notify("鱼饵取不出来（读取异常）", 255, 150, 150)
                break
            end
            m.bait = { t = it, n = have + got }
            B.notify(string.format("已装进鱼饵 ×%d（共 %d）", got, m.bait.n), 150, 230, 255)
            M.save()
            -- 继续循环：手里还有饵就接着吸

        elseif F.extra_of(it) > 0 then
            -- 渔具：装进机器，提供永久渔力加成（照 TShock 的配置表）
            local dup = false
            for _, g in ipairs(m.gears or {}) do
                if g == it then dup = true end
            end
            if dup then
                say(m, "dupg" .. it, "这台钓鱼机里已经有" .. F.extra_name(it) .. "了", 255, 200, 120)
                break
            end
            if take_from_hand(hp, 1) <= 0 then
                B.notify("渔具取不出来（读取异常）", 255, 150, 150)
                break
            end
            m.gears = m.gears or {}
            m.gears[#m.gears + 1] = it
            local sum = F.extra_sum(m.gears, m.potion, m.chum)
            B.notify(string.format("已装进%s（现在渔力加成 +%d）", F.extra_name(it), sum),
                150, 230, 255)
            M.save()
            break

        elseif it == F.POTION or it == F.CHUM then
            local key = (it == F.POTION) and "potion" or "chum"
            if (m[key] or 0) > 3600 * 60 then
                say(m, key .. "max", "这个效果已经够久了，先不用再加",
                    255, 200, 120)
                break
            end
            if take_from_hand(hp, 1) <= 0 then
                B.notify("药水取不出来（读取异常）", 255, 150, 150)
                break
            end
            if it == F.POTION then
                m.potion = (m.potion or 0) + F.POTION_FRAMES
                B.notify(string.format("喝下钓鱼药水：渔力 +%d（%d 分钟）",
                    F.POTION_BONUS, math.floor(m.potion / 3600)), 150, 230, 255)
            else
                m.chum = (m.chum or 0) + F.CHUM_FRAMES
                B.notify(string.format("撒下鱼饵桶：渔力 +%d（%d 分钟）",
                    F.CHUM_BONUS, math.floor(m.chum / 3600)), 150, 230, 255)
            end
            M.save()
            -- 继续循环：可以连着喝几瓶

        else
            break
        end
    end

    -- 空手 → 取渔获
    if (itype == 0 or istack <= 0) and #(m.catches or {}) > 0 then
        local got, rest = 0, {}
        for _, c in ipairs(m.catches) do
            local n = B.inv_add(player, c.t, c.n)
            got = got + n
            if n < c.n then rest[#rest + 1] = { t = c.t, n = c.n - n } end
        end
        m.catches = rest
        if got > 0 then
            B.notify(string.format("取出渔获 ×%d", got), 150, 255, 180)
            M.save()
        else
            B.notify("背包放不下了", 255, 170, 120)
        end
    end
end

local function fish_lua(m)
    local water = m.water or 0
    if water <= 0 then
        say(m, "water", "钓鱼机附近没有水，把箱子放到水边", 255, 170, 120)
        return
    end
    if not m.rod then
        say(m, "norod", "钓鱼机里没有钓竿（手持钓竿点一下机器）", 255, 170, 120)
        return
    end
    if not (m.bait and m.bait.n > 0) then
        say(m, "nobait", "钓鱼机里没有鱼饵（手持鱼饵点一下机器）", 255, 170, 120)
        return
    end

    local pole = B.probe_item(m.rod.t)
    local _, bait = B.probe_item(m.bait.t)
    if pole <= 0 and bait <= 0 then
        say(m, "badgear", "机器里的钓竿/鱼饵识别不了", 255, 170, 120)
        return
    end

    -- v2.1.3：
    --   ① 海拔需求只跟机器所在高度有关，位置不变就永远不变 → 只算一次。
    --   ② 真正会变的是「天气倍率」和「玩家幸运」→ 5 秒刷新一次。
    --      （天气倍率吃的是 Main.time / 白天黑夜 / 下雨 / 风，幸运吃饰品与药水）
    local now = SD.S.frame or 0
    if not m.need then
        m.need = F.need_water(B.atmo(m.y))
    end
    if not m.fish_t or now - m.fish_t > 300 then
        m.fish_t = now
        m.mult = F.multiplier(B.world_env())
        m.luck = B.player_luck(B.local_player())
    end
    local need = m.need
    local gear, gear_txt = F.extra_sum(m.gears, m.potion, m.chum)
    m.gear = gear
    m.gear_txt = gear_txt
    m.crate_potion = F.has_crate_potion(m.gears)
    -- 原版：渔力 = 竿 + 饵 + 渔具加成，再乘时间天气倍率
    local mult = m.mult or 1.0
    local base = F.power(pole, bait, gear)
    base = math.floor(base * mult)
    local power = F.apply_water(base, water, need)
    power = F.apply_luck(power, m.luck or 0, B.rand0f)
    if power <= 0 then
        say(m, "lowwater", string.format("水域太小（%d/%d 格），渔力被压没了", water, need),
            255, 170, 120)
        return
    end
    m.last_base = base
    m.last_power = power

    local lv = F.levels(power, B.rand0, m.crate_potion)
    local itype
    if lv.crate then
        itype = F.pick_crate(power, B.rand)
    elseif F.is_junk(power, water, need, B.rand0) then
        itype = F.pick_junk(B.rand)
    else
        itype = F.pick(lv, power, B.rand)
    end

    if not catch_add(m, itype, 1) then
        say(m, "full", "钓鱼机存满了，空手靠近即可取走", 255, 170, 120)
        return
    end

    if B.rand0f() < F.bait_consume_chance(power, false) then
        m.bait.n = m.bait.n - 1
        if m.bait.n <= 0 then
            m.bait = nil
            B.notify("钓鱼机的鱼饵用完了，补充后自动继续", 255, 170, 120)
        end
    end
    m.catches_n = (m.catches_n or 0) + 1
    -- 上鱼不播报，避免刷满聊天栏（状态播报里能看到累计数）
end

-- ==================== 状态播报 ====================
local function status(m, player)
    -- v2.1.5：先判时间（大多数帧在这里就返回，一次反射都不做），
    --   再判距离；坐标直接用 tick 里缓存的 m.px/m.py（10 帧更新一次），
    --   原来这里每帧都要调 B.player_tile 反射读玩家位置。
    local now = SD.S.frame or 0
    if now - (m.last_status or -99999) < STATUS_GAP then return end
    local px, py = m.px, m.py
    if not px then
        px, py = B.player_tile(player)
        if not px then return end
    end
    if math.max(math.abs(px - m.x), math.abs(py - m.y)) > REACH_STATUS then return end
    m.last_status = now
    local body = string.format("渔获%d", catch_count(m))
    local gear_txt = ""
    if m.gear and m.gear > 0 then
        gear_txt = string.format(" 装备+%d", m.gear)
        if m.gear_txt and m.gear_txt ~= "" then gear_txt = gear_txt .. "(" .. m.gear_txt .. ")" end
    end
    if m.mult and math.abs(m.mult - 1.0) > 0.001 then
        gear_txt = gear_txt .. string.format(" 倍率x%.2f", m.mult)
    end
    B.notify(string.format("钓鱼机 %s 水%d/%d 渔力%s%s", body,
        m.water or 0, m.need or 300, m.last_power and tostring(m.last_power) or "-", gear_txt),
        170, 210, 255)
end
-- ==================== 主循环 ====================
function M.tick(player, pressed_edge)
    if not (B and B.world()) then return end
    M.try_place(player, pressed_edge)
    if not player then return end
    local dead = nil
    for k, m in pairs(MACHINES) do
        -- 存活检查降频（每 60 帧读一次图格）
        if (m.alive_cd or 0) <= 0 then
            m.alive_cd = ALIVE_CHECK
            m.alive_ok = alive(m)
        else
            m.alive_cd = m.alive_cd - 1
        end
        if m.alive_ok == false then
            dead = dead or {}
            dead[#dead + 1] = k
        else
            if (m.potion or 0) > 0 then m.potion = m.potion - 1 end
            if (m.chum or 0) > 0 then m.chum = m.chum - 1 end
            -- v2.1.4：水域统计 = 下半圆分帧扫描。
            --   半径 35 的下半圆共 36 行（dy 0~35），最宽一行 71 格；
            --   每帧只扫一行，36 帧扫完，扫完才更新 m.water。
            --   平时完全不查；每 WATER_SWEEP 帧（10 秒）重新起一轮。
            if (m.water_frames or 0) > 0 then
                m.water_frames = m.water_frames - 1
            else
                local ws = m.wscan
                if not ws then
                    ws = { dy = 0, acc = 0 }
                    m.wscan = ws
                end
                ws.acc = ws.acc + (B.water_rows_down(m.x, m.y, WATER_RADIUS, ws.dy) or 0)
                ws.dy = ws.dy + 1
                if ws.dy > WATER_RADIUS then
                    m.water = ws.acc
                    m.wscan = nil
                    m.water_frames = WATER_SWEEP
                end
            end
            -- v2.1.1：先算距离再决定要不要读背包。
            --   玩家格坐标每 10 帧取一次（2~3 次反射），不够近就直接跳过，
            --   原来不管远近每 3 帧都要读一遍手持物品（8~10 次反射）。
            m.pdist = (m.pdist or 0) - 1
            if m.pdist <= 0 then
                m.pdist = 10
                m.px, m.py = B.player_tile(player)
            end
            local md = 999
            if m.px then
                md = math.max(math.abs(m.px - m.x), math.abs(m.py - m.y))
            end
            if md <= REACH_ACT and (pressed_edge or (SD.S.frame % INTERACT_EVERY) == 0) then
                pcall(lua_interact, m, player, pressed_edge, md)
            end

            -- 上鱼
            m.cd = (m.cd or 0) - 1
            if m.cd <= 0 then
                m.cd = TICK_MIN + B.rand(TICK_MAX - TICK_MIN + 1) - 1
                local ok, err = pcall(fish_lua, m)
                if not ok then U.log_warn("[AFM] 上鱼出错: " .. tostring(err)) end
            end

            pcall(status, m, player)
        end
    end

    if dead then
        for _, k in ipairs(dead) do
            local mach = MACHINES[k]
            if mach then
                -- 先吃掉原版按箱子规则掉出来的那个宝箱（item 48）
                -- v2.1.7：守卫照装，兜底也照跑（不做「守卫装了就不清」的死判断——
                --   守卫可能装上但坐标对不上，兜底是最后一道）
                local dropped = 0
                if type(B.clear_drops_near) == "function" then
                    local okc, n = pcall(B.clear_drops_near, mach.x, mach.y, 48, 4)
                    if okc and type(n) == "number" then dropped = n end
                end
                if dropped > 0 then
                    U.log_info("[AFM] 兜底清掉掉落的宝箱 " .. tostring(dropped) .. " 个")
                end
                local got, detail = dump_all(mach, player)
                local mid = (SD.S and SD.S.item_id) or -1
                local back = 0
                if mid > 0 then back = B.inv_add(player, mid, 1) end
                if back > 0 then
                    detail = (detail ~= "" and (detail .. " ")) or ""
                    detail = detail .. "自动钓鱼机×1"
                    got = got + 1
                end
                if got > 0 then
                    B.notify("钓鱼机已拆除，退还：" .. detail, 255, 230, 150)
                end
            end
            MACHINES[k] = nil
            U.log_info("[AFM] 移除钓鱼机 " .. tostring(k))
        end
        M.save()
    end
end

function M.count()
    local n = 0
    for _ in pairs(MACHINES) do n = n + 1 end
    return n
end

return M