-- 只缓存类型/成员句柄，不缓存回调里的借用NPC/Player句柄。
local B={}; B.__index=B
function B.new(p,log)
 local b=setmetatable({p=p,log=log,types={},fields={},hooks={}},B)
 for _,name in ipairs({'Main','NPC','Player','Item','WorldItem','Projectile','Dust'}) do b.types[name]=p.get_type('Terraria',name) end
 return b
end
function B:field(cls,name,kind,required)
 local key=cls..'.'..name; local f=self.fields[key]
 if not f then
  local t=self.types[cls]; local h,prop; local depth=0
  while t and depth<16 do
   h=self.p.get_field(t,name)
   if h then break end
   prop=self.p.get_property(t,name)
   if prop then break end
   t=self.p.get_parent and self.p.get_parent(t) or nil; depth=depth+1
  end
  f={h=h,kind=kind,getter=prop and self.p.property_get_method(prop),setter=prop and self.p.property_set_method(prop)}
  if not h and not f.getter and self.types[cls] then
   -- 部分元数据不提供属性枚举，但仍可访问其 getter。
   local getter=self.p.get_method(self.types[cls],'get_'..name,0)
   if getter then f.getter=getter end
  end
  if h and name:lower()=='gameupdatecount' and self.p.field_size then
   local size=self.p.field_size(h)
   f.kind=size==4 and 'uint32' or size==8 and 'uint64' or kind
  end
  self.fields[key]=f
 end
 if required and not (f.h or f.getter) then error('缺少必要成员 '..key..'（字段/属性/getter均不可用）') end
 if required and not f.reported then
  self.log('MEMBER',key..' backend='..(f.h and 'field' or 'property')..' type='..tostring(f.kind))
  f.reported=true
 end
 return f
end
function B:get(cls,name,obj,kind,default)
 local f=self:field(cls,name,kind)
 if not f.h and not f.getter then return default end
 local v
 if f.h then v=self.p.get_field_value(f.h,obj,f.kind or kind)
 elseif self.p.method_is_static(f.getter) then v=self.p.invoke(f.getter)
 else v=self.p.invoke(f.getter,obj) end
 if v==nil then return default end
 return v
end
function B:set(cls,name,obj,value,kind)
 local f=self:field(cls,name,kind)
 if not f.h and not f.setter then return false end
 local r
 if f.h then r=self.p.set_field_value(f.h,obj,value,f.kind or kind)
 elseif self.p.method_is_static(f.setter) then r=self.p.invoke(f.setter,value)
 else r=self.p.invoke(f.setter,obj,value) end
 return r~=false
end
function B:vec(cls,name,obj)
 local f=self:field(cls,name,'object')
 if not f.h then return nil end
 return self.p.get_field_vec2(f.h,obj)
end
function B:putvec(cls,name,obj,x,y)
 local f=self:field(cls,name,'object')
 -- LuaLoader returns no values on success; actual write failures throw.
 if f.h then return self.p.set_field_vec2(f.h,obj,x,y)~=false end
 return false
end
function B:exact(cls,name,kinds,static)
 local t=self.types[cls]; if not t then return nil end
 local types={}
 for i,k in ipairs(kinds) do
  if k=='string' then types[i]=self.p.get_type('System','String')
  elseif type(k)=='table' then types[i]=self.p.get_type(k[1],k[2])
  else types[i]=self.p.get_basic_type(k) end
  if not types[i] then return nil end
 end
 local h=self.p.get_method_by_param_types(t,name,types)
 if h and self.p.method_is_static(h)==static then return h end
 return nil
end
function B:chatMethod()
 for _,spec in ipairs({
  {5,{'string','uint8','uint8','uint8','bool'}},
  {4,{'string','uint8','uint8','uint8'}},
  {5,{'string','int32','int32','int32','bool'}},
  {4,{'string','int32','int32','int32'}},
 }) do
  local h=self:exact('Main','NewText',spec[2],true)
  if h then return h,spec[1] end
 end
 if self.p.get_method_by_names then
  local h=self.p.get_method_by_names(self.types.Main,'NewText',{'newText','R','G','B','onlyCurrentPlayer'})
  if h and self.p.method_is_static(h) and self.p.method_param_count(h)==5 then return h,5 end
 end
 return nil,nil
end
function B:hook(h,callback,prefix)
 if not h then return false end
 local options={}
 options[prefix and 'prefix' or 'postfix']=function(obj,args,result)
  local ok,err=xpcall(function() callback(obj,args,result) end,debug.traceback)
  if not ok then self.log('HOOK_ERROR',err) end
  return false -- 永不跳过/覆盖原版方法。
 end
 local hook=self.p.install_hook(h,options)
 if not hook then return false end
 self.hooks[#self.hooks+1]=hook; return true
end
function B:remove()
 for i=#self.hooks,1,-1 do pcall(function() self.hooks[i]:remove() end) end
 self.hooks={}
end
return B
