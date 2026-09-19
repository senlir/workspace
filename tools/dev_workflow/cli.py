from __future__ import annotations

import argparse
import json
import os
import re
import sys
import uuid
from pathlib import Path

from dotenv import load_dotenv
from langgraph.checkpoint.sqlite import SqliteSaver
from langgraph.types import Command

from .graph import DevelopmentWorkflow, load_config


def project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Proposal-discussion-implementation-validation workflow")
    subparsers = parser.add_subparsers(dest="command", required=True)

    start = subparsers.add_parser("start", help="Create a workflow")
    start.add_argument("request")
    start.add_argument("--thread", default=None)
    start.add_argument("--provider", choices=["openai", "minimax", "mock"], default=None)
    start.add_argument("--auto-review", action="store_true", help="Let the reviewer revise proposals until approved")
    start.add_argument("--max-revisions", type=int, default=None)
    start.add_argument("--apply", action="store_true", help="Apply an auto-approved generated diff")
    start.add_argument("--verbose", action="store_true")

    resume = subparsers.add_parser("resume", help="Resume the human discussion checkpoint")
    resume.add_argument("thread")
    resume.add_argument("--decision", choices=["approve", "revise", "reject"], required=True)
    resume.add_argument("--feedback", default="")
    resume.add_argument("--apply", action="store_true", help="Apply the generated diff before validation")
    resume.add_argument("--auto-review", action="store_true", help="Enable reviewer-driven revisions after this decision")
    resume.add_argument("--max-revisions", type=int, default=None)
    resume.add_argument("--verbose", action="store_true")

    continue_work = subparsers.add_parser("continue", help="Use reviewer feedback and continue automatically")
    continue_work.add_argument("thread")
    continue_work.add_argument("--feedback", default="")
    continue_work.add_argument("--max-revisions", type=int, default=None)
    continue_work.add_argument("--verbose", action="store_true")

    status = subparsers.add_parser("status", help="Inspect persisted workflow state")
    status.add_argument("thread")
    status.add_argument("--verbose", action="store_true")
    return parser


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    args = build_parser().parse_args()
    root = project_root()
    load_dotenv(root / ".env")
    config = load_config(root)
    database = root / ".dev_workflow" / "checkpoints.sqlite"
    database.parent.mkdir(parents=True, exist_ok=True)

    with SqliteSaver.from_conn_string(str(database)) as checkpointer:
        graph = DevelopmentWorkflow(root, config).build(checkpointer)
        if args.command == "start":
            thread = args.thread or uuid.uuid4().hex[:12]
            provider = args.provider or os.getenv("DEVFLOW_PROVIDER") or config.get("provider", "mock")
            configured_revisions = int(config.get("auto_review", {}).get("max_revisions", 3))
            configured_patch_attempts = int(config.get("auto_review", {}).get("max_patch_attempts", 2))
            result = graph.invoke(
                {
                    "request": args.request,
                    "thread_id": thread,
                    "provider": provider,
                    "revision": 0,
                    "auto_review": args.auto_review,
                    "max_auto_revisions": args.max_revisions or configured_revisions,
                    "auto_review_round": 0,
                    "apply_changes": args.apply,
                    "implementation_attempt": 0,
                    "max_patch_attempts": configured_patch_attempts,
                },
                {"configurable": {"thread_id": thread}},
            )
            print_result(root, thread, result, args.verbose)
            return 0
        if args.command == "resume":
            result = graph.invoke(
                Command(
                    resume={
                        "decision": args.decision,
                        "feedback": args.feedback,
                        "apply_changes": args.apply,
                        "auto_review": args.auto_review,
                        "max_auto_revisions": args.max_revisions or int(config.get("auto_review", {}).get("max_revisions", 3)),
                        "max_patch_attempts": int(config.get("auto_review", {}).get("max_patch_attempts", 2)),
                    }
                ),
                {"configurable": {"thread_id": args.thread}},
            )
            print_result(root, args.thread, result, args.verbose)
            return 0
        if args.command == "continue":
            runtime = {"configurable": {"thread_id": args.thread}}
            snapshot = graph.get_state(runtime)
            if "discussion" not in snapshot.next:
                raise RuntimeError(f"Thread {args.thread} is not waiting for review confirmation")
            feedback = args.feedback or str(snapshot.values.get("critique", "Resolve all reviewer findings."))
            result = graph.invoke(
                Command(
                    resume={
                        "decision": "revise",
                        "feedback": feedback,
                        "apply_changes": True,
                        "auto_review": True,
                        "max_auto_revisions": args.max_revisions or int(config.get("auto_review", {}).get("max_revisions", 3)),
                        "max_patch_attempts": int(config.get("auto_review", {}).get("max_patch_attempts", 2)),
                    }
                ),
                runtime,
            )
            print_result(root, args.thread, result, args.verbose)
            return 0
        snapshot = graph.get_state({"configurable": {"thread_id": args.thread}})
        if args.verbose:
            print(json.dumps(snapshot.values, ensure_ascii=False, indent=2, default=str))
            if snapshot.next:
                print(f"next: {', '.join(snapshot.next)}")
        else:
            print_status(root, args.thread, snapshot.values, snapshot.next)
        return 0


def print_result(root: Path, thread: str, result: dict, verbose: bool = False) -> None:
    print(f"任务: {thread}")
    interrupts = result.get("__interrupt__", [])
    if interrupts:
        value = interrupts[0].value
        print("状态: 等待确认")
        print(f"审稿: {value.get('review_verdict', 'human')}，第 {value.get('revision', '?')} 版")
        if verbose:
            print("\n--- proposal ---\n" + value["proposal"])
            print("\n--- critique ---\n" + value["critique"])
        else:
            print("问题: " + concise(value.get("critique", "")))
        print(f"详情: {root / '.dev_workflow' / 'runs' / thread}")
        print(f"继续: .\\tools\\devflow.ps1 continue {thread}")
    elif result.get("validation_review"):
        status = result.get("status", "unknown")
        print(f"状态: {'完成' if status == 'complete' else '失败'}")
        print("结果: " + (result["validation_review"] if verbose else concise(result["validation_review"])))
        print(f"日志: {root / '.dev_workflow' / 'runs' / thread}")
    else:
        print(f"状态: {result.get('status', 'unknown')}")


def print_status(root: Path, thread: str, values: dict, next_nodes: tuple[str, ...]) -> None:
    print(f"任务: {thread}")
    waiting = "discussion" in next_nodes
    print(f"状态: {'等待确认' if waiting else values.get('status', 'unknown')}")
    print(f"版本: {values.get('revision', 0)}")
    if values.get("review_verdict"):
        print(f"审稿: {values['review_verdict']}")
    if values.get("critique"):
        print("问题: " + concise(str(values["critique"])))
    print(f"详情: {root / '.dev_workflow' / 'runs' / thread}")
    if waiting:
        print(f"继续: .\\tools\\devflow.ps1 continue {thread}")


def concise(content: str, limit: int = 240) -> str:
    lines = [line.strip(" #*-\t") for line in content.splitlines() if line.strip(" #*-\t")]
    numbered = [line for line in lines if re.match(r"^\d+[.)、]\s*", line)]
    if numbered:
        text = "；".join(numbered[:3])
    else:
        useful = [
            line
            for line in lines
            if len(line) >= 20 and not line.lower().startswith(("looking at", "verdict", "critique", "feedback"))
        ]
        text = " ".join(useful[:2]) or "查看详情文件"
    return text if len(text) <= limit else text[: limit - 3].rstrip() + "..."


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"workflow error: {error}", file=sys.stderr)
        raise
