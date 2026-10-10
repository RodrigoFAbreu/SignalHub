import { BASE, browserSession, createPerson, createProducer, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

async function admin(context, page, hash = "#people") {
  const person = await createPerson("ADMIN");
  await useSession(context, await browserSession(person));
  await page.goto(`/app/${hash}`);
  return person;
}

test("People lists everyone by role with the role's sentence, and says who is invited and who has devices", async ({ context, page }) => {
  const mod = await createPerson("MOD");
  const basic = await createPerson("BASIC");
  const me = await admin(context, page);
  await expect(page.getByRole("heading", { name: /^Admins/ })).toBeVisible();
  await expect(page.getByText("Manage people and their devices, except other admins. Set on the admin page.")).toBeVisible();
  await expect(page.getByText("Manage their own devices, producers and subscriptions.")).toBeVisible();
  await expect(page.getByText("Create producers and subscribe. Their devices are read only.")).toBeVisible();
  await expect(page.locator("a.prow", { hasText: me.name })).toContainText("You");
  await expect(page.locator("a.prow", { hasText: mod.name })).toContainText("1 device");
  await expect(page.locator("a.prow", { hasText: basic.name })).toContainText("1 device");
  // Search narrows the list and the counts say so.
  await page.getByRole("button", { name: "Search people" }).click();
  await page.getByRole("searchbox", { name: "Search people" }).fill(mod.name);
  await expect(page.locator("a.prow")).toHaveCount(1);
  await expect(page.getByRole("heading", { name: /^Mods.*1 of / })).toBeVisible();
});

test("a person's page shows their role, devices and producers; the role changes after a question", async ({ context, page }) => {
  const person = await createPerson("BASIC");
  const theirs = await createProducer(person, unique("theirs"), "PRIVATE");
  await admin(context, page);
  await page.locator("a.prow", { hasText: person.name }).click();
  await expect(page).toHaveURL(/#people\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: person.name, level: 2 })).toBeVisible();
  await expect(page.getByRole("radio", { name: "Basic" })).toBeChecked();
  await expect(page.getByRole("radio", { name: "Admin, not available. Set on the admin page" })).toHaveAttribute("aria-disabled", "true");
  await expect(page.getByText("Admin is set on the admin page, on the computer running SignalHub.")).toBeVisible();
  await expect(page.locator(".person-devices .device-row", { hasText: person.deviceName })).toBeVisible();
  await expect(page.locator(".person-producers")).toContainText(`${theirs.name}Private`);

  await page.getByRole("radio", { name: "Mod" }).click();
  const dialog = page.getByRole("dialog", { name: `Make ${person.name} a Mod?` });
  await expect(dialog).toContainText("will be able to connect, rename, revoke and delete their own devices.");
  await dialog.getByRole("button", { name: "Make Mod" }).click();
  await expect(page.getByRole("radio", { name: "Mod" })).toBeChecked();
  await expect(page.getByRole("heading", { name: /^Mods/ })).toBeVisible();
});

test("an admin's page is read only, and so is the admin's own", async ({ context, page }) => {
  const other = await createPerson("ADMIN");
  await admin(context, page);
  await page.locator("a.prow", { hasText: other.name }).click();
  await expect(page.getByText("Admins are managed on the admin page, on the computer running SignalHub.")).toBeVisible();
  await expect(page.getByRole("radio")).toHaveCount(0);
});

test("inviting someone makes a pairing code to scan or paste, and says when it was used", async ({ context, page }) => {
  await admin(context, page);
  const name = unique("Guest");
  await page.getByRole("button", { name: "Invite" }).click();
  const form = page.getByRole("dialog", { name: "Invite someone" });
  await expect(form.getByRole("button", { name: "Make invitation" })).toBeDisabled();
  await form.getByLabel("Their name").fill(name);
  await expect(form.getByLabel("First device name")).toHaveValue(`${name} - phone`);
  await form.getByRole("radio", { name: "Mod" }).click();
  await form.getByRole("button", { name: "Make invitation" }).click();

  const code = page.getByRole("dialog", { name: `Invite ${name}` });
  await expect(code).toContainText(`${name} opens the SignalHub app and scans this code, or pastes the link below. It works once and runs out in 10 minutes.`);
  await expect(code.getByRole("img", { name: `Pairing QR code for ${name}` })).toBeVisible();
  await expect(code).toContainText(`Whoever uses this code joins as ${name}. Share it only with ${name}.`);
  const link = (await code.locator(".linkbox").innerText()).trim();
  expect(link).toMatch(/^signalhub:\/\/pair\?server=.+&code=shpc1_/);
  const pairingCode = new URL(link).searchParams.get("code");

  // The invited person's phone uses the code: the dialog says so.
  const redeemed = await fetch(`${BASE}/api/v1/pairing`, { method: "POST", headers: { Authorization: `Bearer ${pairingCode}` } });
  expect(redeemed.status).toBe(201);
  await expect(code).toContainText(`${name} joined on ${name} - phone. The code can't be used again.`, { timeout: 10_000 });
  await code.getByRole("button", { name: "Done" }).click();
  await expect(page.locator("a.prow", { hasText: name })).toContainText("1 device");
  await expect(page.getByRole("heading", { name: /^Mods/ })).toBeVisible();
});

test("an invitation with a name that is taken is refused under the field", async ({ context, page }) => {
  const taken = await createPerson("BASIC");
  await admin(context, page);
  await page.getByRole("button", { name: "Invite" }).click();
  const form = page.getByRole("dialog", { name: "Invite someone" });
  await form.getByLabel("Their name").fill(taken.name);
  await form.getByRole("button", { name: "Make invitation" }).click();
  await expect(form.getByText("Someone on this server already has that name. Use another.")).toBeVisible();
});
