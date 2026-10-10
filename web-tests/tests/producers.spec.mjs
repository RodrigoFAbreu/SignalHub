import { BASE, asDevice, browserSession, createPerson, createProducer, publish, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

async function signedIn(context, page, role, hash = "#producers") {
  const person = await createPerson(role);
  await useSession(context, await browserSession(person));
  await page.goto(`/app/${hash}`);
  return person;
}

test("creating a producer shows its key once, in a dialog, and the producer opens", async ({ context, page }) => {
  await signedIn(context, page, "BASIC", "#producers/new");
  const name = unique("weather");
  const create = page.getByRole("button", { name: "Create" });
  await expect(create).toBeDisabled();
  // The name rule is the server's, said while typing.
  await page.getByLabel("Name").fill("bad name!");
  await expect(page.getByText("Use letters, numbers and . _ : / - only, starting with a letter or number.")).toBeVisible();
  await expect(create).toBeDisabled();
  await page.getByLabel("Name").fill(name);
  await expect(create).toBeEnabled();
  await create.click();

  const dialog = page.getByRole("dialog", { name: `${name} is ready` });
  await expect(dialog).toBeVisible();
  const key = (await dialog.locator(".keybox").innerText()).trim();
  expect(key).toMatch(/^shpk1_/);
  // The example sends with this very key to this very server.
  await expect(dialog.locator(".snip")).toContainText(`Authorization: Bearer ${key}`);
  await expect(dialog.locator(".snip")).toContainText(`${BASE}/api/v1/events`);
  await dialog.getByRole("button", { name: "Copy", exact: true }).click();
  await expect(dialog.getByRole("button", { name: "Copied" })).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(key);
  await expect(dialog.getByRole("button", { name: "Done" })).toBeVisible();
  await dialog.getByRole("button", { name: "Done" }).click();

  await expect(page).toHaveURL(/#producers\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name, level: 2, exact: true })).toBeVisible();
  await expect(page.getByText("Only you")).toBeVisible();
  // The key is never shown again: only its prefix is. (The dialog is gone first: it is still
  // in the page while it closes.)
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.locator(".keyrow .mono")).toContainText("shpk1_");
  expect(await page.content()).not.toContain(key);
  // And the key works.
  const sent = await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "From the key" }) });
  expect(sent.status).toBe(201);
});

test("a name that is taken is said under the field, and nothing is created", async ({ context, page }) => {
  const person = await signedIn(context, page, "BASIC", "#producers/new");
  const taken = await createProducer(person, unique("taken"), "PRIVATE");
  await page.getByLabel("Name").fill(taken.name);
  await page.getByRole("button", { name: "Create" }).click();
  await expect(page.getByText("That name is taken. Names are shared by everyone on this server.")).toBeVisible();
  await expect(page.getByRole("dialog")).toHaveCount(0);
});

test("the producers list: search, chips, Yours tag, summary and the bell that subscribes in place", async ({ context, page }) => {
  const owner = await createPerson("BASIC");
  const mine = await createProducer(owner, unique("mine"), "PUBLIC");
  const viewer = await createPerson("BASIC");
  await useSession(context, await browserSession(viewer));
  const own = await createProducer(viewer, unique("own"), "PRIVATE");
  await page.goto("/app/#producers");
  const row = page.locator(".prow-item", { hasText: mine.name });
  await expect(row).toContainText(`${owner.name} · Public`);
  await expect(row.getByRole("button", { name: `Not subscribed to ${mine.name}. Double tap to subscribe.` })).toBeVisible();
  const yours = page.locator(".prow-item", { hasText: own.name });
  await expect(yours).toContainText("Yours");
  await expect(yours).toContainText("Private · 1 key · no events yet");

  await page.getByRole("radio", { name: "Yours" }).click();
  await expect(page.locator(".prow-item")).toHaveCount(1);
  await page.getByRole("radio", { name: "Can subscribe" }).click();
  await expect(page.locator(".prow-item", { hasText: mine.name })).toBeVisible();
  await page.getByRole("radio", { name: "All" }).click();
  await page.getByRole("searchbox", { name: "Find a producer" }).fill("zzzz-nothing");
  await expect(page.getByRole("heading", { name: "No producers match" })).toBeVisible();
  await page.getByRole("button", { name: "Clear search" }).first().click();

  // Subscribing is in place; unsubscribing asks first.
  await row.getByRole("button", { name: /Not subscribed/ }).click();
  await expect(row.getByRole("button", { name: `Subscribed to ${mine.name}. Double tap to unsubscribe.` })).toBeVisible();
  await publish(mine, { title: "From a producer I subscribed to" });
  await page.goto("/app/#inbox");
  await expect(page.locator("a.event-row", { hasText: "From a producer I subscribed to" })).toBeVisible();
  await page.goto("/app/#producers");
  await row.getByRole("button", { name: /Subscribed to/ }).click();
  const dialog = page.getByRole("dialog", { name: `Unsubscribe from ${mine.name}?` });
  await expect(dialog).toContainText("Its events leave your inbox.");
  await dialog.getByRole("button", { name: "Unsubscribe" }).click();
  await expect(row.getByRole("button", { name: /Not subscribed/ })).toBeVisible();
});

test("a failed subscribe says so, with Retry", async ({ context, page }) => {
  const owner = await createPerson("BASIC");
  const mine = await createProducer(owner, unique("flaky"), "PUBLIC");
  await signedIn(context, page, "BASIC");
  await page.route("**/subscription", (route) => route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ title: "boom" }) }));
  const row = page.locator(".prow-item", { hasText: mine.name });
  await row.getByRole("button", { name: /Not subscribed/ }).click();
  await expect(page.getByRole("alert")).toContainText(`Couldn't subscribe to ${mine.name}. Try again.`);
  await page.unroute("**/subscription");
  await page.getByRole("button", { name: "Retry" }).click();
  await expect(row.getByRole("button", { name: /^Subscribed to/ })).toBeVisible();
});

test("a refused copy selects the key, says how to copy by hand, and still lets the person leave", async ({ context, page }) => {
  await signedIn(context, page, "BASIC", "#producers/new");
  // What a browser that does not allow copying does, whatever the runner's own permissions.
  await context.clearPermissions();
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", { value: { writeText: () => Promise.reject(new DOMException("denied", "NotAllowedError")) } });
  });
  await page.reload();
  const name = unique("refused");
  await page.getByLabel("Name").fill(name);
  await page.getByRole("button", { name: "Create" }).click();
  const dialog = page.getByRole("dialog", { name: `${name} is ready` });
  await expect(dialog).toBeVisible();
  const key = (await dialog.locator(".keybox").innerText()).trim();

  await dialog.getByRole("button", { name: "Copy", exact: true }).click();
  await expect(dialog.getByText("This browser did not allow copying.")).toBeVisible();
  await expect(dialog.getByText("press Ctrl+C (Cmd+C on a Mac) to copy it")).toBeVisible();
  await expect(dialog.locator(".keybox.sel")).toBeVisible();
  expect(await page.evaluate(() => String(window.getSelection()).trim())).toBe(key);
  await expect(dialog.getByRole("button", { name: "Copied" })).toHaveCount(0);
  // The dialog is still open, and now offers the way out.
  await expect(dialog.getByRole("button", { name: "Try copy again" })).toBeVisible();
  await dialog.getByRole("button", { name: "I have saved the key" }).click();
  await expect(dialog).toHaveCount(0);
  await expect(page.getByRole("heading", { name, level: 2, exact: true })).toBeVisible();
});

test("Copy and close, refused, keeps the dialog open once and then closes on I have saved the key", async ({ context, page }) => {
  await signedIn(context, page, "BASIC", "#producers/new");
  await context.clearPermissions();
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", { value: { writeText: () => Promise.reject(new DOMException("denied", "NotAllowedError")) } });
  });
  await page.reload();
  const name = unique("refused-close");
  await page.getByLabel("Name").fill(name);
  await page.getByRole("button", { name: "Create" }).click();
  const dialog = page.getByRole("dialog", { name: `${name} is ready` });
  await dialog.getByRole("button", { name: "Copy and close" }).click();
  await expect(dialog.getByText("This browser did not allow copying.")).toBeVisible();
  await expect(dialog).toBeVisible();
  await dialog.getByRole("button", { name: "I have saved the key" }).click();
  await expect(dialog).toHaveCount(0);
});

test("someone else's producer has the subscribed switch and nothing of the owner's controls", async ({ context, page }) => {
  const owner = await createPerson("MOD");
  const theirs = await createProducer(owner, unique("theirs"), "PUBLIC");
  await signedIn(context, page, "BASIC", `#producers/${theirs.id}`);
  await expect(page.getByText(`${owner.name}'s producer`)).toBeVisible();
  await expect(page.getByText("Public · anyone on this server can subscribe")).toBeVisible();
  await expect(page.getByRole("switch", { name: "Subscribed" })).not.toBeChecked();
  await expect(page.getByRole("button", { name: "New key" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /^Rename/ })).toHaveCount(0);
  await page.getByRole("switch", { name: "Subscribed" }).click();
  await expect(page.getByRole("switch", { name: "Subscribed" })).toBeChecked();
  await expect(page.getByRole("button", { name: "See its events" })).toBeVisible();
});

test("an owner renames, changes who can see it, adds and removes people, and manages keys", async ({ context, page }) => {
  const friend = await createPerson("BASIC");
  const person = await signedIn(context, page, "BASIC", "#producers/new");
  const name = unique("home");
  await page.getByLabel("Name").fill(name);
  await page.getByRole("button", { name: "Create" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Copy and close" }).click();
  await expect(page.getByRole("heading", { name, level: 2, exact: true })).toBeVisible();

  // Rename: a taken name is refused in the dialog, a free one is kept.
  const other = await createProducer(friend, unique("other"), "PUBLIC");
  await page.getByRole("button", { name: `Rename ${name}` }).click();
  const rename = page.getByRole("dialog", { name: "Rename producer" });
  await rename.getByLabel("Name").fill(other.name);
  await rename.getByRole("button", { name: "Rename" }).click();
  await expect(rename.getByText("That name is taken.")).toBeVisible();
  const renamed = `${name}-2`;
  await rename.getByLabel("Name").fill(renamed);
  await rename.getByRole("button", { name: "Rename" }).click();
  await expect(page.getByRole("heading", { name: renamed, level: 2, exact: true })).toBeVisible();

  // Who can see it: Private to start; add a person, then make it public and private again.
  await expect(page.getByRole("radio", { name: "Private" })).toBeChecked();
  await page.getByRole("button", { name: "Add people" }).click();
  const add = page.getByRole("dialog", { name: "Add people" });
  await add.getByRole("button", { name: `Add ${friend.name}` }).click();
  await expect(add.getByRole("button", { name: `Added ${friend.name}` })).toBeDisabled();
  await add.getByRole("button", { name: "Done" }).click();
  await expect(page.getByText("Shared with 1 person")).toBeVisible();
  await page.getByRole("radio", { name: "Public" }).click();
  await expect(page.getByText("Anyone on this server can find and subscribe to it.")).toBeVisible();
  await page.getByRole("radio", { name: "Private" }).click();
  const confirm = page.getByRole("dialog", { name: `Make ${renamed} private?` });
  await expect(confirm).toContainText("Only you and the people you add will see it.");
  await confirm.getByRole("button", { name: "Make private" }).click();
  await expect(page.getByText("Shared with 1 person")).toBeVisible();
  await page.getByRole("button", { name: `Remove ${friend.name}` }).click();
  await page.getByRole("dialog", { name: `Remove ${friend.name}?` }).getByRole("button", { name: "Remove" }).click();
  await expect(page.getByText("Only you")).toBeVisible();

  // Keys: a second key is shown once; revoking the first asks, for good.
  await page.getByRole("button", { name: "New key" }).click();
  const key = page.getByRole("dialog", { name: `New key for ${renamed}` });
  const secret = (await key.locator(".keybox").innerText()).trim();
  await key.getByRole("button", { name: "Copy and close" }).click();
  await expect(page.locator(".keyrow .mono")).toHaveCount(2);
  const first = page.getByRole("button", { name: /^Revoke key / }).first();
  await first.click();
  const revoke = page.getByRole("dialog", { name: "Revoke this key?" });
  await expect(revoke).toContainText("stops working at once");
  await revoke.getByRole("button", { name: "Revoke" }).click();
  await expect(page.locator(".keyrow.quiet")).toHaveCount(1);
  const worked = await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "Still works" }) });
  expect(worked.status).toBe(201);

  // Disable and enable.
  await page.getByRole("button", { name: /^Disable/ }).click();
  await page.getByRole("dialog", { name: `Disable ${renamed}?` }).getByRole("button", { name: "Disable" }).click();
  await expect(page.getByText("Paused by you. Its keys don't work, so it sends nothing. Its events stay.")).toBeVisible();
  const refused = await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "x" }) });
  expect(refused.status).toBe(401);
  await page.getByRole("button", { name: /^Enable/ }).click();
  await expect(page.getByRole("button", { name: /^Disable/ })).toBeVisible();
  void person;
});

test("a producer that is not there, or not the person's to see, is the not-here page", async ({ context, page }) => {
  const stranger = await createPerson("BASIC");
  const secret = await createProducer(stranger, unique("secret"), "PRIVATE");
  await signedIn(context, page, "BASIC", `#producers/${secret.id}`);
  await expect(page.getByRole("heading", { name: "This isn't here" })).toBeVisible();
  void asDevice;
});
