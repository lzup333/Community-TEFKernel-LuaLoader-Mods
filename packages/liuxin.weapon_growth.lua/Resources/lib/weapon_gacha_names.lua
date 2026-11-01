-- Read localized Item.Name only on the established player update thread.
local M={}
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
local function unhex(s)
 if #s%2~=0 or s:find('[^%x]')then return nil end
 return(s:gsub('..',function(c)return string.char(tonumber(c,16))end))
end
function M.open(P,env,itemType)
 local self={values={},dirty=false,reported=false}
 local filename='weapon_gacha_names_v1.txt'
 local data=env.read(filename)
 if type(data)=='string' and #data<=2000000 and data:sub(1,10)=='WGNAMES|1\n' then
  for id,value in data:sub(11):gmatch('(%d+)|(%x+)\n')do
   id=tonumber(id);value=unhex(value)
   if id and id>0 and id<=20000 and value and #value>0 and #value<=512 and utf8.len(value)then self.values[id]=value end
  end
 end
 local ok,getter=pcall(function()
  local prop=type(P.get_property)=='function' and P.get_property(itemType,'Name')
  local m=prop and P.property_get_method(prop)
  if not m then m=P.get_method_by_param_types(itemType,'get_Name',{})end
  if m and P.method_is_instance(m) and P.method_param_count(m)==0 then return m end
 end)
 self.getter=ok and getter or nil
 env.log('GACHA_NAMES_API',self.getter and 'Item.Name本地化名称可用；仅标量字符串返回' or 'Item.Name接口不可用，暂显示物品ID')
 function self:cached(id)return self.values[id]end
 function self:resolve(it,id)
  if self.values[id]then return self.values[id]end
  if not self.getter or not it then return nil end
  local ok,name=pcall(function()
   local value=P.invoke(self.getter,it)
   if type(value)=='string'then return value end
   if value and type(P.string_value)=='function'then return P.string_value(value)end
  end)
  if ok and type(name)=='string' and #name>0 and #name<=512 and utf8.len(name) and not name:find('[\r\n%z]')then
   self.values[id]=name;self.dirty=true;return name
  end
  if not self.reported then self.reported=true;env.log('GACHA_NAME_READ_FAILED','未取得有效名称，保留ID占位')end
 end
 function self:save()
  if not self.dirty then return true end
  local ids={};for id in pairs(self.values)do ids[#ids+1]=id end;table.sort(ids)
  local lines={'WGNAMES|1\n'};for _,id in ipairs(ids)do lines[#lines+1]=id..'|'..hex(self.values[id])..'\n'end
  local encoded=table.concat(lines);local ok=env.write(filename,encoded)
  if ok and env.read(filename)==encoded then self.dirty=false;return true end
  return false
 end
 return self
end
return M
