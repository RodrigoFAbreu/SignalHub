import { asDevice, browserSession, createPerson, operator, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

async function signedIn(context, page, role, hash) {
  const person = await createPerson(role);
  const session = await browserSession(person);
  await useSession(context, session);
  await page.goto(`/app/${hash}`);
  return { person, session };
}

test("an admin sees People in the rail, and everyone's devices grouped by person", async ({ context, page }) => {
  const other = await createPerson("MOD");
  await browserSession(other);
  const { person } = await signedIn(context, page, "ADMIN", "#settings/devices");
  await expect(page.getByRole("link", { name: "People" })).toBeVisible();
  await expect(page.getByRole("heading", { name: person.name, level: 2 })).toBeVisible();
  await expect(page.getByRole("heading", { name: other.name, level: 2 })).toBeVisible();
  // Own heading first, with the You tag; the admin's own phone is an admin device with no controls.
  await expect(page.locator(".rolesec").first()).toContainText(`${person.name}You`);
  const adminPhone = page.locator(".device-row", { hasText: person.deviceName });
  await expect(adminPhone).toContainText("Admin device");
  await expect(adminPhone.getByRole("button")).toHaveCount(0);
  // Another user's phone and browser can be revoked or renamed.
  const phone = page.locator(".device-row", { hasText: other.deviceName });
  await expect(phone.getByRole("button", { name: `Revoke ${other.deviceName}` })).toBeVisible();
  await expect(phone.getByRole("button", { name: `More actions for ${other.deviceName}` })).toBeVisible();
  // This browser has a tag, and no Revoke: signing out is in Settings.
  const here = page.locator(".device-row", { hasText: "This browser" });
  await expect(here).toContainText("Browser");
  await expect(here.getByRole("button")).toHaveCount(0);
});

test("a mod sees only their own devices and can rename and revoke them", async ({ context, page }) => {
  const stranger = await createPerson("BASIC");
  const { person } = await signedIn(context, page, "MOD", "#settings/devices");
  await expect(page.getByRole("link", { name: "People" })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Your devices" })).toBeVisible();
  await expect(page.locator(".device-row", { hasText: person.deviceName })).toBeVisible();
  await expect(page.getByText(stranger.deviceName)).toHaveCount(0);
  // A second device can be revoked; the last active one cannot (the browser does not count).
  const second = await operator("POST", "/api/v1/admin/clients", { name: "Second phone", userId: person.userId });
  await page.reload();
  await page.getByRole("button", { name: "Revoke Second phone" }).click();
  const dialog = page.getByRole("dialog", { name: "Revoke Second phone?" });
  await expect(dialog).toContainText("It stops getting events at once and can't be used again.");
  await dialog.getByRole("button", { name: "Revoke" }).click();
  await expect(page.locator(".device-row", { hasText: "Second phone" })).toContainText("Revoked");
  await page.getByRole("button", { name: "Revoke Second phone" }).count();
  await page.getByRole("button", { name: `Revoke ${person.deviceName}` }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Revoke" }).click();
  await expect(page.getByRole("dialog")).toContainText("It's your last active device. Revoking it would lock you out. Connect another device first.");
  await page.getByRole("dialog").getByRole("button", { name: "Cancel" }).click();
  // A revoked device is deleted after a confirmation.
  await page.getByRole("button", { name: "Delete Second phone" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
  await expect(page.locator(".device-row", { hasText: "Second phone" })).toHaveCount(0);
  void second;
});

test("a basic user has no People, reads their devices, and signs out, renames and deletes their own browsers only", async ({ context, page }) => {
  const { person } = await signedIn(context, page, "BASIC", "#settings/devices");
  const second = await browserSession(person, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36");
  await page.reload();
  await expect(page.getByRole("link", { name: "People" })).toHaveCount(0);
  await expect(page.getByText("To add or remove a device, ask an admin of this server.")).toBeVisible();
  // The phone has no control at all: a basic user cannot change devices.
  const phone = page.locator(".device-row", { hasText: person.deviceName });
  await expect(phone.getByRole("button")).toHaveCount(0);
  const chrome = page.locator(".device-row", { hasText: "Chrome on Windows" });
  await chrome.getByRole("button", { name: "More actions for Chrome on Windows" }).click();
  await page.getByRole("menuitem", { name: "Rename" }).click();
  await page.getByLabel("Device name").fill("Work laptop");
  await page.getByRole("button", { name: "Save" }).click();
  const renamed = page.locator(".device-row", { hasText: "Work laptop" });
  await expect(renamed).toBeVisible();
  await renamed.getByRole("button", { name: "Revoke Work laptop" }).click();
  const dialog = page.getByRole("dialog", { name: "Revoke Work laptop?" });
  await expect(dialog).toContainText("It is signed out at once and stops being a device of yours. You can sign it in again later from your phone.");
  await dialog.getByRole("button", { name: "Revoke" }).click();
  await expect(renamed).toContainText("Revoked");
  // The revoked browser really is signed out.
  const gone = await fetch(`${new URL(page.url()).origin}/api/v1/web/session`, { headers: { Cookie: `__Host-signalhub_session=${second.value}` } });
  expect(gone.status).toBe(401);
  await renamed.getByRole("button", { name: "Delete Work laptop" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
  await expect(page.locator(".device-row", { hasText: "Work laptop" })).toHaveCount(0);
  const left = await asDevice(person, "GET", "/api/v1/client/devices");
  expect(left.items.map((device) => device.name)).not.toContain("Work laptop");
});

test("an address that is not a page is the not-found page, and People is not a page for anyone but an admin", async ({ context, page }) => {
  await signedIn(context, page, "MOD", "#people");
  await expect(page.getByRole("heading", { name: "This page isn't here" })).toBeVisible();
  await expect(page.getByText("Check the address, or go back to your inbox.")).toBeVisible();
  await page.goto("/app/#nowhere/at/all");
  await expect(page.getByRole("heading", { name: "This page isn't here" })).toBeVisible();
  await page.getByRole("button", { name: "Go to the inbox" }).click();
  await expect(page).toHaveURL(/#inbox$/);
});

test("Settings is the same for every role: Devices, About this server and this browser, with Sign out", async ({ context, page }) => {
  const { session } = await signedIn(context, page, "BASIC", "#settings");
  void session;
  await expect(page.getByRole("heading", { name: "Settings", level: 1 })).toBeVisible();
  await expect(page.getByRole("link", { name: /^Devices/ })).toContainText("2 devices · 1 browser");
  const about = page.getByRole("button", { name: /About this server/ });
  await expect(about).toHaveAttribute("aria-expanded", "true");
  await expect(page.getByText("The host runs this server and can see every event on it.")).toBeVisible();
  await expect(page.getByText(/^SignalHub .* · commit /).first()).toBeVisible();
  await expect(page.getByText("Signing out here leaves your phone's app untouched.")).toBeVisible();
  // A folding group stays as the person left it.
  await about.click();
  await expect(about).toHaveAttribute("aria-expanded", "false");
  await page.reload();
  await expect(page.getByRole("button", { name: /About this server/ })).toHaveAttribute("aria-expanded", "false");
  await page.getByRole("button", { name: "Rename" }).click();
  await page.getByLabel("Device name").fill("Kitchen tablet");
  await page.getByRole("button", { name: "Save" }).click();
  await expect(page.getByRole("button", { name: /This browser/ })).toContainText("Kitchen tablet");
});
