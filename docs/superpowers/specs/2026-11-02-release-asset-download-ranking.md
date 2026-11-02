# 固定 Release 下载量排序设计

## 目标

使用 GitHub 一个固定 Release（tag：`mod-repository`）承载所有 `.tefpkg` Asset，读取 GitHub 的 `download_count`，让 `index.json` 按下载量降序排列，同时不再把二进制包存入 Git 仓库。

## 约束

- `packages/<pkgId>/` 是仓库内的 Mod 源文件。
- `dist/` 只作为本地临时输出目录，不提交到 Git。
- Release Asset 下载地址必须保持稳定：`releases/download/mod-repository/<pkgId>.tefpkg`。
- `index.json` 仍遵循 TEFManager 的 `mods` 数组格式；增加非破坏性的 `downloadCount` 字段。
- GitHub Actions 每 5 小时重建索引；仓库内容变化时同步所有 Release Assets。
- 原生库过滤规则保持不变。

## 工作流

1. Push 到 `main` 时，Action 从 `packages/` 重新打包所有 Mod 到临时目录。
2. Action 创建或复用固定 Release，并用同名 Asset 覆盖上传包。
3. Action 从 Release API 读取每个 Asset 的 `download_count`，按下载量降序、`pkgId` 升序生成 `index.json`。
4. Action 仅提交 `index.json`；Release 包不进入 Git 历史。
5. 定时任务只执行第 3 步，避免每 5 小时重复上传所有包。

## 非目标

- 不统计 Raw 文件访问量或仓库克隆量。
- 不新增外部下载中转服务。
- 不修改 TEFManager 或 LuaLoader 的 ABI。
