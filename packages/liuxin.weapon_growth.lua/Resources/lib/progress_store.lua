-- 两个交替检查点：新写入失败时保留上一份完整进度；配置文件独立存放。
-- v3 职业共享经验；v1职业经验保留，v2逐武器按同职业最高值迁移，未识别ID保留。
local M={classes={'melee','ranged','magic','summon'},maxXP=11500,maxLevel=20,maxWeaponsPerProfile=4096}
function M.level(xp)
    local level=0
    while level<M.maxLevel do
        local need=100+50*level
        if xp<need then return level,xp,need end
        xp=xp-need;level=level+1
    end
    return level,0,0
end
local function checksum(text)
    local value=0
    for i=1,#text do value=(value*131+text:byte(i))%2147483647 end
    return value
end
local function hex(text) return (text:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
local function unhex(text)
    if #text==0 or #text%2~=0 or text:find('[^0-9a-f]') then return nil end
    return (text:gsub('..',function(v) return string.char(tonumber(v,16)) end))
end
local function validId(id)
    return type(id)=='number' and id==id and id>=1 and id<=2147483647 and id==math.floor(id)
end
local function encode(rows,generation)
    local keys={};for key in pairs(rows) do keys[#keys+1]=key end;table.sort(keys)
    local lines={}
    for _,key in ipairs(keys) do
        local record=rows[key];local row={hex(key)}
        for _,class in ipairs(M.classes) do row[#row+1]=tostring(record[class] or 0) end
        local mask=0;for index,class in ipairs(M.classes) do if record.migrated and record.migrated[class] then mask=mask+2^(index-1) end end;mask=math.floor(mask)
        row[#row+1]=tostring(mask)
        local ids={};for id in pairs(record.weapons or {}) do ids[#ids+1]=tonumber(id) end;table.sort(ids)
        local weapons={}
        for _,id in ipairs(ids) do weapons[#weapons+1]=tostring(id)..':'..tostring(record.weapons[id] or 0) end
        row[#row+1]=table.concat(weapons,',')
        lines[#lines+1]=table.concat(row,'|')
    end
    local payload=table.concat(lines,'\n');if #payload>0 then payload=payload..'\n' end
    local body=tostring(generation)..'\n'..payload
    return 'WGPROGRESS|3|'..generation..'|'..checksum(body)..'\n'..payload
end
local function decode(text)
    if type(text)~='string' or #text>1048576 then return nil end
    local version,generation,sum,payload=text:match('^WGPROGRESS|([123])|(%d+)|(%d+)\n(.*)$')
    version=tonumber(version);generation=tonumber(generation);sum=tonumber(sum)
    if not version or not generation or generation>1000000000 or sum~=checksum(tostring(generation)..'\n'..payload) then return nil end
    local rows,count={},0
    if #payload>0 and payload:sub(-1)~='\n' then return nil end
    for line in payload:gmatch('([^\n]+)\n') do
        local key,a,b,c,d,mask,weaponText
        if version==1 then key,a,b,c,d=line:match('^([0-9a-f]+)|(%d+)|(%d+)|(%d+)|(%d+)$')
        else
            key,a,b,c,d,mask,weaponText=line:match('^([0-9a-f]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)$')
            if not key then key,a,b,c,d,weaponText=line:match('^([0-9a-f]+)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)$');mask='0' end
        end
        key=key and unhex(key)
        if not key or #key>4096 or rows[key] then return nil end
        local maskValue=tonumber(mask) or 0
        if version>=2 and (maskValue<0 or maskValue>15 or maskValue~=math.floor(maskValue)) then return nil end
        local values={tonumber(a),tonumber(b),tonumber(c),tonumber(d)};local row={weapons={},migrated={}}
        for i,class in ipairs(M.classes) do
            if not values[i] or values[i]>M.maxXP then return nil end
            row[class]=values[i]
            if version>=2 and math.floor((tonumber(mask) or 0)/2^(i-1))%2==1 then row.migrated[class]=true end
        end
        if version>=2 and weaponText~='' then
            local weaponCount=0
            for pair in (weaponText..','):gmatch('(.-),') do
                local id,xp=pair:match('^(%d+):(%d+)$');id=tonumber(id);xp=tonumber(xp)
                if not validId(id) or not xp or xp>M.maxXP or row.weapons[id] then return nil end
                row.weapons[id]=xp;weaponCount=weaponCount+1
                if weaponCount>M.maxWeaponsPerProfile then return nil end
            end
        end
        rows[key]=row;count=count+1;if count>1000 then return nil end
    end
    return {generation=generation,rows=rows,version=version}
end
function M.open(read,write,report)
    local names={'weapon_progress_a.dat','weapon_progress_b.dat'}
    local state={generation=0,rows={},slot=nil,dirty=false,blocked=false}
    local found=false
    for i,name in ipairs(names) do
        local text=read(name)
        if text~=nil then
            found=true;local parsed=decode(text)
            if parsed and (not state.slot or parsed.generation>state.generation) then
                state.rows=parsed.rows;state.generation=parsed.generation;state.slot=i
                if parsed.version<3 then
                    for _,row in pairs(state.rows) do
                        -- v2 已均分的职业总额不是当前有效经验，不能再次累加。
                        for _,class in ipairs(M.classes) do
                            if row.migrated[class] then row[class]=0 end
                        end
                    end
                    state.dirty=true
                end
            elseif not parsed then report('SAVE_INVALID',name) end
        end
    end
    if found and not state.slot then state.blocked=true;report('SAVE_BLOCKED','两份进度均无效，保留原文件，不自动覆盖') end
    local function rowFor(self,key,create)
        local row=self.rows[key]
        if row or not create then return row end
        local count=0;for _ in pairs(self.rows) do count=count+1 end
        if count>=1000 then report('SAVE_FAILED','人物数量超过上限');return nil end
        row={weapons={}};self.rows[key]=row
        return row
    end
    function state:migrateClasses(key,categories)
        if self.blocked or type(categories)~='table' then return false end
        local row=self.rows[key];if not row then return true end
        for id,xp in pairs(row.weapons or {}) do
            local class=categories[id]
            if M.names[class] then
                row[class]=math.max(row[class] or 0,xp)
                row.weapons[id]=nil;self.dirty=true
            end
        end
        return true
    end
    function state:getClass(key,class,id)
        if self.blocked or type(key)~='string' or #key==0 or #key>4096 or not M.names[class] then return nil end
        if validId(id) then self:migrateClasses(key,{[id]=class}) end
        local row=self.rows[key]
        return row and row[class] or 0
    end
    function state:save()
        if self.blocked then return false end
        if not self.dirty then return true end
        local slot=self.slot==1 and 2 or 1
        local text=encode(self.rows,self.generation+1)
        if #text>1048576 then report('SAVE_FAILED','进度超过保存上限');return false end
        local ok,err=write(names[slot],text)
        if not ok or read(names[slot])~=text then report('SAVE_FAILED',tostring(err or '写入回读不一致'));return false end
        self.generation=self.generation+1;self.slot=slot;self.dirty=false
        return true
    end
    function state:awardClass(key,class,amount)
        local old=self:getClass(key,class)
        if old==nil or type(amount)~='number' or amount~=amount or amount<=0 then return nil end
        local total=math.min(M.maxXP,old+math.floor(amount))
        local row=rowFor(self,key,true);if not row then return nil end
        if total~=old then row[class]=total;self.dirty=true end
        return {total=total,added=total-old},false -- deferred to independent maintenance autosave
    end
    return state
end
M.names={melee=true,ranged=true,magic=true,summon=true}
return M
