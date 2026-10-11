"""The upgrade and rollback of docs/deployment.md#upgrades, in three phases.

The workflow starts an earlier release's stack, runs `StoreData`, backs up and
upgrades in place to this commit's deployment files, runs `AfterUpgrade`, then
restores the backup with the release again and runs `AfterRollback`. Run a
phase with, for example:

    python container-tests/test_upgrade.py StoreData

Settings: SIGNALHUB_COMPOSE_DIR (the folder of the stack the phase talks to),
SIGNALHUB_REPO (the checkout of this commit, when the tests run from a copy),
SIGNALHUB_UPGRADE_STATE (a file the first phase writes the keys to, for the
others), SIGNALHUB_EXPECT_RELEASE and SIGNALHUB_EXPECT_REVISION (what the
upgraded stack reports) and the setting of the other test modules.

Old steps "Store a producer, a client and a read event", "The data and keys of
the release survive the upgrade" (and, in its "Back up and upgrade" step, the
version and commit the upgraded backend reports) and, in "Rolling back to the
release restores its backup", the events it lists.
"""

import json
import os
import unittest
from pathlib import Path

from signalhub_stack import (
    StackTestCase,
    admin,
    create_client,
    create_producer,
    host,
    postgres_sql,
    proxy,
    publish,
    published_id,
    required,
    wait_until,
)

ROOT = Path(os.environ.get("SIGNALHUB_REPO") or Path(__file__).resolve().parent.parent)
MIGRATIONS = ROOT / "backend/src/main/resources/db/migration"


def state_file() -> Path:
    return Path(required("SIGNALHUB_UPGRADE_STATE"))


def stored() -> dict:
    return json.loads(state_file().read_text())


class StoreData(StackTestCase):
    def test_a_producer_a_client_and_a_read_event_are_stored(self):
        producer = create_producer("ci-upgrade-test")
        client = create_client("ci-upgrade-client")
        event_id = published_id(
            producer["apiKey"], "Before the upgrade", metadata={"release": "previous"}
        )
        key = client["clientKey"]
        self.ok(host().put(f"/api/v1/events/{event_id}/read", token=key))
        self.ok(
            host().put(
                "/api/v1/client/push-preferences",
                token=key,
                body={"minimumSeverity": "HIGH"},
            )
        )
        state_file().write_text(
            json.dumps({"apiKey": producer["apiKey"], "clientKey": key})
        )


class AfterUpgrade(StackTestCase):
    def test_the_events_and_the_producers_key_of_the_release_survive(self):
        events = self.ok(host().get("/api/v1/events", token=stored()["clientKey"]))[
            "items"
        ]
        self.assertEqual(1, len(events))
        self.assertEqual("Before the upgrade", events[0]["title"])
        self.assertEqual("previous", events[0]["metadata"]["release"])
        self.assertIsNotNone(events[0]["readAt"])
        # The key of the release still publishes (after the listing above, which
        # expects only the event stored before).
        self.assertStatus(publish(stored()["apiKey"], "After the upgrade"), 201)

    def test_the_clients_key_and_push_preferences_survive(self):
        client = self.ok(host().get("/api/v1/client", token=stored()["clientKey"]))
        self.assertEqual("HIGH", client["pushPreferences"]["minimumSeverity"])
        self.assertTrue(client["admin"])
        self.assertEqual("ADMIN", client["user"]["role"])

    def test_the_existing_data_became_the_first_users(self):
        # One admin who owns the producer, is subscribed to it and has the client.
        users = self.ok(admin("GET", "/api/v1/admin/users"))["items"]
        self.assertEqual(1, len(users))
        [user] = users
        self.assertEqual("ADMIN", user["role"])
        self.assertEqual(1, len(user["devices"]))
        self.assertEqual(1, len(user["producers"]))
        self.assertEqual(1, len(user["subscriptions"]))
        self.assertEqual("PRIVATE", user["producers"][0]["visibility"])

    def test_every_migration_of_this_commit_is_applied_and_none_failed(self):
        migrations = len(list(MIGRATIONS.glob("V*__*.sql")))
        applied = postgres_sql(
            "SELECT count(*) FILTER (WHERE success), count(*) FILTER (WHERE NOT success)"
            " FROM flyway_schema_history WHERE version IS NOT NULL"
        )
        self.assertEqual(f"{migrations}|0", applied)

    def test_the_upgraded_backend_reports_this_release_and_commit(self):
        info = self.ok(host().get("/q/info"))["signalhub"]
        self.assertEqual(required("SIGNALHUB_EXPECT_RELEASE"), info["version"])
        self.assertEqual(required("SIGNALHUB_EXPECT_REVISION"), info["revision"])


class ProxyAfterUpgrade(StackTestCase):
    """The proxy of an upgraded stack runs the release's proxy/Caddyfile.

    Needs SIGNALHUB_PROXY_URL. A path only the new configuration forwards
    answers, and what must stay hidden still does not.
    """

    def test_the_users_web_page_is_forwarded(self):
        def forwarded() -> bool:
            return proxy().get("/app/").status == 200

        wait_until(forwarded, "the proxy to forward /app/", timeout=30)

    def test_the_admin_page_and_the_management_api_are_not(self):
        self.assertStatus(proxy().get("/admin/"), 404)
        self.assertStatus(proxy().get("/api/v1/admin/producers"), 404)


class ProxyAfterConfigChange(StackTestCase):
    """A changed proxy/Caddyfile alone is in effect after the documented restart."""

    def test_the_changed_configuration_answers(self):
        def answers() -> bool:
            return proxy().get("/ci-probe").status == 200

        wait_until(answers, "the proxy to run the changed configuration", timeout=30)

    def test_the_rest_is_as_before(self):
        self.assertStatus(proxy().get("/app/"), 200)
        self.assertStatus(proxy().get("/admin/"), 404)


class AfterRollback(StackTestCase):
    def test_rolling_back_restores_the_events_of_the_backup(self):
        events = self.ok(host().get("/api/v1/events", token=stored()["clientKey"]))[
            "items"
        ]
        self.assertEqual(["Before the upgrade"], [e["title"] for e in events])


if __name__ == "__main__":
    unittest.main()
