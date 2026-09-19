from __future__ import annotations

import unittest
from pathlib import Path

from .graph import DevelopmentWorkflow


class AutoReviewTest(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = DevelopmentWorkflow(Path.cwd(), {"provider": "mock", "models": {}})

    def test_parses_plain_and_fenced_review_json(self) -> None:
        plain = '{"verdict":"approve","critique":"ok","feedback":""}'
        fenced = "```json\n" + plain + "\n```"
        self.assertEqual(self.workflow._parse_review(plain)["verdict"], "approve")
        self.assertEqual(self.workflow._parse_review(fenced)["critique"], "ok")

    def test_invalid_review_falls_back_to_human(self) -> None:
        review = self.workflow._parse_review("not json")
        self.assertEqual(review["verdict"], "human")
        self.assertEqual(review["critique"], "not json")

    def test_manual_mode_always_pauses(self) -> None:
        route = self.workflow.route_after_review({"auto_review": False, "review_verdict": "approve"})
        self.assertEqual(route, "discussion")

    def test_auto_review_routes_approve_to_implementation(self) -> None:
        route = self.workflow.route_after_review({"auto_review": True, "review_verdict": "approve"})
        self.assertEqual(route, "implementation")

    def test_auto_review_revises_until_limit_then_pauses(self) -> None:
        state = {
            "auto_review": True,
            "review_verdict": "revise",
            "max_auto_revisions": 3,
            "auto_review_round": 2,
        }
        self.assertEqual(self.workflow.route_after_review(state), "proposal")
        state["auto_review_round"] = 3
        self.assertEqual(self.workflow.route_after_review(state), "discussion")


if __name__ == "__main__":
    unittest.main()
