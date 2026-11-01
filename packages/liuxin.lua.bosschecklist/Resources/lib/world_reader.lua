-- 返回读取结果及来源。反射元数据只在当前调用内使用。
local M={}
function M.read(p,t,name,kind)
 if not t then return nil,'type_missing' end
 local field=p.get_field(t,name)
 if field then
  local ok,v=pcall(p.get_field_value,field,nil,kind)
  if ok and type(v)==(kind=='bool' and 'boolean' or kind=='string' and 'string' or 'number') then return v,'field' end
 end
 local getter
 if p.get_property and p.property_get_method then
  local prop=p.get_property(t,name)
  if prop then getter=p.property_get_method(prop) end
 end
 if not getter and p.get_method then getter=p.get_method(t,'get_'..name,0) end
 if getter and p.invoke then
  if p.method_is_instance and p.method_is_instance(getter) then return nil,'instance_getter' end
  local ok,v=pcall(p.invoke,getter)
  if ok and type(v)==(kind=='bool' and 'boolean' or kind=='string' and 'string' or 'number') then return v,'getter' end
 end
 return nil,field and 'field_read_failed' or getter and 'getter_read_failed' or 'member_missing'
end
return M
