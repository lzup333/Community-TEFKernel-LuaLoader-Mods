-- Android 1.4.5.8 NPCID.cs 核对的多实体战斗。只读取，不修改NPC。
local E={}
local families={
 twins={roots={[125]=1,[126]=1},twins=true,parts={}},
 skeletron={roots={[35]=1},parts={{36,'手部',2}}},
 prime={roots={[127]=1},parts={{128,'机械炮',1},{129,'机械锯',1},{130,'机械钳',1},{131,'机械激光',1}}},
 golem={roots={[245]=1},parts={{246,'头部',1},{247,'左拳',1},{248,'右拳',1},{245,'身体',1}}},
 moon={roots={[398]=1},parts={{396,'额头眼',1},{397,'手眼',2},{398,'核心',1}}},
 saucer={roots={[395]=1},extra={[392]=true},parts={{393,'机枪炮台',2},{394,'火箭炮台',2},{395,'核心',1}}},
 dutchman={roots={[491]=1},parts={{492,'舰炮',4}}},
}
local by_type={}
for name,d in pairs(families) do
 d.name=name;d.types={}
 for t in pairs(d.roots) do d.types[t]=true;by_type[t]=d end
 for _,part in ipairs(d.parts) do d.types[part[1]]=true;by_type[part[1]]=d end
 for t in pairs(d.extra or {}) do d.types[t]=true;by_type[t]=d end
end
function E.family(type) return by_type[type] end
local function alive(n) return n and n.life and n.life>0 and n.max and n.max>0 end
function E.build(track,records)
 local d=E.family(track.type)
 if not d then return nil end
 local counts,selected={},{}
 for _,n in ipairs(records) do
  if d.types[n.type] and alive(n) then
   counts[n.type]=(counts[n.type] or 0)+1
   selected[#selected+1]=n
  end
 end
 table.sort(selected,function(a,b) return a.type==b.type and a.index<b.index or a.type<b.type end)
 local roots=0
 for t,limit in pairs(d.roots) do
  if (counts[t] or 0)>limit then return nil end
  roots=roots+(counts[t] or 0)
 end
 if roots==0 then return nil end
 if d.twins then return {mode='twins',family=d.name,bars=selected,parts={}} end
 -- 同类型主体或部件超过一场战斗的数量时不猜配对，保留原版主读数。
 for _,p in ipairs(d.parts) do if (counts[p[1]] or 0)>p[3] then return nil end end
 local parts={}
 for _,p in ipairs(d.parts) do
  local ordinal=0
  for _,n in ipairs(selected) do
   if n.type==p[1] then
    ordinal=ordinal+1
    local defeated=d.name=='moon' and n.type~=398 and n.life==1 and n.locked and n.ai0==-2
    parts[#parts+1]={key=n.key,type=n.type,index=n.index,life=defeated and 0 or n.life,max=n.max,
     locked=n.locked and not defeated,defeated=defeated,name=p[2]..(p[3]>1 and ' '..ordinal or '')}
   end
  end
 end
 return {mode='parts',family=d.name,parts=parts}
end
function E.resolve(bridge,track)
 local d=E.family(track.type)
 if not d then return nil end
 return E.build(track,bridge:scan_npcs(d.types,d.twins))
end
return E
