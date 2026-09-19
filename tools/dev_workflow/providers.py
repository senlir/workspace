from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

from openai import OpenAI


@dataclass(frozen=True)
class ModelSettings:
    provider: str
    model: str
    base_url: str | None = None


class ModelGateway:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config

    def complete(self, phase: str, provider: str, system: str, prompt: str) -> str:
        settings = self._settings(phase, provider)
        if settings.provider == "mock":
            return self._mock_response(phase, prompt)
        if settings.provider == "openai":
            client = OpenAI(api_key=self._required_env("OPENAI_API_KEY"))
            response = client.responses.create(
                model=settings.model,
                instructions=system,
                input=prompt,
            )
            return response.output_text
        if settings.provider == "minimax":
            client = OpenAI(
                api_key=self._required_env("MINIMAX_API_KEY"),
                base_url=settings.base_url,
            )
            response = client.chat.completions.create(
                model=settings.model,
                messages=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": prompt},
                ],
            )
            return response.choices[0].message.content or ""
        raise ValueError(f"Unsupported provider: {settings.provider}")

    def _settings(self, phase: str, provider: str) -> ModelSettings:
        selected = provider or os.getenv("DEVFLOW_PROVIDER") or self.config.get("provider", "mock")
        if selected == "openai":
            model = os.getenv("OPENAI_MODEL") or self.config["models"].get(phase, "gpt-5")
            return ModelSettings(selected, model)
        if selected == "minimax":
            minimax = self.config.get("minimax", {})
            model = os.getenv("MINIMAX_MODEL") or minimax.get("model", "MiniMax-M2.7")
            base_url = os.getenv("MINIMAX_BASE_URL") or minimax.get("base_url", "https://api.minimaxi.com/v1")
            return ModelSettings(selected, model, base_url)
        return ModelSettings("mock", "mock")

    @staticmethod
    def _required_env(name: str) -> str:
        value = os.getenv(name)
        if not value:
            raise RuntimeError(f"Missing required environment variable: {name}")
        return value

    @staticmethod
    def _mock_response(phase: str, prompt: str) -> str:
        if phase == "implementation":
            return "Mock implementation selected. No patch was generated."
        if phase == "validation":
            return "Mock review: validation output was recorded; inspect command exit codes."
        if phase == "discussion":
            return "Mock critique: confirm scope, acceptance criteria, rollback plan, and tests before approval."
        request = prompt.split("REQUEST:", 1)[-1].split("\n", 1)[0].strip()
        return (
            f"# Proposal\n\nGoal: {request}\n\n"
            "## Scope\n- Inspect affected Godot scripts and configuration.\n"
            "- Make the smallest compatible change.\n"
            "- Run the configured deterministic validation commands.\n\n"
            "## Acceptance\n- Existing behavior remains intact.\n- Automated validation passes."
        )
