from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Literal, TypedDict

from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, interrupt

from .providers import ModelGateway
from .repository import apply_patch, expand_command, extract_unified_diff, repository_context, run_command


class WorkflowState(TypedDict, total=False):
    request: str
    provider: str
    thread_id: str
    proposal: str
    critique: str
    feedback: str
    review_decision: str
    apply_changes: bool
    implementation: str
    patch: str
    apply_log: str
    apply_ok: bool
    validation_log: str
    validation_ok: bool
    validation_review: str
    status: str
    revision: int


class DevelopmentWorkflow:
    def __init__(self, root: Path, config: dict[str, Any]) -> None:
        self.root = root
        self.config = config
        self.models = ModelGateway(config)

    def build(self, checkpointer: Any):
        graph = StateGraph(WorkflowState)
        graph.add_node("proposal", self.proposal)
        graph.add_node("critique", self.critique)
        graph.add_node("discussion", self.discussion)
        graph.add_node("implementation", self.implementation)
        graph.add_node("apply", self.apply)
        graph.add_node("validation", self.validation)
        graph.add_node("validation_review", self.validation_review)
        graph.add_edge(START, "proposal")
        graph.add_edge("proposal", "critique")
        graph.add_edge("critique", "discussion")
        graph.add_edge("implementation", "apply")
        graph.add_edge("apply", "validation")
        graph.add_edge("validation", "validation_review")
        graph.add_edge("validation_review", END)
        return graph.compile(checkpointer=checkpointer)

    def proposal(self, state: WorkflowState) -> dict[str, Any]:
        context = repository_context(self.root, self.config)
        feedback = state.get("feedback", "")
        prompt = f"REQUEST: {state['request']}\nREVISION FEEDBACK: {feedback}\n\nREPOSITORY:\n{context}"
        proposal = self.models.complete(
            "proposal",
            state.get("provider", ""),
            "You are a senior game engineer. Produce a scoped proposal with risks, files, acceptance criteria, and tests. Do not write code yet.",
            prompt,
        )
        self._write_artifact(state, "proposal.md", proposal)
        return {"proposal": proposal, "status": "proposal", "revision": state.get("revision", 0) + 1}

    def critique(self, state: WorkflowState) -> dict[str, Any]:
        critique = self.models.complete(
            "discussion",
            state.get("provider", ""),
            "Review a development proposal. Identify missing requirements, regressions, unsafe scope, and weak validation. Be concise.",
            f"REQUEST:\n{state['request']}\n\nPROPOSAL:\n{state['proposal']}",
        )
        self._write_artifact(state, "discussion.md", critique)
        return {"critique": critique, "status": "discussion"}

    def discussion(self, state: WorkflowState) -> Command[Literal["proposal", "implementation", "__end__"]]:
        answer = interrupt(
            {
                "phase": "discussion",
                "proposal": state["proposal"],
                "critique": state["critique"],
                "choices": ["approve", "revise", "reject"],
            }
        )
        decision = str(answer.get("decision", "reject"))
        update = {
            "review_decision": decision,
            "feedback": str(answer.get("feedback", "")),
            "apply_changes": bool(answer.get("apply_changes", False)),
        }
        if decision == "approve":
            return Command(update=update, goto="implementation")
        if decision == "revise":
            return Command(update=update, goto="proposal")
        return Command(update={**update, "status": "rejected"}, goto=END)

    def implementation(self, state: WorkflowState) -> dict[str, Any]:
        context = repository_context(self.root, self.config)
        implementation = self.models.complete(
            "implementation",
            state.get("provider", ""),
            "Implement the approved proposal. Return a valid git unified diff only, with repository-relative paths. Do not include commands or prose outside the diff.",
            f"REQUEST:\n{state['request']}\n\nAPPROVED PROPOSAL:\n{state['proposal']}\n\nREVIEW FEEDBACK:\n{state.get('feedback', '')}\n\nREPOSITORY:\n{context}",
        )
        patch = extract_unified_diff(implementation)
        self._write_artifact(state, "implementation.txt", implementation)
        if patch:
            self._write_artifact(state, "changes.diff", patch)
        return {"implementation": implementation, "patch": patch, "status": "implementation"}

    def apply(self, state: WorkflowState) -> dict[str, Any]:
        if not state.get("apply_changes", False):
            apply_ok = True
            log = "Dry run: patch was generated but not applied."
        else:
            apply_ok, log = apply_patch(self.root, state.get("patch", ""))
        self._write_artifact(state, "apply.log", log)
        return {"apply_log": log, "apply_ok": apply_ok}

    def validation(self, state: WorkflowState) -> dict[str, Any]:
        logs: list[str] = []
        ok = state.get("apply_ok", True)
        for raw_command in self.config.get("validation_commands", []):
            try:
                command = expand_command(raw_command, self.root)
                code, output = run_command(command, self.root)
            except (OSError, RuntimeError, ValueError) as error:
                command = raw_command
                code, output = 1, f"Validation setup failed: {error}"
            ok = ok and code == 0
            logs.append(f"$ {' '.join(command)}\nexit={code}\n{output}")
        log = "\n\n".join(logs)
        self._write_artifact(state, "validation.log", log)
        return {"validation_log": log, "validation_ok": ok, "status": "validation"}

    def validation_review(self, state: WorkflowState) -> dict[str, Any]:
        review = self.models.complete(
            "validation",
            state.get("provider", ""),
            "Review deterministic validation output. Summarize failures and residual risk without claiming unrun checks passed.",
            f"REQUEST:\n{state['request']}\n\nAPPLY RESULT:\n{state.get('apply_log', '')}\n\nVALIDATION:\n{state.get('validation_log', '')}",
        )
        status = "complete" if state.get("validation_ok") else "failed"
        self._write_artifact(state, "validation_review.md", review)
        return {"validation_review": review, "status": status}

    def _write_artifact(self, state: WorkflowState, name: str, content: str) -> None:
        run_dir = self.root / ".dev_workflow" / "runs" / state["thread_id"]
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / name).write_text(content, encoding="utf-8")


def load_config(root: Path) -> dict[str, Any]:
    return json.loads((root / "dev_workflow.json").read_text(encoding="utf-8"))
