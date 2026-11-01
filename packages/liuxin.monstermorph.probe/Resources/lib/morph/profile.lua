local F=require('morph.forms')
local G=require('morph.growth')
local Skills=require('morph.skills')
local Catalog=require('morph.catalog')
local P={};P.__index=P
local function num(v,lo,hi,default)
    v=tonumber(v);if not v or v~=v then return default or lo end
    return math.max(lo,math.min(hi,math.floor(v)))
end
local function checksum(s)local h=0;for i=1,#s do h=(h*31+s:byte(i))%2147483647 end;return h end
local function escape(s)return tostring(s):gsub('[%%|\r\n]',function(c)return string.format('%%%02X',c:byte())end)end
local function unescape(s)return s:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16))end)end
local function split(s)local t={};for v in (s..'|'):gmatch('(.-)|')do t[#t+1]=v end;return t end
function P.empty(read,write)
    return setmetatable({pets={},equipped={},selected='',next_id=1,sequence=0,dirty=false,read_file=read,write_file=write,
        unlocked={},hp={},max={},base={},xp={},growth={}},P)
end
function P:pet(id)for _,p in ipairs(self.pets)do if p.id==id then return p end end end
function P:rebuild()
    F.populate(self.pets)
    self.unlocked,self.hp,self.max,self.base,self.xp,self.growth={},{},{},{},{},{}
    for _,p in ipairs(self.pets)do
        local k=p.id;self.unlocked[k]=true;self.base[k]=p.life;self.xp[k]=p.xp
        p.growth=Skills.sanitize(k,G.clean(p.growth,p.xp),p.xp)
        self.growth[k]=p.growth;self.max[k]=G.stats(p.growth,p.life,p.damage,p.defense,G.level(p.xp)).max_life
        self.hp[k]=math.min(self.max[k],p.hp)
    end
    local team={};local seen={}
    for _,id in ipairs(self.equipped)do if self:pet(id) and not seen[id] and #team<3 then team[#team+1]=id;seen[id]=true end end
    self.equipped=team
    if not self:is_equipped(self.selected) then self.selected=self.equipped[1] or '' end
end
function P:flush()
    for _,p in ipairs(self.pets)do
        if self.hp[p.id]~=nil then p.hp=self.hp[p.id];p.xp=self.xp[p.id];p.growth=self.growth[p.id] end
    end
end
function P:add(snapshot)
    self:flush()
    if #self.pets>=20 then return nil end
    local p={};for k,v in pairs(snapshot)do p[k]=v end
    p.id='p'..self.next_id;self.next_id=self.next_id+1
    p.life=num(p.life,1,100000,100);p.damage=num(p.damage,1,10000,10);p.defense=num(p.defense,0,10000,0)
    p.hp=p.hp or p.life;p.xp=p.xp or 0;p.growth=p.growth or G.clean({},p.xp)
    p.name=p.name or ('怪物'..p.npc);p.netid=p.netid or p.npc;p.ai=p.ai or 3
    p.width=p.width or 20;p.height=p.height or 32;p.immunities=p.immunities or {};p.parts=p.parts or {}
    self.pets[#self.pets+1]=p;self.dirty=true;self:rebuild();return p
end
function P:is_equipped(id)for _,k in ipairs(self.equipped)do if k==id then return true end end;return false end
function P:set_equipped(id,enabled)
    if not self:pet(id) then return false end
    local index;for i,k in ipairs(self.equipped)do if k==id then index=i end end
    if enabled and not index then if #self.equipped>=3 then return false end;self.equipped[#self.equipped+1]=id
    elseif not enabled and index then table.remove(self.equipped,index) end
    if not self:is_equipped(self.selected) then self.selected=self.equipped[1] or '' end
    self.dirty=true;return true
end
function P:remove(id)
    self:flush()
    for i,p in ipairs(self.pets)do if p.id==id then table.remove(self.pets,i);self:set_equipped(id,false);self:rebuild();self.dirty=true;return true end end
    return false
end
function P:encode()
    local out={'MMP3|'..(self.sequence+1)..'|'..self.next_id..'|'..self.selected..'|'..table.concat(self.equipped,',')}
    for _,p in ipairs(self.pets)do
        local k=p.id;local g=self.growth[k];p.hp=self.hp[k] or p.hp;p.xp=self.xp[k] or p.xp;p.growth=g
        local parts={};for _,part in ipairs(p.parts)do parts[#parts+1]=part end
        out[#out+1]=table.concat({'PET',k,p.npc,p.netid,escape(p.name),p.life,p.damage,p.defense,p.ai,p.width,p.height,
            p.nogravity and 1 or 0,p.phase and 1 or 0,p.lava and 1 or 0,p.hp,p.xp,p.favorite and 1 or 0,
            p.share or 0,p.heal or 0,p.native and 1 or 0,table.concat(p.immunities,','),table.concat(parts,',')},'|')
        out[#out+1]=table.concat({'GROW',k,g.str,g.agi,g.vit,g.int,g.spi,g.luk,
            g.choices[1] or '-',g.choices[2] or '-',g.choices[3] or '-',g.equipped[1] or '-',g.equipped[2] or '-'},'|')
    end
    local body=table.concat(out,'\n')..'\n';return body..'END|'..checksum(body)..'\n'
end
function P:decode(raw)
    local body,check=raw:match('^(.*\n)END|(%d+)\n$')
    if not body or checksum(body)~=tonumber(check) then return false end
    local first=split(body:match('([^\n]+)'));if first[1]~='MMP3' then return false end
    self.sequence=num(first[2],0,100000000,0);self.next_id=num(first[3],1,100000000,1);self.selected=first[4] or ''
    for id in (first[5] or ''):gmatch('p%d+')do self.equipped[#self.equipped+1]=id end
    local seen={};local growth={}
    for line in body:gmatch('[^\n]+')do
        local a=split(line)
        if a[1]=='PET' and a[2]:match('^p%d+$') and not seen[a[2]] and #self.pets<20 and #a>=22 then
            local p={id=a[2],npc=num(a[3],1,10000,1),netid=num(a[4],-10000,10000,1),name=unescape(a[5]),life=num(a[6],1,100000,100),
                damage=num(a[7],1,10000,10),defense=num(a[8],0,10000,0),ai=num(a[9],-1,1000,3),width=num(a[10],1,1000,20),height=num(a[11],1,1000,32),
                nogravity=a[12]=='1',phase=a[13]=='1',lava=a[14]=='1',hp=num(a[15],0,200000,100),xp=num(a[16],0,G.threshold(30),0),
                favorite=a[17]=='1',share=num(a[18],0,9,0),heal=num(a[19],0,9999,0),native=a[20]=='1',immunities={},parts={}}
            for n in a[21]:gmatch('%d+')do if #p.immunities<500 then p.immunities[#p.immunities+1]=num(n,0,1000,0) end end
            for n in a[22]:gmatch('%d+')do if #p.parts<32 then p.parts[#p.parts+1]=num(n,1,10000,1) end end
            self.pets[#self.pets+1]=p;seen[p.id]=p;self.next_id=math.max(self.next_id,num(p.id:sub(2),1,100000000,1)+1)
        elseif a[1]=='GROW' and #a==13 then
            local function id(v)return v~='-' and v or nil end
            growth[a[2]]={str=tonumber(a[3]),agi=tonumber(a[4]),vit=tonumber(a[5]),int=tonumber(a[6]),spi=tonumber(a[7]),luk=tonumber(a[8]),
                choices={id(a[9]),id(a[10]),id(a[11])},equipped={id(a[12]),id(a[13])}}
        end
    end
    for _,p in ipairs(self.pets)do p.growth=growth[p.id] or {} end
    self:rebuild();return true
end
function P.new(_,read,write)
    local a=read and read('profile.dat');local b=read and read('profile.alt.dat');local best
    for _,raw in ipairs({a or '',b or ''})do
        local candidate=P.empty(read,write)
        if candidate:decode(raw) and (not best or candidate.sequence>best.sequence) then best=candidate end
    end
    if best then return best end
    local self=P.empty(read,write)
    if a and not a:match('^MMP1')and read then
        local backup=read('profile.legacy.backup')
        if backup and backup:match('^MMP1')then a=backup end
    end
    if a and a:match('^MMP1') then
        local legacy=require('morph.legacy_profile').new(Catalog,function()return a end)
        local ids={}
        for _,f in ipairs(Catalog)do if not f.boss and legacy.unlocked[f.key] then
            local p=self:add{npc=f.npc,name=f.name,life=legacy.base[f.key] or 100,damage=f.damage,defense=0,ai=(f.key=='slime' or f.movement=='charge') and 1 or (f.flight or f.key=='eye') and 5 or 3,
                nogravity=f.flight or f.key=='eye',hp=legacy.hp[f.key],xp=legacy.xp[f.key],growth={choices=legacy.growth[f.key].choices,equipped=legacy.growth[f.key].equipped}}
            ids[f.key]=p.id
        end end
        for _,key in ipairs(legacy.equipped)do if ids[key] then self.equipped[#self.equipped+1]=ids[key] end end
        self.selected=ids[legacy.selected] or self.equipped[1] or '';self.migrated=a
    elseif not a and not b then
        local p=self:add{npc=1,name='史莱姆',life=25,damage=7,defense=2,ai=1,native=true};self.equipped={p.id};self.selected=p.id
    else self.load_error=true end
    self:rebuild();return self
end
function P:save()
    if not self.write_file or self.load_error then return false end
    if self.migrated then
        local ok,result=pcall(self.write_file,'profile.legacy.backup',self.migrated)
        if not ok or result~=true then return false end;self.migrated=nil
    end
    local raw=self:encode();local name=(self.sequence+1)%2==1 and 'profile.dat' or 'profile.alt.dat'
    local ok,result=pcall(self.write_file,name,raw)
    if ok and result==true then self.sequence=self.sequence+1;self.dirty=false;return true end
    return false
end
return P
