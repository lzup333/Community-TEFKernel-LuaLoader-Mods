-- Bounded binary records. Cache data is decoded, never executed as Lua.
local C={};local task=nil
local function enc(v,depth)
 depth=depth or 0;assert(depth<12)
 local t=type(v)
 if t=='number'then local n=math.tointeger(v);assert(n,'non-integral cache number: '..tostring(v));return 'i'..string.pack('<i8',n)
 elseif t=='string'then return 's'..string.pack('<I4',#v)..v
 elseif t=='boolean'then return v and 't'or'f'
 elseif t=='table'then
  local a={};local n=0;for k,x in pairs(v)do n=n+1;a[#a+1]=enc(k,depth+1)..enc(x,depth+1)end
  return 'm'..string.pack('<I4',n)..table.concat(a)
 end;error('unsupported cache value')
end
local function decode(s)
 local pos,budget=1,2000
 local function take(n)assert(n>=0 and pos+n-1<=#s,'truncated');local a=s:sub(pos,pos+n-1);pos=pos+n;return a end
 local function dec(depth)
  budget=budget-1;assert(budget>=0 and depth<12,'limits');local tag=take(1)
  if tag=='i'then return string.unpack('<i8',take(8))
  elseif tag=='s'then local n=string.unpack('<I4',take(4));assert(n<65536);return take(n)
  elseif tag=='t'then return true elseif tag=='f'then return false
  elseif tag=='m'then local n=string.unpack('<I4',take(4));assert(n<=256);local a={}
   for _=1,n do local k=dec(depth+1);assert(type(k)=='number'or type(k)=='string');assert(a[k]==nil);a[k]=dec(depth+1)end;return a
  end;error('invalid cache type')
 end
 local v=dec(0);assert(pos==#s+1);return v
end
local function integer(v,lo,hi)return type(v)=='number'and math.tointeger(v)~=nil and v>=lo and v<=hi end
local function validate(e)
 assert(type(e)=='table'and type(e.r)=='table'and type(e.names)=='table')
 local r=e.r;assert(integer(r.id,1,1000000)and integer(r.output,0,2147483647))
 assert(e.category=='材料'or e.category=='武器'or e.category=='饰品')
 assert(type(r.materials)=='table'and #r.materials<=16 and type(r.stations)=='table'and #r.stations<=20 and type(r.conditions)=='table'and #r.conditions<=32)
 for _,m in ipairs(r.materials)do assert(integer(m.id,1,1000000)and integer(m.count,1,1000000));if m.group then assert(integer(m.group,-2147483648,2147483647))end end
 for _,v in ipairs(r.stations)do assert(integer(v,0,1000000))end
 for _,v in ipairs(r.conditions)do assert(type(v)=='string'and #v<1024)end
 for id,name in pairs(e.names)do assert(integer(id,1,1000000)and type(name)=='string'and #name<1024);assert(utf8.len(name))end
 assert(e.names[r.id])
end
local function header(signature,count)return 'RBLC2'..string.pack('<I4',#signature)..signature..string.pack('<I4',count)end
function C.cancel()task=nil;C.loading=false end
function C.load(D,signature)
 local bytes=mod.read_file('recipes-v2.cache');if not bytes or #bytes>16000000 then return false end
 local ok,pos,count=pcall(function()
  assert(bytes:sub(1,5)=='RBLC2');local len,p=string.unpack('<I4',bytes,6);assert(len<65536)
  assert(bytes:sub(p,p+len-1)==signature);p=p+len
  local n;n,p=string.unpack('<I4',bytes,p);assert(n>0 and n<=50000);return p,n
 end)
 if not ok then D.cacheStatus='缓存失效，重新整理';return false end
 C.loading=true;D.cacheStatus='正在载入本地缓存';D.cacheIndex=0
 task=coroutine.create(function()
  local recipes,items,names={},{},{}
  for i=1,count do
   local len;len,pos=string.unpack('<I4',bytes,pos);assert(len>0 and len<65536 and pos+len-1<=#bytes)
   local e=decode(bytes:sub(pos,pos+len-1));pos=pos+len;validate(e)
   local r=e.r;recipes[r.id]=recipes[r.id]or{};recipes[r.id][#recipes[r.id]+1]=r
   items[r.id]={id=r.id,category=e.category};for id,name in pairs(e.names)do names[id]=name end
   D.cacheIndex=i;if i%24==0 then coroutine.yield()end
  end
  assert(pos==#bytes+1 and next(recipes))
  D.recipes=recipes;D.items=items;D.names=names;D.ready=true;D.index=D.total
  D.cacheStatus='本地配方缓存 · 已就绪';D.cacheLoaded=true;C.loading=false
 end)
 return true
end
function C.save(D,signature)
 C.loading=false;D.cacheStatus='正在保存本地配方'
 task=coroutine.create(function()
  local chunks={};local count=0
  for id,rs in pairs(D.recipes)do for _,r in ipairs(rs)do
   local names={[id]=D.name(id)};for _,m in ipairs(r.materials)do names[m.id]=D.name(m.id)end
   local e={r=r,category=D.items[id].category,names=names}
   local valid,why=pcall(validate,e);assert(valid,'recipe '..tostring(id)..': '..tostring(why))
   local s=enc(e);chunks[#chunks+1]=string.pack('<I4',#s)..s;count=count+1
   if count%24==0 then coroutine.yield()end
  end end
  local result=mod.write_file('recipes-v2.cache',header(signature,count)..table.concat(chunks))
  D.cacheStatus=result and'本地配方缓存 · 已保存'or'缓存写入失败 · 本次可浏览'
  mod.write_file('recipebook_cache.log','version=0.1.9\nstage='..(result and'saved'or'write_failed')..'\nrecipes='..count..'\n')
 end)
end
function C.tick(D)
 if not task then return end
 local start=os.clock()
 repeat
  local ok,err=coroutine.resume(task)
  if not ok then
   task=nil
   if C.loading then D.cacheStatus='缓存损坏，重新整理';C.loading=false;D.index=0;D.recipes={};D.items={};D.cacheLoaded=false
   else D.cacheStatus='缓存保存失败 · 本次可浏览'end
   mod.write_file('recipebook_cache.log','version=0.1.9\nstage=failed\nerror='..tostring(err)..'\n')
   if mod.warn then mod.warn('[RecipeBook][CACHE]',tostring(err))end;return
  end
  if coroutine.status(task)=='dead'then task=nil;return end
 until os.clock()-start>.003
end
return C
