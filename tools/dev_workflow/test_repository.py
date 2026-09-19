from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from .repository import apply_patch, extract_unified_diff, validate_patch_paths


class RepositoryHelpersTest(unittest.TestCase):
    def test_extracts_fenced_diff(self) -> None:
        text = "before\n```diff\ndiff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n```\nafter"
        self.assertTrue(extract_unified_diff(text).startswith("diff --git"))

    def test_rejects_parent_and_internal_paths(self) -> None:
        unsafe_patches = (
            "--- a/../outside.txt\n+++ b/../outside.txt\n",
            "--- a/.git/config\n+++ b/.git/config\n",
            "--- a/.dev_workflow/checkpoints.sqlite\n+++ b/.dev_workflow/checkpoints.sqlite\n",
        )
        for patch in unsafe_patches:
            with self.subTest(patch=patch):
                with self.assertRaises(ValueError):
                    validate_patch_paths(patch)

    def test_applies_checked_patch(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            target = root / "sample.txt"
            target.write_bytes(b"before\n")
            subprocess.run(["git", "add", "sample.txt"], cwd=root, check=True)
            patch = (
                "diff --git a/sample.txt b/sample.txt\n"
                "--- a/sample.txt\n"
                "+++ b/sample.txt\n"
                "@@ -1 +1 @@\n"
                "-before\n"
                "+after\n"
            )
            ok, message = apply_patch(root, patch)
            self.assertTrue(ok, message)
            self.assertEqual(target.read_text(encoding="utf-8"), "after\n")

    def test_empty_patch_is_not_successful(self) -> None:
        ok, message = apply_patch(Path.cwd(), "")
        self.assertFalse(ok)
        self.assertIn("nothing was applied", message)

    def test_recounts_model_generated_hunk_lengths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            target = root / "sample.txt"
            target.write_bytes(b"before\n")
            subprocess.run(["git", "add", "sample.txt"], cwd=root, check=True)
            patch = (
                "diff --git a/sample.txt b/sample.txt\n"
                "--- a/sample.txt\n"
                "+++ b/sample.txt\n"
                "@@ -1,7 +1,9 @@\n"
                "-before\n"
                "+after\n"
            )
            ok, message = apply_patch(root, patch)
            self.assertTrue(ok, message)
            self.assertEqual(target.read_text(encoding="utf-8"), "after\n")

    def test_normalizes_crlf_patch_for_lf_repository_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            target = root / "sample.txt"
            target.write_bytes(b"before\n")
            subprocess.run(["git", "add", "sample.txt"], cwd=root, check=True)
            patch = (
                "diff --git a/sample.txt b/sample.txt\r\n"
                "--- a/sample.txt\r\n"
                "+++ b/sample.txt\r\n"
                "@@ -1 +1 @@\r\n"
                "-before\r\n"
                "+after\r\n"
            )
            ok, message = apply_patch(root, patch)
            self.assertTrue(ok, message)
            self.assertEqual(target.read_text(encoding="utf-8"), "after\n")


if __name__ == "__main__":
    unittest.main()
