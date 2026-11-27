-- Native combat hooks: ItemCheck, Projectile.Damage and scalar NPC.StrikeNPC.
local N=require('wg_native_backend')
local M={experience=N.experience}
function M.install(P,api)
 local self={ready=false}
 function self:reset() N.combat_reset() end
 function self:remove() N.combat_remove();self.ready=false end
 local ok,err=pcall(function()
  local player=P.get_type('Terraria','Player')
  local proj=P.get_type('Terraria','Projectile')
  local npc=P.get_type('Terraria','NPC')
  local f={}
  for _,k in ipairs({'whoAmI','life','lifeMax','boss','friendly','townNPC','immortal','dontTakeDamage','chaseable','SpawnedFromStatue','realLife','type'})do
   f[k]=assert(P.get_field(npc,k),'缺少经验字段 '..k)
  end
  f.playerIndex=assert(P.get_field(player,'whoAmI'))
  f.animation=assert(P.get_field(player,'itemAnimation'))
  f.noMelee=assert(P.get_field(P.get_type('Terraria','Item'),'noMelee'))
  local g=P.get_property(npc,'generation')
  f.generation=assert(g and P.property_get_method(g),'缺少 NPC.generation')
  local held=P.get_property(player,'HeldItem')
  f.heldGetter=held and P.property_get_method(held)
  if f.heldGetter then
   for _,names in ipairs({{'i'},{}})do
    local m=P.get_method_by_names(player,'ItemCheck',names)
    if m and P.method_is_instance(m)and P.method_param_count(m)==#names then f.itemCheck=m;break end
   end
  end
  local function verified(t,name,names)
   local m=P.get_method_by_names(t,name,names)
   assert(m and P.method_is_instance(m)and P.method_param_count(m)==#names,'经验入口不匹配 '..name)
   return m
  end
  f.damage=verified(proj,'Damage',{})
  local int=P.get_basic_type('int32')
  local float=P.get_basic_type('float')
  local bool=P.get_basic_type('bool')
  assert(int and float and bool,'缺少StrikeNPC标量签名类型')
  f.strike=P.get_method_by_param_types(npc,'StrikeNPC',{int,float,int,bool,bool,int})
  assert(f.strike and P.method_is_instance(f.strike)and P.method_param_count(f.strike)==6,'StrikeNPC标量签名不匹配，拒绝安装Native Hook')
  local ids=P.get_type('Terraria.ID','ProjectileID')
  local sets=ids and P.get_inner_type(ids,'Sets')
  if sets and P.get_field(sets,'MinionShot')and P.get_field(sets,'SentryShot')and P.get_field(sets,'IsAWhip')then
   f.bomb=P.get_field(sets,'IsABombWithFuse')
  end
  if not f.bomb then api.log('XP_BOMB_SET_UNAVAILABLE','无法按原版集合排除炸弹射弹经验',true)end
  assert(N.install_combat(f,api),'Native经验核心安装失败')
  self.ready=true
  api.log('MELEE_HOOK_ISOLATED','Native仅使用ItemCheck作用域，不挂接按值Rectangle近战入口',true)
  api.log(f.itemCheck and 'MELEE_XP_READY' or 'MELEE_XP_UNAVAILABLE','Native直接挥砍归因；人物切换和NPC代际校验保留',true)
  api.log('XP_READY','Native经验结算启用；同NPC代际只结算一次，未知来源不猜测',true)
 end)
 if not ok then self:remove();api.log('XP_UNAVAILABLE',tostring(err),true)end
 return self
end
return M
