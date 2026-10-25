"""What other machines reach through the TLS proxy (docs/deployment.md).

Old step "Other machines reach only the product API, over TLS through the
proxy". They need the stack started with the `proxy` profile and
SIGNALHUB_PROXY_URL.
"""

import re
import time
import unittest
from urllib.parse import urljoin, urlsplit

from signalhub_stack import (
    Endpoint,
    StackTestCase,
    admin,
    create_producer,
    proxy,
    published_id,
    wait_until,
)

# Management, health, metrics, OpenAPI and the admin page stay on the host,
# however the path is spelled.
HOST_ONLY_PATHS = [
    "/api/v1/admin/producers",
    "/api//v1/admin/producers",
    "/api/v1/%61dmin/producers",
    "/api/v1/events/../admin/producers",
    "/api/v1/admin/events/delete",
    "/api/v1/admin/status",
    "/api/v1/admin/events/00000000-0000-0000-0000-000000000000/deliveries",
    "/q/info",
    "/q/health",
    "/api/%2e%2e/q/metrics",
    "/q/health/ready",
    "/q/metrics",
    "/q/openapi",
    "/",
    "/admin/",
    "/admin",
    "/admin/admin.js",
    "/%61dmin/",
    "/api/../admin/",
    "/connect/",
    "/connect",
    "/app/../admin/",
    "/app/%2e%2e/admin/",
    "/app/../q/info",
    "/application",
    "/app.css",
    "/webjars/qrcode-generator/2.0.4/dist/qrcode.js",
]


class ProxyProductApi(StackTestCase):
    def test_the_product_api_is_reached_over_tls_with_the_proxys_own_ca(self):
        created = create_producer("ci-proxied")
        published_id(created["apiKey"], "Smoke test")
        listed = []

        def reachable() -> bool:
            response = admin(
                "GET",
                "/api/v1/events",
                endpoint=proxy(),
                query={"producerId": created["producer"]["id"]},
            )
            listed[:] = [response]
            return response.status == 200

        wait_until(reachable, "the proxy to forward the API", timeout=10)
        self.assertEqual("Smoke test", listed[0].json()["items"][0]["title"])

    def test_publishing_reaches_the_backend_which_checks_the_key(self):
        # No event is stored: the key is missing.
        response = proxy().post(
            "/api/v1/events",
            body={"category": "INFO", "severity": "LOW", "title": "Rejected"},
        )
        self.assertStatus(response, 401)

    def test_management_health_metrics_and_the_admin_page_stay_on_the_host(self):
        for path in HOST_ONLY_PATHS:
            with self.subTest(path):
                self.assertStatus(admin("GET", path, endpoint=proxy()), 404)

    def test_plain_http_only_redirects_to_https(self):
        domain = urlsplit(proxy().base_url).hostname
        response = Endpoint(f"http://{domain}").get("/api/v1/events")
        self.assertStatus(response, 308)
        self.assertEqual(
            f"https://{domain}/api/v1/events",
            urljoin(response.url, response.header("Location")),
        )


class ProxyHeldRead(StackTestCase):
    def test_a_sixty_second_held_read_of_an_answer_passes_through_the_proxy(self):
        # Neither the proxy nor the backend sets a response timeout, so the
        # longest wait the API allows comes back as the open question it is.
        created = create_producer("ci-held-read")
        event = published_id(
            created["apiKey"],
            "Merge it?",
            ask={"choices": [{"id": "merge", "label": "Merge"}]},
        )
        started = time.monotonic()

        response = proxy().get(
            f"/api/v1/events/{event}/answer",
            token=created["apiKey"],
            query={"wait": 60},
            timeout=90,
        )

        self.assertStatus(response, 200)
        self.assertEqual("OPEN", response.json()["state"])
        self.assertGreaterEqual(time.monotonic() - started, 58)

    def test_the_producers_close_goes_through_the_proxy(self):
        created = create_producer("ci-proxied-close")
        event = published_id(
            created["apiKey"],
            "Merge it?",
            ask={"choices": [{"id": "merge", "label": "Merge"}]},
        )

        response = proxy().post(
            f"/api/v1/events/{event}/answer/close", token=created["apiKey"]
        )

        self.assertStatus(response, 200)
        self.assertEqual("CLOSED", response.json()["state"])


class ProxyWebPage(StackTestCase):
    """The users' web page is the one static path forwarded."""

    def test_the_web_page_is_served_with_its_policy_and_revalidated(self):
        response = self.assertStatus(proxy().get("/app/"), 200)
        policy = response.header("Content-Security-Policy").lower()
        self.assertTrue(
            policy.startswith("default-src 'none'; script-src 'self'"), policy
        )
        self.assertIn("frame-ancestors 'none'", policy)
        self.assertTrue(response.header("Cache-Control").startswith("no-cache"))
        self.assertEqual("DENY", response.header("X-Frame-Options").upper())
        self.assertEqual("no-referrer", response.header("Referrer-Policy").lower())
        self.assertIn("<title>SignalHub</title>", response.text)

    def test_the_web_page_without_a_slash_redirects_to_it(self):
        response = self.assertStatus(proxy().get("/app"), 301)
        self.assertEqual(
            f"{proxy().base_url}/app/",
            urljoin(response.url, response.header("Location")),
        )

    def test_a_bundled_font_comes_with_the_page(self):
        stylesheet = self.assertStatus(proxy().get("/app/fonts/fonts.css"), 200).text
        found = re.search(r"roboto-v51-[A-Za-z0-9_-]+\.woff2", stylesheet)
        self.assertIsNotNone(found, "the stylesheet names no Roboto font")
        font = self.assertStatus(proxy().get(f"/app/fonts/{found.group(0)}"), 200)
        self.assertEqual("font/woff2", font.header("Content-Type"))

    def test_the_web_pages_script_is_served(self):
        script = self.assertStatus(proxy().get("/app/js/main.js"), 200)
        self.assertIn("SignalHub", script.text)

    def test_signing_in_starts_through_the_proxy(self):
        # The cookie is set only on approval, so none yet.
        started = self.ok(proxy().post("/api/v1/web/sign-ins"))
        self.assertIsNotNone(started["code"])
        self.assertIsNotNone(started["pollSecret"])


if __name__ == "__main__":
    unittest.main()
