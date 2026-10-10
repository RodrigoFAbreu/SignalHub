"""A fresh install that follows docs/deployment.md#setup to the letter.

The workflow downloads (here: builds and packs) a release's deployment files,
sets up .env, an FCM key and the resource limits as documented, starts the
stack and runs these tests, in order: this is a procedure, so each test
builds on the one before. The last two change the stack (the tightest secret
setup, then a restart of Docker, as after a host reboot).

Settings: SIGNALHUB_COMPOSE_DIR (the install), SIGNALHUB_URL (the backend on the
host), SIGNALHUB_PROXY_URL and SIGNALHUB_PROXY_CA (the name clients use, and
Caddy's own CA), SIGNALHUB_EXPECT_IMAGE (the image the files name),
SIGNALHUB_EXPECT_RELEASE and SIGNALHUB_EXPECT_FCM_PROJECT (what the log names).

Old steps "Start the stack" (its log checks), "The host publishes only the ports
docs/deployment.md lists", "Other machines reach the API over TLS, with Caddy's
own CA", "The operator manages on the host; producers and clients go through the
proxy", "Without the admin token, management is off and clients keep reading"
and "Every service comes back by itself when Docker restarts, as after a reboot".
"""

import json
import os
import stat
import unittest

from signalhub_stack import (
    StackTestCase,
    admin,
    admin_token,
    compose,
    compose_dir,
    container,
    create_client,
    create_producer,
    env_file_value,
    host,
    inspect,
    proxy,
    proxy_ca_file,
    required,
    run,
    signalhub_command,
    text,
    up,
    wait_until,
)


def published(service: str) -> list[str]:
    """Host address and port of every published container port, as "ip:port"."""
    ports = json.loads(inspect(container(service), "{{json .NetworkSettings.Ports}}"))
    return sorted(
        {
            f"{binding['HostIp']}:{binding['HostPort']}"
            for bindings in ports.values()
            for binding in bindings or []
        }
    )


class FreshInstall(StackTestCase):
    event_id: str
    client_key: str

    def test_01_the_stack_runs_the_image_the_files_name_and_logs_no_secret(self):
        # Nothing was built: the backend runs the image the files name.
        image = inspect(container("backend"), "{{.Config.Image}}")
        self.assertEqual(required("SIGNALHUB_EXPECT_IMAGE"), image)
        logs = text(compose("logs", "backend"))
        self.assertIn(f"SignalHub {required('SIGNALHUB_EXPECT_RELEASE')} (commit", logs)
        self.assertIn(
            f"FCM push enabled for Firebase project {required('SIGNALHUB_EXPECT_FCM_PROJECT')}",
            logs,
        )
        self.assertIn("Push providers: [fcm]", logs)
        for secret in (env_file_value("SIGNALHUB_DB_PASSWORD"), admin_token()):
            self.assertNotIn(secret, logs, "a secret was logged")

    def test_02_the_env_file_is_private_and_the_host_publishes_only_the_documented_ports(
        self,
    ):
        mode = stat.S_IMODE((compose_dir() / ".env").stat().st_mode)
        self.assertEqual(0o600, mode)
        self.assertEqual([], published("postgres"))
        self.assertEqual(["127.0.0.1:8080"], published("backend"))
        # The proxy on 80 and 443 of every address (IPv4, and IPv6 where Docker has it).
        self.assertEqual(
            ["443", "80"],
            sorted({address.rsplit(":", 1)[1] for address in published("proxy")}),
        )

    def test_03_other_machines_reach_the_api_over_tls_with_caddys_own_ca(self):
        # 401: the API answers, over TLS.
        answer = None

        def reachable() -> bool:
            nonlocal answer
            answer = proxy().get("/api/v1/events")
            return True

        wait_until(reachable, "the proxy to answer", timeout=10)
        self.assertStatus(answer, 401)
        self.assertEqual(401, answer.json()["status"])

    def test_04_producers_and_clients_go_through_the_proxy_the_operator_manages_on_the_host(
        self,
    ):
        producer = create_producer("fresh-install")
        client_key = create_client("fresh-install-phone")["clientKey"]
        # The Python command trusts the CA through SSL_CERT_FILE.
        sent = signalhub_command(
            "send",
            "--category",
            "INFO",
            "--severity",
            "LOW",
            "--title",
            "SignalHub is installed",
            api_key=producer["apiKey"],
            url=proxy().base_url,
            env={"SSL_CERT_FILE": proxy_ca_file()},
        )
        self.assertEqual(0, sent.returncode, sent.stderr.decode())
        FreshInstall.event_id = text(sent).strip()
        FreshInstall.client_key = client_key
        listed = self.ok(proxy().get("/api/v1/events", token=client_key))
        self.assertEqual([FreshInstall.event_id], [e["id"] for e in listed["items"]])
        # The management API is never reachable through the proxy.
        self.assertStatus(
            admin("GET", "/api/v1/admin/producers", endpoint=proxy()), 404
        )

    def test_05_without_the_admin_token_management_is_off_and_clients_keep_reading(
        self,
    ):
        # The tightest setup of docs/deployment.md#secrets.
        env_path = compose_dir() / ".env"
        token = admin_token()
        lines = [
            "SIGNALHUB_ADMIN_TOKEN="
            if line.startswith("SIGNALHUB_ADMIN_TOKEN=")
            else line
            for line in env_path.read_text().splitlines()
        ]
        env_path.write_text("\n".join(lines) + "\n")
        up(timeout=120)
        self.assertStatus(host().get("/api/v1/admin/producers", token=token), 404)
        listed = self.ok(proxy().get("/api/v1/events", token=FreshInstall.client_key))
        self.assertEqual([FreshInstall.event_id], [e["id"] for e in listed["items"]])

    @unittest.skipUnless(
        os.environ.get("SIGNALHUB_ALLOW_DOCKER_RESTART"),
        "set SIGNALHUB_ALLOW_DOCKER_RESTART to let the test restart the Docker daemon",
    )
    def test_06_every_service_comes_back_by_itself_when_docker_restarts(self):
        run("sudo", "systemctl", "restart", "docker")

        # No docker compose command: the restart policy alone brings the stack back.
        def back() -> bool:
            return (
                proxy().get("/api/v1/events", token=FreshInstall.client_key).status
                == 200
            )

        wait_until(
            back,
            "the stack to come back after Docker restarted",
            timeout=180,
            interval=2,
        )
        for service in ("postgres", "backend", "proxy"):
            with self.subTest(service):
                self.assertEqual(
                    "true", inspect(container(service), "{{.State.Running}}")
                )
        listed = self.ok(proxy().get("/api/v1/events", token=FreshInstall.client_key))
        self.assertEqual([FreshInstall.event_id], [e["id"] for e in listed["items"]])


if __name__ == "__main__":
    unittest.main()
