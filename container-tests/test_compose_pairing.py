"""Pairing devices through the proxy, and what an admin device and a basic user's device may do.

Old step "A device pairs through the proxy with a code the operator made on the
host, and an admin device pairs another, sees it used, revokes it and deletes
it". They need the stack started with the `proxy` profile and SIGNALHUB_PROXY_URL.
"""

import unittest
from urllib.parse import quote

from signalhub_stack import (
    StackTestCase,
    admin,
    admin_token,
    create_client,
    create_user,
    mask,
    proxy,
    unique,
)


def device_request(key, method, path, **kwargs):
    return proxy().request(method, path, token=key, **kwargs)


class Pairing(StackTestCase):
    def pairing_uri(self, code: str) -> str:
        return f"signalhub://pair?server={quote(proxy().base_url, safe='')}&code={code}"

    def operator_pairing(self, name: str, user_id: str) -> dict:
        """A code the operator makes on the host for a user's new device."""
        pairing = self.ok(
            admin(
                "POST",
                "/api/v1/admin/pairings",
                body={"name": unique(name), "userId": user_id},
            )
        )
        mask(pairing["code"])
        return pairing

    def redeem(self, code: str):
        return proxy().post("/api/v1/pairing", token=code)

    def paired_device(self, name: str, user_id: str) -> dict:
        """A device of the user, paired through the proxy; the answer holds its key."""
        pairing = self.operator_pairing(name, user_id)
        paired = self.ok(self.redeem(pairing["code"]))
        mask(paired["clientKey"])
        return {**paired, "pairing": pairing}

    def admin_device_key(self) -> str:
        return create_client("ci-admin-device")["clientKey"]

    def test_a_pairing_code_names_the_proxys_address_and_starts_pending(self):
        user = create_user("ci-basic")
        pairing = self.operator_pairing("ci-paired-phone", user["id"])
        self.assertEqual(self.pairing_uri(pairing["code"]), pairing["uri"])
        status = self.ok(admin("GET", f"/api/v1/admin/pairings/{pairing['id']}"))
        self.assertEqual("PENDING", status["state"])
        self.assertIsNone(status["client"])

    def test_creating_pairings_is_management_which_never_leaves_the_host(self):
        response = admin(
            "POST", "/api/v1/admin/pairings", endpoint=proxy(), body={"name": "x"}
        )
        self.assertStatus(response, 404)

    def test_a_device_redeems_the_code_through_the_proxy_and_reads_with_its_key(self):
        user = create_user("ci-basic")
        pairing = self.operator_pairing("ci-paired-phone", user["id"])
        paired = self.ok(self.redeem(pairing["code"]))
        key = mask(paired["clientKey"])
        self.assertEqual(pairing["name"], paired["client"]["name"])
        device = self.ok(device_request(key, "GET", "/api/v1/client"))
        self.assertEqual(pairing["name"], device["name"])
        self.assertIsNone(device["revokedAt"])
        # The device belongs to the second user, who is subscribed to nothing: the
        # owner's events are not theirs.
        self.assertEqual(
            [], self.ok(device_request(key, "GET", "/api/v1/events"))["items"]
        )

    def test_a_pairing_code_works_once(self):
        user = create_user("ci-basic")
        pairing = self.operator_pairing("ci-paired-phone", user["id"])
        self.ok(self.redeem(pairing["code"]))
        self.assertStatus(self.redeem(pairing["code"]), 401)

    def test_whoever_shows_the_code_learns_it_was_used_and_by_which_device(self):
        user = create_user("ci-basic")
        pairing = self.operator_pairing("ci-paired-phone", user["id"])
        paired = self.ok(self.redeem(pairing["code"]))
        status = admin("GET", f"/api/v1/admin/pairings/{pairing['id']}")
        used = self.ok(status)
        self.assertEqual("REDEEMED", used["state"])
        self.assertEqual(
            {"id": paired["client"]["id"], "name": pairing["name"]}, used["client"]
        )
        self.assertNotIn(
            paired["clientKey"], status.text, "the status holds the client key"
        )

    def test_a_basic_users_device_lists_only_its_own_user_devices_and_changes_none(
        self,
    ):
        user = create_user("ci-basic")
        device = self.paired_device("ci-paired-phone", user["id"])
        key, device_id = device["clientKey"], device["client"]["id"]
        listed = self.ok(device_request(key, "GET", "/api/v1/client/devices"))
        self.assertEqual([device_id], [item["id"] for item in listed["items"]])
        self.assertStatus(
            device_request(key, "POST", f"/api/v1/client/devices/{device_id}/revoke"),
            403,
        )

    def test_a_basic_users_device_cannot_create_pairing_codes(self):
        user = create_user("ci-basic")
        key = self.paired_device("ci-paired-phone", user["id"])["clientKey"]
        self.assertStatus(
            device_request(key, "POST", "/api/v1/client/pairings", body={"name": "x"}),
            403,
        )

    def test_an_admin_device_lists_the_devices_of_users_who_are_not_admins(self):
        user = create_user("ci-basic")
        device = self.paired_device("ci-paired-phone", user["id"])
        listed = self.ok(
            device_request(self.admin_device_key(), "GET", "/api/v1/client/devices")
        )
        [found] = [i for i in listed["items"] if i["id"] == device["client"]["id"]]
        self.assertEqual(device["pairing"]["name"], found["name"])

    def test_an_admin_device_pairs_another_device_and_sees_its_code_used(self):
        admin_key = self.admin_device_key()
        outsider = self.paired_device("ci-outsider", create_user("ci-basic")["id"])
        operator_pairing = self.operator_pairing(
            "ci-operator-pairing", create_user("ci-basic")["id"]
        )
        # An admin device creates pairing codes through the proxy too.
        name = unique("ci-device-paired")
        pairing = self.ok(
            device_request(
                admin_key, "POST", "/api/v1/client/pairings", body={"name": name}
            )
        )
        mask(pairing["code"])
        self.assertTrue(pairing["admin"])
        self.assertEqual(self.pairing_uri(pairing["code"]), pairing["uri"])
        redeemed = self.ok(self.redeem(pairing["code"]))
        mask(redeemed["clientKey"])
        self.assertEqual(name, redeemed["client"]["name"])
        self.assertTrue(redeemed["client"]["admin"])
        # The admin device learns through the proxy that its code was used; no other device can.
        used = self.ok(
            device_request(admin_key, "GET", f"/api/v1/client/pairings/{pairing['id']}")
        )
        self.assertEqual("REDEEMED", used["state"])
        self.assertEqual(name, used["client"]["name"])
        self.assertStatus(
            device_request(
                outsider["clientKey"], "GET", f"/api/v1/client/pairings/{pairing['id']}"
            ),
            403,
        )
        # The operator's pairing is not the admin device's.
        self.assertStatus(
            device_request(
                admin_key, "GET", f"/api/v1/client/pairings/{operator_pairing['id']}"
            ),
            404,
        )
        # Asking about pairings with the admin token is management, which never leaves the host.
        self.assertStatus(
            admin(
                "GET",
                f"/api/v1/admin/pairings/{operator_pairing['id']}",
                endpoint=proxy(),
            ),
            404,
        )

    def test_an_admin_device_revokes_a_device_and_deletes_it_once(self):
        admin_key = self.admin_device_key()
        device = self.paired_device("ci-paired-phone", create_user("ci-basic")["id"])
        device_id = device["client"]["id"]
        revoked = self.ok(
            device_request(
                admin_key, "POST", f"/api/v1/client/devices/{device_id}/revoke"
            )
        )
        self.assertIsNotNone(revoked["revokedAt"])
        self.assertStatus(
            device_request(device["clientKey"], "GET", "/api/v1/client"), 401
        )
        # The admin device deletes the revoked device through the proxy, once.
        for expected in (204, 404):
            self.assertStatus(
                device_request(
                    admin_key, "DELETE", f"/api/v1/client/devices/{device_id}"
                ),
                expected,
            )


class SelfService(StackTestCase):
    """Self-service is forwarded like the rest of /api/."""

    def basic_device_key(self) -> str:
        user = create_user("ci-basic")
        pairing = self.ok(
            admin(
                "POST",
                "/api/v1/admin/pairings",
                body={"name": unique("ci-basic-phone"), "userId": user["id"]},
            )
        )
        mask(pairing["code"])
        paired = self.ok(proxy().post("/api/v1/pairing", token=pairing["code"]))
        return mask(paired["clientKey"])

    def test_a_basic_users_device_registers_a_producer_and_sees_its_key_only_once(self):
        key = self.basic_device_key()
        own = self.ok(
            device_request(
                key, "POST", "/api/v1/client/producers", body={"name": unique("ci-own")}
            )
        )
        own_key = mask(own["apiKey"])
        listed = device_request(key, "GET", "/api/v1/client/producers")
        mine = [i for i in self.ok(listed)["items"] if i["id"] == own["producer"]["id"]]
        self.assertEqual("PRIVATE", mine[0]["visibility"])
        self.assertTrue(mine[0]["keys"][0]["prefix"].startswith("shpk1_"))
        self.assertNotIn(own_key, listed.text, "the producer list holds a key")

    def test_a_basic_users_device_lists_the_users_names_and_nothing_else(self):
        key = self.basic_device_key()
        users = self.ok(device_request(key, "GET", "/api/v1/client/users"))["items"]
        self.assertGreaterEqual(len(users), 2)
        for user in users:
            self.assertEqual(["id", "name"], sorted(user))

    def test_only_an_admin_device_invites_users(self):
        basic = self.basic_device_key()
        self.assertStatus(
            device_request(
                basic, "POST", "/api/v1/client/users", body={"name": "ci-invited"}
            ),
            403,
        )
        invited = self.ok(
            device_request(
                create_client("ci-admin-device")["clientKey"],
                "POST",
                "/api/v1/client/users",
                body={"name": unique("ci-invited"), "role": "MOD"},
            )
        )
        self.assertEqual("MOD", invited["user"]["role"])
        self.assertTrue(invited["pairing"]["code"].startswith("shpc1_"))
        mask(invited["pairing"]["code"])

    def test_another_users_producer_is_not_found(self):
        basic = self.basic_device_key()
        own = self.ok(
            device_request(
                basic,
                "POST",
                "/api/v1/client/producers",
                body={"name": unique("ci-own")},
            )
        )
        mask(own["apiKey"])
        self.assertStatus(
            device_request(
                create_client("ci-admin-device")["clientKey"],
                "GET",
                f"/api/v1/client/producers/{own['producer']['id']}",
            ),
            404,
        )

    def test_the_admin_token_is_no_client_key(self):
        self.assertStatus(
            device_request(admin_token(), "GET", "/api/v1/client/producers"), 401
        )


if __name__ == "__main__":
    unittest.main()
