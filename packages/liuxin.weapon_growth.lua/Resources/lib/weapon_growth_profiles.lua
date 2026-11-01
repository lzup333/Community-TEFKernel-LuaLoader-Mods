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
function M.attributes(level,e)
    if type(level)~='number' or level~=level then level=0 end
    local x=math.max(0,math.min(20,math.floor(level)))/20
    local kind=M.kind(e);local a={}
    if e.growthDisabled then return a end
    if kind=='melee_swing' then a={attackSpeed=.03*x,size=.04*x}
    elseif kind=='melee_projectile' then a={crit=3*x,projectileSpeed=.06*x}
    elseif kind=='melee_control' then a={crit=3*x,knockback=.8*x}
    elseif kind=='ranged_fast' then a={useTime=.025*x,ammoSave=.10*x}
    elseif kind=='ranged_heavy' then a={crit=3*x,knockback=.8*x}
    elseif kind=='magic_projectile' then a={castSpeed=.025*x,manaCost=.10*x}
    elseif kind=='magic_channel' then a={crit=3*x,manaCost=.12*x}
    elseif kind=='summon_whip' then a={attackSpeed=.03*x,whipRange=.05*x}
    elseif kind=='summon_minion' then a={knockback=1.2*x}
    elseif kind=='summon_sentry' then a={knockback=1.5*x} end
    -- 不显示/应用没有实际弹药和射弹的成长属性。
    if e.useAmmo==nil or e.useAmmo<=0 then a.ammoSave=nil end
    if e.shoot==nil or e.shoot<=0 or e.channel then a.projectileSpeed=nil end
    if a.crit then a.crit=math.floor(a.crit) end
    return a
end
return M
