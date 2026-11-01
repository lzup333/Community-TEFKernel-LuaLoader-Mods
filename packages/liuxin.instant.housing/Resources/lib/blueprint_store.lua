local B=require('blueprint')
local M={SLOTS=8,MAX_SLOTS=64}
function M.new(mod)
 local saved=mod.read_file('blueprints/slot_count.txt')
 local ids,nextId={},M.SLOTS
 local count=type(saved)=='string' and tonumber(saved:match('^IHSLOTS1,(%d+)$')) or nil
 if type(saved)=='string' and saved:match('^IHSLOTS2,%d+,[%d,]+$') then
  local parts={};for n in saved:sub(#'IHSLOTS2,'+1):gmatch('%d+')do parts[#parts+1]=tonumber(n)end
  local seen={};local valid=#parts>=2 and #parts-1<=M.MAX_SLOTS
  nextId=parts[1]
  for i=2,#parts do
   local id=parts[i];if not id or id<1 or id>nextId or seen[id] then valid=false end
   ids[#ids+1]=id;seen[id]=true
  end
  if not valid or nextId<M.SLOTS or nextId>2147483647 then ids={};nextId=M.SLOTS end
 end
 if #ids==0 then for i=1,(count and count>=M.SLOTS and count<=M.MAX_SLOTS and count or M.SLOTS)do ids[i]=i end;nextId=#ids end
 local s={mod=mod,ids=ids,nextId=nextId}
 local function manifest(list,next)
  return 'IHSLOTS2,'..next..','..table.concat(list,',')
 end
 function s:count()return #self.ids end
 function s:create()
  if #self.ids>=M.MAX_SLOTS then return nil,'复制槽位已达上限（64）' end
  if self.nextId>=2147483647 then return nil,'槽位编号已达上限' end
  local list={table.unpack(self.ids)};list[#list+1]=self.nextId+1
  if not mod.write_file('blueprints/slot_count.txt',manifest(list,self.nextId+1))then return nil,'新建槽位保存失败' end
  self.ids=list;self.nextId=self.nextId+1;return #list
 end
 function s:delete(slot)
  if type(slot)~='number' or slot%1~=0 or slot<1 or slot>#self.ids then return nil,'槽位无效' end
  if #self.ids<=1 then return nil,'至少保留一个槽位' end
  local oldId=self.ids[slot];local list={table.unpack(self.ids)};table.remove(list,slot)
  if not mod.write_file('blueprints/slot_count.txt',manifest(list,self.nextId))then return nil,'删除槽位保存失败' end
  self.ids=list
  -- The loader exposes file writes, but no deletion API. Clear both retired banks;
  -- their IDs are never reused, so an interrupted clear cannot resurrect a blueprint.
  local a=mod.write_file('blueprints/slot'..oldId..'.a','')
  local b=mod.write_file('blueprints/slot'..oldId..'.b','')
  return math.min(slot,#list),not (a and b) and '槽位已移除，旧数据文件清理失败' or nil
 end
 local function path(slot,side)return 'blueprints/slot'..slot..'.'..side end
 local function read(slot,side)
  local raw=mod.read_file(path(slot,side))
  if type(raw)~='string' or #raw<12 or raw:sub(1,4)~='IHS1' then return end
  local generation,hash=string.unpack('<I4I4',raw,5)
  if hash~=B.checksum(raw:sub(5,8)..raw:sub(13)) then return end
  local bp=B.decode(raw:sub(13));if bp then return {generation=generation,bp=bp,side=side} end
 end
 function s:latest(slot)
  if type(slot)~='number' or slot%1~=0 or slot>#self.ids then return end
  local id=self.ids[slot]
  local a,b=read(id,'a'),read(id,'b')
  if not a then return b elseif not b then return a end
  return a.generation>=b.generation and a or b
 end
 function s:load(slot) local v=self:latest(slot);return v and v.bp end
 function s:list()
  local out={};for i=1,#self.ids do local v=self:latest(i);if v then out[#out+1]={slot=i,name=v.bp.name,width=v.bp.width,height=v.bp.height,omitted=v.bp.omitted} end end
  return out
 end
 function s:save(bp,slot)
  local ok,result=pcall(function()
   if not slot then for i=1,#self.ids do if not self:latest(i) then slot=i;break end end end
   assert(slot and slot>=1 and slot<=#self.ids and slot%1==0,'蓝图库已满，请新建复制槽位')
   local last=self:latest(slot);local side=last and (last.side=='a' and 'b' or 'a') or 'a'
   local generation=(last and last.generation or 0)+1;assert(generation<0xffffffff,'存储版本超限')
   local bytes=B.encode(bp);local gen=string.pack('<I4',generation)
   local raw='IHS1'..gen..string.pack('<I4',B.checksum(gen..bytes))..bytes
   local id=self.ids[slot]
   assert(mod.write_file(path(id,side),raw),'蓝图保存失败，旧蓝图已保留')
   local v=read(id,side);assert(v and v.generation==generation,'蓝图写入不完整，旧蓝图已保留')
   return slot
  end)
  if ok then return result end;return nil,tostring(result)
 end
 return s
end
return M
