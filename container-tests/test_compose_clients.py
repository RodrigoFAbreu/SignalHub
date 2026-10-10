"""Registered clients (devices): their inbox, read state, push settings and life cycle.

Old step "A registered client lists events, marks them read and sets its push
target and preferences", through the management API on the host.
"""

import unittest

from signalhub_stack import (
    StackTestCase,
    admin,
    create_client,
    create_producer,
    host,
    published_id,
)


class Clients(StackTestCase):
    def client(self, key: str, method: str, path: str, **kwargs):
        return host().request(method, path, token=key, **kwargs)

    def test_a_client_lists_the_events_of_a_producer_unread(self):
        producer = create_producer("ci-smoke-test")
        published_id(producer["apiKey"], "Smoke test")
        key = create_client("ci-smoke-client")["clientKey"]
        listing = self.ok(
            self.client(
                key,
                "GET",
                "/api/v1/events",
                query={"producerId": producer["producer"]["id"]},
            )
        )
        self.assertEqual("Smoke test", listing["items"][0]["title"])
        self.assertIsNone(listing["items"][0]["readAt"])

    def test_a_client_marks_events_read_and_none_are_left_unread(self):
        producer = create_producer("ci-smoke-test")
        published_id(producer["apiKey"], "Smoke test")
        key = create_client("ci-smoke-client")["clientKey"]
        newest = self.ok(self.client(key, "GET", "/api/v1/events", query={"limit": 1}))[
            "items"
        ][0]["id"]
        marked = self.ok(
            self.client(key, "POST", "/api/v1/events/read", body={"through": newest})
        )
        self.assertGreaterEqual(marked["marked"], 1)
        counted = self.ok(self.client(key, "GET", "/api/v1/events/unread-count"))
        self.assertEqual(0, counted["unread"])

    def test_a_client_sets_its_push_target_and_the_token_is_never_read_back(self):
        key = create_client("ci-smoke-client")["clientKey"]
        answer = self.ok(
            self.client(
                key,
                "PUT",
                "/api/v1/client/push-target",
                body={"provider": "fcm", "token": "ci-smoke-token"},
            )
        )
        self.assertEqual("fcm", answer["pushTarget"]["provider"])
        self.assertNotIn("token", answer["pushTarget"])

    def test_a_client_sets_its_push_preferences(self):
        key = create_client("ci-smoke-client")["clientKey"]
        answer = self.ok(
            self.client(
                key,
                "PUT",
                "/api/v1/client/push-preferences",
                body={"minimumSeverity": "HIGH", "mutedCategories": ["INFO"]},
            )
        )
        self.assertEqual(
            {
                "enabled": True,
                "minimumSeverity": "HIGH",
                "mutedCategories": ["INFO"],
                "mutedProducerIds": [],
            },
            answer["pushPreferences"],
        )

    def test_the_operator_renames_a_client_which_reads_that_it_is_an_admin_device(self):
        created = create_client("ci-smoke-client")
        # It belongs to the owner, an admin.
        renamed = self.ok(
            admin(
                "PATCH",
                f"/api/v1/admin/clients/{created['client']['id']}",
                body={"name": "ci-smoke-admin"},
            )
        )
        self.assertEqual("ci-smoke-admin", renamed["name"])
        self.assertTrue(renamed["admin"])
        registration = self.ok(
            self.client(created["clientKey"], "GET", "/api/v1/client")
        )
        self.assertTrue(registration["admin"])

    def test_an_active_client_is_not_deleted(self):
        created = create_client("ci-smoke-client")
        self.assertStatus(
            admin("DELETE", f"/api/v1/admin/clients/{created['client']['id']}"), 409
        )

    def test_a_revoked_client_does_not_change_and_no_longer_authenticates(self):
        created = create_client("ci-smoke-client")
        path = f"/api/v1/admin/clients/{created['client']['id']}"
        self.ok(admin("POST", f"{path}/revoke"))
        self.assertStatus(admin("PATCH", path, body={"admin": False}), 409)
        self.assertStatus(
            self.client(created["clientKey"], "GET", "/api/v1/events"), 401
        )

    def test_a_revoked_client_is_deleted_once(self):
        created = create_client("ci-smoke-client")
        path = f"/api/v1/admin/clients/{created['client']['id']}"
        self.ok(admin("POST", f"{path}/revoke"))
        self.assertStatus(admin("DELETE", path), 204)
        self.assertStatus(admin("GET", path), 404)
        self.assertStatus(admin("DELETE", path), 404)

    def test_read_state_is_the_users_so_a_new_device_finds_the_event_read(self):
        producer = create_producer("ci-smoke-test")
        event_id = published_id(producer["apiKey"], "Smoke test")
        first = create_client("ci-smoke-client")
        self.ok(
            self.client(
                first["clientKey"],
                "POST",
                "/api/v1/events/read",
                body={"through": event_id},
            )
        )
        path = f"/api/v1/admin/clients/{first['client']['id']}"
        self.ok(admin("POST", f"{path}/revoke"))
        self.assertStatus(admin("DELETE", path), 204)
        # The events it read stay read for a new device of the same user.
        other = create_client("ci-smoke-other")
        event = self.ok(
            self.client(other["clientKey"], "GET", f"/api/v1/events/{event_id}")
        )
        self.assertIsNotNone(event["readAt"])


if __name__ == "__main__":
    unittest.main()
