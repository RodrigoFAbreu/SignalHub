import { BASE, browserSession, createPerson, operator, unique } from "../support/server.mjs";
import { adminSignIn, expect, test } from "../support/page.mjs";

const NOW = () => new Date().toISOString();
const ago = (ms) => new Date(Date.now() - ms).toISOString();

const sample = (name, extra = {}) => ({
  id: crypto.randomUUID(),
  name,
  admin: false,
  kind: "DEVICE",
  user: { id: crypto.randomUUID(), name: "Ana", role: "MOD" },
  createdAt: ago(5 * 86_400_000),
  lastActiveAt: ago(180_000),
  expiresAt: null,
  revokedAt: null,
  pushTarget: { provider: "fcm", updatedAt: ago(5 * 86_400_000) },
  pushPreferences: {},
  pushStatus: { lastSuccess: { at: ago(3_600_000), eventId: crypto.randomUUID() }, lastFailure: null, pendingRetries: 0 },
  ...extra,
});

const failure = (result, extra = {}) => ({ at: ago(60_000), eventId: crypto.randomUUID(), result, ...extra });

/** A device list the page reads in place of the server's, for the words that need a push service. */
async function mockList(page, items) {
  await page.route("**/api/v1/admin/clients", (route) => (route.request().method() === "GET" ? route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items }) }) : route.continue()));
}

const row = (page, name) => page.getByRole("row", { name: new RegExp(`^${name}`) });

test("each device and browser is a row with its user, last activity and how its push is going in words; Push problems counts only the ones that need a look", async ({ page }) => {
  const rodrigo = { id: crypto.randomUUID(), name: "Rodrigo", role: "ADMIN" };
  const items = [
    sample("Working one", { user: rodrigo, admin: true }),
    sample("Retrying one", { pushStatus: { lastSuccess: null, lastFailure: failure("TRANSIENT_FAILURE"), pendingRetries: 2 } }),
    sample("Gave up one", { pushStatus: { lastSuccess: null, lastFailure: failure("TRANSIENT_FAILURE"), pendingRetries: 0 } }),
    sample("Refused one", { pushStatus: { lastSuccess: null, lastFailure: failure("PERMANENT_FAILURE"), pendingRetries: 0 } }),
    sample("Rejected one", { pushTarget: null, pushStatus: { lastSuccess: null, lastFailure: failure("INVALID_TARGET"), pendingRetries: 0 } }),
    sample("No address one", { pushTarget: null, pushStatus: { lastSuccess: null, lastFailure: null, pendingRetries: 0 } }),
    sample("Laptop browser", { kind: "BROWSER", pushTarget: null, expiresAt: new Date(Date.now() + 20 * 86_400_000).toISOString(), pushStatus: { lastSuccess: null, lastFailure: null, pendingRetries: 0 } }),
    sample("Old phone", { revokedAt: ago(2 * 86_400_000), lastActiveAt: ago(2 * 86_400_000) }),
  ];
  await mockList(page, items);
  await adminSignIn(page, "#devices");
  await expect(page.getByRole("heading", { name: "Devices", level: 1 })).toBeVisible();
  await expect(page.locator(".mhead .cnt").first()).toHaveText("8 devices · 7 active");
  await expect(row(page, "Working one")).toContainText("Admin device");
  await expect(row(page, "Working one")).toContainText("Rodrigo");
  await expect(row(page, "Working one")).toContainText("Working");
  await expect(row(page, "Working one")).toContainText("3 min ago");
  await expect(row(page, "Retrying one")).toContainText("Last push failed, retrying");
  await expect(row(page, "Gave up one")).toContainText("Gave up after 5 tries");
  await expect(row(page, "Refused one")).toContainText("Last push failed");
  await expect(row(page, "Rejected one")).toContainText("Push address rejected");
  await expect(row(page, "No address one")).toContainText("No push address");
  // A browser has no push address by design: neutral, not a problem, and never an Admin device tag.
  await expect(row(page, "Laptop browser")).toContainText("Browser");
  await expect(row(page, "Laptop browser")).not.toContainText("Admin device");
  await expect(row(page, "Laptop browser")).toContainText("No push address");
  await expect(row(page, "Old phone")).toContainText("Revoked");
  // Active ones first, revoked last.
  const names = await page.getByRole("row").locator(".nm").allInnerTexts();
  expect(names.at(-1)).toBe("Old phone");
  // Push problems: only the rows that need a look.
  await expect(page.getByRole("button", { name: "Push problems · 4" })).toBeVisible();
  await page.getByRole("button", { name: "Push problems · 4" }).click();
  await expect(page).toHaveURL(/#devices\?f=problems$/);
  await expect(page.getByRole("row")).toHaveCount(5);
  await expect(row(page, "No address one")).toHaveCount(0);
  await expect(page.locator(".mhead .cnt").first()).toHaveText("4 of 8 devices · 7 active");
  // The kind and user menus narrow it too.
  await page.getByRole("button", { name: "All", exact: true }).click();
  await page.getByRole("button", { name: "Kind" }).click();
  await page.getByRole("menuitemradio", { name: "Browsers" }).click();
  await expect(page.getByRole("row")).toHaveCount(2);
  await expect(page.getByRole("button", { name: "Kind: Browsers" })).toBeVisible();
});

test("a device with a push problem says what is wrong in words; the codes and ids are only under Technical details", async ({ page }) => {
  const eventId = crypto.randomUUID();
  const goneId = crypto.randomUUID();
  const retrying = sample("Retrying tab", { pushStatus: { lastSuccess: { at: ago(3 * 3_600_000), eventId: goneId }, lastFailure: failure("TRANSIENT_FAILURE", { at: ago(40 * 60_000), eventId }), pendingRetries: 2 } });
  const gaveUp = sample("Gave up tab", { pushStatus: { lastSuccess: null, lastFailure: failure("TRANSIENT_FAILURE"), pendingRetries: 0 } });
  await mockList(page, [retrying, gaveUp]);
  await page.route(`**/api/v1/events/${eventId}`, (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ id: eventId, title: "Build 1842 failed on main" }) }));
  await page.route(`**/api/v1/events/${goneId}`, (route) => route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ title: "Not Found" }) }));
  await page.route(`**/api/v1/admin/events/${gaveUp.pushStatus.lastFailure.eventId}/deliveries`, (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [{ clientId: gaveUp.id, attempt: 5, outcome: "TRANSIENT_FAILURE", final: true }], users: [] }) }),
  );
  await adminSignIn(page, "#devices");
  await row(page, "Retrying tab").click();
  const pane = page.getByRole("region", { name: "Retrying tab" });
  await expect(pane).toContainText("Ana · Mod");
  await expect(pane).toContainText("Last push failed, retrying");
  await expect(pane).toContainText("Last push failed · 40 min ago");
  await expect(pane).toContainText("Build 1842 failed on main");
  await expect(pane.getByRole("link", { name: "Open event" }).first()).toHaveAttribute("href", `#events/${eventId}`);
  await expect(pane).toContainText("The push service did not accept it this time. SignalHub tries again by itself, up to 5 tries in all.");
  await expect(pane).toContainText("2 pushes waiting for a retry");
  await expect(pane).toContainText("Last push accepted · 3 h ago");
  await expect(pane).toContainText("That event was deleted");
  await expect(pane).toContainText("Firebase Cloud Messaging, set ");
  await expect(pane.getByText("TRANSIENT_FAILURE")).toHaveCount(0);
  await pane.getByRole("button", { name: "Technical details" }).click();
  await expect(pane.getByText("TRANSIENT_FAILURE")).toBeVisible();
  await expect(pane.getByText(retrying.id)).toBeVisible();
  // A push that gave up says how many tries, from the delivery record's final marker.
  await row(page, "Gave up tab").click();
  await expect(page.getByRole("region", { name: "Gave up tab" })).toContainText("Gave up after 5 tries.");
});

test("connecting a device: a dialog with the user chosen as Name · Role, the admin sentence, then the code, its link, the countdown and who used it", async ({ page }) => {
  const admin = await createPerson("ADMIN");
  const mod = await createPerson("MOD");
  await adminSignIn(page, "#devices");
  await page.getByRole("button", { name: "Connect a device" }).first().click();
  const dialog = page.getByRole("dialog", { name: "Connect a device" });
  const name = dialog.getByLabel("Device name");
  // The name starts as New device, with the focus in it, selected.
  await expect(name).toBeFocused();
  await expect(name).toHaveValue("New device");
  const create = dialog.getByRole("button", { name: "Create pairing code" });
  await name.fill("");
  await name.blur();
  await expect(dialog.getByText("Give the device a name.")).toBeVisible();
  await expect(create).toBeDisabled();
  const deviceName = unique("Tablet");
  await name.fill(deviceName);
  await dialog.getByLabel("User").selectOption({ label: `${mod.name} · Mod` });
  await expect(dialog.getByText("It will be an admin device.")).toBeHidden();
  await dialog.getByLabel("User").selectOption({ label: `${admin.name} · Admin` });
  await expect(dialog.getByText("It will be an admin device.")).toBeVisible();
  await expect(dialog.getByText("An admin device connects and revokes other devices and invites users.")).toBeVisible();
  await dialog.getByLabel("User").selectOption({ label: `${mod.name} · Mod` });
  await create.click();

  const code = page.getByRole("dialog", { name: `Pairing code for ${deviceName}` });
  await expect(code).toBeVisible();
  await expect(code).toContainText(`For ${mod.name} (Mod).`);
  await expect(code).toContainText(/Expires in \d:\d\d\. It works once\./);
  await expect(code).toContainText("Waiting for the device to use it…");
  await expect(code).toContainText(`Anyone with this code`);
  const text = await code.innerText();
  const pairingCode = text.match(/shpc1_[A-Za-z0-9_-]+/)?.[0];
  expect(pairingCode, "the code, in the link or on its own").toBeTruthy();
  if (await code.locator("canvas").count()) {
    await expect(code.getByRole("img", { name: "Pairing QR code" })).toBeVisible();
    await code.getByRole("button", { name: "Copy link" }).click();
    await expect(code.getByText("Link copied.")).toBeVisible();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toContain(pairingCode);
    await expect(code.getByRole("button", { name: "Download QR" })).toBeVisible();
  } else {
    await expect(code.getByText("No link or QR code this time")).toBeVisible();
  }
  // The code is open until it is used: Done closes the dialog and the code is listed.
  await code.getByRole("button", { name: "Done" }).click();
  const open = page.getByRole("region", { name: "Open pairing codes" });
  await expect(open).toContainText(deviceName);
  await expect(open).toContainText(`For ${mod.name}`);
  await expect(open).not.toContainText(pairingCode);
  // A device uses it, and the page says which, here in the list.
  const redeemed = await fetch(`${BASE}/api/v1/pairing`, { method: "POST", headers: { Authorization: `Bearer ${pairingCode}` } });
  expect(redeemed.status).toBe(201);
  await page.getByRole("button", { name: "Refresh" }).click();
  await expect(open).toHaveCount(0);
  await page.getByRole("searchbox", { name: "Find a device" }).fill(deviceName);
  await expect(row(page, deviceName)).toContainText(mod.name);
});

test("a pairing code shown in the dialog learns that it was used, says by which device, and can show the device", async ({ page }) => {
  const person = await createPerson("BASIC");
  await adminSignIn(page, "#devices");
  await page.getByRole("button", { name: "Connect a device" }).first().click();
  const dialog = page.getByRole("dialog", { name: "Connect a device" });
  const deviceName = unique("Phone");
  await dialog.getByLabel("Device name").fill(deviceName);
  await dialog.getByLabel("User").selectOption({ label: `${person.name} · Basic` });
  await dialog.getByRole("button", { name: "Create pairing code" }).click();
  const code = page.getByRole("dialog", { name: `Pairing code for ${deviceName}` });
  const pairingCode = (await code.innerText()).match(/shpc1_[A-Za-z0-9_-]+/)[0];
  const redeemed = await fetch(`${BASE}/api/v1/pairing`, { method: "POST", headers: { Authorization: `Bearer ${pairingCode}` } });
  expect(redeemed.status).toBe(201);
  const used = page.getByRole("dialog", { name: "Device connected" });
  await expect(used).toBeVisible({ timeout: 15_000 });
  await expect(used).toContainText(`Used by “${deviceName}”`);
  await expect(used).toContainText(`The device belongs to ${person.name} (Basic) and is connected`);
  await used.getByRole("button", { name: "Show the device" }).click();
  await expect(page).toHaveURL(/#devices\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("region", { name: deviceName })).toBeVisible();
});

test("a pairing code can be cancelled while it is unused, and then it can never be used", async ({ page }) => {
  const person = await createPerson("BASIC");
  await adminSignIn(page, "#devices");
  await page.getByRole("button", { name: "Connect a device" }).first().click();
  const dialog = page.getByRole("dialog", { name: "Connect a device" });
  const deviceName = unique("Cancelled");
  await dialog.getByLabel("Device name").fill(deviceName);
  await dialog.getByLabel("User").selectOption({ label: `${person.name} · Basic` });
  await dialog.getByRole("button", { name: "Create pairing code" }).click();
  const code = page.getByRole("dialog", { name: `Pairing code for ${deviceName}` });
  const pairingCode = (await code.innerText()).match(/shpc1_[A-Za-z0-9_-]+/)[0];
  await code.getByRole("button", { name: "Cancel this code" }).click();
  const ask = page.getByRole("dialog", { name: "Cancel this code?" });
  await ask.getByRole("button", { name: "Cancel this code" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.getByText("Pairing code cancelled.")).toBeVisible();
  const redeemed = await fetch(`${BASE}/api/v1/pairing`, { method: "POST", headers: { Authorization: `Bearer ${pairingCode}` } });
  expect(redeemed.status).toBeGreaterThanOrEqual(400);
  await expect(page.getByRole("region", { name: "Open pairing codes" }).getByText(deviceName)).toHaveCount(0);
});

test("a code that is not used in time says so, and a new one is made for the same device and user", async ({ page }) => {
  const person = await createPerson("BASIC");
  const bodies = [];
  await page.route("**/api/v1/admin/pairings", async (route) => {
    if (route.request().method() !== "POST") return route.continue();
    bodies.push(route.request().postDataJSON());
    return route.fulfill({
      status: 201,
      contentType: "application/json",
      body: JSON.stringify({ id: crypto.randomUUID(), name: bodies.at(-1).name, admin: false, user: { id: person.userId, name: person.name, role: "BASIC" }, code: "shpc1_EXAMPLE-not-a-code0000", expiresAt: new Date(Date.now() + 2500).toISOString(), uri: "signalhub://pair?server=https%3A%2F%2Fsignalhub.example&code=shpc1_EXAMPLE-not-a-code0000" }),
    });
  });
  await page.route("**/api/v1/admin/pairings/*", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ id: "x", state: "PENDING", expiresAt: NOW(), redeemedAt: null, client: null }) }));
  await adminSignIn(page, "#devices");
  await page.getByRole("button", { name: "Connect a device" }).first().click();
  const dialog = page.getByRole("dialog", { name: "Connect a device" });
  const deviceName = unique("Late");
  await dialog.getByLabel("Device name").fill(deviceName);
  await dialog.getByLabel("User").selectOption({ label: `${person.name} · Basic` });
  await dialog.getByRole("button", { name: "Create pairing code" }).click();
  const expired = page.getByRole("dialog", { name: `Pairing code for ${deviceName}` });
  await expect(expired.getByText("This code expired")).toBeVisible({ timeout: 10_000 });
  await expect(expired.getByText(/^Expired at \d\d:\d\d\.$/)).toBeVisible();
  await expect(expired.getByText("Nobody used it in time, and it no longer works.")).toBeVisible();
  // A dead code is never copied: its link is gone.
  await expect(expired.getByText("signalhub://")).toHaveCount(0);
  await expired.getByRole("button", { name: "Make a new code" }).click();
  await expect.poll(() => bodies.length).toBe(2);
  expect(bodies[1]).toEqual(bodies[0]);
});

test("renaming a device is a dialog; an empty name is refused on the field; success is a snack bar with no Undo, and the pane shows the new name", async ({ page }) => {
  const person = await createPerson("BASIC");
  await adminSignIn(page, "#devices");
  await page.getByRole("searchbox", { name: "Find a device" }).fill(person.deviceName);
  await row(page, person.deviceName).click();
  const pane = page.getByRole("region", { name: person.deviceName });
  await pane.getByRole("button", { name: `Rename ${person.deviceName}` }).first().click();
  const dialog = page.getByRole("dialog", { name: "Rename the device" });
  const field = dialog.getByLabel("Name");
  await expect(field).toBeFocused();
  await field.fill("");
  await dialog.getByRole("button", { name: "Rename" }).click();
  await expect(dialog.getByText("Give the device a name.")).toBeVisible();
  const renamed = unique("Renamed");
  await field.fill(renamed);
  await dialog.getByRole("button", { name: "Rename" }).click();
  await expect(page.getByRole("status").filter({ hasText: `Renamed to “${renamed}”.` })).toBeVisible();
  await expect(page.getByRole("button", { name: "Undo" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Dismiss" })).toBeVisible();
  await expect(page.getByRole("region", { name: renamed })).toBeVisible();
});

test("revoking asks first with Cancel focused, waits, says when it did not work and offers Try again; a revoked device can only be deleted, after a question", async ({ page }) => {
  const person = await createPerson("MOD");
  await adminSignIn(page, "#devices");
  await page.getByRole("searchbox", { name: "Find a device" }).fill(person.deviceName);
  await row(page, person.deviceName).click();
  const pane = page.getByRole("region", { name: person.deviceName });
  let fail = true;
  await page.route(`**/api/v1/admin/clients/${person.deviceId}/revoke`, (route) => (fail ? route.fulfill({ status: 500, body: "" }) : route.continue()));
  await pane.getByRole("button", { name: `Revoke ${person.deviceName}`, exact: true }).click();
  const dialog = page.getByRole("dialog", { name: `Revoke “${person.deviceName}”?` });
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
  await expect(dialog).toContainText("It stops working at once, for good, and gets no more pushes.");
  await expect(dialog).toContainText("Nobody is told.");
  await dialog.getByRole("button", { name: `Revoke ${person.deviceName}` }).click();
  await expect(dialog.getByRole("alert")).toContainText("Could not revoke it: SignalHub answered 500. Nothing changed.");
  await expect(dialog.getByRole("button", { name: `Revoke ${person.deviceName}` })).toHaveText("Try again");
  fail = false;
  await dialog.getByRole("button", { name: `Revoke ${person.deviceName}` }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.getByRole("status").filter({ hasText: `Revoked “${person.deviceName}”.` })).toBeVisible();
  // It stops working at once.
  expect((await fetch(`${BASE}/api/v1/client/server`, { headers: { Authorization: `Bearer ${person.key}` } })).status).toBe(401);
  await expect(pane.getByText(/^Revoked on /)).toBeVisible();
  await expect(pane.getByRole("button", { name: `Revoke ${person.deviceName}`, exact: true })).toHaveCount(0);
  await expect(pane.getByRole("button", { name: `Rename ${person.deviceName}` })).toHaveCount(0);
  await pane.getByRole("button", { name: `Delete ${person.deviceName}` }).click();
  const ask = page.getByRole("dialog", { name: `Delete “${person.deviceName}”?` });
  await expect(ask).toContainText("It leaves this list for good");
  await ask.getByRole("button", { name: `Delete ${person.deviceName}` }).click();
  await expect(page.getByRole("status").filter({ hasText: `Deleted “${person.deviceName}”.` })).toBeVisible();
  await expect(page.getByRole("region", { name: person.deviceName })).toHaveCount(0);
  await expect(row(page, person.deviceName)).toHaveCount(0);
});

test("a signed-in browser says Signed in and Signs out, has no push section and no Admin device tag, and its revoke is worded as a sign-out", async ({ page }) => {
  const person = await createPerson("ADMIN");
  const session = await browserSession(person);
  await adminSignIn(page, "#devices");
  await page.getByRole("button", { name: "Kind" }).click();
  await page.getByRole("menuitemradio", { name: "Browsers" }).click();
  await page.getByRole("searchbox", { name: "Find a device" }).fill(person.name);
  const browserRow = page.getByRole("row", { name: new RegExp(`browser, ${person.name}`) }).first();
  await browserRow.click();
  const pane = page.locator("section.pane:not(.prompt)");
  await expect(pane).toContainText("Signed in");
  await expect(pane).toContainText("Signs out");
  await expect(pane).toContainText("by itself");
  await expect(pane).toContainText("No push for browsers");
  await expect(pane.getByText("Admin device")).toHaveCount(0);
  await pane.getByRole("button", { name: /^Revoke /, exact: false }).first().click();
  const dialog = page.getByRole("dialog", { name: /^Sign out “/ });
  await expect(dialog).toContainText("The browser is signed out at once. Signing in again needs a new approval from a device.");
  await dialog.getByRole("button", { name: "Cancel" }).click();
  void session;
});

test("a device name is shown as text, never as markup", async ({ page }) => {
  const markup = `<img src=x onerror="window.__pwned=1" alt="${unique("device")}">`;
  const person = await createPerson("BASIC", unique("xss"));
  await operator("PATCH", `/api/v1/admin/clients/${person.deviceId}`, { name: markup });
  await adminSignIn(page, "#devices");
  await page.getByRole("searchbox", { name: "Find a device" }).fill(markup);
  await expect(page.getByRole("row", { name: new RegExp(`^${markup.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`) })).toBeVisible();
  expect(await page.evaluate(() => window.__pwned)).toBeUndefined();
  expect(await page.locator("img").count()).toBe(0);
});

test("the empty list says what a device is, and offers to connect the first", async ({ page }) => {
  await mockList(page, []);
  await adminSignIn(page, "#devices");
  await expect(page.getByRole("heading", { name: "No device yet" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Connect a device" })).toHaveCount(2);
});
