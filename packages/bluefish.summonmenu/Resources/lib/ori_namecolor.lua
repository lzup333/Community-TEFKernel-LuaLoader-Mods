-- NPC名称不解析聊天标签；在悬停文字绘制时使用原版稀有度颜色。
local N={}
local rarity={2,1,10} -- 绿、蓝、红
function N.install(b,r)
 local busy=false; local installed=0
 local function attach(name,kinds,rareIndex)
  local method=b:exact('Main',name,kinds,false)
  if not method then return end
  local hook=b.p.install_hook(method,{prefix=function(obj,args)
   if busy or not r.cfg.coloredNames or not r.world or r:w('netMode','int32',-1)==2 then return false end
   local ok,text=pcall(b.p.string_value,args[1]); if not ok or type(text)~='string' then return false end
   local tier
   for _,s in pairs(r.states) do
    if s.renamed and s.displayName and (text==s.displayName or (text:sub(1,#s.displayName)==s.displayName and text:sub(#s.displayName+1,#s.displayName+1):match('[%s:(]'))) then tier=s.tier;break end
   end
   if not tier then return false end
   local copy={}; for i=1,#kinds do copy[i]=args[i] end
   copy[rareIndex]=rarity[tier]
   busy=true
   local success,result=pcall(b.p.invoke,method,obj,table.unpack(copy,1,#kinds))
   busy=false
   if not success or result==false then
    r.log('NAME_COLOR_FAILED',tostring(result)); return false
   end
   if not r.nameColorConfirmed then r.nameColorConfirmed=true;r.log('NAME_COLOR_SENT','native hover rarity='..rarity[tier]) end
   return true
  end})
  if hook then b.hooks[#b.hooks+1]=hook;installed=installed+1 end
 end
 local short={'string','int32','uint8','int32','int32','int32','int32','int32'}
 attach('MouseText',short,2);attach('MouseTextNoOverride',short,2)
 attach('MouseText',{'string','string','int32','uint8','int32','int32','int32','int32','int32','bool'},3)
 r.log('NAME_COLOR_ROUTE','hooks='..installed)
 return installed>0
end
return N
