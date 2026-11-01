local L={}
local pools={
 {material={{23,15,30},{75,3,5}},consumable={{40,20,50},{28,2,4}},equipment={{50,1,1},{54,1,1},{53,1,1},{84,1,1}}},
 {material={{381,2,4},{382,2,4},{391,2,4},{520,3,6},{521,3,6}},consumable={{97,20,60},{188,2,4}},equipment={{492,1,1},{493,1,1}}},
 {material={{1225,2,4},{947,8,16},{1006,2,4},{547,3,6},{548,3,6},{549,3,6}},consumable={{500,3,6},{499,2,4}},equipment={{492,1,1},{493,1,1}}},
 {material={{1508,2,4},{3261,2,4},{1552,2,4},{1006,3,6}},consumable={{499,4,8},{500,4,8}},equipment={{492,1,1},{493,1,1}}},
 {material={{3467,2,5},{1508,3,6},{2218,2,4},{1552,2,5},{1006,4,8}},consumable={{499,5,10},{500,5,10}},equipment={{492,1,1},{493,1,1}}},
}
function L.crate(stage,e)
 local pairs={['地牢']={3205,3984},['海洋']={5002,5003},['天空']={3206,3985},corrupt={3203,3982},crimson={3204,3983},hallow={3207,3986},jungle={3208,3987},snow={4405,4406},desert={4407,4408}}
 local pair=pairs[e.special]or pairs[e.biome]or(e.hell and {4877,4878})or{2336,3981}
 return pair[stage==1 and 1 or 2]
end
function L.choose(random,tier,stage,m,e,cfg)
 if tier==1 and random()>(m.reward or .2)then return nil end
 local kind='material'
 if tier==1 then kind=random()<.35 and 'consumable'or'material'
 elseif tier==2 then local roll=random();kind=roll<.7 and'material'or roll<.9 and'consumable'or'equipment'
 else
  local chance=({.2,.4,.4,.25,.15})[stage]
  if cfg.crateRewards and random()<chance then return L.crate(stage,e),1,'crate' end
  kind=random()<.5 and'equipment'or'material'
 end
 if kind=='equipment'and not cfg.equipmentRewards then kind='material'end
 local pool=pools[stage][kind];local v=pool[math.min(#pool,1+math.floor(random()*#pool))]
 local stack=v[2]+math.min(v[3]-v[2],math.floor(random()*(v[3]-v[2]+1)))
 if tier==3 and kind=='material'then stack=stack*2 end
 return v[1],stack,kind
end
L.pools=pools
return L
