-- 只使用原版标量行为；未知行为采用保守加成，不猜测射弹AI或改写攻击机制。
local M={}
function M.kind(e)
    local c=e.category
    if c=='melee' then
        if e.channel then return 'melee_control','持续控制近战' end
        if e.noMelee==false then return 'melee_swing','挥砍近战' end
        return 'melee_projectile','投射近战'
    elseif c=='ranged' then
        if type(e.useTime)=='number' and e.useTime>=25 then return 'ranged_heavy','重型远程' end
        return 'ranged_fast','快速远程'
    elseif c=='magic' then
        if e.channel then return 'magic_channel','持续施法' end
        return 'magic_projectile','普通施法'
    elseif c=='summon' then
        if e.isWhip then return 'summon_whip','鞭子' end
        if e.sentry then return 'summon_sentry','哨兵召唤' end
        return 'summon_minion','仆从召唤'
    end
end
M.attributes=require('wg_native_backend').attributes
return M
