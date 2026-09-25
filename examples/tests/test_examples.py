"""Runs each integration example against a fake events endpoint on 127.0.0.1.

The examples are separate programs, so they run as subprocesses with the
environment a producer would give them. The shell examples need sh, curl and
jq; the others need the Python package in sdk/python installed.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

EXAMPLES = Path(__file__).resolve().parent.parent
KEY = "shpk1_example-test-key"


class FakeEvents:
    """Stores posted events like SignalHub, or answers with a set status."""

    def __init__(self, test: unittest.TestCase) -> None:
        self.requests: list[dict[str, Any]] = []
        self.status = 201
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                fake.requests.append(
                    {"path": self.path, "headers": dict(self.headers), "body": body}
                )
                answer = dict(body, id="0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")
                if fake.status != 201:
                    answer = {"title": "Error", "status": fake.status}
                text = json.dumps(answer).encode("utf-8")
                self.send_response(fake.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(text)))
                self.end_headers()
                self.wfile.write(text)

            def log_message(self, format: str, *args: Any) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{server.server_address[1]}"
        threading.Thread(target=server.serve_forever, daemon=True).start()
        test.addCleanup(server.server_close)
        test.addCleanup(server.shutdown)

    @property
    def events(self) -> list[dict[str, Any]]:
        for request in self.requests:
            assert request["path"] == "/api/v1/events", request["path"]
            assert request["headers"]["Authorization"] == f"Bearer {KEY}"
        return [request["body"] for request in self.requests]


class ExampleTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = FakeEvents(self)
        self.env = dict(
            os.environ, SIGNALHUB_URL=self.server.url, SIGNALHUB_API_KEY=KEY
        )
        self.env.pop("SIGNALHUB_API_KEY_FILE", None)

    def run_example(
        self, *command: str, stdin: str = "", env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            input=stdin,
            env=self.env if env is None else env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )


class RunAndNotifyTest(ExampleTest):
    script = str(EXAMPLES / "shell" / "run-and-notify.sh")

    def test_publishes_a_completed_command(self) -> None:
        result = self.run_example(self.script, "Nightly backup", "echo", "it's done")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "it's done\n")
        [event] = self.server.events
        self.assertEqual(event["category"], "COMPLETED")
        self.assertEqual(event["severity"], "NORMAL")
        self.assertEqual(event["title"], "Nightly backup succeeded")
        self.assertEqual(event["metadata"]["command"], "echo it's done")
        self.assertEqual(event["metadata"]["exitStatus"], 0)
        self.assertIn("`echo it's done` succeeded after", event["message"])
        self.assertTrue(event["context"])

    def test_publishes_a_failed_command_and_keeps_its_exit_status(self) -> None:
        result = self.run_example(self.script, "Sync", "sh", "-c", "exit 7")

        self.assertEqual(result.returncode, 7)
        [event] = self.server.events
        self.assertEqual(event["category"], "BLOCKED")
        self.assertEqual(event["severity"], "HIGH")
        self.assertEqual(event["title"], "Sync failed with exit status 7")
        self.assertEqual(event["metadata"]["exitStatus"], 7)

    def test_a_rejected_event_is_reported_without_changing_the_exit_status(
        self,
    ) -> None:
        self.server.status = 401

        result = self.run_example(self.script, "Sync", "true")

        self.assertEqual(result.returncode, 0)
        self.assertIn("could not publish to SignalHub", result.stderr)

    def test_without_configuration_nothing_runs(self) -> None:
        env = dict(self.env)
        del env["SIGNALHUB_URL"]

        result = self.run_example(self.script, "Sync", "true", env=env)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SIGNALHUB_URL", result.stderr)


class DiskUsageTest(ExampleTest):
    script = str(EXAMPLES / "disk-usage" / "check-disk-usage.sh")

    def test_publishes_when_the_threshold_is_reached(self) -> None:
        # Any file system is at least 0% full.
        result = self.run_example(self.script, tempfile.gettempdir(), "0")

        self.assertEqual(result.returncode, 0, result.stderr)
        [event] = self.server.events
        self.assertEqual(event["category"], "ACTION_REQUIRED")
        used = int(event["metadata"]["usedPercent"])
        self.assertEqual(event["severity"], "CRITICAL" if used >= 98 else "HIGH")
        self.assertEqual(event["metadata"]["thresholdPercent"], "0")
        self.assertIn(f"is {used}% full", event["title"])
        self.assertTrue(event["metadata"]["mount"].startswith("/"))

    def test_publishes_nothing_below_the_threshold(self) -> None:
        # No file system is more than 100% full.
        result = self.run_example(self.script, tempfile.gettempdir(), "101")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.server.requests, [])

    def test_fails_when_signalhub_rejects_the_event(self) -> None:
        self.server.status = 401

        result = self.run_example(self.script, tempfile.gettempdir(), "0")

        self.assertEqual(result.returncode, 1)


class GitHubActionsTest(ExampleTest):
    def step_script(self) -> str:
        """The `run:` script of the workflow's only step."""
        lines = (EXAMPLES / "github-actions" / "notify-on-failure.yml").read_text(
            encoding="utf-8"
        )
        _, block = lines.split("        run: |\n")
        return textwrap.dedent(block)

    def test_the_step_publishes_the_failed_run(self) -> None:
        env = dict(
            self.env,
            REPOSITORY="owner/repo",
            WORKFLOW="CI",
            BRANCH="feature/x",
            COMMIT="0123456789abcdef0123456789abcdef01234567",
            RUN_URL="https://github.com/owner/repo/actions/runs/1",
            RUN_NUMBER="42",
        )

        # The shell GitHub Actions runs `run:` scripts with.
        result = self.run_example(
            "bash",
            "--noprofile",
            "--norc",
            "-eo",
            "pipefail",
            "-c",
            self.step_script(),
            env=env,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        [event] = self.server.events
        self.assertEqual(event["category"], "BLOCKED")
        self.assertEqual(event["severity"], "HIGH")
        self.assertEqual(event["title"], "CI failed on feature/x")
        self.assertEqual(event["context"], "owner/repo")
        self.assertIn("CI #42 failed for 0123456789ab on feature/x", event["message"])
        self.assertEqual(event["metadata"]["runNumber"], 42)
        self.assertEqual(event["metadata"]["branch"], "feature/x")


class AgentHookTest(ExampleTest):
    script = str(EXAMPLES / "coding-agent" / "agent_hook.py")

    def hook(self, **fields: str) -> subprocess.CompletedProcess[str]:
        return self.run_example(sys.executable, self.script, stdin=json.dumps(fields))

    def test_a_waiting_agent_requires_action(self) -> None:
        result = self.hook(
            hook_event_name="Notification",
            session_id="abc123",
            cwd="/home/owner/my project",
            message="Claude needs your permission to use Bash",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        [event] = self.server.events
        self.assertEqual(event["category"], "ACTION_REQUIRED")
        self.assertEqual(event["severity"], "HIGH")
        self.assertEqual(event["title"], "Claude needs your permission to use Bash")
        self.assertEqual(event["context"], "my-project")
        self.assertEqual(
            event["metadata"],
            {
                "hook": "Notification",
                "sessionId": "abc123",
                "directory": "/home/owner/my project",
            },
        )

    def test_a_finished_agent_completed(self) -> None:
        result = self.hook(hook_event_name="Stop", cwd="/work/signalhub")

        self.assertEqual(result.returncode, 0, result.stderr)
        [event] = self.server.events
        self.assertEqual(event["category"], "COMPLETED")
        self.assertEqual(event["title"], "Agent finished in signalhub")

    def test_other_hooks_publish_nothing(self) -> None:
        result = self.hook(hook_event_name="PreToolUse", cwd="/work")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.server.requests, [])

    def test_never_fails_the_agent(self) -> None:
        self.server.status = 503

        result = self.hook(hook_event_name="Stop", cwd="/work")

        self.assertEqual(result.returncode, 0)
        self.assertIn("not published to SignalHub", result.stderr)
        self.assertEqual(
            self.run_example(sys.executable, self.script, stdin="not json").returncode,
            0,
        )


class UsageThresholdTest(ExampleTest):
    script = str(EXAMPLES / "usage-threshold" / "usage_threshold.py")

    def setUp(self) -> None:
        super().setUp()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.state = str(Path(directory.name) / "level")

    def check(self, used: str) -> subprocess.CompletedProcess[str]:
        return self.run_example(
            sys.executable,
            self.script,
            "--name=API quota",
            f"--used={used}",
            "--limit=10000",
            "--context=account-1",
            f"--state-file={self.state}",
        )

    def test_notifies_each_level_once(self) -> None:
        for used in ("1000", "8200", "8500", "10000", "12000"):
            self.assertEqual(self.check(used).returncode, 0)

        warning, exceeded = self.server.events
        self.assertEqual(warning["category"], "ACTION_REQUIRED")
        self.assertEqual(warning["severity"], "HIGH")
        self.assertEqual(warning["title"], "API quota is at 82%")
        self.assertEqual(warning["context"], "account-1")
        self.assertEqual(warning["metadata"]["level"], "warning")
        self.assertEqual(exceeded["category"], "BLOCKED")
        self.assertEqual(exceeded["severity"], "CRITICAL")
        self.assertEqual(exceeded["title"], "API quota is used up (100%)")

    def test_notifies_again_after_usage_drops(self) -> None:
        for used in ("9000", "100", "9000"):
            self.assertEqual(self.check(used).returncode, 0)

        self.assertEqual(len(self.server.events), 2)

    def test_retries_on_the_next_run_after_a_temporary_failure(self) -> None:
        self.server.status = 503
        self.assertEqual(self.check("9000").returncode, 3)
        self.server.status = 201
        self.assertEqual(self.check("9000").returncode, 0)

        self.assertEqual(len(self.server.requests), 2)

    def test_a_rejected_event_exits_1(self) -> None:
        self.server.status = 401

        self.assertEqual(self.check("9000").returncode, 1)


if __name__ == "__main__":
    unittest.main()
