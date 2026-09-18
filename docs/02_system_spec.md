# 系统规格与数据约定

## 1. 场景划分

- `Main`：流程状态机，切换启动、游戏、结算。
- `GameWorld`：物理世界、滚屏、内容组对象池、边界循环。
- `Player`：输入结果、移动、动画、护盾/火箭状态。
- `ContentGroup`：按 `cfg_zuhe` 实例化平台、怪物和道具。
- `HUD`：生命、时间、分数、能量和暂停/音效。
- `PlatformBridge`：微信登录、分享、排行、广告；桌面环境提供空实现。

## 2. 状态机

`BOOT -> HOME -> PLAYING -> GAME_OVER -> PLAYING`

- `PLAYING` 才推进物理、计时和生成。
- 应用失焦时进入暂停，恢复后不补算离线时间。
- 结算只允许触发一次，避免生命与时间同帧归零造成重复结算。

## 3. 坐标与单位

- Godot 使用左上原点的画布坐标和像素单位。
- 配置中的 `lang`、`houdu`、`guaiwu*x` 沿用旧版像素值。
- `py` 是旧 P2 世界中的内容组高度索引，每单位约 50 px；导入时转换为 `y = -py * 50`。
- 设计宽度固定为 640，横向位置无需缩放；视口由 Godot stretch 处理。

## 4. 数据加载

- JSON 是权威运行时配置，CSV 仅供审阅与批量编辑。
- 所有表加载时校验：主键唯一、外键存在、数组列长度一致、资源名可解析。
- `cfg_score_zuhe.ids` 使用 `#` 分组、`&` 表示二选一。
- `cfg_score_zuhe.daojuid` 与 `ids` 的 `#` 分组数量必须一致。
- 所有概率与随机数由单一 RNG 提供，支持固定种子复现问题。

## 5. 碰撞层建议

| 层 | Godot 对象 | 与谁碰撞 |
|---:|---|---|
| 1 | Player | Platform、Monster、Pickup、Boundary |
| 2 | Platform | Player、Monster |
| 3 | Monster | Player、Platform |
| 4 | Pickup | Player |
| 5 | Boundary | Player |

怪物和道具适合用 `Area2D`；玩家用 `CharacterBody2D` 或 `RigidBody2D`。为保持旧版弹射手感，首选 `CharacterBody2D` 加显式速度积分，结果更可控。

## 6. 动画迁移

- Egret MovieClip JSON 保存帧矩形和标签，可在导入阶段转换为 Godot `SpriteFrames`。
- 玩家 `playmc3` 标签：`walk1` 待机，`walk2` 蓄力，`walk3` 普通飞行，`walk4` 强力飞行/复位。
- 怪物统一动画名 `walk`。
- 原 `playmc1`、`playmc2` 在资源清单中声明但文件缺失，且运行逻辑实际只使用 `playmc3`；迁移时删除无效依赖。

## 7. 存档

- 本地持久化：最高分、音效开关、是否完成新手引导。
- 微信开放数据域排行榜通过适配层上报最高分。
- 原 PHP 金币服务接口未接入有效流程，且实现存在接口错误，首版不迁移。
