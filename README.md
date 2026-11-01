# Community-TEFKernel-LuaLoader-Mods

TEFKernel / LuaLoader 社区 Mod 仓库，收录适用于 LuaLoader 的纯 Lua Terraria Mod。

仓库索引：[`index.json`](index.json)  
下载目录：[`dist/`](dist/)

## 使用

将以下仓库地址添加到支持 TEFKernel 社区仓库的 Mod 管理器：

```text
https://raw.githubusercontent.com/lzup333/Community-TEFKernel-LuaLoader-Mods/main/index.json
```

也可以直接从 `dist/` 下载对应的 `.tefpkg`，并按 LuaLoader / TEFKernel 的目录规范
安装到目标 ModLoader 的 Mod 目录。

## 收录范围

- 仅收录 LuaLoader 纯 Lua Mod。
- 包必须包含 `Info.json`、`Manifest.json`、`luamod.json` 和入口 Lua 脚本。
- 每个包必须提供稳定且唯一的 `pkgId`。
- 仓库索引提供版本、兼容信息、文件大小和 SHA-256 校验值。
- 包内实际包含 `.so`、`.dll`、`.dylib` 或 `.so.*` 文件的 Mod 不会收录。
- 仅存在 `native/` 目录但没有二进制库文件，不会因此被拒绝。

## 包结构

```text
dist/<pkgId>.tefpkg       # 下载包
packages/<pkgId>/         # 可审查的包内容
index.json                # 仓库索引
repository.json           # 仓库元数据
```

`.tefpkg` 包遵循 TEFManager 的 Mod 清单约定；LuaLoader 运行时仍从解压后的 Mod 目录
读取 `luamod.json` 和入口脚本。

## 提交 Mod

欢迎通过 Pull Request 提交 Mod。请确保：

1. `Info.json.pkgId` 与 `luamod.json.pkg_id` 完全一致；
2. 版本号和 `versionCode` 与实际发布版本一致；
3. 不包含原生动态库、私密配置或构建临时文件；
4. Mod 可以在当前 LuaLoader / TEFKernel 版本下正常运行；
5. 不要重复占用已有 Mod 的 `pkgId`。

仓库维护者会重新生成标准化下载包和索引，并在合并前检查包内容与校验值。
