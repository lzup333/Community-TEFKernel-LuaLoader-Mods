-- Reverse the supplied character-to-pinyin map. The candidate list is for
-- item-name search; it is not a full phrase-based Chinese input method.
local py=require('pinyin')
local groups={}
for cp,key in pairs(py)do
 if type(cp)=='number' and type(key)=='string' then
  local list=groups[key]or{};groups[key]=list;list[#list+1]=utf8.char(cp)
 end
end
local priority={}
local common='铁铜银金石木土剑镐斧锤弓枪箭靴火冰水光暗星云风雷草蜂蜂蜜熔岩黑曜闪耀泰拉配方合成工具材料饰品武器夜地下神圣生命药水箱鱼龙骨羽灵魂怪兽王之盒床门墙砖瓶桶灯书台工作炉砧链蓝绿红黄白紫机械晶体月日天海沙雨雪树藤锭矿块块魔法战士射手召唤伤害防御速度增加使用获得力量能量世界标题八音邪眼晶心花'
local rank=0
for _,cp in utf8.codes(common)do local ch=utf8.char(cp);if not priority[ch]then rank=rank+1;priority[ch]=rank end end
for _,list in pairs(groups)do table.sort(list,function(a,b)local x,y=priority[a]or 100000,priority[b]or 100000;if x==y then return a<b end;return x<y end)end
return {candidates=function(s)return groups[s]or{}end}
