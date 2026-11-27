-- One native subscription per metadata token in this Lua VM.
-- Other mods keep their own VM; this is not a cross-mod singleton.
local M={}
function M.open(native,warn)
 local registry={};local stats={native=0,callbacks=0,errors=0,maxDepth=0}
 local proxy=setmetatable({_compat_stats=stats},{__index=native})
 local function keyFor(m,spec)
  if native.method_token then
   local ok,token=pcall(native.method_token,m)
   if ok and token and token~=0 then
    local name=native.method_name and native.method_name(m)or ''
    return tostring(token)..':'..name..':'..tostring(native.method_param_count(m))
   end
  end
  return spec._wg_key or tostring(m)
 end
 function proxy.install_hook(method,spec)
  local key=keyFor(method,spec);local bus=registry[key]
  if not bus then
   bus={listeners={},frames={},overflow=0,lastError=-1};registry[key]=bus
   local function call(fn,...)
    stats.callbacks=stats.callbacks+1
    local ok,a,b=pcall(fn,...)
    if ok then return a,b end
    stats.errors=stats.errors+1
    local now=os.time()
    if now-bus.lastError>=30 then bus.lastError=now;if warn then warn('[COMPAT][HOOK_ERROR] '..key..' '..tostring(a))end end
   end
   local h=native.install_hook(method,{
    override_result=true,copy=spec.copy,
    prefix=function(instance,args,result)
     if #bus.frames>=64 then bus.overflow=bus.overflow+1;return false end
     local frame={}
     for _,e in ipairs(bus.listeners)do if not e.removed then frame[#frame+1]=e end end
     bus.frames[#bus.frames+1]=frame;stats.maxDepth=math.max(stats.maxDepth,#bus.frames)
     local skipped,value=false,nil
     for _,e in ipairs(frame)do
      if not e.removed and e.spec.prefix then local skip,v=call(e.spec.prefix,instance,args,result);if skip==true then skipped=true;value=v end end
     end
     return skipped,value
    end,
    postfix=function(instance,args,result)
     if bus.overflow>0 then bus.overflow=bus.overflow-1;return result end
     local frame=table.remove(bus.frames)or {}
     -- Apply result overrides first, so diagnostic observers see the actual value.
     for _,e in ipairs(frame)do
      if not e.removed and e.spec.override_result and e.spec.postfix then
       local v=call(e.spec.postfix,instance,args,result);if v~=nil then result=v end
      end
     end
     -- Unwind non-overriding contexts in reverse order.
     for i=#frame,1,-1 do local e=frame[i]
      if not e.removed and not e.spec.override_result and e.spec.postfix then call(e.spec.postfix,instance,args,result)end
     end
     return result
    end})
   if not h then registry[key]=nil;return nil end
   bus.native=h;stats.native=stats.native+1
  end
  local e={spec=spec};bus.listeners[#bus.listeners+1]=e
  local subscription={}
  function subscription:remove()
   if e.removed then return end;e.removed=true
   for i=#bus.listeners,1,-1 do if bus.listeners[i]==e then table.remove(bus.listeners,i)end end
   if #bus.listeners==0 then bus.native:remove();registry[key]=nil;bus.frames={};stats.native=stats.native-1 end
  end
  return subscription
 end
 return proxy
end
return M
