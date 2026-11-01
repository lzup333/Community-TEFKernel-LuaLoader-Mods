local M={}
local materials={
 {{23,'凝胶',20},{75,'坠落之星',4}},
 {{381,'钴锭',4},{382,'秘银锭',3},{391,'精金锭',3},{520,'光明之魂',4},{521,'暗影之魂',4}},
 {{947,'叶绿矿',12},{1006,'叶绿锭',3}},
 {{1508,'灵气',4},{1552,'蘑菇矿锭',3},{3261,'幽灵锭',3}},
 {{1508,'灵气',6},{1552,'蘑菇矿锭',4},{3261,'幽灵锭',4}},
}
local exploration={{296,'洞穴探险药水',2},{299,'夜猫子药水',3},{291,'鱼鳃药水',2},{288,'黑曜石皮药水',2}}
local combat={{292,'铁皮药水',3},{289,'再生药水',3},{290,'敏捷药水',3},{293,'魔力再生药水',3},{301,'荆棘药水',3}}
local equipment={{{50,'魔镜',1},{53,'瓶中云',1},{54,'赫尔墨斯靴',1},{84,'抓钩',1}},{{492,'恶魔之翼',1},{493,'天使之翼',1}}}
local function pick(random,pool)return pool[math.min(#pool,1+math.floor(random()*#pool))]end
function M.risk(o,mode)
 local weight=o.kind=='extreme'and 10 or o.kind=='nohit'and 5 or o.kind=='tier'and(o.tier==3 and 9 or 3)or o.kind=='styles'and 4 or 1
 local score=o.goal*weight*360/o.seconds+(mode==5 and 0 or(mode-1)*.4)
 local level=o.kind=='tier'and o.tier==3 and 3 or score>=7 and 3 or score>=4 and 2 or 1
 if o.kind=='extreme'then level=3 end
 if o.kind=='tier'or o.kind=='styles'or o.kind=='nohit'then level=math.max(2,level)end
 return level,score
end
function M.pool(stage)
 stage=math.max(1,math.min(5,math.floor(stage or 1)))
 local pool={}
 for _,group in ipairs({exploration,combat,materials[stage],equipment[stage==1 and 1 or 2]})do for _,v in ipairs(group)do pool[#pool+1]=v end end
 pool[#pool+1]=stage==1 and{40,'木箭',100}or{97,'火枪子弹',150}
 pool[#pool+1]=stage==1 and{2336,'金匣',1}or{3981,'钛金匣',1}
 pool[#pool+1]={73,'金币',math.min(12,stage*2+1)}
 return pool
end
function M.generate(random,o,mode,stage,used)
 local level=M.risk(o,mode)
 local available={};for _,v in ipairs(M.pool(stage))do if not used or not used[v[1]]then available[#available+1]=v end end
 if #available<3 then available=M.pool(stage)end
 local rewards={};local count=2+math.min(1,math.floor(random()*2))
 for i=1,count do
  local index=math.min(#available,1+math.floor(random()*#available));local v=table.remove(available,index)
  local max=v[3];local min=max==1 and 1 or math.max(1,math.ceil(max*.5))
  if v[1]~=73 and max>1 then max=math.max(min,math.floor(max*1.5))end
  local stack=min+math.min(max-min,math.floor(random()*(max-min+1)))
  rewards[#rewards+1]={id=v[1],name=v[2],stack=stack};if used then used[v[1]]=true end
 end
 local labels={};for _,entry in ipairs(rewards)do labels[#labels+1]=entry.name..'×'..entry.stack end
 return rewards,table.concat(labels,'、'),level,'random'
end
return M
