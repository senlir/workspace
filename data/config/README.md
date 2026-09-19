# 配置表说明

JSON 为运行时权威数据，CSV 为策划编辑视图。编码统一为 UTF-8。

| 文件 | 主键 | 作用 |
|---|---|---|
| `cfg_daoju.json` | `id` | 道具效果、资源、能量消耗 |
| `cfg_guaiwu.json` | `id` | 怪物行为、悬空高度、资源、速度 |
| `cfg_shuzhi.json` | `id` | 平台长度、延时坠落、资源、碰撞厚度 |
| `cfg_platform_profiles.json` | `id` | 各平台素材的站位面、碰撞厚度和边缘留白 |
| `cfg_zuhe.json` | `id` | 内容组的平台、怪物与坐标组合 |
| `cfg_score_zuhe.json` | `score` | 按分数档位排列内容组和道具序列 |
| `cfg_shangcheng.json` | `id` | 未启用的商店条目 |

字段约定：

- `movetype`：1 为立即巡逻，2 为接近玩家高度后追击。
- `sky`：怪物高于平台的像素距离。
- `lang`：平台长度（旧拼写，迁移后代码解释为 `length`）。
- `time`：平台接触后坠落延时，0 表示不坠落。
- `houdu`：平台碰撞厚度。
- `surface_y`：平台图片顶部到站位面的像素距离。
- `collision_height`：从站位面向下计算的有效碰撞厚度。
- `edge_inset`：平台左右两端不可站立的像素距离。
- `shuzhi*dir`：0 从左侧生成，1 为水平镜像。
- `ids`：`#` 分隔序列位置，`&` 分隔该位置的随机候选。
- `daojuid`：与 `ids` 的序列位置一一对应；0 表示不生成。
