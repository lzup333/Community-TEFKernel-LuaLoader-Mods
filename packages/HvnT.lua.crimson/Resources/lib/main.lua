-- 血色 (Crimson)：永久血月 + 永久夜晚
-- 模组类型：世界规则
-- 游戏版本：Terraria 1.4.5.8 (PE / Il2Cpp)
-- 修改点：Hook Terraria.Main.UpdateTime（private static void UpdateTime()，0 参数）
--         postfix 模式：原版每帧推进完时间后，把世界强制写回“夜晚 + 血月”。
--         字段均为 static，故 instance 传 nil。
-- 多人支持：UpdateTime 与 dayTime/time/bloodMoon 均为服务器权威，
--         原版 syncWorldState 会自动同步给客户端，无需额外网络处理。

mod.meta = {
    pkg_id = "HvnT.lua.crimson",
    version = "1.0.0",
    version_code = 1,
    api_version = 1,
    multiplayer_safe = true,
}

-- Terraria 夜间：dayTime=false，time 从 32400 递减到 0 后转白天。
-- 所以只要 time 快降到 0（黎明）就把它 resc 回夜间起点 32400，
-- 世界就永远处于夜晚，不会触发“天亮”逻辑。
local NIGHT_START = 32400.0
-- 黎明前一点的安全阈值，防止边界值触发 StartDay
local NIGHT_MIN   = 60.0

local f_day_time
local f_time
local f_blood_moon
local fired = false

local function crimson_night()
    -- 显式指定类型（Android/Il2Cpp 上不依赖字段类型查询，参照 ManaLock 的写法更稳）
    -- 永久血月
    mod.patch.set_field_value(f_blood_moon, nil, true, "bool")
    -- 永久夜晚：白天则立即转回夜晚
    local is_day = mod.patch.get_field_value(f_day_time, nil, "bool")
    if is_day then
        mod.patch.set_field_value(f_day_time, nil, false, "bool")
        mod.patch.set_field_value(f_time, nil, NIGHT_START, "double")
    else
        -- 已是夜晚：防止 time 走到 0 触发黎明
        local t = mod.patch.get_field_value(f_time, nil, "double")
        if t < NIGHT_MIN then
            mod.patch.set_field_value(f_time, nil, NIGHT_START, "double")
        end
    end
    if not fired then
        fired = true
        mod.info("血色已生效：永久血月 + 永久夜晚")
    end
end

function setup()
    local main_t = mod.patch.get_type("Terraria", "Main")
    if not main_t then
        mod.error("未找到 Terraria.Main 类型，血色模组未生效")
        return
    end

    f_day_time   = mod.patch.get_field(main_t, "dayTime")
    f_time       = mod.patch.get_field(main_t, "time")
    f_blood_moon = mod.patch.get_field(main_t, "bloodMoon")

    if not (f_day_time and f_time and f_blood_moon) then
        mod.error("dayTime/time/bloodMoon 字段获取失败，血色模组未生效")
        return
    end

    -- Terraria.Main.UpdateTime：private static void UpdateTime()，0 参数
    local m_update_time = mod.patch.get_method(main_t, "UpdateTime", 0)
    if not m_update_time then
        mod.error("未找到 Main.UpdateTime 方法，血色模组未生效")
        return
    end

    -- postfix：等原版时间推进完毕后再强制写回，避免被原版逻辑覆盖
    mod.patch.install_hook(m_update_time, { postfix = crimson_night })
end

function mod.cleanup()
    mod.info("血色已卸载，世界时间恢复正常（血月状态将由原版逻辑自然处理）")
end

todo_list = { "setup" }