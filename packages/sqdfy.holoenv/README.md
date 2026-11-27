# 环境监控 v1.1.2 —— 聊天栏单行版

> Terraria 手机版（1.4.5.8 + LuaLoader）模组。只做一件事：把当前环境压成一行，
> 发到聊天栏。没有悬浮面板，不写文件，不改任何游戏数值。

---

## 1. 输出格式

```
环境：丛林丨群系：地表丨事件：史莱姆雨
```

- **环境**：群系名（腐化之地 / 猩红之地 / 神圣之地 / 丛林 / 雪原 / 蘑菇洞 /
  地下沙漠 / 沙漠 / 地牢 / 丛林神庙 / 蜂巢 / 花岗岩洞 / 大理石洞 / 海滩 /
  陨石区 / 墓地 / 微光之地）。
  - 地表没有特殊群系 → 森林；地下没有特殊群系 → 岩层。
  - 多个群系同时成立 → 用「／」连接，最多两个，多了补「等」。
- **群系**：地表 / 地下 / 洞穴 / 地狱 / 太空。
- **事件**：入侵（带剩余数量）/ 血月 / 日食 / 南瓜月 / 霜月 / 史莱姆雨；
  没有就写「无」。同时多个用「、」连接。

有事件时整行显示为暖橙色，平时是青色。

---

## 2. 什么时候发

1. 进世界约 0.5 秒后发第一行；
2. 之后只在**群系 / 层深 / 事件**变化时再发；
3. 两次播报至少间隔 `report_interval` 秒（默认 3），快速穿越群系会合并；
4. 同一环境不会重复刷屏。

---

## 3. v1.1.0 修复了什么（名称沿用至今）

**症状**：不管走到哪都显示「森林 / 岩层」。

**原因**：手机版 `Player` 的地带标记不是字段，而是**属性**：

```
C# 属性        →  运行时 getter
ZoneJungle     →  get_ZoneJungle
ZoneSnow       →  get_ZoneSnow
ZoneRockLayerHeight → get_ZoneRockLayerHeight
```

v1.0.0 用 `patch.get_field` 读，全部拿到 `nil`，于是群系判定失败，回落到
「森林 / 岩层」；层深则靠 Y 坐标兜底。

**修法**：每个地带标记按「先字段、再属性」解析：

```lua
local f = find_field(T_Player, name)          -- 桌面/其它版本可能是字段
if f then return { kind = "field", h = f } end
local prop = patch.get_property(T_Player, name)
if prop then return { kind = "prop", h = patch.property_get_method(prop) } end
```

读取时字段走 `get_field_value`，属性走 `patch.invoke(getter, player)`。
启动日志会打印「地带 22/22」，用来确认解析成功。

---

## 4. 环境是怎么判定的

### 层深

按顺序匹配，命中即停：

| 标记 | 显示 |
|---|---|
| `ZoneUnderworldHeight` | 地狱 |
| `ZoneSkyHeight` | 太空 |
| `ZoneRockLayerHeight` | 洞穴 |
| `ZoneDirtLayerHeight` | 地下 |
| `ZoneOverworldHeight` | 地表 |

全部读不到时，用 `position.Y / 16` 与 `Main.worldSurface`、`Main.rockLayer`、
`Main.maxTilesY - 200` 兜底推算。

### 群系

按顺序收集所有为真的标记：腐化 / 猩红 / 神圣 / 丛林 / 雪原 / 蘑菇 /
地下沙漠 / 沙漠 / 地牢 / 丛林神庙 / 蜂巢 / 花岗岩洞 / 大理石洞 / 海滩 /
陨石区 / 墓地 / 微光之地。

### 事件

- 入侵：`Main.invasionType`（1 哥布林 / 2 雪人军团 / 3 海盗 / 4 火星），
  带 `invasionSize / invasionSizeStart` 剩余量；
- `Main.bloodMoon` / `eclipse` / `pumpkinMoon` / `snowMoon` / `slimeRain`。

---

## 5. 设置

| 键 | 默认 | 说明 |
|---|---|---|
| `enabled` | 开 | 播报总开关 |
| `report_interval` | 3 秒 | 最短播报间隔，1~30 秒 |

配置文件在 `Resources/config.json`：

```json
{"schemaVersion":1,"values":{"enabled":"true","report_interval":"3"}}
```

改完重进世界生效。

---

## 6. 数据来源（全部只读）

| 来源 | 用途 |
|---|---|
| `Player.Zone*`（属性或字段） | 群系、层深 |
| `Player.position` | 坐标兜底层深 |
| `Main.invasionType` / `invasionSize` / `invasionSizeStart` | 入侵与剩余量 |
| `Main.bloodMoon` / `eclipse` / `pumpkinMoon` / `snowMoon` / `slimeRain` | 事件 |
| `Main.worldSurface` / `rockLayer` / `maxTilesY` | 层深兜底 |
| `Player.whoAmI` / `active` | 只处理本机玩家 |

所有读取都在 `pcall` 里；取不到的项只显示「未知 / 无」，不会报错退出。

---

## 7. 工作方式

```
Player.Update(postfix) ──每 10 帧──▶ env.read() ──▶ sample
                                              │
                                              ▼
                                       report.tick()
                                  （三项签名变化才发，带节流）
                                              │
                                              ▼
                                       Main.NewText ×1
```

- 主挂点 `Player.Update`：实例就是玩家本人，用 `whoAmI == Main.myPlayer` 过滤
  联机时其它玩家的 Update；
- 备挂点 `Main.Update`：主挂点没装上时自己计时，从玩家数组取样本；
- 聊天发送连续失败 5 次自动停播；卸载时移除全部钩子。

---

## 8. 兼容性

| 情况 | 表现 |
|---|---|
| 手机版 1.4.5.8 | 正常（Zone 属性路径） |
| 地带标记是字段的版本 | 正常（字段路径） |
| 没有 `Main.NewText` | 日志提示一次，不报错 |
| 单项字段缺失 | 该项「未知 / 无」 |
| 多人游戏 | 只读本机玩家，消息仅本地可见 |

---

## 9. 文件结构

```
环境监控v1.1.2.zip
├─ luamod.json            加载器入口
├─ Info.json              展示信息与两个设置项
├─ Manifest.json          资源/图标声明
├─ icon.png               512×512 图标
├─ README.md              本文件
└─ Resources/
   ├─ config.json         默认配置
   └─ lib/
      ├─ main.lua         生命周期、钩子、聊天发送
      ├─ env.lua          地带属性/字段解析与环境采样
      ├─ format.lua       单行文案
      ├─ report.lua       播报调度（0.5 秒首播、去重、节流、熔断）
      └─ config.lua       读 config.json
```

自测脚本在 `test/`（不打包）：用假的 `mod` / `patch` 模拟手机版属性路径，
验证首行、变化播报、不重复、以及「只装 Main.Update」的兜底路径。

---

## 10. 版本

- **v1.1.2**：包名前缀改为 `sqdfy.holoenv`，作者改为「烧钱的肥鱼」；功能不变。
- **v1.1.1**：模组名改为「环境监控」，作者改为「坠落」；功能与 v1.1.0 相同。
- **v1.1.0**：去掉悬浮面板，只保留聊天栏单行播报；修复手机版 `Player.Zone*`
  属性读取（不再永远显示森林 / 岩层）。
- **v1.0.0**：首版，六行快照 + 全息面板。
