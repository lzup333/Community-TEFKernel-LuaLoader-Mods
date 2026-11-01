-- Verified GUIVirtualInputController.ControlType values from the supplied 1.4.5.8 dump.
local B={};B.__index=B
B.actions={{'transform','变身/解除'},{'cycle','切换伙伴'},{'capture','捕获伙伴'},{'skill','形态技能'},{'learned_1','学习技能一'},{'learned_2','学习技能二'}}
B.keys={{'none','不替换'},
 {'left','左',0,'controlLeft'},{'right','右',1,'controlRight'},{'jump','跳跃',2,'controlJump'},{'up','上',3,'controlUp'},{'down','下',4,'controlDown'},
 {'inventory','背包',5,'controlInv'},{'heal','快速治疗',6,'controlQuickHeal'},{'mana','快速回魔',7,'controlQuickMana'},
 {'mount','坐骑',8,'controlMount'},{'buff','快速增益',9,'controlQuickBuff'},{'grapple','抓钩',10,'controlHook'},
 {'attack','攻击',11,'controlUseItem'},{'usetile','使用物块',12,'controlUseTile'},{'interact','交互',13,'controlUseTile'},
 {'zoomin','放大',14},{'zoomout','缩小',15},{'autofire','自动攻击',16},{'smart','智能光标',17,'controlSmart'},
 {'inventorytoggle','背包切换',18,'controlInv'},{'autoselect','自动选择',19,'controlTorch'},
 {'grappleselect','抓钩选择',20},{'lockon','目标锁定',21},{'profile','操作配置切换',22},{'usebutton','使用按钮',23,'controlUseItem'},
 {'settings','设置',24},{'loadoutone','装备栏一',25},{'loadouttwo','装备栏二',26},{'loadoutthree','装备栏三',27},
 {'loadoutcycle','轮换装备栏',28},{'interactonly','仅交互',29,'controlUseTile'},{'togglefire','攻击/交互切换',30},
 {'dash','冲刺',31},{'armorability','套装能力',32}}
B.modifiers={{'','无（单键）'}}
for i=2,#B.keys do B.modifiers[#B.modifiers+1]=B.keys[i]end
local keys,actions,mods={},{},{}
for _,k in ipairs(B.keys)do keys[k[1]]=k end
for _,a in ipairs(B.actions)do actions[a[1]]=true end
for _,m in ipairs(B.modifiers)do mods[m[1]]=m end
function B.parts(value)
 if keys[value]then return'',value end
 local mod,key=tostring(value):match('^(%a+)_(%a+)$')
 if mod and mods[mod]and keys[key]and key~='none'then return mod,key end
 return'','none'
end
function B.new(bridge,read,write)
 local self=setmetatable({b=bridge,write=write,map={},held={},pending={},key_down={},routes={}},B)
 local raw=read and read('bindings.dat')
 if raw and raw:match('^MMB1\n')then
  local used={};for action,value in raw:gmatch('\n([%w_]+)=([%w_]+)')do
   local m,k=B.parts(value);local v=m~=''and m..'_'..k or k
   if actions[action]and k~='none'and not used[v]then self.map[action]=v;used[v]=true end
  end
 end
 return self
end
function B:get(action)return self.map[action]or'none'end
function B:set(action,modifier,key)
 if not actions[action]or not mods[modifier]or not keys[key]then return false,'无效按键'end
 if modifier==key then return false,'组合需要两个不同按键'end
 local value;if key~='none'then value=modifier~=''and modifier..'_'..key or key end
 for other,v in pairs(self.map)do if value and other~=action and v==value then return false,'该组合已被其他动作使用'end end
 local old=self.map[action];self.map[action]=value
 local lines={'MMB1'};for _,a in ipairs(B.actions)do lines[#lines+1]=a[1]..'='..self:get(a[1])end
 local ok,result=pcall(self.write or function()return false end,'bindings.dat',table.concat(lines,'\n')..'\n')
 if not ok or result~=true then self.map[action]=old;return false,'保存失败，绑定未更改'end
 self:reset();return true,'按键绑定已保存'
end
function B:raw(index,field,player)
 -- Only plain booleans survive a native input callback. No stored native handles.
 local buttons=self.sample or self.buttons
 return buttons and buttons[index]==true or false
end
function B:resolve(key,player)
 -- First key may be any game control. Specific combinations win over single keys.
 for i=2,#B.modifiers do local m=B.modifiers[i]
  if self:raw(m[3],m[4],player)then
   local combo=m[1]..'_'..key
   for action,value in pairs(self.map)do if value==combo then return action,combo end end
  end
 end
 for action,value in pairs(self.map)do if value==key then return action,key end end
end
function B:edge(action,value,down)
 if down and not self.held[value]then self.pending[action]=true end
 self.held[value]=down
end
function B:route(key,player,down)
 if not down then
  local old=self.routes[key];if old then self.held[old[2]]=false end
  self.key_down[key]=nil;self.routes[key]=nil;return nil
 end
 if not self.key_down[key]then
  local action,value=self:resolve(key,player);self.key_down[key]=true
  self.routes[key]=action and{action,value}or false
 end
 local route=self.routes[key]
 if route then self:edge(route[1],route[2],true);return route[1],route[2]end
end
function B:current(key,player)
 if self.key_down[key]then local route=self.routes[key];if route then return route[1],route[2]end;return nil end
 return self:resolve(key,player)
end
function B:capture(instance,player)
 local b=self.b
 if not next(self.map)then self:reset();return end
 if not b:valid(player)then self:reset();return end
 local a=b:get('Controls','Pressed',instance,'object');if not a then return end
 self.sample={};for i=0,math.min(32,b.p.array_length(a)-1)do self.sample[i]=b.p.array_at(a,i,'bool')==true end
 self.sample[11]=self.sample[11]or b:get('Controls','wasFireButtonFiring',instance,'bool')==true or b:get('Controls','UseButtonPressed',instance,'bool')==true
 local previous=b:get('Controls','WasPressed',instance,'object')
 for i=2,#B.keys do local k=B.keys[i]
  local down=self.sample[k[3]]==true
  local action=self:route(k[1],player,down)
  if action and down then
   b.p.array_set(a,k[3],false,'bool');if previous and k[3]<b.p.array_length(previous)then b.p.array_set(previous,k[3],false,'bool')end
   if k[4]then b:set('Player',k[4],player,false,'bool')end
   if k[1]=='attack'or k[1]=='usebutton'then b:set('Controls','wasFireButtonFiring',instance,false,'bool');b:set('Controls','UseButtonPressed',instance,false,'bool');if b.touch then b.touch.use=false end end
   if k[1]=='jump'and b.touch then b.touch.jump=false end
  end
 end
 self.buttons=self.sample;self.sample=nil
end
function B:mask(player)
 if not next(self.map)or not self.b:valid(player)then return end
 for i=2,#B.keys do local k=B.keys[i];if self:current(k[1],player)then
  if k[4]then self.b:set('Player',k[4],player,false,'bool')end
  if self.b.touch then if k[1]=='attack'then self.b.touch.use=false elseif k[1]=='jump'then self.b.touch.jump=false end end
 end end
end
function B:replace(player,key)
 if not self.b:valid(player)then return false end
 local k=keys[key];local physical=self:raw(k[3],k[4],player)
 local action
 if physical then action=self:route(key,player,true)else action=self:current(key,player);if not self.key_down[key]then return false end end
 if not action then return false end
 self.b:set('Player',k[4],player,false,'bool');return true
end
function B:take(action)local hit=self.pending[action];self.pending[action]=nil;return hit or false end
function B:reset()self.pending={};self.held={};self.key_down={};self.routes={};self.sample=nil;self.buttons=nil end
return B
