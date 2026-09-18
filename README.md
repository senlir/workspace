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
