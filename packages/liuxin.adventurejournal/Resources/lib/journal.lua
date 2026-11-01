-- Pure Lua state: no game objects, no engine calls.
local N=require('narrator')
local J={}
local keys={'kills','blocks','coins','ores','potions','deaths','gear'}
local function record() local r={events={},seen={},facts={}};for _,k in ipairs(keys) do r[k]=0 end;return r end
function J.new()
 local daily=record();daily.narrationSeed=1
 return {schema=1,day=1,daily=daily,days={},trips={},seenBoss={},trip=nil,narrationSerial=1}
end
function J.attach(s)
 assert(s.schema==1 and type(s.daily)=='table','存档格式不匹配')
 for _,r in ipairs(s.days or {}) do r.gear=r.gear or 0 end
 for _,r in ipairs(s.trips or {}) do r.gear=r.gear or 0 end
 s.daily.gear=s.daily.gear or 0;if s.trip then s.trip.gear=s.trip.gear or 0 end
 s.seenGear=s.seenGear or {};return setmetatable({s=s,homeTicks=0,outTicks=0}, {__index=J})
end
function J:add(k,n)
 assert(self.s.daily[k]~=nil and n>=0); self.s.daily[k]=self.s.daily[k]+n
 if self.s.trip then self.s.trip[k]=self.s.trip[k]+n end
end
function J:event(key,text,detail)
 local changed=false
 for _,r in ipairs({self.s.daily,self.s.trip}) do
  if not r.seen[key] then
   changed=true
   r.seen[key]=true;r.events[#r.events+1]=text
   if detail then r.facts=r.facts or {};r.facts[#r.facts+1]={kind=detail.kind,name=detail.name} end
  end
 end
 return changed
end
function J:visit(name)
 return self:event('zone:'..name,'探索区域：'..name,{kind='zone',name=name})
end
function J:start()
 self.s.narrationSerial=(self.s.narrationSerial or (#self.s.days+#self.s.trips+1))+1
 self.s.trip=record();self.s.trip.narrationSeed=self.s.narrationSerial
 self.s.trip.startDay=self.s.day;self.homeTicks=0;self.outTicks=0
end
function J:finish(reason)
 local r=self.s.trip;if not r then return end
 r.endDay=self.s.day;r.reason=reason;self.s.trips[#self.s.trips+1]=r
 if #self.s.trips>200 then table.remove(self.s.trips,1) end
 self.s.trip=nil;self.homeTicks=0;return r
end
function J:position(distance,dead,options)
 local c=options or {home_distance=45,depart_distance=100,home_seconds=5,depart_seconds=2}
 if dead then self.homeTicks=0;self.outTicks=0;return end
 if self.s.trip then
  if distance<=c.home_distance then self.homeTicks=self.homeTicks+1 else self.homeTicks=0 end
  if self.homeTicks>=c.home_seconds*2 then return 'end',self:finish(self.s.trip.deaths>0 and '返回家中（途中曾死亡）' or '平安归家') end
 else
  if distance>=c.depart_distance then self.outTicks=self.outTicks+1 else self.outTicks=0 end
  if self.outTicks>=c.depart_seconds*2 then self:start();return 'start' end
 end
end
function J:clock(daytime)
 if self.s.lastDaytime==false and daytime==true then
  local r=self.s.daily;r.day=self.s.day;self.s.days[#self.s.days+1]=r
  if #self.s.days>180 then table.remove(self.s.days,1) end
  self.s.narrationSerial=(self.s.narrationSerial or (#self.s.days+#self.s.trips+1))+1
  self.s.day=self.s.day+1;self.s.daily=record();self.s.daily.narrationSeed=self.s.narrationSerial
  self.s.lastDaytime=daytime;return r
 end
 self.s.lastDaytime=daytime
end
function J.money(n)
 local p=math.floor(n/1000000);local g=math.floor(n/10000)%100;local s=math.floor(n/100)%100;local c=n%100
 local t={};if p>0 then t[#t+1]=p..'铂' end;if g>0 then t[#t+1]=g..'金' end;if s>0 then t[#t+1]=s..'银' end
 if c>0 or #t==0 then t[#t+1]=c..'铜' end;return table.concat(t)
end
function J.summary(r)
 return string.format('击杀 %d · 挖掘 %d · 拾取钱币 %s\n矿石 %d · 药水 %d · 死亡 %d',r.kills,r.blocks,J.money(r.coins),r.ores,r.potions,r.deaths)
end
function J.title(r)
 local keys=r.seen or {};local f=N.analyze(r)
 for _,k in ipairs({'boss:398','boss:113','boss:35'}) do if keys[k] then return ({['boss:398']='月下决战',['boss:113']='地狱决战',['boss:35']='地牢之门'})[k] end end
 if f.main=='boss' then return '挑战强敌' end
 if f.main=='gear' then return '珍宝入袋' end
 if f.main=='explore' and keys['zone:地牢'] then return '地牢探险' end
 if f.main=='mining' then
  if (r.blocks or 0)==0 then return '原矿入袋' end
  return ((r.ores or 0)>=20 or (r.blocks or 0)>=100) and '采掘收获' or '采掘小记'
 end
 return ({explore='探索足迹',combat='沿途激战',coins='沿途收获',supplies='补给小记',setback='险途记录',idle='悠闲时光'})[f.main] or '平凡的收获'
end
function J.intro(r,tone,style) return N.compose(r,tone,style,J.money) end
local function listNames(names,limit,unit)
 local t={};limit=limit or #names
 for i=1,math.min(#names,limit) do t[#t+1]=names[i] end
 return table.concat(t,'、')..(#names>limit and ('（共'..#names..(unit or '项')..'）') or '')
end
function J.report(r,style,eventLimit,tone)
 style=tonumber(style) or 2
 local f=N.analyze(r);local lines={}
 local function line(s) lines[#lines+1]=s end
 if style==1 then
  if #f.bosses>0 then line('战果：击败 '..listNames(f.bosses,1)) end
  if #f.gear>0 then line('新装备：'..listNames(f.gear,1)) end
  if #f.zones>0 then line('到访：'..listNames(f.zones,2,'处')) end
  line('钱币 '..J.money(r.coins)..' · 击杀 '..r.kills..' · 死亡 '..r.deaths)
  line('');line('小结：'..J.intro(r,tone,1))
 elseif style==2 then
  if #f.bosses>0 then line('战果：击败 '..listNames(f.bosses,2)) end
  line('收获：钱币 '..J.money(r.coins))
  if #f.gear>0 then line('新装备：'..listNames(f.gear,2)) end
  if r.blocks>0 or r.ores>0 then line('采掘：挖掘 '..r.blocks..' · 原矿 '..r.ores) end
  line('战斗：击杀 '..r.kills..' · 药水 '..r.potions..' · 死亡 '..r.deaths)
  if #f.zones>0 then line('到访：'..listNames(f.zones,3,'处')) end
  line('');line('【旅途小记】');line(J.intro(r,tone,2))
 else
  line('【重要经历】')
  local important={}
  for _,e in ipairs(r.events or {}) do if not e:match('^探索区域：') then important[#important+1]=e end end
  local limit=eventLimit or 12
  if #important==0 then line('没有记录到重要事件。') end
  for i=1,math.min(#important,limit) do line(important[i]) end
  if #important>limit then line('另有 '..(#important-limit)..' 条经历，可在旅行日志查看。') end
  line('');line('【冒险统计】')
  line('击杀敌怪：'..r.kills);line('挖掘方块：'..r.blocks)
  line('拾取钱币：'..J.money(r.coins));line('获得原矿：'..r.ores)
  line('使用药水：'..r.potions);line('死亡次数：'..r.deaths)
  line('新稀有装备：'..(r.gear or 0)..'件')
  line('');line('【到访地点】')
  if #f.zones==0 then line('没有记录到到访地点。') else
   local count=math.min(#f.zones,eventLimit or 12)
   for i=1,count do line(f.zones[i]) end
   if #f.zones>count then line('另有 '..(#f.zones-count)..' 处，可在旅行日志查看。') end
  end
  line('');line('【旅途小记】');line(J.intro(r,tone,3))
 end
 return table.concat(lines,'\n')
end
function J.display(r,label,style,eventLimit,tone)
 local header='【冒险手记 · '..J.title(r)..'】'
 local status=label or (r.day and ('记录第'..r.day..'天') or '本次冒险')
 if r.endDay and not status:find(r.reason or '平安归家',1,true) then status=status..' · '..(r.reason or '已归家') end
 return header..'\n'..status..'\n\n'..J.report(r,style,eventLimit,tone)
end
function J.text(s,tone)
 local out={'冒险手记（从安装后开始计日；按世界/角色分别保存）',''}
 local function show(title,r)
  out[#out+1]=J.display(r,title,3,math.max(#(r.events or {}),#N.analyze(r).zones),tone)
  out[#out+1]=''
 end
 for _,r in ipairs(s.days) do show('记录第'..r.day..'天',r) end
 show('记录第'..s.day..'天（进行中）',s.daily)
 for i,r in ipairs(s.trips) do show('冒险 '..i..' · 第'..r.startDay..'—'..r.endDay..'天 · '..r.reason,r) end
 if s.trip then show('本次冒险（进行中）',s.trip) end
 return table.concat(out,'\n')
end
function J.encode(v)
 local t=type(v)
 if t=='number' or t=='boolean' then return tostring(v) elseif t=='string' then return string.format('%q',v)
 elseif t=='table' then local a={'{'};for k,x in pairs(v) do a[#a+1]='['..J.encode(k)..']='..J.encode(x)..',' end;a[#a+1]='}';return table.concat(a) end
 error('不能保存 '..t)
end
function J.decode(raw)
 if not raw or #raw>4000000 then return nil end
 local f=load('return '..raw,'journal','t',{});if not f then return nil end
 local ok,s=pcall(f);if ok and type(s)=='table' and s.schema==1 then return s end
end
return J
