-- 修改后重新加载模组；联机玩法以房主设置为准，客户端视觉/信息可独立关闭。
local cfg={
 difficulty="normal", performance="standard", taskDisplay="gui",
 visuals=true, combatStyles=true, breakWindow=true, archive=true, huntContract=true, contractRewards=true, contractRefreshMinutes=3, enabled=true, actions=true, headText=true, skillNotices=true, ai=true, autoCollect=true, extraLoot=true, notices=true, coloredNames=true, maxActive=12,
 echoRange=640,
 -- 前期不开放终焉体，沿用源码中的有效权重。
 echoHitProtection=true, correctDeathSource=true, effectSize='standard', footEffects=true, bossDialog=true, bossAutoAI=true, beeSurfaceTest=false, environmentNotices=true, crateRewards=true, equipmentRewards=true,
 debug=false, terrainNoticeTicks=300, globalEchoLimit=24,
}

local limits={maxActive={1,16}}
local visible={headText=true,footEffects=true,coloredNames=true,notices=true,bossDialog=true, bossAutoAI=true,beeSurfaceTest=true,skillNotices=true,environmentNotices=true,correctDeathSource=true,maxActive=true}
function cfg.load(host,log)
 if type(host.read_file)~='function' then return false end
 local ok,raw=pcall(host.read_file,'config.json')
 if not ok or type(raw)~='string' or #raw>65536 then return false end
 local values=raw:match('"values"%s*:%s*{(.-)}')
 if not values then return false end
 local loaded=0
 for key,current in pairs(cfg)do
  if visible[key] then
   local token=values:match('"'..key..'"%s*:%s*([^,%}%s]+)')
   if type(current)=='boolean' then
    if token=='true' or token=='false' then cfg[key]=token=='true';loaded=loaded+1 end
   elseif token then
    local n=tonumber(token);local bound=limits[key]
    if n and n==n and n%1==0 and n>=bound[1] and n<=bound[2] then cfg[key]=n;loaded=loaded+1 end
   end
  end
 end
 local difficulty=values:match('"difficulty"%s*:%s*"([%a]+)"')
 if require('difficulty').valid(difficulty) then cfg.difficulty=difficulty;loaded=loaded+1 end
 local taskDisplay=values:match('"taskDisplay"%s*:%s*"([%a]+)"')
 if taskDisplay=='gui'or taskDisplay=='notice'then cfg.taskDisplay=taskDisplay;loaded=loaded+1 end
 local size=values:match('"effectSize"%s*:%s*"([%a]+)"')
 if size=='small'or size=='standard'or size=='large'then cfg.effectSize=size;loaded=loaded+1 end
 local performance=values:match('"performance"%s*:%s*"([%a]+)"')
 if performance=='standard'or performance=='low'or performance=='minimal'or performance=='quality'then cfg.performance=performance;loaded=loaded+1 end
 if log then log('CONFIG','loaded='..loaded..' source=private_config');log('BOSS_CONFIG','auto='..tostring(cfg.bossAutoAI)..' beeSurfaceTest='..tostring(cfg.beeSurfaceTest))end
 return true
end
return cfg
