-- 崩溃修复 main.lua  v1.0.1
-- 作用：本模组「存在且被启用」即可让「崩坏探针」不退出。
-- 原理：探针进世界时读 LuaLoader 的 enables.txt，发现本 mod id 在列表里 → 不崩。
-- 因此本模组无需做任何事（空壳），不写文件、不写日志、不 hook。
mod.meta = { pkg_id = "lua.qing.crashfix", version = "1.0.1", version_code = 101, api_version = 1 }

function setup()
  -- 啥也不用干。存在即生效。
end

todo_list = { "setup" }
