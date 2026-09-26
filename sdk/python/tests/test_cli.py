from __future__ import annotations

import contextlib
import importlib.metadata
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from signalhub.cli import main, version

from tests.fake_server import start
from tests.test_client import KEY, unused_url


class SendTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = start(self)
        self.env = {"SIGNALHUB_URL": self.server.url, "SIGNALHUB_API_KEY": KEY}

    def send(
        self, *args: str, env: dict[str, str] | None = None, stdin: str = ""
    ) -> int:
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        return main(
            ["send", *args],
            environ=self.env if env is None else env,
            stdin=io.StringIO(stdin),
            stdout=self.stdout,
            stderr=self.stderr,
        )

    def test_publishes_and_prints_the_event_id(self) -> None:
        status = self.send(
            "--category", "info", "--severity", "low", "--title", "Hello"
        )

        self.assertEqual(status, 0)
        self.assertEqual(
            self.stdout.getvalue(), "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b\n"
        )
        self.assertEqual(
            self.server.requests[0]["body"],
            {"category": "INFO", "severity": "LOW", "title": "Hello"},
        )

    def test_sends_every_option(self) -> None:
        status = self.send(
            "--category=action_required",
            "--severity=HIGH",
            "--title=Implementation review required",
            "--message=A human gate is waiting.",
            "--context=github.com/owner/repo",
            '--metadata={"run": 42, "branch": "main"}',
            "--meta=branch=feature",
            "--meta=link=https://example.com/?a=b",
            "--occurred-at=2026-09-25T14:03:00Z",
            "--idempotency-key=run-42",
        )

        self.assertEqual(status, 0, self.stderr.getvalue())
        self.assertEqual(
            self.server.requests[0]["headers"]["Idempotency-Key"], "run-42"
        )
        self.assertEqual(
            self.server.requests[0]["body"],
            {
                "category": "ACTION_REQUIRED",
                "severity": "HIGH",
                "title": "Implementation review required",
                "message": "A human gate is waiting.",
                "context": "github.com/owner/repo",
                "metadata": {
                    "run": 42,
                    "branch": "feature",
                    "link": "https://example.com/?a=b",
                },
                "occurredAt": "2026-09-25T14:03:00Z",
            },
        )

    def test_reads_the_message_from_standard_input(self) -> None:
        self.send(
            "--category=INFO",
            "--severity=LOW",
            "--title=t",
            "--message=-",
            stdin="line\n",
        )

        self.assertEqual(self.server.requests[0]["body"]["message"], "line\n")

    def test_prints_the_stored_event_as_json(self) -> None:
        self.send("--category=INFO", "--severity=LOW", "--title=t", "--json")

        event = json.loads(self.stdout.getvalue())
        self.assertEqual(event["producer"]["name"], "test")
        self.assertEqual(event["title"], "t")

    def test_reads_the_key_from_a_file_before_the_environment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "key")
            with open(path, "w", encoding="utf-8") as file:
                file.write("shpk1_from_file\n")
            status = self.send(
                "--category=INFO",
                "--severity=LOW",
                "--title=t",
                f"--api-key-file={path}",
                f"--url={self.server.url}",
                env={"SIGNALHUB_API_KEY": KEY},
            )

        self.assertEqual(status, 0, self.stderr.getvalue())
        self.assertEqual(
            self.server.requests[0]["headers"]["Authorization"],
            "Bearer shpk1_from_file",
        )

    def test_a_rejected_event_exits_1_with_the_violations(self) -> None:
        self.server.respond(
            400,
            {
                "title": "Bad Request",
                "status": 400,
                "violations": [{"field": "category", "message": "must be one of ..."}],
            },
        )

        status = self.send("--category=NOPE", "--severity=LOW", "--title=t")

        self.assertEqual(status, 1)
        self.assertEqual(self.stdout.getvalue(), "")
        self.assertIn("category: must be one of ...", self.stderr.getvalue())

    def test_an_invalid_key_exits_1(self) -> None:
        self.server.respond(
            401, {"title": "Unauthorized", "status": 401, "violations": []}
        )

        self.assertEqual(self.send("--category=INFO", "--severity=LOW", "--title=t"), 1)
        self.assertIn("401 Unauthorized", self.stderr.getvalue())

    def test_temporary_failures_exit_3(self) -> None:
        self.server.respond(503)
        self.assertEqual(self.send("--category=INFO", "--severity=LOW", "--title=t"), 3)

        env = {"SIGNALHUB_URL": unused_url(), "SIGNALHUB_API_KEY": KEY}
        self.assertEqual(
            self.send("--category=INFO", "--severity=LOW", "--title=t", env=env), 3
        )
        self.assertIn("cannot reach SignalHub", self.stderr.getvalue())

    def test_usage_and_configuration_errors_exit_2_without_sending(self) -> None:
        cases = {
            "no url": (["--title=t"], {"SIGNALHUB_API_KEY": KEY}, "SIGNALHUB_URL"),
            "no key": (["--title=t"], {"SIGNALHUB_URL": self.server.url}, "no API key"),
            "bad json": (["--title=t", "--metadata={"], self.env, "not valid JSON"),
            "not an object": (["--title=t", "--metadata=[1]"], self.env, "JSON object"),
            "bad pair": (["--title=t", "--meta=novalue"], self.env, "KEY=VALUE"),
            "no title": ([], self.env, "--title"),
            "empty key": (["--title=t", "--idempotency-key="], self.env, "ASCII"),
        }
        for name, (args, env, expected) in cases.items():
            with self.subTest(name):
                with mock.patch("sys.stderr", new=io.StringIO()) as parser_stderr:
                    status = self.send(
                        "--category=INFO", "--severity=LOW", *args, env=env
                    )
                self.assertEqual(status, 2)
                self.assertIn(
                    expected, self.stderr.getvalue() + parser_stderr.getvalue()
                )
        self.assertEqual(self.server.requests, [])


class CommandTest(unittest.TestCase):
    def test_runs_as_a_module_and_documents_the_exit_status(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "signalhub", "send", "--help"],
            capture_output=True,
            text=True,
            check=True,
        )

        self.assertIn("--category", result.stdout)
        self.assertIn("SIGNALHUB_API_KEY", result.stdout)


class VersionTest(unittest.TestCase):
    def test_a_release_build_reports_its_signalhub_version(self) -> None:
        with mock.patch("importlib.metadata.version", return_value="1.2.3"):
            self.assertEqual(version(), "SignalHub 1.2.3")

    def test_any_other_build_reports_a_development_build(self) -> None:
        with mock.patch("importlib.metadata.version", return_value="0.0.0.dev0"):
            self.assertEqual(version(), "SignalHub development build")
        missing = importlib.metadata.PackageNotFoundError("signalhub")
        with mock.patch("importlib.metadata.version", side_effect=missing):
            self.assertEqual(version(), "SignalHub development build")

    def test_the_command_prints_its_version_without_a_subcommand(self) -> None:
        stdout = io.StringIO()
        with (
            mock.patch("importlib.metadata.version", return_value="1.2.3"),
            contextlib.redirect_stdout(stdout),
        ):
            status = main(["--version"])

        self.assertEqual(status, 0)
        self.assertEqual(stdout.getvalue(), "SignalHub 1.2.3\n")

    def test_an_install_from_the_repository_is_a_development_build(self) -> None:
        # The tests run against `pip install ./sdk/python`, which is not a
        # release's build.
        result = subprocess.run(
            [sys.executable, "-m", "signalhub", "--version"],
            capture_output=True,
            text=True,
            check=True,
        )

        self.assertEqual(result.stdout, "SignalHub development build\n")
        self.assertEqual(importlib.metadata.version("signalhub"), "0.0.0.dev0")


if __name__ == "__main__":
    unittest.main()
