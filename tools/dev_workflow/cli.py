from __future__ import annotations

import argparse
import json
import os
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

    resume = subparsers.add_parser("resume", help="Resume the human discussion checkpoint")
    resume.add_argument("thread")
    resume.add_argument("--decision", choices=["approve", "revise", "reject"], required=True)
    resume.add_argument("--feedback", default="")
    resume.add_argument("--apply", action="store_true", help="Apply the generated diff before validation")
    resume.add_argument("--auto-review", action="store_true", help="Enable reviewer-driven revisions after this decision")
    resume.add_argument("--max-revisions", type=int, default=None)

    status = subparsers.add_parser("status", help="Inspect persisted workflow state")
    status.add_argument("thread")
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
            print_result(thread, result)
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
            print_result(args.thread, result)
            return 0
        snapshot = graph.get_state({"configurable": {"thread_id": args.thread}})
        print(json.dumps(snapshot.values, ensure_ascii=False, indent=2, default=str))
        if snapshot.next:
            print(f"next: {', '.join(snapshot.next)}")
        return 0


def print_result(thread: str, result: dict) -> None:
    print(f"thread: {thread}")
    print(f"status: {result.get('status', 'unknown')}")
    interrupts = result.get("__interrupt__", [])
    if interrupts:
        value = interrupts[0].value
        print("\n--- proposal ---\n" + value["proposal"])
        print("\n--- critique ---\n" + value["critique"])
        print(f"\nreview verdict: {value.get('review_verdict', 'human')} (revision {value.get('revision', '?')})")
        print(f"\nResume with: python -m tools.dev_workflow.cli resume {thread} --decision approve [--apply]")
    elif result.get("validation_review"):
        print("\n--- validation review ---\n" + result["validation_review"])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"workflow error: {error}", file=sys.stderr)
        raise
