# 资源目录与导入约定

## 1. 目录

| 目录 | 内容 | 来源 |
|---|---|---|
| `assets/backgrounds` | 游戏背景和左右边界 | `game2/resource/assets/bg` |
| `assets/ui` | 首页/HUD 图集与位图字体 | `game0`、`game1`、`ImageFontStyle9` |
| `assets/animations/player` | 玩家 MovieClip 图集 | `playmc3` |
| `assets/animations/enemies` | 怪物 MovieClip 图集 | `movie` 中非玩家、非特效资源 |
| `assets/animations/effects` | 护盾、火箭、治疗、火焰效果 | `hudun`、`huojian`、`jiaxue`、`fire2` |
| `assets/audio` | BGM 与音效 | `1.mp3`–`6.mp3` |

每个 Egret 动画的 `.json` 与同名 `.png` 必须成对保留。图集 JSON 中的坐标、裁剪偏移和源尺寸都参与动画还原，不能只切图片而丢弃偏移。

## 2. 命名策略

- 第一阶段保留原文件名，避免配置和代码引用失配。
- `source_assets/物件/滚梯/滚梯1.png` 至 `滚梯4.png` 为美术源帧，保持原文件独立提交，不合并图集；Godot 运行时直接用于 `line24` 四帧循环动画。
- Godot 场景和脚本使用语义名；通过资源映射表连接旧文件名。
- 不将 `bin-debug`、`bin-release`、Egret 默认控件皮肤迁入 Godot。
- 源美术目录 `战斗鸡` 保留在旧工程作为归档，Godot 只接入经过确认的运行时资源。

## 3. 资源角色

- `bg1.jpg`：首屏游戏背景。
- `bg2.jpg`：后续循环背景。
- `bg3.jpg`：启动页背景。
- `bgl1.png`、`bgl2.png`：左右场景边界。
- `game0`：启动页和结算窗口 UI。
- `game1`：HUD、数字、平台、触摸提示和少量角色/UI 素材。
- `playmc3`：当前实际使用的玩家完整动作图集。

## 4. Godot 导入规则

- 像素资源关闭 Filter 与 Mipmaps，2D 拉伸使用整数或保持清晰的画布缩放。
- JPG 背景允许有损 VRAM 压缩；含透明通道的 PNG 保持无损导入。
- 音效设为非循环，`1.mp3` BGM 循环。
- 图集转换后保留原 JSON，方便核对帧偏移和动画标签。
