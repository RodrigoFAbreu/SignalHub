import { createServer } from "node:http";
import { BASE, asDevice, browserSession, createPerson, useSession } from "../support/server.mjs";
import { expect, sessionCookie, signIn, test } from "../support/page.mjs";

test("the session cookie is HttpOnly, Secure, SameSite=Strict and lasts 30 days, and no script can read it", async ({ page }) => {
  const person = await createPerson("BASIC");
  await signIn(page, person);
  const cookie = await sessionCookie(page);
  expect(cookie).toBeTruthy();
  expect(cookie.httpOnly).toBe(true);
  expect(cookie.secure).toBe(true);
  expect(cookie.sameSite).toBe("Strict");
  expect(cookie.path).toBe("/");
  const days = (cookie.expires - Date.now() / 1000) / 86_400;
  expect(days).toBeGreaterThan(29.9);
  expect(days).toBeLessThan(30.1);
  expect(await page.evaluate(() => document.cookie)).toBe("");
  // Nothing secret is kept in storage either: only the UI preferences and a hint.
  const stored = await page.evaluate(() => JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }));
  expect(stored).not.toContain(cookie.value);
  expect(stored).not.toMatch(/shck1_|shsp1_|shsc1_/);
});

test("a state-changing request needs the token: without it, or from another origin, nothing changes", async ({ page }) => {
  const person = await createPerson("BASIC");
  await signIn(page, person);
  const me = await page.evaluate(() => fetch("/api/v1/web/session", { credentials: "same-origin" }).then((r) => r.json()));
  const patch = (headers) =>
    page.evaluate(async ({ id, headers }) => {
      const response = await fetch(`/api/v1/client/devices/${id}`, { method: "PATCH", credentials: "same-origin", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify({ name: "Renamed" }) });
      return response.status;
    }, { id: me.client.id, headers });

  expect(await patch({})).toBe(403);
  expect(await patch({ "X-SignalHub-CSRF": "wrong" })).toBe(403);
  expect(await patch({ "X-SignalHub-CSRF": me.csrfToken })).toBe(200);
});

test("another origin's page cannot use the session, with or without the cookie reaching the server", async ({ page }) => {
  const person = await createPerson("BASIC");
  await signIn(page, person);
  const before = await page.evaluate(() => fetch("/api/v1/web/session", { credentials: "same-origin" }).then((r) => r.json()));

  // A second origin the test serves: another port on the same host is the same *site*, so the
  // browser does send the SameSite=Strict cookie there; the server's own checks must stop it.
  const evil = createServer((request, response) => {
    response.setHeader("Content-Type", "text/html");
    response.end(`<!doctype html><body><script>
      fetch(${JSON.stringify(BASE)} + "/api/v1/web/session/sign-out", { method: "POST", credentials: "include", mode: "no-cors" });
      fetch(${JSON.stringify(BASE)} + "/api/v1/client/devices/${before.client.id}", { method: "DELETE", credentials: "include", mode: "no-cors", headers: { "X-SignalHub-CSRF": "guess" } });
    </script>
    <form id="f" method="POST" action="${BASE}/api/v1/web/session/sign-out"></form>
    <script>document.getElementById("f").submit()</script></body>`);
  });
  await new Promise((resolve) => evil.listen(0, "127.0.0.1", resolve));
  try {
    const origins = [`http://127.0.0.1:${evil.address().port}/`, `http://localhost:${evil.address().port}/`];
    for (const origin of origins) {
      // The victim opens the attacker's page in another tab of the same browser.
      const victim = await page.context().newPage();
      await victim.goto(origin);
      await victim.waitForTimeout(800);
      await victim.close();
    }
  } finally {
    evil.close();
  }
  const after = await page.evaluate(() => fetch("/api/v1/web/session", { credentials: "same-origin" }).then((r) => r.status));
  expect(after).toBe(200);
  // And the browser is still listed as active.
  const devices = await asDevice(person, "GET", "/api/v1/client/devices");
  expect(devices.items.find((device) => device.id === before.client.id).revokedAt).toBeNull();
});

test("revoking the browser from a device shows the signed-out page on the next request, never the old content", async ({ page }) => {
  const person = await createPerson("BASIC");
  await signIn(page, person);
  const me = await page.evaluate(() => fetch("/api/v1/web/session", { credentials: "same-origin" }).then((r) => r.json()));
  await asDevice(person, "POST", `/api/v1/client/devices/${me.client.id}/revoke`);
  await page.getByRole("link", { name: "Producers" }).click();
  await expect(page.getByRole("heading", { name: "You're signed out" })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Main" })).toHaveCount(0);
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  // It keeps the address, so signing in again returns to the same place.
  await expect(page).toHaveURL(/#producers$/);
});

test("signing out asks first, ends the session and tells the other tabs", async ({ context, page }) => {
  const person = await createPerson("BASIC");
  await signIn(page, person);
  const other = await context.newPage();
  await other.goto("/app/#inbox");
  await expect(other.getByRole("navigation", { name: "Main" })).toBeVisible();

  await page.getByRole("link", { name: "Settings" }).click();
  await page.getByRole("button", { name: "Sign out" }).click();
  const dialog = page.getByRole("dialog", { name: "Sign out of this browser?" });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByText("This browser stops being a device of yours. Your phone and your other devices are not affected.")).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
  await dialog.getByRole("button", { name: "Sign out" }).click();

  await expect(page.getByRole("heading", { name: "You're signed out" })).toBeVisible();
  expect(await sessionCookie(page)).toBeUndefined();
  await expect(other.getByText("You signed out in another tab.")).toBeVisible();
  await other.getByRole("button", { name: "Sign in again" }).click();
  await expect(other.getByRole("heading", { name: "Sign in again" })).toBeVisible();
  // The person's phone is untouched.
  const devices = await asDevice(person, "GET", "/api/v1/client/devices");
  expect(devices.items.filter((device) => device.kind === "DEVICE" && !device.revokedAt)).toHaveLength(1);
});

test("when the 30 days end the page says so, keeps what it shows and signs in again at the same address", async ({ page, context }) => {
  const person = await createPerson("BASIC");
  const session = await browserSession(person);
  await useSession(context, session);
  const real = await (await fetch(`${BASE}/api/v1/web/session`, { headers: { Cookie: `__Host-signalhub_session=${session.value}` } })).json();
  const ended = { ...real, client: { ...real.client, expiresAt: new Date(Date.now() - 1000).toISOString() } };
  await page.route("**/api/v1/web/session", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(ended) }));
  await page.route("**/api/v1/client/**", (route) => route.fulfill({ status: 401, contentType: "application/json", body: "{}" }));
  await page.goto("/app/#settings/devices");
  await expect(page.getByText("Your sign-in ended.")).toBeVisible();
  await page.getByRole("button", { name: "Sign in again" }).click();
  await expect(page.getByRole("heading", { name: "Sign in again" })).toBeVisible();
  await expect(page).toHaveURL(/#settings\/devices$/);
});
