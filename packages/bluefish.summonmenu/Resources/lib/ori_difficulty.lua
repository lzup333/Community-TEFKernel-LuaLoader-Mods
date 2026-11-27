-- Extra scaling is applied to already world-scaled NPC stats, never twice.
local D={}
local profiles={
 normal={name='普通',chance=.15,bonus=1,lifeCap=4,damageCap=2,defenseCap=14,
  cooldown={8,6,4},earlyCooldown={11,8,6},warning=60,projectile=35,earlyProjectile=20,
  hitCap=25,earlyHitCap=15,cap=8,special=.30,rotation=true,
  weights={75,20,5},lateWeights={65,25,10},earlyTier2=.20}
}
function D.valid(key)return key==nil or key=='normal' end
function D.get(cfg)return profiles.normal end
function D.cap(cfg)return math.min(cfg.maxActive or 8,D.get(cfg).cap)end
function D.chance(cfg,stage,protection)
 return D.get(cfg).chance*({.8,1,1.1,1.2,1.3})[stage]*(protection and protection.chance or 1)
end
function D.cooldown(cfg,s)
 local p=D.get(cfg);local seconds=(s.stage==1 and p.earlyCooldown or p.cooldown)[s.tier or 1]
 if s.action=='summon'then seconds=math.max(seconds,18)
 elseif s.action=='guard'then seconds=math.max(seconds,9)
 elseif s.action=='blink'or s.action=='illusion'then seconds=math.max(seconds,9)end
 return math.floor(seconds*60+.5)
end
function D.warning(cfg,s)
 if s.combat then
  local crazy=false;local easy=false
  local special=s.action=='blink'or s.action=='summon'or s.action=='illusion'
  return math.max(s.stage==1 and 60 or 0,special and(crazy and 36 or 45)or s.action=='echo'and(crazy and 33 or 42)or(crazy and 20 or easy and 42 or 30))
 end
 return math.max(D.get(cfg).warning,s.stage==1 and 75 or 0,
  s.style=='trick'and 75 or 0,
  (s.action=='blink'or s.action=='illusion'or s.action=='summon')and 90 or 0)
end
function D.breakFrames(cfg,s)
 return math.min(D.warning(cfg,s),s.stage==1 and 20 or D.get(cfg).name=='疯狂'and 8 or D.get(cfg).name=='轻松'and 20 or 12)
end
function D.tier(random,stage,cfg,protection)
 local p=D.get(cfg)
 if protection then return random()<math.min(protection.tier2*p.earlyTier2/.20,p.earlyTier2)and 2 or 1 end
 local w=stage>=4 and p.lateWeights or p.weights
 local x=random()*100
 return x<w[1]and 1 or x<w[1]+w[2]and 2 or 3
end
function D.stats(base,stats,cfg,tier)
 return require('ori_native_backend').difficulty_stats(base,stats,D.get(cfg),tier)
end
return D
