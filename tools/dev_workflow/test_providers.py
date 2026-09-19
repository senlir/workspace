from __future__ import annotations

import unittest

from .providers import ModelGateway


class ModelGatewayTest(unittest.TestCase):
    def test_strips_minimax_reasoning_block(self) -> None:
        content = "<think>\nprivate reasoning\n</think>\n\nVisible answer"
        self.assertEqual(ModelGateway._strip_reasoning(content), "Visible answer")

    def test_preserves_plain_content(self) -> None:
        self.assertEqual(ModelGateway._strip_reasoning("Visible answer"), "Visible answer")


if __name__ == "__main__":
    unittest.main()
