# Community-TEFKernel-LuaLoader-Mods

TEFKernel / LuaLoader 社区 Mod 仓库，收录适用于 LuaLoader 的纯Lua的Mod。

## 使用
更新LuaLoader

Mod 包存放在本仓库的固定 GitHub Release `mod-repository` 中，索引会按 GitHub 记录的下载量从高到低排列。

## 收录范围

- 仅收录 LuaLoader 纯 Lua Mod。
- 包必须包含 `Info.json`、`Manifest.json`、`Manifest.json.file` 指定的加载配置文件和入口 Lua 脚本；配置文件不要求必须命名为 `luamod.json`。
- 每个包必须提供稳定且唯一的 `pkgId`。
- 仓库索引提供版本、兼容信息、文件大小和 SHA-256 校验值。
- 包内实际包含 `.so`、`.dll`、`.dylib` 或 `.so.*` 文件的 Mod 不会收录。
- `.tefpkg` 发布包不存放在 Git 仓库中，由 GitHub Actions 自动生成并同步到固定 Release。

## 提交 Mod

打开一个Issue,向lzup333申请提交Mod,待审核通过后即可进入仓库

仓库维护者会重新生成标准化下载包和索引，并在合并前检查包内容与校验值。
