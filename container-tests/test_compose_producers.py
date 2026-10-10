"""Producers, their keys and the events they publish, on the Compose stack.

Old steps "Register a producer through the management API", "Publishing
without a valid key is rejected", "A published event survives a backend
restart", "The owner lists the event with the admin token" (its listing and
its producer's last event), "The Python command publishes an event", "Metrics
count the events published since the restart", "The integration examples
publish through the public API" and "A revoked key no longer authenticates".
"""

import re
import sys
import unittest
from pathlib import Path

from signalhub_stack import (
    StackTestCase,
    admin,
    admin_token,
    compose,
    create_producer,
    host,
    publish,
    published_id,
    run,
    signalhub_command,
    text,
    up,
)

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "examples"


class ProducerKeys(StackTestCase):
    def test_registering_a_producer_returns_its_key_once(self):
        created = create_producer("ci-smoke-test")
        self.assertTrue(created["apiKey"].startswith("shpk1_"))
        self.assertTrue(created["producer"]["id"])
        self.assertTrue(created["keyId"])

    def test_publishing_without_a_valid_key_is_rejected(self):
        for label, token in (
            ("no key", None),
            ("a key that does not exist", "shpk1_not-a-key"),
            ("the admin token", admin_token()),
        ):
            with self.subTest(label):
                self.assertStatus(
                    host().post(
                        "/api/v1/events",
                        token=token,
                        body={
                            "category": "INFO",
                            "severity": "LOW",
                            "title": "Rejected",
                        },
                    ),
                    401,
                )

    def test_a_revoked_key_no_longer_authenticates(self):
        created = create_producer("ci-revoked")
        key = created["apiKey"]
        self.assertStatus(publish(key, "Before the revocation"), 201)
        self.ok(
            admin(
                "POST",
                f"/api/v1/admin/producers/{created['producer']['id']}/keys/{created['keyId']}/revoke",
            )
        )
        self.assertStatus(publish(key, "Revoked"), 401)


class PublishedEvents(StackTestCase):
    def test_a_published_event_survives_a_backend_restart(self):
        created = create_producer("ci-smoke-test")
        event_id = published_id(
            created["apiKey"], "Smoke test", metadata={"check": "restart"}
        )
        compose("restart", "backend")
        up(timeout=120)
        event = self.ok(admin("GET", f"/api/v1/events/{event_id}"))
        self.assertEqual("Smoke test", event["title"])
        self.assertEqual("restart", event["metadata"]["check"])
        self.assertEqual(created["producer"]["name"], event["producer"]["name"])
        self.assertEqual(created["producer"]["id"], event["producer"]["id"])
        # Reading an event needs the owner's credential, not only its ID.
        self.assertStatus(host().get(f"/api/v1/events/{event_id}"), 401)

    def test_the_owner_lists_events_with_the_admin_token(self):
        created = create_producer("ci-listed")
        published_id(created["apiKey"], "Smoke test")
        listing = self.ok(
            admin(
                "GET",
                "/api/v1/events",
                query={"producerId": created["producer"]["id"], "limit": 10},
            )
        )
        self.assertEqual(["Smoke test"], [item["title"] for item in listing["items"]])
        self.assertIsNone(listing.get("nextCursor"))

    def test_listing_events_needs_a_credential(self):
        self.assertStatus(host().get("/api/v1/events"), 401)

    def test_the_producer_list_shows_the_last_event_of_each_producer(self):
        created = create_producer("ci-last-event")
        producer_id = created["producer"]["id"]
        published_id(created["apiKey"], "Smoke test")
        newest = self.ok(
            admin(
                "GET", "/api/v1/events", query={"producerId": producer_id, "limit": 1}
            )
        )["items"][0]["createdAt"]
        producers = self.ok(admin("GET", "/api/v1/admin/producers"))["items"]
        [producer] = [item for item in producers if item["id"] == producer_id]
        self.assertEqual(newest, producer["lastEventAt"])


class PythonCommand(StackTestCase):
    def test_the_python_command_publishes_an_event(self):
        created = create_producer("ci-sdk")
        sent = signalhub_command(
            "send",
            "--category",
            "action-required",
            "--severity",
            "HIGH",
            "--title",
            "From the command",
            "--context",
            "ci/sdk",
            "--metadata",
            '{"run": 42}',
            "--meta",
            "step=smoke",
            "--link",
            "https://ci.example.com/runs/42",
            api_key=created["apiKey"],
        )
        self.assertEqual(0, sent.returncode, sent.stderr.decode())
        event = self.ok(admin("GET", f"/api/v1/events/{text(sent).strip()}"))
        self.assertEqual("ACTION_REQUIRED", event["category"])
        self.assertEqual("From the command", event["title"])
        self.assertEqual({"run": 42, "step": "smoke"}, event["metadata"])
        self.assertEqual(created["producer"]["id"], event["producer"]["id"])
        self.assertEqual("https://ci.example.com/runs/42", event["link"])

    def test_the_python_command_exits_with_status_1_for_an_invalid_key(self):
        sent = signalhub_command(
            "send",
            "--category",
            "INFO",
            "--severity",
            "LOW",
            "--title",
            "Rejected",
            api_key="shpk1_not-a-key",
        )
        self.assertEqual(1, sent.returncode)


def metric(name: str) -> float:
    """The value of an unlabelled Prometheus series; 0 while it has none yet."""
    body = host().get("/q/metrics", headers={"Accept": "text/plain"}).text
    found = re.search(rf"^{re.escape(name)} (\S+)$", body, re.MULTILINE)
    return float(found.group(1)) if found else 0.0


class Metrics(StackTestCase):
    def test_metrics_count_the_events_published(self):
        created = create_producer("ci-metrics")
        before = metric("signalhub_events_published_total")
        # Rejected events do not count.
        publish("shpk1_not-a-key", "Rejected")
        self.assertEqual(before, metric("signalhub_events_published_total"))
        published_id(created["apiKey"], "Counted")
        self.assertEqual(before + 1, metric("signalhub_events_published_total"))

    def test_metrics_include_the_dispatch_backlog_pool_and_http_series(self):
        # An event read by ID makes the request series appear.
        created = create_producer("ci-series")
        event_id = published_id(created["apiKey"], "Series")
        self.ok(admin("GET", f"/api/v1/events/{event_id}"))
        body = host().get("/q/metrics", headers={"Accept": "text/plain"}).text
        self.assertRegex(body, r"(?m)^signalhub_push_dispatch_pending ")
        self.assertRegex(body, r"(?m)^agroal_active_count")
        self.assertRegex(
            body,
            r'(?m)^http_server_requests_seconds_count\{.*uri="/api/v1/events/\{id\}"',
        )


class IntegrationExamples(StackTestCase):
    """Unrelated producers, each with its own key, through the same contract."""

    def register(self, name: str) -> dict:
        created = create_producer(name)
        return {"name": created["producer"]["name"], "key": created["apiKey"]}

    def example(self, command, producer, stdin=None, env=None, quiet=True):
        result = run(
            *command,
            cwd=ROOT,
            env={
                "SIGNALHUB_URL": host().base_url,
                "SIGNALHUB_API_KEY": producer["key"],
                **(env or {}),
            },
            input=stdin,
        )
        # The shell and agent examples report a failed publish without failing.
        if quiet:
            self.assertEqual(
                "", result.stderr.decode(), "the example reported an error"
            )
        return result

    def test_the_examples_publish_one_event_each(self):
        shell = self.register("example-shell")
        self.example(
            [str(EXAMPLES / "shell/run-and-notify.sh"), "Example job", "true"], shell
        )
        disk = self.register("example-disk-usage")
        self.example([str(EXAMPLES / "disk-usage/check-disk-usage.sh"), "/", "0"], disk)
        agent = self.register("example-agent")
        self.example(
            [sys.executable, str(EXAMPLES / "coding-agent/agent_hook.py")],
            agent,
            stdin=(
                '{"hook_event_name": "Notification", "cwd": "/work/example", '
                '"message": "Waiting for approval"}'
            ),
        )
        usage = self.register("example-usage")
        self.example(
            [
                sys.executable,
                str(EXAMPLES / "usage-threshold/usage_threshold.py"),
                "--name",
                "Example quota",
                "--used",
                "95",
                "--limit",
                "100",
            ],
            usage,
        )
        # The workflow's step, run twice for one run attempt as a retry would:
        # its idempotency key stores the event once.
        github = self.register("example-github")
        workflow = (EXAMPLES / "github-actions/notify-on-failure.yml").read_text()
        step = workflow.split("        run: |\n", 1)[1]
        script = "\n".join(
            line[10:] if line.startswith(" " * 10) else line
            for line in step.splitlines()
        )
        for _ in range(2):
            self.example(
                ["bash", "-eo", "pipefail", "-c", script],
                github,
                env={
                    "REPOSITORY": "owner/repo",
                    "WORKFLOW": "CI",
                    "BRANCH": "main",
                    "COMMIT": "0123456789abcdef",
                    "RUN_URL": "https://github.com/owner/repo/actions/runs/7",
                    "RUN_NUMBER": "3",
                    "RUN_ID": "7",
                    "RUN_ATTEMPT": "1",
                },
                quiet=False,
            )
        newest = self.ok(admin("GET", "/api/v1/events", query={"limit": 5}))["items"]
        self.assertEqual(
            [
                [
                    github["name"],
                    "BLOCKED",
                    "https://github.com/owner/repo/actions/runs/7",
                ],
                [usage["name"], "ACTION_REQUIRED", None],
                [agent["name"], "ACTION_REQUIRED", None],
                [disk["name"], "ACTION_REQUIRED", None],
                [shell["name"], "COMPLETED", None],
            ],
            [[e["producer"]["name"], e["category"], e.get("link")] for e in newest],
        )


if __name__ == "__main__":
    unittest.main()
