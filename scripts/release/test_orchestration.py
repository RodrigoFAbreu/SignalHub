"""Guard entry-point and reusable-release wiring."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / ".github/workflows"


class OrchestrationTests(unittest.TestCase):
    def test_main_owns_push_and_calls_release(self):
        main = (ROOT / "main.yml").read_text()
        self.assertIn("  push:\n    branches: [main]", main)
        self.assertIn("  workflow_dispatch:", main)
        self.assertIn("uses: ./.github/workflows/release.yml", main)

    def test_release_is_reusable_and_retains_its_ci_gate(self):
        release = (ROOT / "release.yml").read_text()
        self.assertIn("  workflow_call:", release)
        self.assertIn("  workflow_dispatch:", release)
        self.assertNotIn("  push:", release.split("permissions:", 1)[0])
        self.assertIn("uses: ./.github/workflows/ci.yml", release)
        self.assertIn("    needs: ci\n", release)


if __name__ == "__main__":
    unittest.main()
