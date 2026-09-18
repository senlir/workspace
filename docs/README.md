# 弹弹鸟 Godot 重制资料索引

本目录记录从 Egret 5.2.8 工程反推得到的产品规则，并作为 Godot 重制的唯一设计基线。

- `01_game_design.md`：完整玩法、流程、操作、计分和难度设计。
- `02_system_spec.md`：系统级规则、状态与 Godot 实现约束。
- `03_content_audit.md`：原工程完成度、缺陷、歧义和迁移决策。
- `04_asset_catalog.md`：资源分类、命名、来源与导入约定。

配置主数据位于 `../data/config`。JSON 是运行时权威数据，`csv` 是策划可编辑视图。修改后必须保持 ID 与引用关系一致。
