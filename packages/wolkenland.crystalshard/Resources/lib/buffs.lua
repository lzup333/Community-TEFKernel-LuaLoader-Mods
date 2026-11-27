-- 自定义 Buff：晶核侵蚀（Boss 战里给玩家挂的减益）。
--
-- 按官方文档的时机来（doc/api.md「注册返回值与 ID 分配时机」）：
--   • register 只能在 **mod 加载阶段** 调，返回值是 -1 的「登记号」，不是真 ID；
--   • ID 由内核初始化时统一分配（401, 402, …），加载阶段不要调 add/time/remove；
--   • 真要用的时候按名字现查 runtime_id。
-- 所以这里加载阶段只做 register 一件事，运行期才查 ID、挂 Buff。
--
-- 效果自己实现：原版不认识自定义 buffType，写不进 Player.UpdateBuffs。
-- 这里每帧压低 statDefense / moveSpeed；原版 ResetEffects 每帧重算这两项，
-- 所以 Buff 一消失自动恢复，不用手动还原。
local q = mod.quickapi
local M = {}

-- 开关：默认开着；万一换了旧内核又崩，把它改回 false 就能照常进游戏。
-- 实测记录（都是同一颗内核 1055584 字节 / md5 80107a82...）：
--   1.2.24 完整 spec（贴图+语言表）在 setup 注册 → 进主菜单前闪退
--   1.2.26 只传 name（无贴图无语言表）在 setup 注册 → 同样闪退
--   1.2.28 只调 register、之后不碰任何接口 → 同样闪退
--   1.2.29 带 update 回调 → 同样闪退
-- 唯一能正常启动的是「加载阶段完全不注册」。等内核那边修好，把开关改成 true 即可。
M.ENABLED = true

M.erosion_name = "crystal_erosion"
M.minion_name = "crystal_minion"     -- 碎晶精魂：召唤物身上的那个 buff
M.registered = false
M.error = nil

M.EROSION_DEFENSE = 6      -- 防御 -6
M.EROSION_SPEED = 0.12     -- 移速 -12%（Player.moveSpeed 默认 1.0）
M.EROSION_FRAMES = 900     -- 被击中后挂 15 秒（60 帧 = 1 秒）

-- 碎晶精魂的心跳：update 回调每帧 +1。召唤物用它判断 buff 还在不在 ——
-- 比查剩余时间可靠（自定义 buff 的 time 查询实测拿不到值）。
M.minion_heartbeat = 0

local ids = {}

local function api()
    if type(mod) ~= "table" then return nil end
    local buff = mod.buff
    if type(buff) ~= "table" then return nil end
    if type(buff.register) ~= "function" then return nil end
    return buff
end

function M.available()
    return api() ~= nil
end

-- 每帧回调：buff_index 是内核激活列表的下标，不是 buffType 槽位
local function erosion_update(player, buff_index)
    if not player then return end
    local own = q.get_field_value("Terraria", "Player", "whoAmI", player, "int32")
    if own == nil then return end

    local defense = q.get_field_value("Terraria", "Player", "statDefense", player, "int32")
    if type(defense) == "number" then
        q.set_field_value("Terraria", "Player", "statDefense", player,
                defense - M.EROSION_DEFENSE, "int32")
    end
    if M.EROSION_SPEED > 0 then
        local speed = q.get_field_value("Terraria", "Player", "moveSpeed", player, "float")
        if type(speed) == "number" then
            q.set_field_value("Terraria", "Player", "moveSpeed", player,
                    speed - M.EROSION_SPEED, "float")
        end
    end
end

-- 加载阶段调用：只登记，不查 ID、不挂 Buff。
function M.register()
    if not M.ENABLED then
        mod.info("碎晶之链：自定义 Buff 暂时关闭（内核加载阶段注册会闪退）")
        return
    end
    if not api() then
        mod.warn("碎晶之链：加载器没有 mod.buff，晶核侵蚀不会生效（其余功能不受影响）")
        return
    end
    if M.registered then return end

    -- 碎晶精魂：显示用（玩家自己能看到召唤栏里挂着什么），不做数值效果
    local ok_min, min_id = pcall(api().register, {
        name = M.minion_name,
        texture = "CrystalMinionBuff.png",
        no_time = true,          -- 召唤物 buff 不显示倒计时
        update = function(player, buff_index)
            M.minion_heartbeat = M.minion_heartbeat + 1
        end,
        language = {
            zh = { name = "碎晶精魂", description = "一只碎晶跟着你。\n双击图标可以把它们全叫回来。" },
            en = { name = "Shard Spirit", description = "A shard is following you.\nDouble-tap the icon to dismiss them." },
        },
    })
    -- 加载阶段 register 返回 -1 是「登记成功、ID 待分配」，不算失败
    if ok_min and type(min_id) == "number" then
        if min_id > 0 then ids[M.minion_name] = min_id end
        mod.info("碎晶之链：碎晶精魂已登记（登记号 " .. tostring(min_id) .. "）")
    else
        mod.warn("碎晶之链：碎晶精魂注册失败：" .. tostring(min_id))
    end

    local def = {
        name = M.erosion_name,
        texture = "CrystalErosion.png",
        debuff = true,
        no_time = false,
        language = {
            zh = { name = "晶核侵蚀", description = "晶核在啃你的护甲。\n防御 -6，移动速度 -12%。" },
            en = { name = "Core Erosion", description = "The core is eating your armor.\n-6 defense, -12% movement speed." },
        },
        update = erosion_update,
    }
    local ok, id = pcall(api().register, def)
    if not ok then
        M.error = tostring(id)
        mod.warn("碎晶之链：Buff 注册抛错 " .. M.erosion_name .. "：" .. tostring(id))
        return
    end
    if type(id) ~= "number" then
        M.error = "注册返回 " .. tostring(id)
        return
    end
    if id > 0 then ids[M.erosion_name] = id end
    M.registered = true
    -- 这里只报登记号，不碰 runtime_id（加载阶段它一定是 -1/nil）
    mod.info("碎晶之链：晶核侵蚀已登记（登记号 " .. tostring(id) .. "）")
end

-- 游戏内调用：按名字现查内核分配的 ID。
function M.runtime_id(name)
    local cached = ids[name]
    if cached then return cached end
    local buff = api()
    if not buff or type(buff.runtime_id) ~= "function" then return nil end
    local ok, id = pcall(buff.runtime_id, name)
    if ok and type(id) == "number" and id > 0 then
        ids[name] = id
        return id
    end
    return nil
end

-- 挂 Buff：time 是帧数（60 帧 = 1 秒）。返回实际时长，失败 nil。
function M.add(id, player, frames)
    local buff = api()
    if not buff or type(id) ~= "number" then return nil end
    local ok, actual = pcall(buff.add, id, player, frames or 600)
    if not ok then
        M.error = tostring(actual)
        return nil
    end
    return actual
end

function M.time(id, player)
    local buff = api()
    if not buff or type(buff.time) ~= "function" then return 0 end
    local ok, left = pcall(buff.time, id, player)
    if ok and type(left) == "number" then return left end
    return 0
end

function M.remove(id, player)
    local buff = api()
    if not buff or type(buff.remove) ~= "function" then return end
    pcall(buff.remove, id, player)
end

-- 给玩家挂侵蚀（Boss 战用，也用于 /crystal buff 自测）
function M.apply_erosion(player, frames)
    frames = frames or 600
    local id = M.runtime_id(M.erosion_name)
    if not id then return nil, "没有分到 ID" end
    local actual = M.add(id, player, frames)
    if not actual then return nil, M.error or "挂 Buff 失败" end
    return actual, id
end

return M
