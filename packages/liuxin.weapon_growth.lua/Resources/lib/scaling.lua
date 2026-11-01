local M = {}
-- 满级20：各职业新增伤害最多20%，不叠加召唤额外伤害。
M.killDamagePerLevel={melee=.01,ranged=.01,magic=.01,summon=.01}
function M.kill_damage_multiplier(level,category)
 if type(level)~='number' or level~=level or not M.killDamagePerLevel[category] then return 1 end
 return 1+math.max(0,math.min(20,math.floor(level)))*M.killDamagePerLevel[category]
end
M.worldBonus={[0]=0,.04,.08,.12,.22,.27,.32,.37,.42,.46,.50}
function M.world_growth(current,origin,allow)
 if not allow then return 1,'period_growth_off' end
 if M.worldBonus[current]==nil or M.worldBonus[origin]==nil then return 1,'unknown_source' end
 return 1+math.max(0,M.worldBonus[current]-M.worldBonus[origin]),'period_growth'
end
M.names = {[0]='初期','克苏鲁之眼后','邪恶生物群系 Boss 后','骷髅王后','困难模式','任意机械 Boss 后','全部机械 Boss 后','世纪之花后','石巨人后','四柱阶段','月亮领主后'}
M.modeNames={[0]='普通',[1]='专家',[2]='大师',[3]='旅途'}
local function positive(n) return type(n)=='number' and n==n and n>0 and n<math.huge end
-- 两个均值均来自同类、同原生时期的样本；禁止使用单件武器DPS计算系数。
function M.period_multiplier(current,origin,currentAverage,originAverage,strength,cap,suppress,allowGrowth)
    if origin==current then return 1,'current_source' end
    if type(origin)~='number' or not M.names[origin] then return 1,'unknown_source' end
    if not M.names[current] or not positive(currentAverage) or not positive(originAverage) then return 1,'no_reference' end
    if type(strength)~='number' or strength~=strength or strength<0 or strength>1 or not positive(cap) or cap<1 then return 1,'invalid_parameters' end
    local ratio=(currentAverage/originAverage)^strength
    if origin<current then
        if not allowGrowth then return 1,'period_growth_off' end
        return math.min(cap,math.max(1,ratio)),'period_growth'
    end
    if not suppress then return 1,'suppression_off' end
    return math.min(1,ratio),'period_suppression'
end
-- 两个独立系数只在最终伤害处相乘，不按单件武器强弱二次压制。
function M.combine_coefficients(period,level,cap)
    if not positive(period) then period=1 end
    if not positive(level) then level=1 end
    local result
    if period<1 then result=period*math.min(1.2,level)
    else result=1+math.max(0,period-1)+math.max(0,level-1) end
    result=math.min(1.6,result)
    if positive(cap) then result=math.min(cap,result) end
    return result
end
function M.damage(value,multiplier)
    return math.max(1,math.min(2147483647,math.floor(value*multiplier+0.500000001)))
end
return M
