"""Exercise the rolling alias promotion without registry access or credentials."""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/release.yml"


class LatestPromotionTests(unittest.TestCase):
    def setUp(self):
        workflow = WORKFLOW.read_text()
        self.job = workflow.split("\n  latest:\n", 1)[1]
        self.script = textwrap.dedent(self.job.split("        run: |\n", 1)[1])

    def run_promotion(self, failure=""):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            log = directory / "calls.jsonl"
            docker = directory / "docker"
            docker.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "with open(os.environ['CALL_LOG'], 'a') as stream:\n"
                "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "if sys.argv[1] == 'login':\n"
                "    sys.stdin.read()\n"
                "mode = 'promote' if sys.argv[1] == 'buildx' else sys.argv[1]\n"
                "sys.exit(1 if mode == os.environ['FAILURE'] else 0)\n"
            )
            docker.chmod(0o755)
            digest = "sha256:" + "a" * 64
            image = "ghcr.io/example/application"
            environment = {
                **os.environ,
                "PATH": str(directory) + os.pathsep + os.environ["PATH"],
                "CALL_LOG": str(log),
                "FAILURE": failure,
                "TOKEN": "fixture-only",
                "GITHUB_ACTOR": "fixture",
                "IMAGE": image,
                "IMAGE_REF": image + "@" + digest,
                "DIGEST": digest,
            }
            result = subprocess.run(
                ["bash", "-e", "-c", self.script],
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result.returncode, calls, image + "@" + digest

    def test_waits_for_complete_release_and_requires_a_version(self):
        self.assertIn("needs: [version, image, release]", self.job)
        self.assertIn("outputs.next != ''", self.job)
        self.assertIn("packages: write", self.job)

    def test_promotes_the_exact_released_manifest_and_logs_out(self):
        status, calls, source = self.run_promotion()
        self.assertEqual(status, 0)
        self.assertIn(
            [
                "buildx",
                "imagetools",
                "create",
                "--prefer-index=false",
                "--tag",
                "ghcr.io/example/application:latest",
                source,
            ],
            calls,
        )
        self.assertEqual(calls[-1], ["logout", "ghcr.io"])

    def test_failed_login_prevents_promotion(self):
        status, calls, _ = self.run_promotion("login")
        self.assertNotEqual(status, 0)
        self.assertFalse(any(call[0] == "buildx" for call in calls))

    def test_failed_promotion_fails_the_job_and_logs_out(self):
        status, calls, _ = self.run_promotion("promote")
        self.assertNotEqual(status, 0)
        self.assertEqual(calls[-1], ["logout", "ghcr.io"])


if __name__ == "__main__":
    unittest.main()
