-- ============================================================================
-- 城镇NPC无敌 v1.5.0
-- ----------------------------------------------------------------------------
-- 城镇 NPC 不会受到敌怪伤害；岩浆、玩家武器等其它伤害照常生效。
--
-- 做法：钩 NPC.StrikeNPC，按伤害来源决定是否拦截。
--
--   敌怪接触   BeHurtByOtherNPC -> StrikeNPCNoInteraction(dmg, 6, dir)
--              -> StrikeNPC(knockBack = 6, owner = 255)            -> 拦截
--   敌怪弹幕   Projectile.Damage -> StrikeNPC(knockBack > 0, owner = 255) -> 拦截
--   岩浆       Collision_LavaCollision -> StrikeNPCNoInteraction(50, 0f, 0)
--              -> StrikeNPC(knockBack = 0, owner = 255)            -> 放行
--   玩家武器   Player / Projectile -> StrikeNPC(owner = 0~254)     -> 放行
--
-- 判据：
--   owner 在 0~254  -> 玩家来源，放行
--   knockBack <= 0  -> 环境来源（岩浆等），放行
--   其余            -> 敌怪伤害，拦截（返回 true 跳过原方法，伤害为 0）
-- ============================================================================

mod.meta = { pkg_id = "bluefish.npcguard", version = "1.5.0", version_code = 150, api_version = 1 }

local P = mod.patch
local F = {}

local function is_town(npc)
    if not npc or not F.town then return false end
    local ok, v = pcall(P.get_field_value, F.town, npc, "bool")
    return ok and v == true
end

function setup()
    local okT, T = pcall(P.get_type, "Terraria", "NPC")
    if not (okT and T) then return end
    F.T = T

    local okF, f = pcall(P.get_field, T, "townNPC")
    if not (okF and f) then return end
    F.town = f

    local m
    for i = 1, 3 do
        local n = ({ 6, 5, 4 })[i]
        local ok, v = pcall(P.get_method, T, "StrikeNPC", n)
        if ok and v then m = v break end
    end
    if not m then return end

    pcall(P.install_hook, m, { prefix = function(inst, args)
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
    end })
end

mod.setup = setup
todo_list = { "setup" }
