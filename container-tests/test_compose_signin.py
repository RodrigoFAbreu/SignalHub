"""A browser signs in through the proxy with a code a device approves (no passwords).

Old step "A browser signs in through the proxy with a code a device approves,
reads with its cookie, and signs out". They need the stack started with the
`proxy` profile and SIGNALHUB_PROXY_URL.
"""

import re
import unittest
from urllib.parse import quote

from signalhub_stack import StackTestCase, create_client, mask, proxy

FIREFOX = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"


class BrowserSignIn(StackTestCase):
    def setUp(self):
        self.device_key = create_client("ci-signin-phone")["clientKey"]

    def start(self) -> dict:
        started = self.ok(
            proxy().post("/api/v1/web/sign-ins", headers={"User-Agent": FIREFOX})
        )
        mask(started["pollSecret"])
        mask(started["code"])
        return started

    def poll(self, started: dict):
        return proxy().get(
            f"/api/v1/web/sign-ins/{started['id']}", token=started["pollSecret"]
        )

    def device(self, method: str, path: str, **kwargs):
        return proxy().request(method, path, token=self.device_key, **kwargs)

    def approve(self, started: dict) -> None:
        # A device (any role) looks the code up and approves it, through the proxy.
        asked = self.ok(
            self.device(
                "POST",
                "/api/v1/client/web-sign-ins/lookup",
                body={"code": started["code"]},
            )
        )
        self.assertEqual(started["id"], asked["id"])
        self.assertEqual("Firefox on Linux", asked["browserName"])
        self.ok(
            self.device("POST", f"/api/v1/client/web-sign-ins/{started['id']}/approve")
        )

    def sign_in(self) -> tuple[dict, str]:
        """A signed-in browser: the sign-in and its cookie."""
        started = self.start()
        self.approve(started)
        signed_in = self.poll(started)
        self.assertEqual("SIGNED_IN", self.ok(signed_in)["state"])
        cookie = re.match(r"([^;]+);", signed_in.header("Set-Cookie")).group(1)
        mask(cookie.split("=", 1)[1])
        return started, cookie

    def test_the_link_the_page_shows_names_the_proxys_address(self):
        started = self.start()
        self.assertEqual("Firefox on Linux", started["browserName"])
        prefix = (
            f"signalhub://signin?server={quote(proxy().base_url, safe='')}&code=shsc1_"
        )
        self.assertTrue(started["uri"].startswith(prefix), started["uri"])

    def test_a_new_sign_in_is_pending(self):
        self.assertEqual("PENDING", self.ok(self.poll(self.start()))["state"])

    def test_the_approved_browser_gets_a_hardened_cookie_on_its_next_poll(self):
        started = self.start()
        self.approve(started)
        signed_in = self.poll(started)
        self.assertEqual("SIGNED_IN", self.ok(signed_in)["state"])
        # HttpOnly, Secure, SameSite=Strict, for a fixed 30 days.
        self.assertRegex(
            signed_in.header("Set-Cookie"),
            r"(?i)^__Host-signalhub_session=shck1_[^;]*; Max-Age=2592000; Path=/; "
            r"Secure; HttpOnly; SameSite=Strict",
        )
        mask(re.match(r"[^=]+=([^;]+);", signed_in.header("Set-Cookie")).group(1))

    def test_the_cookie_reads_the_session_and_the_client_api_like_a_device(self):
        _, cookie = self.sign_in()
        session = self.ok(proxy().get("/api/v1/web/session", cookie=cookie))
        self.assertEqual("BROWSER", session["client"]["kind"])
        self.assertIsNotNone(session["client"]["expiresAt"])
        self.assertEqual(
            "BROWSER",
            self.ok(proxy().get("/api/v1/client", cookie=cookie))["kind"],
        )

    def test_the_code_works_once(self):
        started, _ = self.sign_in()
        self.assertEqual("EXPIRED", self.ok(self.poll(started))["state"])

    def test_the_admin_page_and_the_management_api_never_answer_a_browser(self):
        _, cookie = self.sign_in()
        self.assertStatus(proxy().get("/api/v1/admin/clients", cookie=cookie), 404)

    def test_signing_out_needs_the_token_the_page_reads_from_its_session(self):
        _, cookie = self.sign_in()
        csrf = self.ok(proxy().get("/api/v1/web/session", cookie=cookie))["csrfToken"]
        mask(csrf)
        # Not the cookie alone.
        self.assertStatus(
            proxy().post("/api/v1/web/session/sign-out", cookie=cookie), 403
        )
        self.assertStatus(
            proxy().post(
                "/api/v1/web/session/sign-out",
                cookie=cookie,
                headers={"X-SignalHub-CSRF": csrf},
            ),
            204,
        )
        self.assertStatus(proxy().get("/api/v1/web/session", cookie=cookie), 401)

    def test_the_device_that_approved_a_browser_is_untouched_by_its_sign_out(self):
        _, cookie = self.sign_in()
        csrf = self.ok(proxy().get("/api/v1/web/session", cookie=cookie))["csrfToken"]
        proxy().post(
            "/api/v1/web/session/sign-out",
            cookie=cookie,
            headers={"X-SignalHub-CSRF": csrf},
        )
        self.assertEqual(
            "DEVICE", self.ok(self.device("GET", "/api/v1/client"))["kind"]
        )


if __name__ == "__main__":
    unittest.main()
