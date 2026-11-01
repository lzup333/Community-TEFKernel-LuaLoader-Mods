# Community-TEFKernel-LuaLoader-Mods

LuaLoader 纯 Lua Mod 社区仓库。包格式遵循 TEFManager：`Info.json`、`Manifest.json`、
`luamod.json` 和入口脚本必须位于包内，下载包放在 `dist/`，解压后的可审查目录放在
`packages/<pkgId>/`。

## 导入 Mod

```bash
python3 tools/lualoader_modrepo.py --repo . init
python3 tools/lualoader_modrepo.py --repo . import /path/to/Mods
```

导入器支持批量扫描 ZIP/TEFPKG。包内实际存在 `.so`、`.dll`、`.dylib` 或 `.so.*` 文件
时会跳过；仅有名为 `native/` 的目录不会跳过。重复 `pkgId` 会进入交互式选择，并展示
版本、`versionCode`、`main.lua` 修改时间、包大小、SHA-256 和来源路径。

## 本地包管理器目录

默认仓库工作目录为 `~/.local/share/lualoader-modrepo/repository`，配置为
`~/.config/lualoader/modrepo.json`，状态和日志为 `~/.local/state/lualoader-modrepo/`。
使用 `--repo` 可以指定当前工作区的社区仓库目录。

## 仓库结构

```text
packages/<pkgId>/       # 导入后的可审查内容
dist/<pkgId>.tefpkg     # 供下载的标准化包
index.json              # 静态索引，包含 SHA-256
repository.json         # 仓库元数据
tools/lualoader_modrepo.py
```

LuaLoader 客户端安装前会再次校验索引 SHA-256、包清单和原生库后缀。
