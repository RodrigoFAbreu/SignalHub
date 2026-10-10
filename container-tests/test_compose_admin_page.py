"""The operator's admin page and status, served by the backend on the host.

Parts of the old step "The owner lists the event with the admin token".
"""

import re
import unittest

from signalhub_stack import StackTestCase, admin, host


class AdminPage(StackTestCase):
    def page(self) -> str:
        response = self.assertStatus(host().get("/admin/"), 200)
        return response.text

    def test_the_admin_page_is_served(self):
        self.assertIn("SignalHub admin", self.page())

    def test_the_admin_page_has_its_sections(self):
        page = self.page()
        for section in ("producers", "events", "status"):
            with self.subTest(section):
                self.assertIn(f'id="section-{section}" data-section="{section}"', page)

    def test_the_admin_page_has_the_send_and_delete_event_forms(self):
        page = self.page()
        self.assertIn('id="send-event"', page)
        self.assertIn('id="delete-events"', page)

    def test_the_status_section_reads_the_status_summary(self):
        status = self.ok(admin("GET", "/api/v1/admin/status"))
        self.assertEqual([], status["pushProviders"])
        self.assertGreaterEqual(status["pendingDispatches"], 0)
        self.assertIsNone(status["eventRetentionSeconds"])

    def test_every_asset_of_the_admin_page_is_served(self):
        # The page and its QR library are served on the host.
        assets = re.findall(r'(?:src|href)="([^"]+)"', self.page())
        self.assertTrue(assets)
        for asset in assets:
            if asset.startswith("#"):
                continue
            path = asset if asset.startswith("/") else f"/admin/{asset}"
            with self.subTest(asset):
                self.assertStatus(host().get(path), 200)

    def test_the_old_connect_page_is_gone(self):
        for path in ("/connect/", "/connect"):
            with self.subTest(path):
                self.assertStatus(host().get(path), 404)


if __name__ == "__main__":
    unittest.main()
