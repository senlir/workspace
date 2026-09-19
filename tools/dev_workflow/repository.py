from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any


def run_command(args: list[str], root: Path, timeout: int = 180) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            args,
            cwd=root,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            shell=False,
        )
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode("utf-8", "replace") if isinstance(error.stdout, bytes) else error.stdout or ""
        stderr = error.stderr.decode("utf-8", "replace") if isinstance(error.stderr, bytes) else error.stderr or ""
        return 124, (stdout + stderr + f"\nCommand timed out after {timeout}s.").strip()
    output = (completed.stdout + completed.stderr).strip()
    return completed.returncode, output


def repository_context(root: Path, config: dict[str, Any]) -> str:
    context_config = config.get("context", {})
    max_chars = int(context_config.get("max_chars", 120000))
    extensions = set(context_config.get("extensions", [".gd", ".tscn", ".json", ".md"]))
    sections: list[str] = []
    for label, command in (
        ("git status", ["git", "status", "--short"]),
        ("recent commits", ["git", "log", "-5", "--oneline"]),
    ):
        code, output = run_command(command, root)
        sections.append(f"## {label} (exit {code})\n{output}")

    used = sum(len(section) for section in sections)
    excluded = {".git", ".godot", ".venv", ".dev_workflow", "artifacts", "source_assets"}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in extensions:
            continue
        if any(part in excluded for part in path.relative_to(root).parts):
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        block = f"\n## FILE {path.relative_to(root).as_posix()}\n{content}\n"
        if used + len(block) > max_chars:
            break
        sections.append(block)
        used += len(block)
    return "\n".join(sections)


def extract_unified_diff(text: str) -> str:
    if "```diff" in text:
        extracted = text.split("```diff", 1)[1].split("```", 1)[0].strip() + "\n"
        return extracted.replace("\r\n", "\n").replace("\r", "\n")
    marker = text.find("diff --git ")
    extracted = text[marker:].strip() + "\n" if marker >= 0 else ""
    return extracted.replace("\r\n", "\n").replace("\r", "\n")


def validate_patch_paths(patch: str) -> None:
    for line in patch.splitlines():
        if not line.startswith(("+++ ", "--- ")):
            continue
        raw = line[4:].split("\t", 1)[0]
        if raw == "/dev/null":
            continue
        if raw.startswith(("a/", "b/")):
            raw = raw[2:]
        path = Path(raw)
        if not path.parts or path.is_absolute() or ".." in path.parts:
            raise ValueError(f"Unsafe patch path: {raw}")
        if path.parts[0] in {".git", ".dev_workflow", ".venv"}:
            raise ValueError(f"Unsafe patch path: {raw}")


def apply_patch(root: Path, patch: str) -> tuple[bool, str]:
    if not patch:
        return False, "No unified diff was produced; nothing was applied."
    patch = patch.replace("\r\n", "\n").replace("\r", "\n")
    validate_patch_paths(patch)
    process = subprocess.run(
        ["git", "apply", "--check", "--recount", "-"],
        cwd=root,
        input=patch.encode("utf-8"),
        capture_output=True,
    )
    if process.returncode != 0:
        return False, f"Patch check failed:\n{process.stderr.decode('utf-8', 'replace').strip()}"
    applied = subprocess.run(
        ["git", "apply", "--recount", "-"],
        cwd=root,
        input=patch.encode("utf-8"),
        capture_output=True,
    )
    if applied.returncode != 0:
        return False, f"Patch apply failed:\n{applied.stderr.decode('utf-8', 'replace').strip()}"
    return True, "Patch applied successfully."


def expand_command(command: list[str], root: Path) -> list[str]:
    values = {"PROJECT_ROOT": str(root), "GODOT_BIN": os.getenv("GODOT_BIN", "")}
    expanded: list[str] = []
    for item in command:
        value = item
        for key, replacement in values.items():
            value = value.replace("${" + key + "}", replacement)
        if not value:
            raise RuntimeError(f"Missing environment value in validation command: {command}")
        expanded.append(value)
    return expanded
