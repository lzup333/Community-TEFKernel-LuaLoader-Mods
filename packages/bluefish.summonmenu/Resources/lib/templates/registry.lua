local M={}
local list={
 {id='prison',name='NPC监狱房',layout='草木横屋、石砖悬屋、暗砖竖屋',block=191,wall=4,roof=192,beam=191},
 {id='box',name='普通方块房',layout='平顶木屋、门、背景墙与基本家具',block=30,wall=4,roof=30,beam=30},
}
for _,v in ipairs(list) do v.fixed=true;v.maxFloors=1 end
function M.list() return list end
function M.get(id) for _,v in ipairs(list) do if v.id==id then return v end end end
return M
