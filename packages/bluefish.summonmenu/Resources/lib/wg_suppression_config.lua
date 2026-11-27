-- 参数为测试起点；机制标签不自动削弱。特殊修正待实测后启用。
local M={version='stage-scale-v1',power={[0]=1,1.45,2.1,3.2,7,11,16,24,34,50,80}}
M.weapons={
 [4956]={tags='multi_projectile,repeat_hit'},
 [3541]={tags='channel_ramp,repeat_hit'},
 [3389]={tags='secondary_projectile,repeat_hit'},
 [3029]={tags='multi_projectile,ammo_interaction'},
 [3474]={tags='persistent_summon,damage_over_time'},
 [3531]={tags='persistent_summon,slot_scaling'},
 [4912]={tags='tag_proc'},
 [3473]={tags='pierce,repeat_hit'},
 [3543]={tags='damage_over_time'},
}
return M
