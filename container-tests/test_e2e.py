"""Producer to push to client inbox, with FCM push enabled against a fake FCM.

The workflow starts scripts/e2e/fake_fcm.py (a stand-in for Google's token
endpoint and the FCM HTTP v1 API), records what it receives in
SIGNALHUB_FCM_SENDS, and starts the stack with a throwaway service account key
and the app's Firebase options in SIGNALHUB_FIREBASE_OPTIONS (see the job in
.github/workflows/ci-containers.yml).

Old steps "Start a fake FCM, PostgreSQL and the backend with FCM push enabled"
(its log lines), "Register a producer and two clients with push targets", "The
producer publishes a low and a high severity event", "Push goes out through FCM
as the clients' preferences allow", "The client opens the pushed event from its
inbox and reads it" and "A second user with a private producer gets only their
own events, by inbox and by push".
"""

import json
import re
import unittest
from pathlib import Path

from signalhub_stack import (
    StackTestCase,
    admin,
    compose,
    create_client,
    create_producer,
    create_user,
    host,
    mask,
    published_id,
    required,
    signalhub_command,
    text,
    unique,
    wait_until,
)


def send(api_key: str, *args: str) -> str:
    """Publishes with the Python command and returns the event's ID."""
    sent = signalhub_command("send", *args, api_key=api_key)
    if sent.returncode != 0:
        raise AssertionError(f"signalhub send failed: {sent.stderr.decode()}")
    return text(sent).strip()


def sends() -> list[dict]:
    path = Path(required("SIGNALHUB_FCM_SENDS"))
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def sent_to(token: str) -> list[dict]:
    return [send for send in sends() if send["message"]["token"] == token]


def register_client(name: str, push_token: str, **fields) -> str:
    key = create_client(name, **fields)["clientKey"]
    answer = host().put(
        "/api/v1/client/push-target",
        token=key,
        body={"provider": "fcm", "token": push_token},
    )
    if answer.status != 200:
        raise AssertionError(f"{answer}: {answer.text}")
    return key


def counter(result: str) -> float:
    body = host().get("/q/metrics", headers={"Accept": "text/plain"}).text
    found = re.search(
        rf'^signalhub_push_deliveries_total\{{result="{result}",?\}} (\S+)$',
        body,
        re.MULTILINE,
    )
    return float(found.group(1)) if found else 0.0


def deliveries(event_id: str) -> list[dict]:
    return admin("GET", f"/api/v1/admin/events/{event_id}/deliveries").json()["items"]


class PushEndToEnd(StackTestCase):
    @classmethod
    def setUpClass(cls):
        cls.options = json.loads(
            Path(required("SIGNALHUB_FIREBASE_OPTIONS")).read_text()
        )
        cls.delivered_before = counter("delivered")
        cls.invalid_before = counter("invalid_target")
        producer = create_producer("e2e-producer")
        cls.producer_name = producer["producer"]["name"]
        cls.phone_token = unique("e2e-phone-token")
        cls.stale_token = unique("unregistered-e2e-token")
        cls.phone_key = register_client("e2e-phone", cls.phone_token)
        # Its app was uninstalled: FCM answers UNREGISTERED for this token.
        cls.stale_key = register_client("e2e-stale", cls.stale_token)
        cls.phone_name = (
            host().get("/api/v1/client", token=cls.phone_key).json()["name"]
        )
        cls.stale_name = (
            host().get("/api/v1/client", token=cls.stale_key).json()["name"]
        )
        host().put(
            "/api/v1/client/push-preferences",
            token=cls.phone_key,
            body={"minimumSeverity": "HIGH"},
        )
        cls.low_id = send(
            producer["apiKey"],
            "--category", "INFO", "--severity", "LOW",
            "--title", "Nightly backup finished",
        )  # fmt: skip
        cls.high_id = send(
            producer["apiKey"],
            "--category", "ACTION_REQUIRED", "--severity", "HIGH",
            "--title", "Approve the deployment", "--message", "Production is waiting.",
            "--meta", "run=7",
        )  # fmt: skip
        cls.producer_id = producer["producer"]["id"]
        # Both events are dispatched in order, so once the high one reached the
        # phone and the stale target is gone, the low one was already handled.
        wait_until(
            lambda: (
                any(
                    s["message"]["data"]["eventId"] == cls.high_id
                    for s in sent_to(cls.phone_token)
                )
                and host()
                .get("/api/v1/client", token=cls.stale_key)
                .json()["pushTarget"]
                is None
            ),
            "the push to reach the phone and the stale target to go",
            timeout=60,
        )
        # The high event's records are written after its sends, which the wait above saw.
        wait_until(
            lambda: len(deliveries(cls.high_id)) == 2,
            "the delivery records",
            timeout=30,
        )

    def test_the_stack_started_with_fcm_push_enabled(self):
        logs = text(compose("logs", "backend"))
        self.assertIn("Push providers: [fcm]", logs)
        self.assertIn("Push client options: served for fcm", logs)

    def test_the_phone_gets_the_firebase_options_it_registers_its_token_with(self):
        config = self.ok(host().get("/api/v1/client/push-config", token=self.phone_key))
        self.assertEqual("fcm", config["provider"])
        self.assertEqual(self.options, config["options"])

    def test_the_phone_gets_only_the_high_severity_event_as_fcm_expects_it(self):
        self.assertEqual(
            [
                {
                    "path": "/v1/projects/signalhub-e2e/messages:send",
                    "message": {
                        "token": self.phone_token,
                        "android": {"priority": "HIGH"},
                        "notification": {
                            "title": "Approve the deployment",
                            "body": "Production is waiting.",
                        },
                        "data": {
                            "eventId": self.high_id,
                            "category": "ACTION_REQUIRED",
                            "severity": "HIGH",
                        },
                    },
                }
            ],
            sent_to(self.phone_token),
        )

    def test_fcms_unregistered_answer_removes_the_stale_clients_target(self):
        self.assertTrue(
            any(
                s["message"]["data"]["eventId"] == self.low_id
                for s in sent_to(self.stale_token)
            )
        )
        stale = self.ok(host().get("/api/v1/client", token=self.stale_key))
        self.assertIsNone(stale["pushTarget"])

    def test_the_delivery_metrics_count_one_delivered_and_one_invalid_target(self):
        self.assertEqual(1.0, counter("delivered") - self.delivered_before)
        self.assertEqual(1.0, counter("invalid_target") - self.invalid_before)

    def test_delivery_records_hold_no_push_token(self):
        for event_id in (self.low_id, self.high_id):
            answer = admin("GET", f"/api/v1/admin/events/{event_id}/deliveries")
            self.assertNotIn("-token", answer.text)

    def test_the_low_events_delivery_records_say_what_happened_per_device(self):
        records = [
            [r["clientName"], r["attempt"], r["outcome"], r["detail"]]
            for r in deliveries(self.low_id)
        ]
        self.assertEqual(
            [
                [self.phone_name, 1, "FILTERED", "below the minimum severity"],
                [self.stale_name, 1, "INVALID_TARGET", "HTTP 404 UNREGISTERED"],
            ],
            records,
        )

    def test_the_high_events_delivery_records_say_what_happened_per_device(self):
        records = [
            [r["clientName"], r["attempt"], r["outcome"], r["detail"]]
            for r in deliveries(self.high_id)
        ]
        self.assertEqual(
            [
                [self.phone_name, 1, "DELIVERED", None],
                [self.stale_name, 1, "NO_TARGET", None],
            ],
            records,
        )

    def test_the_client_opens_the_pushed_event_from_its_inbox_and_reads_it(self):
        def phone(method, path):
            return host().request(method, path, token=self.phone_key)

        pushed = sent_to(self.phone_token)[0]["message"]["data"]["eventId"]
        event = self.ok(phone("GET", f"/api/v1/events/{pushed}"))
        self.assertEqual("Approve the deployment", event["title"])
        self.assertEqual({"run": "7"}, event["metadata"])
        self.assertEqual(self.producer_name, event["producer"]["name"])
        self.assertIsNone(event["readAt"])
        # The inbox holds every event, pushed or not, newest first.
        inbox = self.ok(
            host().get(
                "/api/v1/events",
                token=self.phone_key,
                query={"producerId": self.producer_id},
            )
        )["items"]
        self.assertEqual([self.high_id, self.low_id], [e["id"] for e in inbox])
        self.assertTrue(all(e["readAt"] is None for e in inbox))
        unread = self.ok(phone("GET", "/api/v1/events/unread-count"))["unread"]
        self.assertGreaterEqual(unread, 2)
        self.assertIsNotNone(
            self.ok(phone("PUT", f"/api/v1/events/{pushed}/read"))["readAt"]
        )
        self.assertEqual(
            unread - 1, self.ok(phone("GET", "/api/v1/events/unread-count"))["unread"]
        )


class SecondUser(StackTestCase):
    """A second user with a private producer gets only their own events."""

    def test_a_guest_gets_their_own_events_by_inbox_and_by_push(self):
        guest = create_user("e2e-guest")
        token = unique("e2e-guest-token")
        guest_key = register_client("e2e-guest-phone", token, userId=guest["id"])
        producer = create_producer("e2e-guest-producer", ownerId=guest["id"])
        event_id = send(
            producer["apiKey"],
            "--category", "ACTION_REQUIRED", "--severity", "CRITICAL",
            "--title", "For the guest only",
        )  # fmt: skip
        wait_until(
            lambda: any(
                s["message"]["data"]["eventId"] == event_id for s in sent_to(token)
            ),
            "the push to reach the guest",
            timeout=60,
        )
        # Only the guest's device was pushed: nobody else got anything for it.
        self.assertEqual(
            [token],
            [
                s["message"]["token"]
                for s in sends()
                if s["message"]["data"]["eventId"] == event_id
            ],
        )
        # The guest's inbox holds their event alone, and the owner's events are not found for them.
        inbox = self.ok(host().get("/api/v1/events", token=guest_key))
        self.assertEqual([event_id], [e["id"] for e in inbox["items"]])
        unread = self.ok(host().get("/api/v1/events/unread-count", token=guest_key))
        self.assertEqual(1, unread["unread"])
        owner_key = create_client("e2e-owner-phone")["clientKey"]
        owner_event = published_id(
            create_producer("e2e-owner-producer")["apiKey"], "Owner"
        )
        self.assertStatus(
            host().get(f"/api/v1/events/{owner_event}", token=guest_key), 404
        )
        # And the owner's device does not find the guest's.
        self.assertStatus(
            host().get(f"/api/v1/events/{event_id}", token=owner_key), 404
        )
        # The operator sees it too, for testing and debugging.
        seen = self.ok(admin("GET", f"/api/v1/events/{event_id}"))
        self.assertEqual("For the guest only", seen["title"])
        mask(guest_key)


if __name__ == "__main__":
    unittest.main()
