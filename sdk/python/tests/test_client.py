from __future__ import annotations

import os
import socket
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from signalhub import (
    Ask,
    AuthenticationError,
    Category,
    Choice,
    ConfigurationError,
    QuestionAnsweredError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
    UnreachableError,
    ValidationError,
    Violation,
    derive_choice_ids,
)

from tests.fake_server import start

KEY = "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_secret"


def unused_url() -> str:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    return f"http://127.0.0.1:{port}"


class PublishTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = start(self)
        self.hub = SignalHub(self.server.url, KEY)

    def test_posts_the_event_with_the_api_key_and_returns_it_as_stored(self) -> None:
        event = self.hub.publish(category="INFO", severity="LOW", title="Hello")

        request = self.server.requests[0]
        self.assertEqual(request["path"], "/api/v1/events")
        self.assertEqual(request["headers"]["Authorization"], f"Bearer {KEY}")
        self.assertEqual(request["headers"]["Content-Type"], "application/json")
        self.assertEqual(
            request["body"], {"category": "INFO", "severity": "LOW", "title": "Hello"}
        )
        self.assertEqual(event["id"], "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b")
        self.assertEqual(event["title"], "Hello")

    def test_sends_every_optional_field(self) -> None:
        occurred = datetime(2026, 9, 25, 16, 3, tzinfo=timezone(timedelta(hours=2)))
        self.hub.publish(
            category=Category.ACTION_REQUIRED,
            severity=Severity.HIGH,
            title="Review required",
            message="A human gate is waiting.",
            context="github.com/owner/repo",
            metadata={"run": 42, "nested": {"ok": True}},
            link="https://github.com/owner/repo/pull/7",
            occurred_at=occurred,
        )

        self.assertEqual(
            self.server.requests[0]["body"],
            {
                "category": "ACTION_REQUIRED",
                "severity": "HIGH",
                "title": "Review required",
                "message": "A human gate is waiting.",
                "context": "github.com/owner/repo",
                "metadata": {"run": 42, "nested": {"ok": True}},
                "link": "https://github.com/owner/repo/pull/7",
                "occurredAt": "2026-09-25T16:03:00+02:00",
            },
        )

    def test_sends_no_idempotency_key_unless_given(self) -> None:
        self.hub.publish(category="INFO", severity="LOW", title="t")

        self.assertNotIn("Idempotency-Key", self.server.requests[0]["headers"])

    def test_sends_the_idempotency_key_as_a_header(self) -> None:
        self.hub.publish(
            category="INFO", severity="LOW", title="t", idempotency_key="run-1842"
        )

        self.assertEqual(
            self.server.requests[0]["headers"]["Idempotency-Key"], "run-1842"
        )

    def test_a_repeat_answered_with_200_returns_the_stored_event(self) -> None:
        stored = {"id": "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b", "title": "t"}
        self.server.respond(200, stored)

        event = self.hub.publish(
            category="INFO", severity="LOW", title="t", idempotency_key="k"
        )

        self.assertEqual(event, stored)

    def test_a_key_used_for_another_event_is_a_rejection(self) -> None:
        self.server.respond(
            422,
            {
                "title": "Idempotency key already used",
                "status": 422,
                "violations": [
                    {
                        "field": "Idempotency-Key",
                        "message": "was already used for a different event",
                    }
                ],
            },
        )

        with self.assertRaises(ValidationError) as raised:
            self.hub.publish(
                category="INFO", severity="LOW", title="t", idempotency_key="k"
            )

        self.assertFalse(raised.exception.temporary)
        self.assertIn("Idempotency-Key: was already used", str(raised.exception))

    def test_refuses_keys_that_cannot_be_sent_in_a_header(self) -> None:
        for key in ["", "line\nbreak", "caf\u00e9"]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.hub.publish(
                    category="INFO", severity="LOW", title="t", idempotency_key=key
                )
        self.assertEqual(self.server.requests, [])

    def test_normalizes_category_and_severity_names(self) -> None:
        self.hub.publish(category=" action-required ", severity="critical", title="t")

        body = self.server.requests[0]["body"]
        self.assertEqual(
            (body["category"], body["severity"]), ("ACTION_REQUIRED", "CRITICAL")
        )

    def test_leaves_values_it_does_not_know_to_the_server(self) -> None:
        self.hub.publish(category="future_category", severity="NORMAL", title="t")

        self.assertEqual(self.server.requests[0]["body"]["category"], "FUTURE_CATEGORY")

    def test_leaves_checking_the_link_to_the_server(self) -> None:
        self.hub.publish(
            category="INFO", severity="LOW", title="t", link="HTTPS://Example.com/a%20b"
        )

        self.assertEqual(
            self.server.requests[0]["body"]["link"], "HTTPS://Example.com/a%20b"
        )

    def test_passes_timestamp_strings_through(self) -> None:
        self.hub.publish(
            category="INFO",
            severity="LOW",
            title="t",
            occurred_at="2026-09-25T14:03:00Z",
        )

        self.assertEqual(
            self.server.requests[0]["body"]["occurredAt"], "2026-09-25T14:03:00Z"
        )

    def test_rejects_timestamps_without_an_offset(self) -> None:
        with self.assertRaises(ValueError):
            self.hub.publish(
                category="INFO",
                severity="LOW",
                title="t",
                occurred_at=datetime(2026, 9, 25),  # noqa: DTZ001 - naive on purpose
            )
        self.assertEqual(self.server.requests, [])

    def test_joins_the_path_to_a_base_address_with_a_prefix(self) -> None:
        SignalHub(self.server.url + "/signalhub/", KEY).publish(
            category="INFO", severity="LOW", title="t"
        )

        self.assertEqual(self.server.requests[0]["path"], "/signalhub/api/v1/events")


class ErrorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = start(self)
        self.hub = SignalHub(self.server.url, KEY)

    def publish(self) -> None:
        self.hub.publish(category="INFO", severity="LOW", title="t")

    def test_validation_errors_carry_the_violations(self) -> None:
        self.server.respond(
            400,
            {
                "title": "Bad Request",
                "status": 400,
                "violations": [
                    {"field": "title", "message": "must not be blank"},
                    {"field": "", "message": "unknown field"},
                ],
            },
        )

        with self.assertRaises(ValidationError) as caught:
            self.publish()

        error = caught.exception
        self.assertEqual(error.status, 400)
        self.assertFalse(error.temporary)
        self.assertEqual(
            error.violations,
            [Violation("title", "must not be blank"), Violation("", "unknown field")],
        )
        self.assertEqual(
            str(error),
            "400 Bad Request: the event was rejected: title: must not be blank; unknown field",
        )

    def test_a_body_too_large_is_a_rejection(self) -> None:
        self.server.respond(413)

        with self.assertRaises(ValidationError) as caught:
            self.publish()
        self.assertEqual(caught.exception.status, 413)
        self.assertEqual(caught.exception.violations, [])

    def test_unauthorized_is_an_authentication_error(self) -> None:
        self.server.respond(
            401, {"title": "Unauthorized", "status": 401, "violations": []}
        )

        with self.assertRaises(AuthenticationError) as caught:
            self.publish()
        self.assertFalse(caught.exception.temporary)
        self.assertIn("API key", str(caught.exception))

    def test_server_errors_are_temporary(self) -> None:
        for status in (500, 502, 503, 429):
            with self.subTest(status=status):
                self.server.respond_raw(status, "<html>proxy error</html>")
                with self.assertRaises(RequestError) as caught:
                    self.publish()
                self.assertTrue(caught.exception.temporary)
                self.assertNotIsInstance(caught.exception, ValidationError)

    def test_not_found_points_at_the_url(self) -> None:
        self.server.respond(404)

        with self.assertRaises(RequestError) as caught:
            self.publish()
        self.assertNotIsInstance(caught.exception, ValidationError)
        self.assertIn("base address", str(caught.exception))

    def test_redirects_are_reported_not_followed(self) -> None:
        self.server.headers["Location"] = "https://elsewhere.example/api/v1/events"
        for status in (301, 302, 307, 308):
            with self.subTest(status=status):
                self.server.respond(status)
                with self.assertRaises(RequestError) as caught:
                    self.publish()
                self.assertEqual(caught.exception.status, status)
                self.assertFalse(caught.exception.temporary)
                self.assertIn(
                    "redirected to https://elsewhere.example", str(caught.exception)
                )
        self.assertEqual(len(self.server.requests), 4)

    def test_a_success_that_is_not_json_is_an_error(self) -> None:
        self.server.respond_raw(201, "not json")

        with self.assertRaises(SignalHubError) as caught:
            self.publish()
        self.assertIn("did not answer with JSON", str(caught.exception))

    def test_an_unreachable_server_is_reported(self) -> None:
        with self.assertRaises(UnreachableError):
            SignalHub(unused_url(), KEY).publish(
                category="INFO", severity="LOW", title="t"
            )


class ConfigurationTest(unittest.TestCase):
    def test_requires_an_http_url(self) -> None:
        with self.assertRaises(ConfigurationError):
            SignalHub("localhost:8080", KEY)

    def test_requires_a_key_that_fits_in_a_header(self) -> None:
        for key in ("", "shpk1_a b", "shpk1_ab\n", "shpk1_\x00"):
            with self.subTest(key=key), self.assertRaises(ConfigurationError):
                SignalHub("http://localhost:8080", key)

    def test_reads_url_and_key_from_the_environment(self) -> None:
        server = start(self)
        env = {"SIGNALHUB_URL": server.url, "SIGNALHUB_API_KEY": KEY}
        with mock.patch.dict(os.environ, env, clear=True):
            SignalHub.from_env().publish(category="INFO", severity="LOW", title="t")
        self.assertEqual(
            server.requests[0]["headers"]["Authorization"], f"Bearer {KEY}"
        )

    def test_reads_the_key_from_a_file(self) -> None:
        server = start(self)
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "key")
            with open(path, "w", encoding="utf-8") as file:
                file.write(KEY + "\n")
            env = {"SIGNALHUB_URL": server.url, "SIGNALHUB_API_KEY_FILE": path}
            with mock.patch.dict(os.environ, env, clear=True):
                SignalHub.from_env().publish(category="INFO", severity="LOW", title="t")
        self.assertEqual(
            server.requests[0]["headers"]["Authorization"], f"Bearer {KEY}"
        )

    def test_missing_settings_are_named(self) -> None:
        with (
            mock.patch.dict(os.environ, {}, clear=True),
            self.assertRaisesRegex(ConfigurationError, "SIGNALHUB_URL"),
        ):
            SignalHub.from_env()
        with (
            mock.patch.dict(os.environ, {"SIGNALHUB_URL": "http://x"}, clear=True),
            self.assertRaisesRegex(ConfigurationError, "SIGNALHUB_API_KEY"),
        ):
            SignalHub.from_env()

    def test_an_unreadable_or_empty_key_file_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            empty = os.path.join(directory, "empty")
            open(empty, "w").close()
            for path, reason in (
                (empty, "empty"),
                (os.path.join(directory, "none"), "cannot"),
            ):
                env = {"SIGNALHUB_URL": "http://x", "SIGNALHUB_API_KEY_FILE": path}
                with (
                    self.subTest(reason=reason),
                    mock.patch.dict(os.environ, env, clear=True),
                    self.assertRaisesRegex(ConfigurationError, reason),
                ):
                    SignalHub.from_env()


if __name__ == "__main__":
    unittest.main()


QUESTION = {"choices": [{"id": "merge", "label": "Merge"}], "multiple": False}
OPEN = {"state": "OPEN", "answer": None}
ANSWERED = {
    "state": "ANSWERED",
    "answer": {"choices": ["merge"], "text": None, "by": {"id": "u", "name": "Ana"}},
}
CLOSED = {"state": "CLOSED", "closedBy": "PRODUCER", "closeNote": "elsewhere"}
EVENT_ID = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"


class AskTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = start(self)
        self.hub = SignalHub(self.server.url, KEY)

    def publish(self, ask: object) -> dict:
        return self.hub.publish(
            category="action-required", severity="high", title="Merge it?", ask=ask
        )

    def test_publishes_a_question_with_only_what_was_given(self) -> None:
        self.publish(
            Ask([Choice("merge", "Merge", "Squash now"), Choice("hold", "Hold")])
        )

        self.assertEqual(
            self.server.requests[0]["body"]["ask"],
            {
                "choices": [
                    {"id": "merge", "label": "Merge", "description": "Squash now"},
                    {"id": "hold", "label": "Hold"},
                ]
            },
        )

    def test_sends_multiple_text_style_and_closing_time_when_given(self) -> None:
        closes = datetime(2026, 10, 17, 9, 0, tzinfo=timezone.utc)

        self.publish(
            Ask(
                [Choice("a", "A"), Choice("b", "B")],
                multiple=True,
                text="optional",
                text_style="other",
                closes_at=closes,
            )
        )

        ask = self.server.requests[0]["body"]["ask"]
        self.assertIs(ask["multiple"], True)
        self.assertEqual(ask["text"], "OPTIONAL")
        self.assertEqual(ask["textStyle"], "OTHER")
        self.assertEqual(ask["closesAt"], "2026-10-17T09:00:00+00:00")

    def test_a_closing_time_needs_an_offset(self) -> None:
        with self.assertRaisesRegex(ValueError, "closes_at must be timezone-aware"):
            self.publish(Ask(closes_at=datetime(2026, 10, 17, 9, 0)))  # noqa: DTZ001

    def test_a_question_given_as_json_is_sent_as_it_is(self) -> None:
        self.publish({"text": "REQUIRED"})

        self.assertEqual(self.server.requests[0]["body"]["ask"], {"text": "REQUIRED"})

    def test_derives_the_ids_of_choices_that_have_none(self) -> None:
        ids = derive_choice_ids(
            [
                Choice(None, "Merge now!"),
                Choice(None, "Ação  Rápida"),
                Choice(None, "???"),
                Choice(None, "merge NOW"),
                Choice("explicit", "Explicit"),
                Choice(None, "x" * 100),
            ]
        )

        self.assertEqual(
            ids,
            [
                "merge-now",
                "acao-rapida",
                "choice-3",
                "merge-now-2",
                "explicit",
                "x" * 60,
            ],
        )

    def test_a_derived_id_avoids_an_explicit_one(self) -> None:
        self.assertEqual(
            derive_choice_ids([Choice(None, "Hold"), Choice("hold", "Wait")]),
            ["hold-2", "hold"],
        )

    def test_an_event_without_a_question_sends_no_ask(self) -> None:
        self.publish(None)

        self.assertNotIn("ask", self.server.requests[0]["body"])


class AnswerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.server = start(self)
        self.hub = SignalHub(self.server.url, KEY)
        self.sleeps: list[float] = []
        self.now = 0.0

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.now += seconds

    def wait(self, timeout: float | None = None) -> dict:
        return self.hub.wait_answer(
            EVENT_ID, timeout, sleep=self.sleep, clock=self.clock
        )

    def test_reads_the_answer_with_the_producers_key(self) -> None:
        self.server.respond(200, ANSWERED)

        state = self.hub.read_answer(EVENT_ID)

        self.assertEqual(state, ANSWERED)
        request = self.server.requests[0]
        self.assertEqual(request["method"], "GET")
        self.assertEqual(request["path"], f"/api/v1/events/{EVENT_ID}/answer")
        self.assertEqual(request["headers"]["Authorization"], f"Bearer {KEY}")

    def test_a_held_read_asks_the_server_to_wait(self) -> None:
        self.server.respond(200, OPEN)

        self.hub.read_answer(EVENT_ID, wait=60)

        self.assertEqual(
            self.server.requests[0]["path"], f"/api/v1/events/{EVENT_ID}/answer?wait=60"
        )

    def test_a_wait_longer_than_the_server_holds_is_refused_here(self) -> None:
        with self.assertRaises(ValueError):
            self.hub.read_answer(EVENT_ID, wait=61)

    def test_wait_answer_returns_at_once_when_answered(self) -> None:
        self.server.respond(200, ANSWERED)

        self.assertEqual(self.wait(), ANSWERED)
        self.assertEqual(len(self.server.requests), 1)
        self.assertTrue(self.server.requests[0]["path"].endswith("?wait=60"))

    def test_wait_answer_returns_a_closed_question_too(self) -> None:
        self.server.respond(200, CLOSED)

        self.assertEqual(self.wait(), CLOSED)

    def test_wait_answer_pauses_five_seconds_after_an_early_open(self) -> None:
        self.server.respond(200, OPEN)
        self.server.respond(200, ANSWERED)

        self.assertEqual(self.wait(), ANSWERED)
        self.assertEqual(self.sleeps, [5.0])

    def test_wait_answer_does_not_pause_after_a_full_wait(self) -> None:
        # The fake answers instantly, so make the clock say a minute passed.
        ticks = iter([0.0, 61.0, 61.0, 61.0, 61.0, 61.0])
        self.server.respond(200, OPEN)
        self.server.respond(200, ANSWERED)

        state = self.hub.wait_answer(
            EVENT_ID, None, sleep=self.sleep, clock=lambda: next(ticks)
        )

        self.assertEqual(state, ANSWERED)
        self.assertEqual(self.sleeps, [])

    def test_wait_answer_retries_temporary_errors_after_five_seconds(self) -> None:
        self.server.respond(502, {"title": "Bad Gateway"})
        self.server.respond(503)
        self.server.respond(200, ANSWERED)

        self.assertEqual(self.wait(), ANSWERED)
        self.assertEqual(self.sleeps, [5.0, 5.0])

    def test_wait_answer_retries_when_the_server_is_unreachable(self) -> None:
        hub = SignalHub(unused_url(), KEY)
        attempts = 0

        def sleep(seconds: float) -> None:
            nonlocal attempts
            attempts += 1
            self.now += seconds

        with self.assertRaises(UnreachableError):
            hub.wait_answer(EVENT_ID, 12, sleep=sleep, clock=self.clock)
        self.assertEqual(attempts, 2)

    def test_wait_answer_raises_a_missing_event_at_once(self) -> None:
        self.server.respond(404, {"title": "Event not found", "status": 404})

        with self.assertRaises(RequestError) as caught:
            self.wait()

        self.assertEqual(caught.exception.status, 404)
        self.assertEqual(self.sleeps, [])

    def test_wait_answer_raises_a_rejected_key_at_once(self) -> None:
        self.server.respond(401, {"title": "Unauthorized", "status": 401})

        with self.assertRaises(AuthenticationError):
            self.wait()

    def test_wait_answer_returns_the_open_state_when_its_timeout_passes(self) -> None:
        for _ in range(10):
            self.server.respond(200, OPEN)

        state = self.wait(12)

        self.assertEqual(state["state"], "OPEN")
        # Asks for what is left, never for more than the timeout allows.
        self.assertTrue(self.server.requests[0]["path"].endswith("?wait=12"))

    def test_close_question_posts_the_note(self) -> None:
        self.server.respond(200, CLOSED)

        state = self.hub.close_question(EVENT_ID, "elsewhere")

        self.assertEqual(state, CLOSED)
        request = self.server.requests[0]
        self.assertEqual(request["method"], "POST")
        self.assertEqual(request["path"], f"/api/v1/events/{EVENT_ID}/answer/close")
        self.assertEqual(request["body"], {"note": "elsewhere"})

    def test_close_question_without_a_note_sends_no_body(self) -> None:
        self.server.respond(200, CLOSED)

        self.hub.close_question(EVENT_ID)

        self.assertIsNone(self.server.requests[0]["body"])
        self.assertNotIn("Content-Type", self.server.requests[0]["headers"])

    def test_close_question_raises_the_answer_when_someone_answered_first(self) -> None:
        self.server.respond(
            409,
            {
                "title": "The question is already answered",
                "status": 409,
                "violations": [],
                "question": ANSWERED,
            },
        )

        with self.assertRaises(QuestionAnsweredError) as caught:
            self.hub.close_question(EVENT_ID)

        self.assertEqual(caught.exception.state, ANSWERED)
        self.assertEqual(caught.exception.status, 409)

    def test_close_question_on_an_event_that_asks_nothing_is_a_plain_rejection(
        self,
    ) -> None:
        self.server.respond(409, {"title": "The event asks nothing", "status": 409})

        with self.assertRaises(ValidationError):
            self.hub.close_question(EVENT_ID)

    def test_an_event_id_is_escaped_in_the_path(self) -> None:
        self.server.respond(404, {"title": "Event not found"})

        with self.assertRaises(RequestError):
            self.hub.read_answer("../admin")

        self.assertEqual(
            self.server.requests[0]["path"], "/api/v1/events/..%2Fadmin/answer"
        )
