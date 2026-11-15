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

    def test_generic_tests_and_project_checks_have_separate_jobs(self):
        python = (WORKFLOWS / "ci-python.yml").read_text()
        self.assertIn("python-tests.yml@main", python)
        self.assertIn("test-directory: ${{ matrix.directory }}", python)
        self.assertIn("test-pattern: ${{ matrix.pattern || 'test*.py' }}", python)
        self.assertIn("  tooling:", python)
        self.assertIn("  workflow-lint:", python)
        self.assertNotIn("test-command:", python)
        self.assertNotIn("after-test-command:", python)
        backend = (WORKFLOWS / "ci-backend.yml").read_text()
        self.assertIn("java-tests.yml@main", backend)
        self.assertIn("    needs: postgres-image", backend)
        self.assertIn("run: bash ../scripts/ci/check-postgres-image.sh", backend)
        self.assertNotIn("before-test-command:", backend)

    def test_python_matrix_preserves_all_previous_suites_and_interpreters(self):
        python = (WORKFLOWS / "ci-python.yml").read_text()
        for directory in [
            "scripts/release",
            "scripts/device-review",
            "scripts/ci",
            "container-tests",
            "examples/tests",
        ]:
            self.assertIn("directory: " + directory, python)
        self.assertIn("suite: SDK tests (Python 3.10)", python)
        self.assertIn("suite: SDK tests (Python 3.12)", python)
        self.assertIn("pattern: test_helpers.py", python)
        self.assertIn("fail-fast: false", python)
        self.assertIn("max-parallel: 2", python)


if __name__ == "__main__":
    unittest.main()
