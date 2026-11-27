require("quickapi")

mod.meta = { pkg_id = "wolkenland.crystalshard", version = "1.2.84" }

local content = require("content")

function setup()
    math.randomseed(os.time())
    local ok, err = pcall(content.register_all)
    if not ok then
        mod.warn("碎晶之链：内容注册失败 " .. tostring(err))
        return
    end
    mod.info("碎晶之链 v1.2.84 已加载")
end

todo_list = { "setup" }
