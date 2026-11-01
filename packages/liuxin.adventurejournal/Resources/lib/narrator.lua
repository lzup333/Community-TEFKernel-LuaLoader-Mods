-- Offline analysis and composition. Only recorded facts support conclusions.
local N={}
N.tones={'平实记录','温暖鼓励','轻松吐槽','史诗叙事','简短冷静'}
local function unique(list,value)
 if type(value)~='string' or value=='' then return end
 for _,v in ipairs(list) do if v==value then return end end;list[#list+1]=value
end
function N.analyze(r)
 local f={bosses={},gear={},zones={},afterDeathGear={},afterDeathBoss={},beforeDeathZones={}}
 local death=false
 for _,e in ipairs(r.facts or {}) do
  if e.kind=='death' then death=true
  elseif e.kind=='boss' then unique(f.bosses,e.name);if death then unique(f.afterDeathBoss,e.name) end
  elseif e.kind=='gear' then unique(f.gear,e.name);if death then unique(f.afterDeathGear,e.name) end
  elseif e.kind=='zone' then unique(f.zones,e.name);if not death then unique(f.beforeDeathZones,e.name) end end
 end
 -- Legacy text supports facts, but never a claim about event order.
 for _,e in ipairs(r.events or {}) do
  unique(f.bosses,e:match('^击败 (.-)。$'))
  unique(f.gear,e:match('^首次获得.-：(.-)。$'))
  unique(f.zones,e:match('^探索区域：(.-)$'))
 end
 local scores={
  {key='boss',score=#f.bosses>0 and 100+math.min(30,#f.bosses*5) or 0},
  {key='gear',score=#f.gear>0 and 65+math.min(20,#f.gear*5) or 0},
  {key='mining',score=(r.ores or 0)>0 and 30+math.min(30,(r.ores or 0)/2) or ((r.blocks or 0)>0 and 18+math.min(30,(r.blocks or 0)/10) or 0)},
  {key='explore',score=#f.zones>0 and 20+math.min(30,#f.zones*6) or 0},
  {key='combat',score=(r.kills or 0)>0 and 15+math.min(40,(r.kills or 0)*0.8) or 0},
  {key='coins',score=(r.coins or 0)>0 and 10+math.min(25,(r.coins or 0)/10000) or 0},
  {key='supplies',score=(r.potions or 0)>0 and 8 or 0},
 }
 for i,s in ipairs(scores) do s.rank=i end
 table.sort(scores,function(a,b) return a.score==b.score and a.rank<b.rank or a.score>b.score end)
 f.main=scores[1].score>0 and scores[1].key or ((r.deaths or 0)>0 and 'setback' or 'idle')
 for i=2,#scores do
  local s=scores[i]
  -- Boss victories already represent combat; don't narrate it twice.
  if s.score>=15 and not (f.main=='boss' and s.key=='combat') then f.secondary=s.key;break end
 end
 f.deaths=r.deaths or 0;f.finished=r.endDay~=nil;f.daily=r.day~=nil
 return f
end
local function choose(r,salt,count)
 local n=math.floor((r.kills or 0)*3+(r.blocks or 0)+(r.ores or 0)*7+(r.deaths or 0)*11+(r.coins or 0)+(r.startDay or r.day or 0)*13+(r.narrationSeed or 0)*19)&0xffffffff
 for _,e in ipairs(r.events or {}) do for i=1,#e do n=((n~e:byte(i))*16777619)&0xffffffff end end
 -- Mix each grammatical slot independently; simple modulo made all slots
 -- choose the same variant together, leaving only two complete wordings.
 n=((n~salt)*16777619)&0xffffffff
 n=((n~(n>>16))*2246822507)&0xffffffff;n=n~(n>>13)
 return n%count+1
end
-- Plan once, then let each voice choose its own syntax and point of view.
-- Names are anchors, not a second recitation of every statistic.
local function nameList(a,limit)
 local t={};for i=1,math.min(#a,limit or 1) do t[#t+1]=a[i] end
 return table.concat(t,'、')
end
local function pick(r,salt,a) return a[choose(r,salt,#a)] end
local function zoneName(f,limit)
 -- Prefer distinctive places over generic height bands in a short narrative.
 local selected={};local generic={['森林']=true,['地表']=true,['地下']=true,['洞穴']=true}
 for _,v in ipairs(f.zones) do if not generic[v] then selected[#selected+1]=v end end
 if #selected==0 then selected=f.zones end
 return nameList(selected,limit)
end
local function plan(r,style)
 local f=N.analyze(r)
 local p={facts=f,main=f.main,details={},deathMentioned=false,used={},nameLimit=style==3 and 2 or 1}
 p.used[p.main]=true
 if p.main=='boss' and #f.afterDeathBoss>0 then p.turn='boss';p.subject=nameList(f.afterDeathBoss,style==3 and 2 or 1)
 elseif p.main=='gear' and #f.afterDeathGear>0 then p.turn='gear';p.subject=nameList(f.afterDeathGear,style==3 and 2 or 1)
 elseif p.main=='boss' then p.subject=nameList(f.bosses,style==3 and 2 or 1)
 elseif p.main=='gear' then p.subject=nameList(f.gear,style==3 and 2 or 1)
 elseif p.main=='explore' then p.subject=zoneName(f,style==3 and 2 or 1) end
 if p.turn then
  p.deathMentioned=true
  if style~=1 and #f.beforeDeathZones>0 then
   p.scene=nameList(f.beforeDeathZones,p.nameLimit);p.used.explore=true
  end
 end
 if style~=1 then
  local function add(k)
   if k and not p.used[k] then p.details[#p.details+1]=k;p.used[k]=true end
  end
  -- Concrete gear and places make a better story than another numeric tally.
  if #f.gear>0 then add('gear') end
  if #f.zones>0 then add('explore') end
  add(f.secondary)
  if style==3 then
   if (r.ores or 0)>0 or (r.blocks or 0)>0 then add('mining') end
   if (r.coins or 0)>0 then add('coins') end
   if (r.potions or 0)>0 then add('supplies') end
  end
  if style==2 then while #p.details>1 do table.remove(p.details) end
  else while #p.details>2 do table.remove(p.details) end end
 end
 return p
end
local function lead(r,p,tone,style)
 local f=p.facts;local k=p.main;local n=p.subject
 local scope=f.daily and '今天' or '这趟'
 if style==1 and (k=='boss' or k=='gear' or k=='explore') then
  if p.turn=='boss' then return ({'倒下之后，还是击败了'..n..'。','你倒下过，后来仍赢下了'..n..'。','复活过，也赢了'..n..'，这趟有挫折也有战绩。','倒下未能终结征途，'..n..'已败落。','死亡后击败'..n..'。'})[tone] end
  if p.turn=='gear' then return ({'倒下之后，又拿到了'..n..'。','你倒下过，后来又拿到了'..n..'。','复活点去过了，'..n..'也拿到了。','倒下的印记之后，仍有'..n..'的新收获。','死亡后获得'..n..'。'})[tone] end
  if k=='boss' then return ({scope..'击败了'..n..'。','你赢下了'..n..'，值得开心一下。',n..'输给你了，这趟有战绩了。',n..'败落，胜利属于冒险者。','击败'..n..'。'})[tone] end
  if k=='gear' then return ({scope..'拿到了'..n..'。',n..'拿到手了，替你高兴。',n..'拿到了，'..scope..'有点东西。',n..'成为征途的新收获。','获得'..n..'。'})[tone] end
  return ({scope..'去过了'..n..'。','你把足迹留在了'..n..'。',n..'去过了，'..scope..'也算认了个地名。','冒险者的足迹留在'..n..'。','到访'..n..'。'})[tone]
 end
 if p.turn then
  if k=='boss' then return ({
   '倒下之后，还是击败了'..n..'。',
   '你倒下过，但后来还是击败了'..n..'，这一刻值得为自己高兴一下。',
   '复活点接待过你，'..n..'后来也没能赢过你——这趟算是把场子找回来了。',
   '倒下未能终结征途，'..n..'随后败落，冒险者为这一章写下了胜利。',
   '死亡后击败'..n..'。',
  })[tone] end
  return ({
   '倒下之后，又拿到了'..n..'。',
   '你倒下过，后来又拿到了'..n..'，这段旅程也有值得开心的地方。',
   '复活点去过了，'..n..'后来也拿到了，这趟有挫折也有好东西。',
   '倒下的印记之后，'..n..'成为征途中新的收获。',
   '死亡后获得'..n..'。',
  })[tone]
 end
 if k=='boss' then
  local a={
   {scope..'击败了'..n..'。','把'..n..'记进战绩，'..scope..'便有了一件值得回想的事。'},
   {'你击败了'..n..'，把这次胜利好好收在心里吧。',n..'被你击败了，这一刻可以为自己高兴一下。'},
   {n..'没能赢过你，战绩栏可以添一笔了。',scope..'给'..n..'交了份败北通知，结果已经写进战绩。'},
   {n..'败落，胜利写进了冒险者的征途。','冒险者击败了'..n..'，这一章已有值得铭记的战果。'},
   {'击败'..n..'。',n..'已被击败。'},
  };return pick(r,31,a[tone])
 elseif k=='gear' then
  local a={
   {scope..'拿到了'..n..'，这份收获值得单独记一笔。',n..'是'..scope..'值得记住的新收获。'},
   {'你拿到了'..n..'，'..scope..'有了一件值得开心的事。',scope..'遇见的好消息，是拿到了'..n..'。'},
   {n..'拿到手了，'..scope..'的收获栏有牌面了。',scope..'拿到了'..n..'——好东西的名字，当然要单独写一行。'},
   {n..'成为冒险者的新收获，为这一章添上了珍宝的印记。','冒险者获得了'..n..'，征途留下了新的收获。'},
   {'新获得'..n..'。','获得新装备：'..n..'。'},
  };return pick(r,37,a[tone])
 elseif k=='explore' then
  local a={
   {scope..'去过了'..n..'，这份足迹也值得留住。',n..'也有了'..scope..'的足迹。'},
   {'你去过了'..n..'，这份经历已经属于你了。',scope..'的足迹留在了'..n..'，平常的探索也值得记住。'},
   {scope..'去过'..n..'，这地方算是打过照面了。',n..'去过了，'..scope..'也算认了个地名。'},
   {'冒险者的足迹留在'..n..'，征途由此添上一页。',n..'留下了冒险者的足迹，这片地域已进入征途的篇章。'},
   {'到访'..n..'。','足迹：'..n..'。'},
  };return pick(r,41,a[tone])
 elseif k=='mining' then
  local mined=(r.blocks or 0)>0;local ore=(r.ores or 0)>0
  if not mined then return ({
   scope..'收集到了原矿，收获里多了这一项。',
   '你收集到了原矿，这份小收获也值得开心。',
   scope..'收集了原矿，收获清单终于有点矿物含量了。',
   '原矿成为冒险者的收获，为征途添上了资源的一笔。',
   '收集到原矿。',
  })[tone] end
  return ({
   ore and (scope..'挖了些方块，也收集到了原矿。') or (scope..'挖了些方块，采掘的经历也留在了手记里。'),
   ore and '你既挖了方块，也收集到了原矿，实实在在的收获值得给自己一点肯定。' or '你挖过的方块，也算这一段旅程的成果。',
   ore and (scope..'既挖了方块，也收集了原矿——这页手记有点矿工味了。') or (scope..'的采掘没少记，镐子也有它的存在感。'),
   ore and '采掘与原矿收获，写下了冒险者征途的另一面。' or '方块的挖掘，成为冒险者此行留下的一笔。',
   ore and '挖掘方块，收集到原矿。' or '完成方块挖掘。',
  })[tone]
 elseif k=='combat' then
  local many=(r.kills or 0)>=20
  return ({
   scope..(many and '击败了不少敌怪。' or '也有击败敌怪的经历。'),
   many and '你击败了不少敌怪，这些战斗也值得记住。' or '你击败过敌怪，小小的战果也算数。',
   many and (scope..'击败的敌怪不少，战绩栏挺忙。') or (scope..'有敌怪被你击败，战绩栏没有空着。'),
   many and '众多敌怪败于冒险者之手，征途已有交战的印记。' or '敌怪被冒险者击败，战果写进了征途。',
   many and '击败多名敌怪。' or '击败敌怪。',
  })[tone]
 elseif k=='coins' then return ({
  scope..'拾取了钱币，也是这一页的小收获。',
  '你拾取了钱币，小收获也值得开心一下。',
  scope..'拾取了钱币，至少收获栏不是空白的。',
  '拾取的钱币，成为冒险者此行收获的一笔。',
  '拾取了钱币。',
 })[tone]
 elseif k=='supplies' then return ({
  scope..'用过药水，这一页主要留下了补给消耗。',
  '你用过的药水也记下了，这段经历不只看收获。',
  scope..'主要给药水记了账，补给栏先交作业了。',
  '药水的消耗，也成为征途上的一笔。',
  '使用过药水。',
 })[tone]
 elseif k=='setback' then
  p.deathMentioned=true
  return ({
   f.deaths>=3 and (scope..'多次倒下，这段经历并不顺利。') or (scope..'曾倒下，这一页也留下了受挫的经历。'),
   '你倒下过，别急着把这一页看作失败，受挫也可以被好好记住。',
   f.deaths>=3 and (scope..'多次倒下，复活点的接待工作挺忙。') or (scope..'也去复活点报了到，这页先算受挫篇。'),
   '冒险者曾倒下，征途留下了受挫的印记。',
   '经历死亡。',
  })[tone]
 end
 return ({
  scope..'没有什么大事可记，先留一页平常的经历。',
  '没什么特别的收获也没关系，平常的日子也可以好好过。',
  scope..'没什么大事，手记难得不用加班。',
  '这一页暂未写下显著战果，征途也有平静的留白。',
  '暂无显著活动或收获。',
 })[tone]
end
local function detail(r,p,k,tone)
 local f=p.facts;local n
 if k=='gear' then
  if #f.afterDeathGear>0 and not p.deathMentioned then
   n=nameList(f.afterDeathGear,p.nameLimit);p.deathMentioned=true
   return ({'倒下之后，还拿到了'..n..'。','倒下之后，你又拿到了'..n..'，这份收获也值得开心。','虽然去过复活点，后来也拿到了'..n..'，不全是坏消息。','倒下的印记之后，'..n..'仍成为新的收获。','死亡后获得'..n..'。'})[tone]
  end
  n=nameList(f.gear,p.nameLimit)
  return ({'途中还拿到了'..n..'。','你还拿到了'..n..'，又多了一件开心的事。',n..'也拿到了，收获清单还挺会加戏。',n..'也成为冒险者此行的收获。','另获得'..n..'。'})[tone]
 elseif k=='explore' then
  n=zoneName(f,p.nameLimit)
  return ({'也去过了'..n..'。',n..'也有了你的足迹。',n..'也去过了，这趟还挺有内容。','足迹也留在了'..n..'。','另到访'..n..'。'})[tone]
 elseif k=='mining' then
  if (r.blocks or 0)==0 then return ({'还收集到了原矿。','你还收集到了原矿，小收获也有分量。','原矿也收集到了，收获清单又添一项。','原矿也成为此行的收获。','另收集到原矿。'})[tone] end
  return ({'采掘也占了这趟的一部分。','你还挖过方块，这份劳动也算数。','方块也挖了，镐子没白占工具栏。','采掘的经历，也留在了征途中。','另有方块挖掘。'})[tone]
 elseif k=='combat' then return ({'途中也击败过敌怪。','沿途击败的敌怪，也是你的战果。','敌怪也打过了，战绩栏没闲着。','敌怪的败落，也写进了征途。','另击败敌怪。'})[tone]
 elseif k=='coins' then return ({'拾取的钱币也算一份收获。','拾取的钱币，也是你这一趟的小收获。','钱币也拾取了，收获栏又添一项。','拾取的钱币，也添上了收获的一笔。','另拾取钱币。'})[tone]
 elseif k=='supplies' then return ({'药水也用过了，补给消耗同样记着。','你也用过药水，别忘了照顾自己的补给。','药水也用过了，补给这趟出了份力。','药水的消耗，也留在了这一段征途中。','另使用药水。'})[tone] end
end
local function ending(r,p,tone,style)
 local f=p.facts;local died=f.deaths>0
 local scope=f.daily and '今天' or '这趟'
 if style==1 and f.finished then
  if died and not p.deathMentioned then return ({'途中曾倒下，现已到家。','你也曾倒下，现在到家了，歇一歇吧。','复活点报过到，家也回到了，先收工。','虽曾倒下，终已归家。','曾死亡，已归家。'})[tone] end
  if died then return ({'已经到家，先记到这里。','到家了，安心歇一会儿吧。','到家收工，下一趟再写。','冒险者终已归家。','已归家。'})[tone] end
  return ({'没有死亡，平安到家。','你平安回来了，安心歇一会儿吧。','零死亡到家，复活点这趟没加班。','冒险者未曾倒下，已平安归家。','无死亡，已归家。'})[tone]
 end
 if f.finished then
  if died and not p.deathMentioned then return ({
   scope..'也曾倒下，如今已经到家，先记到这里。',
   '你也曾倒下，现在已经到家了，给自己留一点休息的时间吧。',
   f.deaths>=3 and '复活点接待了你好几回；到家收工，这趟先给它放个假。' or '复活点也报过到；到家收工，这趟先记到这里。',
   '虽曾倒下，冒险者终已归家；这一章暂且收笔。',
   '曾死亡，已归家。',
  })[tone] end
  if died then return pick(r,59,({
   {'到家了，这趟就记到这里。','如今已到家，留待下一次出发。'},
   {'现在到家了，可以安心歇一会儿。','回家了，给自己留一点休息的时间吧。'},
   {'到家收工，下一趟再接着写。','已经到家，这趟先给手记合个页。'},
   {'冒险者终已归家，征途在此暂且收笔。','归家的脚步，为这一章留下了收尾。'},
   {'已归家。','本次冒险结束。'},
  })[tone]) end
  return pick(r,61,({
   {'没有死亡，已经平安到家。','一路没有倒下，如今已平安归家。'},
   {'这趟没有倒下过，如今到家了，安心歇一会儿吧。','平安回来了，先安心歇一会儿吧。'},
   {'零死亡，到家收工——复活点这趟没轮到你。','平安到家，复活点这趟总算不用接待你。'},
   {'未曾倒下，终已归家。新的篇章，留待下一次出发。','冒险者已平安归家，此行在这里暂歇。'},
   {'无死亡，已归家。','平安归家。'},
  })[tone])
 end
 -- Daily and unfinished records never claim a return home.
 if died and not p.deathMentioned then return ({
  scope..'也曾倒下，这些经历都留在了同一页。',
  '你也曾倒下，受挫的经历同样值得被记住。',
  f.deaths>=3 and ('复活点接待了好几回，'..scope..'有点费命。') or '复活点也报过到，挫折栏同样有内容。',
  '倒下的印记，也留在了冒险者的征途中。',
  '曾死亡。',
 })[tone] end
 if not died and p.main~='idle' then return ({
  scope..'没有死亡，这一页还算平稳。',
  '你没有倒下过，平安也是值得珍惜的一份收获。',
  '死亡次数是零，复活点这页没抢到戏份。',
  '冒险者未曾倒下，这一页没有败亡的印记。',
  '无死亡。',
 })[tone] end
end
function N.compose(r,tone,style)
 tone=math.max(1,math.min(5,math.floor(tonumber(tone) or 1)))
 style=math.max(1,math.min(3,math.floor(tonumber(style) or 2)))
 local p=plan(r,style)
 local lines={}
 if p.scene then
  local scope=p.facts.daily and '今天' or '这趟'
  lines[#lines+1]=({scope..'去过了'..p.scene..'。',scope..'，你把足迹留在了'..p.scene..'。','先跟'..p.scene..'打了个照面。','冒险者的足迹先留在了'..p.scene..'。','到访'..p.scene..'。'})[tone]
 end
 lines[#lines+1]=lead(r,p,tone,style)
 for i,k in ipairs(p.details) do
  local s=detail(r,p,k,tone)
  if s then
   -- Plain diaries can join a small secondary event to the main action,
   -- instead of repeating a new subject at the start of every sentence.
   if tone==1 and i==1 and not p.scene and not p.turn and #lines[#lines]<120 and (k=='gear' or k=='explore') then
    s=s:gsub('^途中','');lines[#lines]=lines[#lines]:gsub('。$','')..'，'..s
   else lines[#lines+1]=s end
  end
 end
 local close=ending(r,p,tone,style);if close then lines[#lines+1]=close end
 if tone==5 then
  for i=1,#lines-1 do lines[i]=lines[i]:gsub('。$','；') end
 end
 return table.concat(lines)
end
return N
