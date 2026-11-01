-- Pure Lua location classifier. Nil probes mean unknown, never default forest.
local L={}
L.probes={
 'ZoneDungeon','ZoneJungle','ZoneSnow','ZoneDesert','ZoneUndergroundDesert',
 'ZoneCorrupt','ZoneCrimson','ZoneHallow','ZoneGlowshroom','ZoneBeach',
 'ZoneGranite','ZoneMarble','ZoneHive','ZoneLihzhardTemple','ShoppingZone_Forest',
 'ZoneSkyHeight','ZoneOverworldHeight','ZoneDirtLayerHeight','ZoneRockLayerHeight','ZoneUnderworldHeight',
}
function L.resolve(f)
 local depth
 for _,d in ipairs({{'ZoneUnderworldHeight','地狱'},{'ZoneSkyHeight','太空'},
  {'ZoneRockLayerHeight','洞穴'},{'ZoneDirtLayerHeight','地下'},{'ZoneOverworldHeight','地表'}}) do
  if f[d[1]]==true then depth=d[2];break end
 end
 local names,seen={},{}
 local function put(s) if not seen[s] then names[#names+1]=s;seen[s]=true end end
 local function biome(s)
  if depth=='洞穴' or depth=='地下' then s='地下'..s
  elseif depth=='地狱' or depth=='太空' then s=s..'（'..depth..'）' end
  put(s)
 end
 for _,d in ipairs({{'ZoneCrimson','猩红之地'},{'ZoneCorrupt','腐化之地'},
  {'ZoneHallow','神圣之地'},{'ZoneJungle','丛林'},{'ZoneSnow','雪原'},
  {'ZoneGlowshroom','发光蘑菇区'}}) do if f[d[1]]==true then biome(d[2]) end end
 if f.ZoneUndergroundDesert==true then put('地下沙漠')
 elseif f.ZoneDesert==true then biome('沙漠') end
 for _,d in ipairs({{'ZoneDungeon','地牢'},{'ZoneLihzhardTemple','丛林神庙'},
  {'ZoneHive','蜂巢'},{'ZoneGranite','花岗岩洞'},{'ZoneMarble','大理石洞'},{'ZoneBeach','海滩'}}) do
  if f[d[1]]==true then put(d[2]) end
 end
 if #names==0 then
  if depth=='地表' and f.ShoppingZone_Forest==true then put('森林')
  elseif depth then put(depth) end
 end
 return names
end
function L.new() return setmetatable({counts={}}, {__index=L}) end
-- Called every 30 local player updates: four consecutive samples ~= 2 seconds.
function L:sample(names)
 local nextCounts,confirmed={},{}
 for _,s in ipairs(names) do
  nextCounts[s]=math.min(4,(self.counts[s] or 0)+1)
  if nextCounts[s]>=4 then confirmed[#confirmed+1]=s end
 end
 self.counts=nextCounts;return confirmed
end
function L:reset() self.counts={} end
return L
