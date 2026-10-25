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
from datetime import datetime, timezone
from unittest import mock

from signalhub.cli import main, version

from tests.fake_server import start
from tests.test_client import KEY, unused_url


class SendBase(unittest.TestCase):
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


class SendTest(SendBase):
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
            "--link=https://github.com/owner/repo/actions/runs/42",
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
                "link": "https://github.com/owner/repo/actions/runs/42",
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


class AskOptionsTest(SendBase):
    def ask(self, *args: str) -> dict:
        status = self.send(
            "--category=action-required", "--severity=high", "--title=Merge?", *args
        )
        self.assertEqual(status, 0, self.stderr.getvalue())
        return self.server.requests[0]["body"]["ask"]

    def test_a_plain_send_asks_nothing(self) -> None:
        self.send("--category=INFO", "--severity=LOW", "--title=t")

        self.assertNotIn("ask", self.server.requests[0]["body"])

    def test_choices_with_ids_and_descriptions(self) -> None:
        ask = self.ask(
            "--choice=merge=Merge",
            "--choice-description=merge=Squash-merge now",
            "--choice=hold=Hold",
        )

        self.assertEqual(
            ask,
            {
                "choices": [
                    {
                        "id": "merge",
                        "label": "Merge",
                        "description": "Squash-merge now",
                    },
                    {"id": "hold", "label": "Hold"},
                ]
            },
        )

    def test_a_choice_without_an_id_gets_one_from_its_label(self) -> None:
        ask = self.ask("--choice=Merge now", "--choice=Restart = now?")

        self.assertEqual(
            [(c["id"], c["label"]) for c in ask["choices"]],
            [("merge-now", "Merge now"), ("restart-now", "Restart = now?")],
        )

    def test_a_description_may_name_a_derived_id(self) -> None:
        ask = self.ask("--choice=Merge now", "--choice-description=merge-now=Do it")

        self.assertEqual(ask["choices"][0]["description"], "Do it")

    def test_multiple_text_and_text_style(self) -> None:
        ask = self.ask(
            "--choice=a=A",
            "--choice=b=B",
            "--multiple",
            "--text=optional",
            "--text-style=other",
        )

        self.assertIs(ask["multiple"], True)
        self.assertEqual(ask["text"], "OPTIONAL")
        self.assertEqual(ask["textStyle"], "OTHER")

    def test_a_typed_question_has_no_choices(self) -> None:
        ask = self.ask("--text=required")

        self.assertEqual(ask, {"choices": [], "text": "REQUIRED"})

    def test_closes_in_becomes_a_time_that_far_ahead(self) -> None:
        before = datetime.now(timezone.utc)

        ask = self.ask("--choice=a=A", "--closes-in=2h")

        closes = datetime.fromisoformat(ask["closesAt"])
        self.assertAlmostEqual((closes - before).total_seconds(), 7200, delta=30)

    def test_bad_question_options_exit_2_without_sending(self) -> None:
        cases = {
            "unit": (["--choice=a=A", "--closes-in=2w"], "s, m, h or d"),
            "number": (["--choice=a=A", "--closes-in=soon"], "s, m, h or d"),
            "pair": (["--choice=a=A", "--choice-description=a"], "ID=TEXT"),
            "unknown id": (
                ["--choice=a=A", "--choice-description=b=text"],
                "which no --choice has",
            ),
            "text": (["--choice=a=A", "--text=maybe"], "invalid choice"),
        }
        for name, (args, expected) in cases.items():
            with self.subTest(name):
                with mock.patch("sys.stderr", new=io.StringIO()) as parser_stderr:
                    status = self.send(
                        "--category=INFO", "--severity=LOW", "--title=t", *args
                    )
                self.assertEqual(status, 2)
                self.assertIn(
                    expected, self.stderr.getvalue() + parser_stderr.getvalue()
                )
        self.assertEqual(self.server.requests, [])


EVENT = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"
ANSWERED = {
    "state": "ANSWERED",
    "answer": {"choices": ["merge", "hold"], "text": "after lunch"},
}
CHOICE_ONLY = {"state": "ANSWERED", "answer": {"choices": ["merge"], "text": None}}
TYPED = {"state": "ANSWERED", "answer": {"choices": [], "text": "yes"}}
CLOSED = {
    "state": "CLOSED",
    "closedBy": "PRODUCER",
    "closedAt": "2026-10-25T10:00:00Z",
    "closeNote": "Answered in the session",
}


class QuestionCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = start(self)
        self.env = {"SIGNALHUB_URL": self.server.url, "SIGNALHUB_API_KEY": KEY}

    def run_command(self, *args: str) -> int:
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        return main(
            list(args),
            environ=self.env,
            stdin=io.StringIO(),
            stdout=self.stdout,
            stderr=self.stderr,
        )

    def test_wait_answer_prints_the_choice_ids_then_the_text(self) -> None:
        self.server.respond(200, ANSWERED)

        status = self.run_command("wait-answer", EVENT)

        self.assertEqual(status, 0)
        self.assertEqual(self.stdout.getvalue(), "merge\nhold\n\nafter lunch\n")

    def test_wait_answer_prints_only_the_ids_without_text(self) -> None:
        self.server.respond(200, CHOICE_ONLY)

        self.run_command("wait-answer", EVENT)

        self.assertEqual(self.stdout.getvalue(), "merge\n")

    def test_wait_answer_prints_an_empty_line_before_a_typed_answer(self) -> None:
        self.server.respond(200, TYPED)

        self.run_command("wait-answer", EVENT)

        self.assertEqual(self.stdout.getvalue(), "\nyes\n")

    def test_wait_answer_json_prints_the_state(self) -> None:
        self.server.respond(200, ANSWERED)

        status = self.run_command("wait-answer", EVENT, "--json")

        self.assertEqual(status, 0)
        self.assertEqual(json.loads(self.stdout.getvalue()), ANSWERED)

    def test_a_closed_question_exits_5_and_json_carries_how(self) -> None:
        self.server.respond(200, CLOSED)

        status = self.run_command("wait-answer", EVENT, "--json")

        self.assertEqual(status, 5)
        state = json.loads(self.stdout.getvalue())
        self.assertEqual(state["closedBy"], "PRODUCER")
        self.assertEqual(state["closeNote"], "Answered in the session")
        self.assertIn("closed", self.stderr.getvalue())

    def test_a_closed_question_says_so_without_json(self) -> None:
        self.server.respond(200, CLOSED)

        status = self.run_command("wait-answer", EVENT)

        self.assertEqual(status, 5)
        self.assertEqual(self.stdout.getvalue(), "")
        self.assertIn(
            "by the producer: Answered in the session", self.stderr.getvalue()
        )

    def test_its_own_timeout_exits_6(self) -> None:
        self.server.respond(200, {"state": "OPEN"})
        self.server.respond(200, {"state": "OPEN"})

        with mock.patch("time.sleep"):
            status = self.run_command("wait-answer", EVENT, "--timeout=1s")

        self.assertEqual(status, 6)
        self.assertTrue(self.server.requests[0]["path"].endswith("?wait=1"))

    def test_a_missing_event_exits_1(self) -> None:
        self.server.respond(404, {"title": "Event not found", "status": 404})

        self.assertEqual(self.run_command("wait-answer", EVENT), 1)

    def test_a_bad_timeout_exits_2(self) -> None:
        self.assertEqual(self.run_command("wait-answer", EVENT, "--timeout=soon"), 2)
        self.assertEqual(self.server.requests, [])

    def test_a_failing_server_exits_3_when_the_timeout_passes(self) -> None:
        self.server.respond(503)

        with mock.patch("time.sleep"):
            status = self.run_command("wait-answer", EVENT, "--timeout=2s")

        self.assertEqual(status, 3)

    def test_close_question_exits_0_and_sends_the_note(self) -> None:
        self.server.respond(200, CLOSED)

        status = self.run_command("close-question", EVENT, "--note", "elsewhere")

        self.assertEqual(status, 0)
        request = self.server.requests[0]
        self.assertEqual(request["path"], f"/api/v1/events/{EVENT}/answer/close")
        self.assertEqual(request["body"], {"note": "elsewhere"})

    def test_close_question_exits_0_when_the_time_closed_it_already(self) -> None:
        self.server.respond(200, {**CLOSED, "closedBy": "TIME"})

        self.assertEqual(self.run_command("close-question", EVENT), 0)

    def test_close_question_exits_7_and_prints_the_answer_given_first(self) -> None:
        self.server.respond(
            409,
            {
                "title": "The question is already answered",
                "status": 409,
                "violations": [],
                "question": ANSWERED,
            },
        )

        status = self.run_command("close-question", EVENT)

        self.assertEqual(status, 7)
        self.assertEqual(self.stdout.getvalue(), "merge\nhold\n\nafter lunch\n")

    def test_close_question_on_a_missing_event_exits_1(self) -> None:
        self.server.respond(404, {"title": "Event not found", "status": 404})

        self.assertEqual(self.run_command("close-question", EVENT), 1)


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
