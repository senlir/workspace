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
    review_verdict: str
    review_feedback: str
    auto_review: bool
    max_auto_revisions: int
    auto_review_round: int
    apply_changes: bool
    implementation: str
    implementation_attempt: int
    max_patch_attempts: int
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
        graph.add_conditional_edges(
            "critique",
            self.route_after_review,
            {"discussion": "discussion", "proposal": "proposal", "implementation": "implementation"},
        )
        graph.add_edge("implementation", "apply")
        graph.add_conditional_edges(
            "apply",
            self.route_after_apply,
            {"implementation": "implementation", "validation": "validation"},
        )
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
        revision = state.get("revision", 0) + 1
        self._write_artifact(state, "proposal.md", proposal)
        self._write_artifact(state, f"proposal-r{revision}.md", proposal)
        return {"proposal": proposal, "status": "proposal", "revision": revision}

    def critique(self, state: WorkflowState) -> dict[str, Any]:
        context = repository_context(self.root, self.config)
        raw_review = self.models.complete(
            "review",
            state.get("provider", ""),
            (
                "You are an independent senior reviewer. Check the proposal against the repository. "
                "Return JSON only with keys verdict, critique, and feedback. verdict must be approve or revise. "
                "Approve only when there are no blocking or high-risk correctness, scope, rollback, or validation issues. "
                "Production hot paths must not contain assertions that belong in tests. "
                "feedback must be concrete instructions for a revise verdict and must be empty for approve."
            ),
            (
                f"REVISION: {state.get('revision', 1)}\nREQUEST:\n{state['request']}\n\n"
                f"PROPOSAL:\n{state['proposal']}\n\nREPOSITORY:\n{context}"
            ),
        )
        review = self._parse_review(raw_review)
        if review["verdict"] == "human":
            repaired = self.models.complete(
                "review",
                state.get("provider", ""),
                "Convert the supplied review to JSON only. Use keys verdict, critique, feedback. verdict must be approve or revise.",
                raw_review,
            )
            review = self._parse_review(repaired)
        critique = review["critique"]
        review_round = state.get("auto_review_round", 0) + 1 if state.get("auto_review", False) else 0
        self._write_artifact(state, "discussion.md", critique)
        self._write_artifact(state, f"review-r{state.get('revision', 1)}.json", json.dumps(review, ensure_ascii=False, indent=2))
        return {
            "critique": critique,
            "review_verdict": review["verdict"],
            "review_feedback": review["feedback"],
            "feedback": review["feedback"],
            "auto_review_round": review_round,
            "status": "review",
        }

    def route_after_review(self, state: WorkflowState) -> Literal["discussion", "proposal", "implementation"]:
        if not state.get("auto_review", False):
            return "discussion"
        verdict = state.get("review_verdict", "human")
        if verdict == "approve":
            return "implementation"
        max_revisions = max(1, state.get("max_auto_revisions", 3))
        if verdict == "revise" and state.get("auto_review_round", 0) < max_revisions:
            return "proposal"
        return "discussion"

    def discussion(self, state: WorkflowState) -> Command[Literal["proposal", "implementation", "__end__"]]:
        answer = interrupt(
            {
                "phase": "discussion",
                "proposal": state["proposal"],
                "critique": state["critique"],
                "review_verdict": state.get("review_verdict", "human"),
                "revision": state.get("revision", 0),
                "auto_review_round": state.get("auto_review_round", 0),
                "choices": ["approve", "revise", "reject"],
            }
        )
        decision = str(answer.get("decision", "reject"))
        update = {
            "review_decision": decision,
            "feedback": str(answer.get("feedback", "")),
            "apply_changes": bool(answer.get("apply_changes", False)),
            "auto_review": bool(answer.get("auto_review", state.get("auto_review", False))),
            "max_auto_revisions": max(1, int(answer.get("max_auto_revisions", state.get("max_auto_revisions", 3)))),
            "auto_review_round": 0 if bool(answer.get("auto_review", False)) else state.get("auto_review_round", 0),
        }
        if decision == "approve":
            return Command(update=update, goto="implementation")
        if decision == "revise":
            return Command(update=update, goto="proposal")
        return Command(update={**update, "status": "rejected"}, goto=END)

    @staticmethod
    def _parse_review(content: str) -> dict[str, str]:
        cleaned = content.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else ""
            cleaned = cleaned.rsplit("```", 1)[0].strip()
        elif "{" in cleaned and "}" in cleaned:
            cleaned = cleaned[cleaned.find("{") : cleaned.rfind("}") + 1]
        try:
            value = json.loads(cleaned)
        except (json.JSONDecodeError, TypeError):
            return {"verdict": "human", "critique": content.strip(), "feedback": ""}
        verdict = str(value.get("verdict", "human")).lower()
        if verdict not in {"approve", "revise"}:
            verdict = "human"
        critique = str(value.get("critique", "")).strip() or content.strip()
        feedback = str(value.get("feedback", "")).strip()
        if verdict == "approve":
            feedback = ""
        return {"verdict": verdict, "critique": critique, "feedback": feedback}

    def implementation(self, state: WorkflowState) -> dict[str, Any]:
        context = repository_context(self.root, self.config)
        attempt = state.get("implementation_attempt", 0) + 1
        previous_failure = state.get("apply_log", "")
        implementation = self.models.complete(
            "implementation",
            state.get("provider", ""),
            (
                "Implement the approved proposal. Return a valid git unified diff only, with repository-relative paths. "
                "Use exact repository context, correct hunk counts, and omit fabricated index hashes. "
                "Keep test assertions in existing test or smoke-test code, never in production hot paths. "
                "Do not include commands or prose outside the diff."
            ),
            (
                f"PATCH ATTEMPT: {attempt}\nREQUEST:\n{state['request']}\n\nAPPROVED PROPOSAL:\n{state['proposal']}\n\n"
                f"REVIEW FEEDBACK:\n{state.get('feedback', '')}\n\nPREVIOUS APPLY FAILURE:\n{previous_failure}\n\n"
                f"REPOSITORY:\n{context}"
            ),
        )
        patch = extract_unified_diff(implementation)
        self._write_artifact(state, "implementation.txt", implementation)
        if patch:
            self._write_artifact(state, "changes.diff", patch)
        return {"implementation": implementation, "patch": patch, "implementation_attempt": attempt, "status": "implementation"}

    def apply(self, state: WorkflowState) -> dict[str, Any]:
        if not state.get("apply_changes", False):
            apply_ok = True
            log = "Dry run: patch was generated but not applied."
        else:
            try:
                apply_ok, log = apply_patch(self.root, state.get("patch", ""))
            except (OSError, RuntimeError, ValueError) as error:
                apply_ok, log = False, f"Patch rejected: {error}"
        self._write_artifact(state, "apply.log", log)
        return {"apply_log": log, "apply_ok": apply_ok}

    def route_after_apply(self, state: WorkflowState) -> Literal["implementation", "validation"]:
        if state.get("apply_ok", False):
            return "validation"
        max_attempts = max(1, state.get("max_patch_attempts", 2))
        if state.get("implementation_attempt", 0) < max_attempts:
            return "implementation"
        return "validation"

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
        (run_dir / name).write_text(content, encoding="utf-8", newline="\n")


def load_config(root: Path) -> dict[str, Any]:
    return json.loads((root / "dev_workflow.json").read_text(encoding="utf-8"))
