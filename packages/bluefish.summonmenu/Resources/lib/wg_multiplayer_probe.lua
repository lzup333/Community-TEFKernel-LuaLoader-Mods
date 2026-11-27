-- 联机诊断独立于成长系统。仅监听，不发送数据、不改伤害。
local M={}
function M.install(P,api)
 local self={hooks={},last={},counts={},enabled=true}
 local function emit(tag,key,message,force)
  if not api.enabled() then return end
  if not force then key=tag end -- 按入口限频，避免大量射弹槽产生无限日志键。
  local now=os.time();self.counts[key]=(self.counts[key] or 0)+1
  if not force and now-(self.last[key] or -100)<3 then return end
  self.last[key]=now
  api.log(tag,'netMode='..tostring(api.mode())..' local='..tostring(api.localPlayer())..' count='..self.counts[key]..' '..message,true)
 end
 local function text(value)
  if type(value)=='string' then return value end
  if value then local ok,s=pcall(P.string_value,value);if ok then return s end end
 end
 local function install(t,name,n,callbacks)
  local names=name=='StrikeNPC' and {'Damage','knockBack','hitDirection','crit','fromNet','owner'}
   or (name=='GetWeaponDamage' and {'sItem'})
  local m=t and (names and P.get_method_by_names(t,name,names) or P.get_method(t,name,n))
  if not m or P.method_param_count(m)~=n then
   api.log('MP_PROBE_UNAVAILABLE',name..' 签名不可用',true);return
  end
  local keys={GetWeaponDamage='Player.GetWeaponDamage(Item)',Damage='Projectile.Damage()',StrikeNPC='NPC.StrikeNPC(scalars)'}
  local spec={_wg_key=keys[name]}
  for phase,fn in pairs(callbacks) do
   spec[phase]=function(instance,args,result)
    if not api.enabled() then return false end
    local ok,err=pcall(fn,instance,args or {},result)
    if not ok then emit('MP_PROBE_ERROR',name,tostring(err)) end
    return false -- 不修改原方法返回值，不跳过原版。
   end
  end
  local ok,h=pcall(P.install_hook,m,spec)
  if ok and h then self.hooks[#self.hooks+1]=h;api.log('MP_PROBE_READY',name,true)
  else api.log('MP_PROBE_UNAVAILABLE',name..' '..tostring(h),true) end
 end
 local ok,err=pcall(function()
  local chat=P.get_type('Terraria.Chat','ChatMessage')
  local getter=chat and P.get_method(chat,'get_Text',0)
  local backing=chat and P.get_field(chat,'<Text>k__BackingField')
  local function message(o)
   if getter then return text(P.invoke(getter,o)) end
   if backing then return P.get_field_value(backing,o,'string') end
  end
  local function marker(s) return type(s)=='string' and #s<=160 and s:match('^WGPROBE%s+[%w_-]+%s*$') end
  install(P.get_type('Terraria.Chat','ChatHelper'),'SendChatMessageFromClient',1,{postfix=function(_,args)
   local s=message(args[1]);if marker(s) then emit('MP_CHAT_OUT',s,s,true) end
  end})
  install(P.get_type('Terraria.Chat','ChatCommandProcessor'),'ProcessIncomingMessage',2,{postfix=function(_,args)
   local s=message(args[1]);if marker(s) then emit('MP_CHAT_IN',s..':'..tostring(args[2]),'sender='..tostring(args[2])..' '..s,true) end
  end})
  -- 只读取安全标量签名的伤害入口，不读取网络包缓冲区。
  local player=P.get_type('Terraria','Player');local item=P.get_type('Terraria','Item')
  local pi=P.get_field(player,'whoAmI');local it=P.get_field(item,'type')
  install(player,'GetWeaponDamage',1,{postfix=function(instance,args,result)
   if not args[1] then return end
   local owner=P.get_field_value(pi,instance,'int32');local id=P.get_field_value(it,args[1],'int32')
   emit('MP_WEAPON_DAMAGE','weapon:'..tostring(owner)..':'..tostring(id),'owner='..tostring(owner)..' item='..tostring(id)..' observedResult='..tostring(result))
  end})
  local proj=P.get_type('Terraria','Projectile');local fields={}
  for _,n in ipairs({'owner','type','whoAmI','damage'}) do fields[n]=P.get_field(proj,n) end
  local function desc(o)
   local parts={};for _,n in ipairs({'owner','type','whoAmI','damage'}) do
    if fields[n] then parts[#parts+1]=n..'='..tostring(P.get_field_value(fields[n],o,'int32')) end
   end
   return table.concat(parts,' ')
  end
  local function positive(o)
   if not api.enabled() or not fields.damage then return false end
   local n=P.get_field_value(fields.damage,o,'int32');return type(n)=='number' and n>0
  end
  install(proj,'Damage',0,{prefix=function(o) if positive(o) then emit('MP_PROJECTILE_BEFORE',desc(o),desc(o)) end end,
   postfix=function(o) if positive(o) then emit('MP_PROJECTILE_AFTER',desc(o),desc(o)) end end})
  local npc=P.get_type('Terraria','NPC');local life=P.get_field(npc,'life');local slot=P.get_field(npc,'whoAmI')
  local strikes={}
  install(npc,'StrikeNPC',6,{prefix=function(o,args)
   strikes[#strikes+1]={life=P.get_field_value(life,o,'int32'),slot=P.get_field_value(slot,o,'int32'),damage=args[1],owner=args[6],fromNet=args[5]}
  end,postfix=function(o,_,result)
   local f=table.remove(strikes);if not f then return end
   local after=P.get_field_value(life,o,'int32')
   emit('MP_STRIKE','strike:'..tostring(f.owner)..':'..tostring(f.slot),'npc='..tostring(f.slot)..' owner='..tostring(f.owner)
    ..' fromNet='..tostring(f.fromNet)..' requested='..tostring(f.damage)..' returned='..tostring(result)..' life='..tostring(f.life)..'->'..tostring(after))
  end})
 end)
 if not ok then api.log('MP_PROBE_UNAVAILABLE',tostring(err),true) end
 function self:reset() self.last={};self.counts={} end
 function self:remove() for _,h in ipairs(self.hooks) do pcall(function() h:remove() end) end;self.hooks={};self:reset() end
 return self
end
return M
