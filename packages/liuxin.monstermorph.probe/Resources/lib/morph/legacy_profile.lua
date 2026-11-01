-- Small, versioned profile stored in Loader's per-mod private directory.
local G=require('morph.growth')
local Skills=require('morph.skills')
local Profile={}
Profile.__index=Profile
local function valid_number(v,lo,hi,default)
    v=tonumber(v)
    if not v or v~=v then return default end
    return math.max(lo,math.min(hi,math.floor(v)))
end

function Profile.new(forms,read_file,write_file)
    local self=setmetatable({unlocked={},equipped={},hp={},max={},xp={},base={},growth={},selected=forms[1].key,dirty=false,
        read_file=read_file,write_file=write_file},Profile)
    for i,form in ipairs(forms) do
        -- Start with slime; other forms are earned by capturing them.
        self.unlocked[form.key]=(i==1 or (form.prototype==true and form.enabled~=false))
        self.hp[form.key]=100;self.max[form.key]=100;self.xp[form.key]=0;self.base[form.key]=100;self.growth[form.key]=G.clean({},0)
    end
    self.equipped[1]=forms[1].key
    local raw=read_file and read_file('profile.dat')
    if type(raw)=='string' then self:decode(raw,forms) end
    return self
end

function Profile:decode(raw,forms)
    local selected=raw:match('^MMP1|([%w_]+)\n')
    if not selected and not raw:match('^MMP1\n') then return false end
    if selected then self.selected=selected end
    local bykey={};for _,form in ipairs(forms) do bykey[form.key]=form end
    self.equipped={}
    local equipped={}
    for line in raw:gmatch('[^\n]+') do
        local key,u,h,m,x,e=line:match('^([%w_]+)|([01])|(%d+)|(%d+)|(%d+)|([01])$')
        if key and bykey[key] then
            self.unlocked[key]=(u=='1');self.hp[key]=valid_number(h,0,100000,self.hp[key])
            self.max[key]=valid_number(m,1,100000,self.max[key]);self.xp[key]=valid_number(x,0,100000000,0)
            self.hp[key]=math.min(self.hp[key],self.max[key])
            if e=='1' and not equipped[key] and self.unlocked[key] and bykey[key].enabled~=false and not bykey[key].boss and #self.equipped<3 then self.equipped[#self.equipped+1]=key;equipped[key]=true end
        end
    end
    for _,form in ipairs(forms)do self.base[form.key]=self.max[form.key] end
    for line in raw:gmatch('[^\n]+') do
        local k,base,st,ag,vi,c1,c2,c3,e1,e2=line:match('^RPG2|([%w_]+)|(%d+)|(%d+)|(%d+)|(%d+)|([%w_-]+)|([%w_-]+)|([%w_-]+)|([%w_-]+)|([%w_-]+)$')
        if k and bykey[k] then
            self.base[k]=valid_number(base,1,100000,100)
            local function skill(v)return v~='-' and v or nil end
            self.growth[k]=Skills.sanitize(k,G.clean({str=st,agi=ag,vit=vi,
                choices={skill(c1),skill(c2),skill(c3)},equipped={skill(e1),skill(e2)}},self.xp[k]),self.xp[k])
        end
    end
    -- Don't accept an empty/corrupt unlock set. Keep the safe starter form.
    local any=false;for _,form in ipairs(forms) do if not form.prototype and self.unlocked[form.key] then any=true end end
    if not any then self.unlocked[forms[1].key]=true end
    if #self.equipped==0 then
        for _,form in ipairs(forms) do if form.enabled~=false and not form.boss and self.unlocked[form.key] then self.equipped[1]=form.key;break end end
    end
    self.dirty=false
    return true
end

function Profile:encode(forms)
    local slots={};for _,k in ipairs(self.equipped) do slots[k]=true end
    local out={'MMP1|'..self.selected}
    for _,f in ipairs(forms) do local k=f.key
        out[#out+1]=table.concat({k,self.unlocked[k] and '1' or '0',self.hp[k] or 0,
            self.max[k] or 100,self.xp[k] or 0,slots[k] and '1' or '0'},'|')
        local g=self.growth[k]
        out[#out+1]=table.concat({'RPG2',k,self.base[k] or 100,g.str,g.agi,g.vit,
            g.choices[1] or '-',g.choices[2] or '-',g.choices[3] or '-',g.equipped[1] or '-',g.equipped[2] or '-'},'|')
    end
    return table.concat(out,'\n')..'\n'
end

function Profile:save(forms)
    if not self.write_file then return false end
    local ok,result=pcall(self.write_file,'profile.dat',self:encode(forms))
    if ok and result==true then self.dirty=false;return true end
    return false
end

function Profile:unlock(form)
    if self.unlocked[form.key] then return false end
    self.unlocked[form.key]=true
    if form.enabled~=false and not form.boss and #self.equipped<3 then self.equipped[#self.equipped+1]=form.key end
    self.dirty=true;return true
end

function Profile:is_equipped(key)
    for _,k in ipairs(self.equipped) do if k==key then return true end end
    return false
end

function Profile:set_equipped(key,enabled)
    if not self.unlocked[key] then return false end
    local index
    for i,k in ipairs(self.equipped) do if k==key then index=i;break end end
    if enabled and not index then
        if #self.equipped>=3 then return false end
        self.equipped[#self.equipped+1]=key
    elseif not enabled and index then
        if #self.equipped<=1 then return false end
        table.remove(self.equipped,index)
    end
    self.dirty=true;return true
end

return Profile
