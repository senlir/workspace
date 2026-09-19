# 弹弹鸟 Godot 重制版

基于原 Egret 项目的配置与美术资源实现，运行环境为 Godot 4.7.2 Mono。

## 运行

用 Godot 打开本目录并运行项目，或执行：

```powershell
& 'D:\softs\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe' --path 'D:\godotspace\newbird'
```

## 操作

- 按住鼠标左键或触摸屏幕，向任意方向拖动。
- 松手后，角色向拖动方向的反方向弹射。
- 拖动距离越长，弹射力度越大。
- 落在平台上后可再次弹射。

目标是在 180 秒内不断向上，躲避或踩落怪物，收集加时、治疗和能量道具。生命归零或时间耗尽后结算。

## 验证

```powershell
& '.\tools\validate_content.ps1'
& 'D:\softs\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' --path 'D:\godotspace\newbird' -- --capture-smoke
```

截图输出在 `artifacts`，测试覆盖配置加载、内容生成、图集渲染、拖拽弹射和结算重开。

## AI 开发工作流

项目内置 LangGraph 的 `提案 -> 审稿 -> 实现 -> 验证` 工作流，可切换 OpenAI、MiniMax 或无密钥的 mock 提供方，并支持审稿代理自动批改：

```powershell
py -3 -m venv .venv
& '.\.venv\Scripts\python.exe' -m pip install -r requirements-workflow.txt
& '.\.venv\Scripts\python.exe' -m tools.dev_workflow.cli start '描述本次开发目标' --provider mock
& '.\.venv\Scripts\python.exe' -m tools.dev_workflow.cli start '描述本次开发目标' --provider minimax --auto-review --apply
```

配置、审批和恢复命令见 [`tools/dev_workflow/README.md`](tools/dev_workflow/README.md)。

## 平台调校

在 Godot 中打开并运行 `tools/platform_tuning/platform_tuning.tscn`，可逐个平台调整：

- `surface_y`：素材顶部到角色脚底站位面的距离。
- `collision_height`：平台向下的碰撞厚度。
- `edge_inset`：左右两侧不可站立的视觉留白。

保存后写入 `data/config/cfg_platform_profiles.json`，重新开始一局即可生效。红线表示站位面，绿色区域表示有效碰撞范围。
