-- Extra scaling is applied to already world-scaled NPC stats, never twice.
local D={}
local profiles={
 easy={name='轻松',chance=.08,bonus=.55,lifeCap=2.5,damageCap=1.5,defenseCap=8,
  cooldown={12,9,6},earlyCooldown={15,11,8},warning=90,projectile=25,earlyProjectile=15,
  hitCap=20,earlyHitCap=12,cap=4,special=.15,rotation=false,
  weights={85,13,2},lateWeights={75,20,5},earlyTier2=.10},
 normal={name='普通',chance=.15,bonus=1,lifeCap=4,damageCap=2,defenseCap=14,
  cooldown={8,6,4},earlyCooldown={11,8,6},warning=60,projectile=35,earlyProjectile=20,
  hitCap=25,earlyHitCap=15,cap=8,special=.30,rotation=true,
  weights={75,20,5},lateWeights={65,25,10},earlyTier2=.20},
 crazy={name='疯狂',chance=.40,bonus=1.5,lifeCap=6,damageCap=2.8,defenseCap=22,
  cooldown={5,3.5,2.5},earlyCooldown={8,6,4},warning=45,projectile=40,earlyProjectile=25,
  hitCap=30,earlyHitCap=18,cap=12,special=.50,rotation=true,
  weights={60,28,12},lateWeights={45,35,20},earlyTier2=.30}
}
function D.valid(key)return profiles[key]~=nil end
function D.get(cfg)return profiles[cfg and (cfg.remoteDifficulty or cfg.difficulty)]or profiles.normal end
function D.cap(cfg)return math.min(cfg.maxActive or 8,D.get(cfg).cap)end
function D.chance(cfg,stage,protection)
 return D.get(cfg).chance*({.8,1,1.1,1.2,1.3})[stage]*(protection and protection.chance or 1)
end
function D.cooldown(cfg,s)
 local p=D.get(cfg);local seconds=(s.stage==1 and p.earlyCooldown or p.cooldown)[s.tier or 1]
 if s.action=='summon'then seconds=math.max(seconds,({easy=22,normal=18,crazy=14})[cfg.difficulty or 'normal']or 18)
 elseif s.action=='guard'then seconds=math.max(seconds,({easy=12,normal=9,crazy=7})[cfg.difficulty or 'normal']or 9)
 elseif s.action=='blink'or s.action=='illusion'then seconds=math.max(seconds,({easy=12,normal=9,crazy=7})[cfg.difficulty or 'normal']or 9)end
 return math.floor(seconds*60+.5)
end
function D.warning(cfg,s)
 if s.combat then
  local crazy=D.get(cfg).name=='疯狂';local easy=D.get(cfg).name=='轻松'
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
 local p=D.get(cfg)
 local function round(v)return math.floor(v+.5)end
 local life=math.min(p.lifeCap,1+math.max(0,stats.max/base.max-1)*p.bonus)
 local damage=math.min(p.damageCap,1+math.max(0,stats.damage/math.max(1,base.damage)-1)*p.bonus)
 stats.max=math.max(1,round(base.max*life))
 stats.life=math.max(1,math.min(stats.max,round(stats.max*math.min(1,base.life/base.max))))
 stats.damage=math.max(1,round(base.damage*damage))
 stats.defense=base.defense+math.min(p.defenseCap,round(math.max(0,stats.defense-base.defense)*p.bonus))
 -- Preserve knockback counterplay in easy; stronger resistance in crazy.
 stats.knock=base.knock*math.max(.25,1-({.2,.4,.6})[tier]*p.bonus)
 return stats
end
return D
