# LangGraph 开发工作流

工作流固定经过：`提案 -> 讨论（人工审批）-> 实现 -> 验证`。状态保存到 `.dev_workflow/checkpoints.sqlite`，每次运行的提案、补丁和验证日志保存在 `.dev_workflow/runs/<thread>/`。

## 安装

```powershell
py -3 -m venv .venv
& '.\.venv\Scripts\python.exe' -m pip install -r requirements-workflow.txt
```

复制 `.env.example` 为 `.env` 并填写需要的值，CLI 会自动加载；也可以直接设置当前终端环境变量。`.env` 已被 Git 忽略，密钥不要写入其他受跟踪文件。

## 启动与讨论

```powershell
& '.\.venv\Scripts\python.exe' -m tools.dev_workflow.cli start '调整 line24 的滚动速度' --provider mock
```

命令会生成提案和审查意见，然后在讨论节点暂停。根据输出的 thread ID 恢复：

```powershell
# 只生成补丁并验证，不修改工作区
& '.\.venv\Scripts\python.exe' -m tools.dev_workflow.cli resume <thread> --decision approve

# 批准并实际应用补丁，再运行固定验证命令
& '.\.venv\Scripts\python.exe' -m tools.dev_workflow.cli resume <thread> --decision approve --apply

# 要求按反馈重新提案
& '.\.venv\Scripts\python.exe' -m tools.dev_workflow.cli resume <thread> --decision revise --feedback '不要修改配置表'
```

## 模型切换

- OpenAI：设置 `OPENAI_API_KEY`，使用 `--provider openai`。
- MiniMax：中国区默认 `MINIMAX_BASE_URL=https://api.minimaxi.com/v1`，设置 `MINIMAX_API_KEY` 后使用 `--provider minimax`。
- mock：无需联网和密钥，用于验证状态机与人工审批流程。

模型提供方优先级为命令行 `--provider`、`DEVFLOW_PROVIDER` 环境变量、`dev_workflow.json` 默认值。OpenAI 各阶段模型可分别在 `models` 中调整；MiniMax 模型使用 `MINIMAX_MODEL` 或 `minimax.model`。

各阶段模型、上下文大小和验证命令均可在根目录 `dev_workflow.json` 修改。默认验证包含内容配置检查、Godot 无窗口启动检查和 Git 空白错误检查。项目已有的 `--capture-smoke` 会更新截图产物，因此没有放进默认工作流，发布前仍应单独运行完整截图回归。

实现阶段只接受仓库相对路径的 unified diff；模型输出的命令不会执行。
选择 `--apply` 后，补丁缺失、路径越界或 `git apply --check` 失败都会让最终状态变为 `failed`。
