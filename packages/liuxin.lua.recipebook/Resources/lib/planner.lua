-- Pure planning: aggregate shared demand before rounding output batches.
local M={}
function M.plan(root,quantity,recipes,choices)
 local order,mark,edges,cycles={},{},{},{}
 local function visit(id)
  if mark[id]==1 then cycles[id]=true;return end
  if mark[id]==2 then return end
  mark[id]=1
  local rs=recipes[id] or {};local r=rs[choices[id] or 1]
  if r then
   edges[id]=r
   for _,m in ipairs(r.materials)do if not m.group then visit(m.id) end end
  end
  mark[id]=2;order[#order+1]=id
 end
 visit(root)
 local demand,leaves,steps={[root]=quantity},{},{}
 for i=#order,1,-1 do
  local id=order[i];local n=demand[id] or 0;local r=edges[id]
  if n>0 then
   if r and not cycles[id] then
    local batches=math.ceil(n/math.max(1,r.output));steps[#steps+1]={id=id,recipe=r,batches=batches,need=n}
    for _,m in ipairs(r.materials)do
     local key=m.group and ('g'..m.group) or m.id
     if m.group then
      local leaf=leaves[key] or {id=m.id,group=m.group,alternatives=m.alternatives,name=m.name,unresolved=m.unresolved,quantity=0}
      leaf.quantity=leaf.quantity+m.count*batches;leaves[key]=leaf
     else demand[key]=(demand[key] or 0)+m.count*batches end
    end
   else leaves[id]={id=id,quantity=n,cycle=cycles[id]} end
  end
 end
 local flat={};for _,v in pairs(leaves)do flat[#flat+1]=v end
 table.sort(flat,function(a,b)return tostring(a.group or a.id)<tostring(b.group or b.id) end)
 return flat,steps,cycles
end
return M
