-- 仅在原版NPC.AI调用栈内观察弹幕；不按未知source对象强行读取NPC字段。
local A={};A.__index=A
local function family(style,id)
 if style==0 then return '直射' elseif style==1 then return '抛射'
 elseif style==18 and id==44 then return '镰刀' end
end
function A.new(r,io)
 return setmetatable({r=r,io=io,stack={},samples={},moves={},blocked={},dirty=false},A)
end
function A:enter(n)
 local r=self.r;local slot=r:slot(n)
 local valid=r.world~=nil and r.world==r:w('worldID','int32',nil) and r:n(n,'active') and r:authority() and r:sameSlot(n,slot)
  and not require('bossguard').isBoss(r,n) and not r:n(n,'friendly') and not r:n(n,'townNPC')
 self.stack[#self.stack+1]=valid and {slot=slot,type=r:n(n,'type','int32',0)} or false
end
function A:leave() self.stack[#self.stack]=nil end
function A:observe(args,index)
 local r=self.r;local parent=self.stack[#self.stack]
 if not parent or r.echoGenerating or r.cfg.autoCollect==false or not r:authority() then return end
 -- 已被本模组强化的NPC也不进入学习池，避免学到加工后的攻击。
 local state=r.states[parent.slot];if state and state.tier then return end
 local arr=r:w('projectile','object',nil)
 if not arr or type(index)~='number' or index<0 or index>=r.b.p.array_length(arr) then return end
 local shot=r.b.p.array_at(arr,index,'object');if not shot then return end
 local id=r.b:get('Projectile','type',shot,'int32',0)
 local style=r.b:get('Projectile','aiStyle',shot,'int32',-1);local kind=family(style,id)
 local vx,vy=r.b:vec('Projectile','velocity',shot);if not vx then return end
 local speed=math.sqrt(vx*vx+vy*vy)
 if not kind or id<=0 or id>2000 or speed<2 or speed>14
  or not r.b:get('Projectile','hostile',shot,'bool',false)
  or r.b:get('Projectile','friendly',shot,'bool',true)
  or not r.b:get('Projectile','tileCollide',shot,'bool',false)
  or r.b:get('Projectile','damage',shot,'int32',0)<=0
  or r.b:get('Projectile','width',shot,'int32',999)>32
  or r.b:get('Projectile','height',shot,'int32',999)>32
  or r.b:get('Projectile','extraUpdates',shot,'int32',99)>1 then return end
 local offset=r.projectileModern and 1 or 0
 for i=9+offset,10+offset do if (args[i] or 0)~=0 then return end end
 if r.projectileModern and (args[12] or 0)~=0 then return end
 local key=parent.type..':'..id;if self.blocked[key] then return end
 local entry=self.samples[key]
 if not entry then
  local size=0;for _ in pairs(self.samples) do size=size+1 end;if size>=128 then return end
  entry={n=0,speed=0};self.samples[key]=entry
 end
 entry.n=entry.n+1;entry.speed=entry.speed+speed
 if entry.n~=3 or #self.moves>=64 then return end
 local npcArr=r:w('npc','object',nil);local npc=npcArr and r.b.p.array_at(npcArr,parent.slot,'object')
 if not npc or r:n(npc,'type','int32',0)~=parent.type then return end
 local name='怪物'..parent.type
 if r.nameGetter then local raw=r.b.p.invoke(r.nameGetter,npc);if raw then name=r.b.p.string_value(raw) or name end end
 local move={name=name,donor=parent.type,projectile=id,speed=math.max(3,math.min(10,entry.speed/3)),count=1,spread=0,style=style,kind=kind,learned=true,key=key}
 self.moves[#self.moves+1]=move;self.dirty=true
 r.log('ECHO_LEARN','donor='..parent.type..' name='..name..' projectile='..id..' family='..kind..' samples=3')
end
function A:disable(move)
 self.blocked[move.key]=true
 for i=#self.moves,1,-1 do if self.moves[i].key==move.key then table.remove(self.moves,i) end end
 self.dirty=true;self.r.log('ECHO_QUARANTINE',move.key)
end
local function hex(s) return (s:gsub('.',function(c)return ('%02x'):format(c:byte())end)) end
function A:save()
 if not self.dirty or not self.io or not self.io.write_file then return end
 local rows={'OR_ECHO_201'}
 for _,m in ipairs(self.moves) do rows[#rows+1]=('%d\t%d\t%.3f\t%d\t%s'):format(m.donor,m.projectile,m.speed,m.style,hex(m.name)) end
 local ok,result=pcall(self.io.write_file,'echo_catalog.tsv',table.concat(rows,'\n')..'\n')
 if ok and result~=false and result~=nil then self.dirty=false else self.r.log('ECHO_SAVE_FAILED',tostring(result)) end
end
function A:load()
 if not self.io or not self.io.read_file then return end
 local ok,data=pcall(self.io.read_file,'echo_catalog.tsv')
 if not ok or type(data)~='string' or #data>32768 or data:sub(1,12)~='OR_ECHO_201\n' then return end
 for line in data:gmatch('[^\n]+') do
  local donor,id,speed,style,name=line:match('^(%d+)\t(%d+)\t([%d.]+)\t(%d+)\t([0-9a-f]+)$')
  donor,id,speed,style=tonumber(donor),tonumber(id),tonumber(speed),tonumber(style)
  if donor and donor>0 and donor<1000 and id>0 and id<=2000 and speed and speed>=3 and speed<=10 and family(style,id) and #name<=512 and #name%2==0 and #self.moves<64 then
   local key=donor..':'..id
   if not self.samples[key] then
    name=name:gsub('..',function(h)return string.char(tonumber(h,16))end)
    self.moves[#self.moves+1]={name=name,donor=donor,projectile=id,speed=speed,style=style,kind=family(style,id),count=1,spread=0,learned=true,key=key}
    self.samples[key]={n=3,speed=speed*3}
   end
  end
 end
 self.r.log('ECHO_CATALOG','loaded='..#self.moves)
end
return A
