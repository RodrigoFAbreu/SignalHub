"""What the operator does on the host with the admin token, and never through the proxy.

Old step "The operator sends a test event, reads an event's deliveries and
deletes events on the host, after a dry run, and never through the proxy".
"""

import unittest

from signalhub_stack import (
    StackTestCase,
    admin,
    compose,
    create_producer,
    proxy,
    published_id,
    text,
)


class OperatorEvents(StackTestCase):
    def backend_log(self) -> str:
        return text(compose("logs", "--no-log-prefix", "backend"))

    def producer_with_events(self, name: str, count: int = 2) -> tuple[dict, list[str]]:
        created = create_producer(name)
        ids = [published_id(created["apiKey"], "To delete") for _ in range(count)]
        return created, ids

    def test_the_operator_sends_a_test_event_as_a_producer_without_its_key(self):
        created = create_producer("ci-smoke-deleted")
        producer_id = created["producer"]["id"]
        event = self.ok(
            admin(
                "POST",
                f"/api/v1/admin/producers/{producer_id}/events",
                body={
                    "category": "ACTION_REQUIRED",
                    "severity": "HIGH",
                    "title": "Test event",
                },
            )
        )
        self.assertEqual(producer_id, event["producer"]["id"])
        self.assertEqual("Test event", event["title"])
        self.assertRegex(
            self.backend_log(), rf"Operator sent event .* as producer {producer_id}"
        )

    def test_sending_a_test_event_never_goes_through_the_proxy(self):
        created = create_producer("ci-smoke-proxied")
        response = admin(
            "POST",
            f"/api/v1/admin/producers/{created['producer']['id']}/events",
            endpoint=proxy(),
            body={"category": "INFO", "severity": "LOW", "title": "Through the proxy"},
        )
        self.assertStatus(response, 404)

    def test_an_events_deliveries_are_read_on_the_host_and_never_through_the_proxy(
        self,
    ):
        _, [event_id, _] = self.producer_with_events("ci-deliveries")
        deliveries = self.ok(
            admin("GET", f"/api/v1/admin/events/{event_id}/deliveries")
        )
        self.assertIsInstance(deliveries["items"], list)
        self.assertStatus(
            admin(
                "GET", f"/api/v1/admin/events/{event_id}/deliveries", endpoint=proxy()
            ),
            404,
        )

    def test_deleting_one_event_removes_it_and_its_deliveries(self):
        _, [event_id, _] = self.producer_with_events("ci-delete-one")
        path = f"/api/v1/admin/events/{event_id}"
        self.assertStatus(admin("DELETE", path), 204)
        self.assertStatus(admin("DELETE", path), 404)
        self.assertStatus(admin("GET", f"{path}/deliveries"), 404)

    def test_a_dry_run_counts_what_deleting_a_producers_events_would_remove(self):
        created, _ = self.producer_with_events("ci-dry-run")
        producer_id = created["producer"]["id"]
        counted = self.ok(
            admin(
                "POST",
                "/api/v1/admin/events/delete",
                body={"producerId": producer_id, "dryRun": True},
            )
        )
        self.assertEqual(2, counted["count"])
        self.assertTrue(counted["dryRun"])
        listing = self.ok(
            admin("GET", "/api/v1/events", query={"producerId": producer_id})
        )
        self.assertEqual(2, len(listing["items"]))

    def test_deleting_events_never_goes_through_the_proxy(self):
        created, _ = self.producer_with_events("ci-delete-proxied")
        response = admin(
            "POST",
            "/api/v1/admin/events/delete",
            endpoint=proxy(),
            body={"producerId": created["producer"]["id"]},
        )
        self.assertStatus(response, 404)

    def test_deleting_a_producers_events_keeps_the_producer_and_every_other_event(
        self,
    ):
        doomed, _ = self.producer_with_events("ci-smoke-deleted")
        kept, _ = self.producer_with_events("ci-kept")
        doomed_id = doomed["producer"]["id"]
        deleted = self.ok(
            admin(
                "POST",
                "/api/v1/admin/events/delete",
                body={"producerId": doomed_id},
            )
        )
        self.assertEqual(2, deleted["count"])
        self.assertFalse(deleted["dryRun"])
        self.assertEqual(
            [],
            self.ok(admin("GET", "/api/v1/events", query={"producerId": doomed_id}))[
                "items"
            ],
        )
        # The producer stays, and so does every other event.
        producer = self.ok(admin("GET", f"/api/v1/admin/producers/{doomed_id}"))
        self.assertEqual(doomed["producer"]["name"], producer["name"])
        self.assertIsNone(producer["lastEventAt"])
        kept_events = self.ok(
            admin("GET", "/api/v1/events", query={"producerId": kept["producer"]["id"]})
        )
        self.assertEqual(2, len(kept_events["items"]))
        self.assertIn(f"Deleted 2 events of producer {doomed_id}", self.backend_log())


if __name__ == "__main__":
    unittest.main()
