local P={}
function P.profile(w)
 if w.hard then return nil end
 if w.boss2 then return {cap=8,chance=1,tier2=.25}end
 if w.boss1 or w.slimeKing or w.boss3 then return {cap=3,chance=.75,tier2=.10}end
 return {cap=2,chance=.5,tier2=0}
end
function P.stats(base,tier)
 local life=tier==1 and 1.15 or 1.35
 local damage=tier==1 and 1.05 or 1.15
 return {max=math.max(1,math.floor(base.max*life+.5)),life=math.max(1,math.floor(base.life*life+.5)),damage=math.max(1,math.floor(base.damage*damage+.5)),defense=base.defense+(tier==1 and 1 or 2),value=base.value,scale=base.scale,knock=base.knock}
end
function P.nearSpawn(r,n)
 local sx=r:w('spawnTileX','int32',-1);local sy=r:w('spawnTileY','int32',-1)
 if sx<0 or sy<0 then return false end
 local x,y=r.b:vec('NPC','position',n);if not x then return false end
 -- Protect a 120-tile-radius circle; deep underground outside the circle remains eligible.
 return (x-sx*16)^2+(y-sy*16)^2<1920^2
end
return P
