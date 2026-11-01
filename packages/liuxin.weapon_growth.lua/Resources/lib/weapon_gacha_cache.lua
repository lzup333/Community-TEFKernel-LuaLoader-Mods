-- Durable metadata only. Never persist managed/native pointers.
local M={}
local classes={'melee','ranged','magic','summon'}
local valid={melee=true,ranged=true,magic=true,summon=true}
local function sum(s)local n=0;for i=1,#s do n=(n*131+s:byte(i))%2147483647 end;return n end
local filename='weapon_gacha_pool_1458_v1.txt'
function M.load(read,count)
 local data=read(filename)
 if type(data)~='string' or #data>2000000 then return nil end
 local c,check,body=data:match('^WGPOOL|1|1458|(%d+)|(%d+)\n(.*)$')
 if tonumber(c)~=count or tonumber(check)~=sum(body or '')then return nil end
 local catalog,locations,n={complete=true},{},0
 for line in body:gmatch('([^\n]+)\n')do
  local id,r,slot,category,mask=line:match('^(%d+)|(%d+)|(-?%d+)|([a-z]+)|(%d+)$')
  id,r,slot,mask=tonumber(id),tonumber(r),tonumber(slot),tonumber(mask)
  if not id or id<1 or id>20000 or locations[id] or not r or r>=count or not slot or slot< -1 or slot>99 or not valid[category] or not mask or mask<1 or mask>15 then return nil end
  local categories={};for i,cname in ipairs(classes)do if mask & (1<<(i-1))~=0 then categories[cname]=true end end
  if not categories[category]then return nil end
  catalog[id]={category=category,categories=categories,name=({melee='近战',ranged='远程',magic='魔法',summon='召唤'})[category]..'武器#'..id}
  locations[id]={recipe=r,slot=slot};n=n+1
 end
 if n==0 or body:sub(-1)~='\n' then return nil end
 return catalog,locations,n
end
function M.save(write,read,count,catalog,locations)
 local ids={};for id in pairs(locations)do ids[#ids+1]=id end;table.sort(ids)
 local lines={}
 for _,id in ipairs(ids)do
  local e,loc=catalog[id],locations[id];local mask=0
  for i,c in ipairs(classes)do if e.category==c or e.categories and e.categories[c]then mask=mask | (1<<(i-1))end end
  lines[#lines+1]=id..'|'..loc.recipe..'|'..loc.slot..'|'..e.category..'|'..mask..'\n'
 end
 local body=table.concat(lines);local data='WGPOOL|1|1458|'..count..'|'..sum(body)..'\n'..body
 local ok=write(filename,data);return ok and read(filename)==data
end
return M
