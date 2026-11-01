-- 与游戏接口无关的规则、概率和属性计算。
local C={}
C.names={'异化体','灾变体','终焉体'}
C.nameColors={'4CAF50','3D8DFF','E53935'}
function C.displayName(tier,original,colored)
 local name=C.names[tier]..'·'..original
 return name
end
C.life={{1.25,1.65,0},{1.45,2.10,3.20},{1.70,2.70,4.20},{2,3.40,5.50},{2.40,4.40,7}}
C.damage={{1.10,1.30,0},{1.25,1.60,2},{1.45,2,2.50},{1.70,2.50,3.10},{2,3.10,3.80}}
C.flat={{2,4,0},{4,7,12},{6,10,16},{8,14,22},{10,18,30}}
function C.rng(seed)
 local s=math.floor(tonumber(seed) or 1)%2147483647
 if s<=0 then s=1 end
 return function() s=(s*48271)%2147483647; return s/2147483647 end
end
function C.stage(w)
 if w.moon then return 5 elseif w.plantera then return 4
 elseif w.mech1 and w.mech2 and w.mech3 then return 3
 elseif w.hard then return 2 else return 1 end
end
function C.mode(w)
 if w.zenith then return 4 elseif w.journey then return 5
 elseif w.master then return 3 elseif w.expert then return 2 else return 1 end
end
function C.modifiers()
 return {life=1,damage=1,defense=1,chance=1,speed=1,reward=.20,cala=1,apo=1}
end
-- Bounded soft compensation; never guarantees conversion. Success resets misses.
function C.spawnChance(base,misses)
 if base<=0 then return 0,0 end
 local limit=20
 local progress=math.min(limit,math.max(0,misses or 0))/limit
 return math.min(.6,base*(1+.5*progress)),limit
end
function C.tier(random,stage,mode,m)
 local w=stage==1 and {75,25,0} or ({ {75,20,5},{65,25,10},{55,30,15},{45,35,20},{75,20,5} })[mode]
 local a,b,c=w[1],w[2]*m.cala,w[3]*m.apo
 local r=random()*(a+b+c)
 if r<a then return 1 elseif r<a+b then return 2 else return 3 end
end
local function round(v) return math.floor(v+.5) end
function C.stats(base,tier,stage,mode,m)
 -- base already includes vanilla Expert/Master/Journey strength.
 local modeStats={1,1,1}
 local max=math.max(1,round(base.max*C.life[stage][tier]*modeStats[1]*m.life))
 return {max=max,life=math.max(1,round(max*math.min(1,base.life/base.max))),
 damage=math.max(1,round(base.damage*C.damage[stage][tier]*modeStats[2]*m.damage)),
 defense=round((base.defense*({1.10,1.20,1.30})[tier]+C.flat[stage][tier])*modeStats[3]*m.defense),
 value=math.min(base.value*15,base.value*({1.5,3,6})[tier]*({1,1.15,1.35,1.60,2})[stage]),
 scale=base.scale*({1.05,1.10,1.15})[tier],knock=base.knock*({.8,.6,.4})[tier]}
end
return C
