-- 精简定制版：所有开关写死在这里，不读 config.json，也没有模组设置页面
local cfg={
 enabled=true,
 difficulty='normal',
 headText=true,
 coloredNames=true,
 maxActive=8,
 ai=true,
 actions=true,
 combatStyles=true,          -- 风格系统（猎杀/压制/诡变/守御）；缺它会全部 style=nil
 correctDeathSource=true,    -- 击败提示写「玩家被XX击败了」
 breakWindow=true,
 bossAutoAI=true,
 autoCollect=true,
 extraLoot=true,
 crateRewards=true,
 equipmentRewards=true,
 notices=false,
 archive=false,
 echoRange=640,
 echoHitProtection=true,
 globalEchoLimit=24,
}
-- 兼容旧调用点；不再从存档读取任何设置
function cfg.load() return true end
return cfg
