-- 带长度、校验与备份的纯数据存档；不load/执行存档文本。
local S={};S.__index=S
local MAX=4194304
local function sum(raw)
 local a,b=1,0;for i=1,#raw do a=(a+raw:byte(i))%65521;b=(b+a)%65521 end
 return('%08x'):format(b*65536+a)
end
local function encode(v,depth,budget)
 budget=budget or {nodes=0};budget.nodes=budget.nodes+1;if budget.nodes>250000 then error('state nodes')end
 depth=depth or 0;if depth>12 then error('state depth')end
 local t=type(v)
 if t=='number'then if v~=v or math.abs(v)>1e15 then error('state number')end;return'n'..('%.17g'):format(v)..';'
 elseif t=='boolean'then return v and 'b1' or'b0'
 elseif t=='string'then if #v>65536 then error('state string')end;return's'..#v..':'..v
 elseif t=='table'then
  local keys={};for k in pairs(v)do if type(k)~='string'and type(k)~='number'then error('state key')end;keys[#keys+1]=k;if #keys>8192 then error('state table')end end
  table.sort(keys,function(a,b)return type(a)==type(b)and a<b or type(a)<type(b)end)
  local out={'t'..#keys..':'};for _,k in ipairs(keys)do out[#out+1]=encode(k,depth+1,budget);out[#out+1]=encode(v[k],depth+1,budget)end
  return table.concat(out)
 end
 error('state type')
end
local function decode(raw)
 if type(raw)~='string'or #raw>MAX then return end
 local pos,nodes=1,0
 local function take(depth)
  nodes=nodes+1;if nodes>250000 or depth>12 then error('state bounds')end
  local tag=raw:sub(pos,pos);pos=pos+1
  if tag=='n' then
   local endAt=assert(raw:find(';',pos,true));local value=tonumber(raw:sub(pos,endAt-1));pos=endAt+1
   assert(value and value==value and math.abs(value)<=1e15);return value
  elseif tag=='b'then local value=raw:sub(pos,pos);pos=pos+1;assert(value=='0'or value=='1');return value=='1'
  elseif tag=='s'or tag=='t'then
   local endAt=assert(raw:find(':',pos,true));local digits=raw:sub(pos,endAt-1);assert(digits:match('^%d+$'))
   local count=tonumber(digits);assert(count and count<=(tag=='s'and 65536 or 8192));pos=endAt+1
   if tag=='s'then assert(pos+count-1<=#raw);local value=raw:sub(pos,pos+count-1);pos=pos+count;return value end
   local value={};for _=1,count do local k=take(depth+1);assert(type(k)=='string'or type(k)=='number');assert(value[k]==nil);value[k]=take(depth+1)end;return value
  end
  error('state tag')
 end
 local ok,value=pcall(take,0);if not ok or pos~=#raw+1 then return end;return value
end
function S.pack(value)
 local ok,body=pcall(encode,value);if not ok or #body>MAX-64 then return end
 return'OR_STATE_220\n'..sum(body)..'\n'..body
end
function S.unpack(raw)
 if type(raw)~='string'or #raw>MAX then return end
 local checksum,body=raw:match('^OR_STATE_220\n([0-9a-f]+)\n(.*)$')
 if not body or #checksum~=8 or sum(body)~=checksum then return end
 local value=decode(body);if type(value)~='table'or value.version~=220 then return end;return value
end
function S.new(host,log)
 local self=setmetatable({host=host,log=log,data={version=220,profiles={},contracts={},mail={},receipts={},serial=0},writable=type(host.write_file)=='function'},S)
 if type(host.read_file)=='function'then
  for _,path in ipairs({'rewrite_state.dat','rewrite_state_backup.dat'})do
   local ok,raw=pcall(host.read_file,path);local data=ok and S.unpack(raw)
   if data and type(data.profiles)=='table'and type(data.contracts)=='table'and type(data.mail)=='table'and type(data.receipts)=='table'and type(data.serial)=='number'then self.data=data;self.lastGood=raw;break end
  end
 end
 return self
end
function S:save()
 if not self.writable then return false end
 local raw=S.pack(self.data);if not raw then self.log('STATE_SAVE_FAILED','bounds/invalid data');return false end
 if raw==self.lastGood then return true end
 if self.lastGood then
  local ok,result=pcall(self.host.write_file,'rewrite_state_backup.dat',self.lastGood)
  if not ok or result~=true then self.log('STATE_BACKUP_FAILED','save withheld');return false end
 end
 local ok,result=pcall(self.host.write_file,'rewrite_state.dat',raw)
 if not ok or result~=true then self.log('STATE_SAVE_FAILED','retain pending data');return false end
 self.lastGood=raw;return true
end
function S.clone(value)return decode(encode(value))end
function S.token()
 local out={};for i=1,16 do out[i]=('%02x'):format(math.random(0,255))end;return table.concat(out)
end
S.encode=encode;S.decode=decode
return S
