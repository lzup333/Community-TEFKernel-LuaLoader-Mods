local G={MAX_LEVEL=30,levels={5,15,30},keys={'str','agi','vit','int','spi','luk'},labels={'力量','敏捷','体质','智力','精神','幸运'}}
local thresholds={0};for l=1,29 do thresholds[l+1]=math.floor(thresholds[l]+100+40*(l-1)+10*(l-1)^2)end
local function integer(n,max)n=tonumber(n);if not n or n~=n then return 0 end;return math.max(0,math.min(max or 100000000,math.floor(n)))end
function G.threshold(level)return thresholds[math.max(1,math.min(30,level))]end
function G.level(xp)local level=1;while level<30 and (xp or 0)>=thresholds[level+1]do level=level+1 end;return level end
function G.clean(data,xp)
    data=data or {};local left=(G.level(xp)-1)*3;local out={choices={},equipped={}}
    for _,k in ipairs(G.keys)do out[k]=math.min(left,integer(data[k],87));left=left-out[k]end
    for i=1,3 do out.choices[i]=data.choices and data.choices[i]end
    for i=1,2 do out.equipped[i]=data.equipped and data.equipped[i]end
    return out
end
function G.points(xp,data)local n=(G.level(xp)-1)*3;for _,k in ipairs(G.keys)do n=n-(data[k] or 0)end;return n end
function G.stats(d,base,damage,defense,level)
    d=d or {};level=level or 1;local scale=.01*(level-1)
    return {damage=math.floor(damage*(1+scale+.015*(d.str or 0))+.5),magic_damage=math.floor(damage*(1+scale+.015*(d.int or 0))+.5),
        max_life=math.floor(base*(1+.02*(level-1)))+6*(d.vit or 0),defense=(defense or 0)+.5*(d.vit or 0)+math.floor((level-1)/5),
        speed=1+math.min(.30,.005*(d.agi or 0)),attack_interval=1-math.min(.25,.003*(d.agi or 0)),cooldown=1-math.min(.40,.004*(d.spi or 0)),
        resistance=math.min(.50,.005*(d.spi or 0)),crit=math.min(.50,.05+.002*(d.luk or 0)),crit_damage=1.5+.005*(d.luk or 0),
        knockback=1+.01*(d.str or 0),reduction=0}
end
return G
