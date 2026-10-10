"""Operations that restart, stop or empty parts of the Compose stack.

They change the stack, so run them last (CI runs this module after the
`test_compose_*.py` ones): the backend is recreated with other settings, the
database is stopped, replaced from a backup and migrated past this release.
Each test leaves the stack running as it found it.

Old steps "JSON logs carry the startup summary and no secrets", "A backup
restores into an empty database", "Readiness reports DOWN while PostgreSQL is
stopped", "The backend refuses a database that a newer release migrated" and
"The image refuses to start without database settings".
"""

import json
import os
import subprocess
import unittest

from signalhub_stack import (
    StackTestCase,
    admin,
    admin_token,
    compose,
    create_client,
    create_producer,
    env_file_value,
    host,
    postgres_sql,
    publish,
    published_id,
    run,
    text,
    up,
)

RESTORE = (
    'pg_restore --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-owner'
    " --no-privileges --exit-on-error --single-transaction"
)


def proxy_ca() -> bytes:
    return compose(
        "exec", "-T", "proxy", "cat", "/data/caddy/pki/authorities/local/root.crt"
    ).stdout


class Operations(StackTestCase):
    def test_json_logs_carry_the_startup_summary_and_no_secrets(self):
        # Recreates the backend with other settings; the next test run sets them back.
        self.addCleanup(up)
        up(
            timeout=120,
            env={"SIGNALHUB_LOG_JSON": "true", "SIGNALHUB_EVENTS_RETENTION": "400d"},
        )
        logs = text(compose("logs", "--no-log-prefix", "backend"))
        # Every line is a JSON object: loading fails on the first one that is not.
        lines = [json.loads(line) for line in logs.splitlines() if line.strip()]
        summary = [
            line["message"]
            for line in lines
            if line.get("loggerName", "").endswith(".StartupDiagnostics")
        ]
        self.assertTrue(summary, "the startup summary is not logged")
        self.assertRegex(
            summary[0],
            r"^SignalHub development build; Configuration: profile prod; database "
            r"jdbc:postgresql://postgres:5432/signalhub as signalhub; management API enabled; "
            r".*event retention 400d; JSON logs on; Java 25\.",
        )
        for secret in (admin_token(), env_file_value("SIGNALHUB_DB_PASSWORD")):
            if secret:
                self.assertNotIn(secret, logs, "a secret reached the logs")
        # The admin page's Status section reports the retention set (400 days, in seconds).
        status = self.ok(admin("GET", "/api/v1/admin/status"))
        self.assertEqual(34560000, status["eventRetentionSeconds"])

    def test_readiness_reports_down_while_postgresql_is_stopped(self):
        self.addCleanup(up)
        compose("stop", "postgres")
        self.assertStatus(host().get("/q/health/ready"), 503)
        self.assertStatus(host().get("/q/health/live"), 200)
        compose("start", "postgres")
        up(timeout=120)

    def test_the_backend_refuses_a_database_that_a_newer_release_migrated(self):
        self.addCleanup(up)
        self.addCleanup(
            postgres_sql, "DELETE FROM flyway_schema_history WHERE version = '99999'"
        )
        compose("stop", "backend")
        postgres_sql(
            "INSERT INTO flyway_schema_history"
            " (installed_rank, version, description, type, script, checksum,"
            " installed_by, execution_time, success)"
            " SELECT max(installed_rank) + 1, '99999', 'from a newer release', 'SQL',"
            " 'V99999__from_a_newer_release.sql', 0, current_user, 0, true"
            " FROM flyway_schema_history"
        )
        before = postgres_sql("SELECT count(*) FROM flyway_schema_history")
        try:
            started = compose(
                "run", "--rm", "--no-deps", "backend", check=False, timeout=120
            )
        except subprocess.TimeoutExpired:
            self.fail("still running after 120s")
        self.assertNotEqual(0, started.returncode, "started on a newer schema")
        output = text(started) + started.stderr.decode(errors="replace")
        self.assertIn("migrations 99999 are unknown to this release", output)
        self.assertEqual(
            before, postgres_sql("SELECT count(*) FROM flyway_schema_history")
        )

    def test_the_image_refuses_to_start_without_database_settings(self):
        image = json.loads(text(compose("config", "--format", "json")))["services"][
            "backend"
        ]["image"]
        name = "signalhub-no-database"
        run("docker", "rm", "--force", name, check=False)
        self.addCleanup(run, "docker", "rm", "--force", name, check=False)
        run("docker", "run", "--detach", "--name", name, image)
        try:
            code = text(run("docker", "wait", name, timeout=60)).strip()
        except subprocess.TimeoutExpired:
            self.fail("still running after 60s")
        logs = run("docker", "logs", name)
        self.assertIn(
            "No database configured", text(logs) + logs.stderr.decode(errors="replace")
        )
        self.assertNotEqual("0", code)


class BackupAndRestore(StackTestCase):
    """The commands of docs/architecture.md#backup-and-restore."""

    def restore(self, backup: bytes) -> subprocess.CompletedProcess:
        return compose(
            "exec", "-T", "postgres", "sh", "-c", RESTORE, input=backup, check=False
        )

    def test_a_backup_restores_into_an_empty_database(self):
        self.addCleanup(up)
        has_proxy = bool(os.environ.get("SIGNALHUB_PROXY_URL"))
        ca_before = proxy_ca() if has_proxy else None
        created = create_producer("ci-backup")
        key, producer_id = created["apiKey"], created["producer"]["id"]
        before_id = published_id(key, "Before the backup")
        reader = create_client("ci-backup-reader")["clientKey"]
        self.ok(
            host().post(
                "/api/v1/events/read", token=reader, body={"through": before_id}
            )
        )

        dump = compose(
            "exec",
            "-T",
            "postgres",
            "sh",
            "-c",
            'pg_dump --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --format=custom',
        ).stdout
        compose("exec", "-T", "postgres", "pg_restore", "--list", input=dump)
        later_id = published_id(key, "After the backup")

        # Only the database volume: the proxy keeps its certificates and CA.
        compose("down")
        run("docker", "volume", "rm", "signalhub_postgres-data")
        up("postgres", timeout=120)
        self.assertEqual(0, self.restore(dump).returncode)
        up(timeout=120)

        # Events from before the backup are back, with their read state; later ones are gone.
        # (Read state is the user's, so it is read with a device of the owner.)
        restored = create_client("ci-restored")["clientKey"]
        titles = self.ok(
            host().get(
                "/api/v1/events", token=restored, query={"producerId": producer_id}
            )
        )["items"]
        self.assertEqual(["Before the backup"], [item["title"] for item in titles])
        self.assertIsNotNone(titles[0]["readAt"])
        self.assertStatus(admin("GET", f"/api/v1/events/{later_id}"), 404)
        # The producer's key still works: the backup holds its hash.
        self.assertStatus(publish(key, "After the restore"), 201)
        # Restoring over existing data fails and changes nothing.
        unread = self.ok(host().get("/api/v1/events/unread-count", token=restored))
        self.assertNotEqual(
            0, self.restore(dump).returncode, "restored over existing data"
        )
        self.assertEqual(
            unread, self.ok(host().get("/api/v1/events/unread-count", token=restored))
        )
        if has_proxy:
            self.assertEqual(ca_before, proxy_ca(), "the proxy lost its CA")


if __name__ == "__main__":
    unittest.main()
