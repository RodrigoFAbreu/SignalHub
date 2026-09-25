from __future__ import annotations

import os
import socket
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from signalhub import (
    AuthenticationError,
    Category,
    ConfigurationError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
    UnreachableError,
    ValidationError,
    Violation,
)

from tests.fake_server import FakeSignalHub, start

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
                "occurredAt": "2026-09-25T16:03:00+02:00",
            },
        )

    def test_normalizes_category_and_severity_names(self) -> None:
        self.hub.publish(category=" action-required ", severity="critical", title="t")

        body = self.server.requests[0]["body"]
        self.assertEqual(
            (body["category"], body["severity"]), ("ACTION_REQUIRED", "CRITICAL")
        )

    def test_leaves_values_it_does_not_know_to_the_server(self) -> None:
        self.hub.publish(category="future_category", severity="NORMAL", title="t")

        self.assertEqual(self.server.requests[0]["body"]["category"], "FUTURE_CATEGORY")

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
                occurred_at=datetime(2026, 9, 25),
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
        with FakeSignalHub() as server:
            env = {"SIGNALHUB_URL": server.url, "SIGNALHUB_API_KEY": KEY}
            with mock.patch.dict(os.environ, env, clear=True):
                SignalHub.from_env().publish(category="INFO", severity="LOW", title="t")
            self.assertEqual(
                server.requests[0]["headers"]["Authorization"], f"Bearer {KEY}"
            )

    def test_reads_the_key_from_a_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "key")
            with open(path, "w", encoding="utf-8") as file:
                file.write(KEY + "\n")
            with FakeSignalHub() as server:
                env = {"SIGNALHUB_URL": server.url, "SIGNALHUB_API_KEY_FILE": path}
                with mock.patch.dict(os.environ, env, clear=True):
                    SignalHub.from_env().publish(
                        category="INFO", severity="LOW", title="t"
                    )
                self.assertEqual(
                    server.requests[0]["headers"]["Authorization"], f"Bearer {KEY}"
                )

    def test_missing_settings_are_named(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "SIGNALHUB_URL"):
                SignalHub.from_env()
        with mock.patch.dict(os.environ, {"SIGNALHUB_URL": "http://x"}, clear=True):
            with self.assertRaisesRegex(ConfigurationError, "SIGNALHUB_API_KEY"):
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
                ):
                    with self.assertRaisesRegex(ConfigurationError, reason):
                        SignalHub.from_env()


if __name__ == "__main__":
    unittest.main()
