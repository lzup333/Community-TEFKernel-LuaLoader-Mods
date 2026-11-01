-- Read-only adapter for Terraria 1.4.5.8. No game state writes or native offsets.
local D={recipes={},items={},names={},ready=false,index=0,total=0,errors=0}
local C=require('cache')
local p=mod.patch
local function safe(fn,...)
 if not fn then return nil end
 local ok,v=pcall(fn,...);if ok and v~=false then return v end
end
local function field(t,n)return t and safe(p.get_field,t,n)end
local function read(f,obj,kind)return f and safe(p.get_field_value,f,obj,kind)end
local function method(t,n,c)return t and safe(p.get_method,t,n,c)end
local function getter(t,n)
 local prop=t and safe(p.get_property,t,n)
 return prop and safe(p.property_get_method,prop)
end
local function retain(v)return v and safe(p.retain,v)end
local function text(v)
 if type(v)=='string' then return v end
 return v and safe(p.string_value,v)
end
function D.init()
 mod.write_file('recipebook_runtime.log','RecipeBook 0.1.20\nstage=init_begin\n')
 if not p then D.error='未找到 LuaLoader patch 接口';return false end
 local main=safe(p.get_type,'Terraria','Main');local recipe=safe(p.get_type,'Terraria','Recipe')
 local item=safe(p.get_type,'Terraria','Item');local lang=safe(p.get_type,'Terraria','Lang')
 local player=safe(p.get_type,'Terraria','Player')
 D.f={mainRecipes=field(main,'recipe'),num=field(recipe,'numRecipes'),out=field(recipe,'createItem'),materials=field(recipe,'requiredItem'),tile=field(recipe,'requiredTile'),quick=field(recipe,'requiredItemQuickLookup'),accepted=field(recipe,'acceptedGroups'),type=field(item,'type'),stack=field(item,'stack'),accessory=field(item,'accessory'),damage=field(item,'damage'),player=field(main,'player'),inventory=field(player,'inventory')}
 D.conditions={};for _,n in ipairs({'needWater','needHoney','needLava','needSnowBiome','needGraveyardBiome','needMechdusa','needTorchGodsFavor','crimson','corruption'})do D.conditions[n]=field(recipe,n)end
 D.nameMethod=retain(method(lang,'GetItemNameValue',1))
 D.gameMenu=retain(getter(main,'gameMenu'));D.screenWidth=retain(getter(main,'screenWidth'));D.screenHeight=retain(getter(main,'screenHeight'));D.myPlayer=retain(getter(main,'myPlayer'))
 -- Metadata handles too must survive across GUI callbacks.
 for k,v in pairs(D.f)do D.f[k]=retain(v)end
 for k,v in pairs(D.conditions)do D.conditions[k]=retain(v)end
 if not D.f.mainRecipes or not D.f.num or not D.f.out or not D.f.materials or not D.f.type then D.error='当前游戏的配方接口与 1.4.5.8 不匹配';return false end
 mod.write_file('recipebook_runtime.log','RecipeBook 0.1.20\nstage=init_ready\n')
 return true
end
function D.name(id)
 if D.names[id]then return D.names[id]end
 local s=text(safe(p.invoke,D.nameMethod,id))
 if not s or s=='' then s='物品 #'..tostring(id) end
 D.names[id]=s;return s
end
-- Android dictionary/list generic helper calls are intentionally absent here.
-- The supplied crash ended in Dictionary`2 resolution; no Lua pcall can catch SIGSEGV.
local lastCheckpoint=-120
local function checkpoint(stage)
 D.stage=stage
 if stage=='scan_batch' and D.index-lastCheckpoint<120 then return end
 lastCheckpoint=D.index
 mod.write_file('recipebook_runtime.log','RecipeBook 0.1.20\nstage='..stage..'\nindex='..D.index..' total='..D.total..'\nerrors='..D.errors..'\n')
end
local labels={needWater='靠近水',needHoney='靠近蜂蜜',needLava='靠近熔岩',needSnowBiome='雪原环境',needGraveyardBiome='墓地环境',needMechdusa='特殊种子条件',needTorchGodsFavor='火把神恩赐',crimson='猩红世界条件',corruption='腐化世界条件'}
function D.decode(obj)
 local out=read(D.f.out,obj,'object');if not out then return end
 local id=read(D.f.type,out,'int32');if not id or id<=0 then return end
 local r={id=id,output=read(D.f.stack,out,'int32') or 1,materials={},stations={},conditions={}}
 local tile=read(D.f.tile,obj,'int32');if tile and tile>=0 then r.stations[1]=tile end
 local arr=read(D.f.materials,obj,'object');local quick=read(D.f.quick,obj,'object')
 if not arr then return end
 local quickN=quick and safe(p.array_length,quick) or 0
 local accepted=read(D.f.accepted,obj,'object');local groupCount=accepted and (safe(p.array_length,accepted) or 0) or 0
 for i=0,math.min(safe(p.array_length,arr) or 0,15)-1 do
  local it=safe(p.array_at,arr,i);local mid=it and read(D.f.type,it,'int32');local count=it and read(D.f.stack,it,'int32')
  if mid and mid>0 and count and count>0 then
   local m={id=mid,count=count}
   -- Quick entries preserve group identity; this struct is exactly two int32s in the supplied source.
   if quick and i<quickN and p.array_at_raw then
    local raw=safe(p.array_at_raw,quick,i,8)
    if raw and #raw==8 then
     local qid,qcount=string.unpack('<i4i4',raw)
     if qcount==count and qid~=mid then
      m.group=qid;m.unresolved=true;m.name=D.name(mid)..'（可替代）'
     end
    end
   end
   if groupCount>0 and not m.group then
    -- If quick lookup is unavailable, do not guess which slot belongs to which group.
    r.groupWarning=true
   end
   D.name(mid)
   r.materials[#r.materials+1]=m
  end
 end
 for n,f in pairs(D.conditions)do if read(f,obj,'bool')==true then r.conditions[#r.conditions+1]=labels[n]end end
 D.name(id)
 D.items[id]=D.items[id] or {id=id,category=read(D.f.accessory,out,'bool')==true and '饰品' or ((read(D.f.damage,out,'int32') or 0)>0 and '武器' or '材料')}
 D.recipes[id]=D.recipes[id] or {};D.recipes[id][#D.recipes[id]+1]=r
end
function D.tick()
 if D.ready then C.tick(D);return end
 if D.error then return end
 if not D.gameMenu then D.error='未找到游戏菜单状态接口，已停止自动读取';return end
 local okMenu,inMenu=pcall(p.invoke,D.gameMenu)
 if not okMenu or inMenu~=false then D.waitingWorld=true;return end
 D.waitingWorld=false
 local arr=read(D.f.mainRecipes,nil,'object');local n=read(D.f.num,nil,'int32') or 0
 if not arr or n<=0 then return end
 D.total=math.min(n,safe(p.array_length,arr) or 0,50000)
 if not D.signature then
  -- Sample stable primitive fields; never cache managed handles or inventory.
  local parts={'1.4.5.8/schema2',tostring(D.total),D.name(1),D.name(5000)}
  for j=0,15 do
   local obj=safe(p.array_at,arr,math.floor((D.total-1)*j/15))
   local out=obj and read(D.f.out,obj,'object')
   parts[#parts+1]=tostring(out and read(D.f.type,out,'int32'))
   parts[#parts+1]=tostring(out and read(D.f.stack,out,'int32'))
   parts[#parts+1]=tostring(obj and read(D.f.tile,obj,'int32'))
   for _,name in ipairs({'needWater','needHoney','needLava','needSnowBiome','needGraveyardBiome','needMechdusa','needTorchGodsFavor','crimson','corruption'})do parts[#parts+1]=tostring(obj and read(D.conditions[name],obj,'bool'))end
   local accepted=obj and read(D.f.accepted,obj,'object');parts[#parts+1]=tostring(accepted and safe(p.array_length,accepted))
   local mats=obj and read(D.f.materials,obj,'object')
   for k=0,math.min(mats and safe(p.array_length,mats)or 0,15)-1 do
    local it=safe(p.array_at,mats,k)
    parts[#parts+1]=tostring(it and read(D.f.type,it,'int32'))..':'..tostring(it and read(D.f.stack,it,'int32'))
   end
  end
  D.signature=table.concat(parts,'|')
  if not D.forceScan then C.load(D,D.signature)end
 end
 if C.loading then C.tick(D);return end
 checkpoint('scan_batch')
 for i=D.index,math.min(D.index+5,D.total-1)do
  local obj=safe(p.array_at,arr,i);if obj then local ok,e=pcall(D.decode,obj);if not ok then D.errors=D.errors+1;mod.warn('[RecipeBook][SCAN]',i,tostring(e))end end
 end
 D.index=math.min(D.index+6,D.total)
 if D.index>=D.total then
  if not next(D.recipes)then D.error='配方表存在，但未能读取产物，请提交加载器日志';mod.error('[RecipeBook][EMPTY_INDEX] '..D.error);mod.write_file('recipebook_runtime.log',D.error);return end
  D.ready=true;if D.errors==0 then C.save(D,D.signature)else D.cacheStatus='部分配方读取失败 · 未保存缓存'end;checkpoint('ready');mod.info('[RecipeBook][READY]',D.total,'recipes; errors',D.errors);mod.write_file('recipebook_runtime.log','RecipeBook 0.1.20\nplatform='..tostring(mod.platform)..' arch='..tostring(mod.arch)..'\nindexed='..D.total..' errors='..D.errors..'\n')end
end
function D.rebuild()
 C.cancel();D.ready=false;D.error=nil;D.recipes={};D.items={};D.names={};D.index=0
 D.signature=nil;D.forceScan=true;D.cacheStatus='重新整理';D.errors=0
end
function D.inventory()
 local result={};local idx=safe(p.invoke,D.myPlayer);local arr=read(D.f.player,nil,'object')
 if type(idx)~='number' or not arr then return result end
 local player=safe(p.array_at,arr,idx);local bag=player and read(D.f.inventory,player,'object')
 if bag then for i=0,math.min(safe(p.array_length,bag) or 0,58)-1 do
  local it=safe(p.array_at,bag,i);local id=it and read(D.f.type,it,'int32');local n=it and read(D.f.stack,it,'int32')
  if id and id>0 and n and n>0 then result[id]=(result[id] or 0)+n end
 end end
 return result
end
function D.screen()
 return safe(p.invoke,D.screenWidth) or 1000,safe(p.invoke,D.screenHeight) or 700
end
return D
