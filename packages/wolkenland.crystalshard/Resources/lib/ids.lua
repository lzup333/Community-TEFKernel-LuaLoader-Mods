-- 注册名常量：所有跨文件引用的内容名集中在这里，避免手抄字符串出错。
return {
    item = {
        -- 材料
        shard   = "CrystalShard",
        core    = "CrystalCore",
        -- 召唤物
        bag     = "CrystalTreasureBag",
        beacon  = "CrystalBeacon",
        summon  = "CrystalCoreSummon",
        -- 近战
        blade   = "CrystalBlade",
        hammer  = "CrystalHammer",
        -- 远程
        spear   = "CrystalSpear",
        rifle   = "CrystalRifle",
        -- 魔法
        staff   = "CrystalStaff",
        -- 召唤
        minion_staff = "CrystalSummonStaff",
        -- 饰品
        charm   = "CrystalCoreCharm",
        bracer  = "CrystalBracer",
        cloak   = "CrystalCloak",
        eye     = "CrystalEye",
        badge   = "CrystalBadge",
    },
    projectile = {
        beam       = "CrystalBeam",
        bolt       = "CrystalBolt",
        spike      = "CrystalSpike",
        spike_red  = "CrystalSpikeRed",
        shot       = "CrystalShot",
        magic      = "CrystalMagicBolt",
        minion     = "CrystalMinion",
        minion_shot = "CrystalMinionShot",
        minion_spike = "CrystalMinionSpike",   -- 召唤物专用的晶刺（比 Boss 的小、伤害更高）
    },
    npc = {
        golem = "CrystalGolem",
        boss  = "CrystalCoreLord",
    },
    -- 中文名（聊天指令按名字查找、/gave 用）
    zh = {
        shard = "碎晶", core = "晶核", bag = "晶核宝藏袋", beacon = "晶核信标",
        summon = "晶核召唤符", blade = "碎晶刃", hammer = "碎晶锤",
        spear = "碎晶长枪", rifle = "碎晶步枪", staff = "碎晶法杖",
        minion_staff = "碎晶权杖", charm = "晶核护符", bracer = "碎晶护腕",
        cloak = "碎晶披风", eye = "碎晶之眼", badge = "晶簇徽章",
    },
}
