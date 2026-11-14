"""Guard the CI entry point and reusable validation/release wiring."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github/workflows"


class OrchestrationTests(unittest.TestCase):
    def test_ci_validates_prs_and_main_then_releases_only_main_pushes(self):
        ci = (WORKFLOWS / "ci.yml").read_text()
        self.assertIn("  pull_request:", ci)
        self.assertIn("types: [opened, edited, reopened, synchronize]", ci)
        self.assertIn("name: Conventional Commit title", ci)
        self.assertIn("github.event_name == 'push' && github.ref)", ci)
        self.assertIn("  push:\n    branches: [main]", ci)
        self.assertIn("  workflow_dispatch:", ci)
        self.assertIn("    needs: [python, backend, app, image, containers]", ci)
        release = ci.split("\n  release:\n", 1)[1]
        self.assertIn("    needs: passed", release)
        self.assertIn(
            "if: github.event_name == 'push' && github.ref == 'refs/heads/main'",
            release,
        )
        self.assertIn("uses: ./.github/workflows/release.yml", release)
        self.assertFalse((WORKFLOWS / "main.yml").exists())

    def test_release_is_called_after_validation_without_recursive_ci(self):
        release = (WORKFLOWS / "release.yml").read_text()
        self.assertIn("  workflow_call:", release)
        self.assertNotIn("  workflow_dispatch:", release)
        self.assertNotIn("uses: ./.github/workflows/ci.yml", release)
        self.assertNotIn("    needs: ci\n", release)

    def test_shared_checks_keep_project_assertions(self):
        python = (WORKFLOWS / "ci-python.yml").read_text()
        self.assertIn("python-checks.yml@main", python)
        self.assertIn("check-command: bash scripts/ci/check-python.sh", python)
        self.assertIn("after-check-command: bash scripts/ci/check-workflows.sh", python)
        backend = (WORKFLOWS / "ci-backend.yml").read_text()
        self.assertIn("java-build-publish.yml@main", backend)
        self.assertIn(
            "before-check-command: bash ../scripts/ci/check-postgres-image.sh", backend
        )
        self.assertIn("publish: false", backend)


if __name__ == "__main__":
    unittest.main()
