import { BASE, asDevice, createPerson, createProducer, operator, publish, unique } from "../support/server.mjs";
import { adminSignIn, expect, test } from "../support/page.mjs";

/** Opens Producers with the search narrowed to one producer, and returns its row. */
async function find(page, name) {
  await page.getByRole("searchbox", { name: "Find a producer" }).fill(name);
  const row = page.getByRole("row", { name: new RegExp(`^${name}`) });
  await expect(row).toBeVisible();
  return row;
}

async function open(page, name, hash = "#producers") {
  await adminSignIn(page, hash);
  const row = await find(page, name);
  await row.click();
  await expect(page.getByRole("region", { name })).toBeVisible();
}

const send = (producer, extra = {}) => publish(producer, { title: "Hello", ...extra });

test("the list says each producer's owner, who sees it, its working keys and its last event; Quiet is only for enabled ones that went silent", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const quiet = await createProducer(owner, unique("quiet"), "PRIVATE");
  const talking = await createProducer(owner, unique("talking"), "PUBLIC");
  await send(talking);
  await adminSignIn(page, "#producers");
  await expect(page.getByRole("heading", { name: "Producers", level: 1 })).toBeVisible();
  const quietRow = await find(page, quiet.name);
  await expect(quietRow).toContainText("Quiet");
  await expect(quietRow).toContainText(owner.name);
  await expect(quietRow).toContainText("Private");
  await expect(quietRow).toContainText("None stored");
  const talkingRow = await find(page, talking.name);
  await expect(talkingRow).toContainText("Public");
  await expect(talkingRow).toContainText("just now");
  await expect(talkingRow).not.toContainText("Quiet");
  // The count says what is shown; the header says when the list was read.
  await expect(page.getByText(/^Updated \d\d:\d\d$/)).toBeVisible();
});

test("the chips and the owner menu narrow the list, say how many match, and are kept in the address", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const a = await createProducer(owner, unique("filter-a"), "PUBLIC");
  const b = await createProducer(owner, unique("filter-b"), "PRIVATE");
  await operator("POST", `/api/v1/admin/producers/${b.id}/disable`);
  await adminSignIn(page, "#producers");
  const search = page.getByRole("searchbox", { name: "Find a producer" });
  await search.fill("filter-");
  await expect(page.getByRole("row", { name: new RegExp(`^${a.name}`) })).toBeVisible();
  await page.getByRole("button", { name: "Disabled" }).click();
  await expect(page).toHaveURL(/\?f=disabled&q=filter-$/);
  await expect(page.getByRole("row", { name: new RegExp(`^${b.name}`) })).toBeVisible();
  await expect(page.getByRole("row", { name: new RegExp(`^${a.name}`) })).toHaveCount(0);
  await expect(page.getByRole("row", { name: new RegExp(`^${b.name}`) })).toContainText("Disabled");
  await expect(page.locator(".mhead .cnt").first()).toContainText(/^\d+ of \d+ producers$/);
  // The owner menu is a menu of the owners there are.
  await page.getByRole("button", { name: "Disabled" }).click();
  await page.getByRole("button", { name: "All", exact: true }).click();
  await page.getByRole("button", { name: /^Owner/ }).click();
  await page.getByRole("menuitemradio", { name: owner.name }).click();
  await expect(page.getByRole("button", { name: `Owner: ${owner.name}` })).toBeVisible();
  await expect(page).toHaveURL(new RegExp(`owner=[0-9a-f-]{36}`));
  // No match: the filters stay, one press clears them.
  await search.fill("no-producer-is-named-this");
  await expect(page.getByRole("heading", { name: "No producers match" })).toBeVisible();
  await expect(page.getByText("Nothing is named “no-producer-is-named-this” with these filters.")).toBeVisible();
  await page.getByRole("button", { name: "Clear search and filters" }).click();
  await expect(search).toHaveValue("");
  await expect(page).toHaveURL(/#producers$/);
});

test("an empty server says so, with the one action repeated in the middle of the page", async ({ page }) => {
  await page.route("**/api/v1/admin/producers", (route) => (route.request().method() === "GET" ? route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) }) : route.continue()));
  await adminSignIn(page, "#producers");
  await expect(page.getByRole("heading", { name: "No producers yet" })).toBeVisible();
  await expect(page.getByText("A producer is anything that sends events")).toBeVisible();
  await expect(page.getByRole("searchbox", { name: "Find a producer" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "New producer" })).toHaveCount(2);
});

test("creating a producer: a dialog, the name rule said while typing, the key shown once and never again", async ({ page, context }) => {
  await adminSignIn(page, "#producers");
  await page.getByRole("button", { name: "New producer" }).first().click();
  const dialog = page.getByRole("dialog", { name: "New producer" });
  await expect(dialog.getByLabel("Name")).toBeFocused();
  const create = dialog.getByRole("button", { name: "Create" });
  await expect(create).toBeDisabled();
  await dialog.getByLabel("Name").fill("bad name!");
  await expect(dialog.getByText("Use letters, numbers and . _ : / - only, starting with a letter or number.")).toBeVisible();
  await expect(create).toBeDisabled();
  await dialog.getByLabel("Name").fill("x".repeat(101));
  await expect(dialog.getByText("Use 100 characters or fewer.")).toBeVisible();
  const name = unique("greenhouse");
  await dialog.getByLabel("Name").fill(name);
  // New producers start private, as in the app; the owner is chosen as "Name · Role".
  await expect(dialog.getByRole("radio", { name: "Private" })).toBeChecked();
  await expect(dialog.getByLabel("Owner")).toContainText("· Admin");
  await expect(create).toBeEnabled();
  await create.click();

  const keyDialog = page.getByRole("dialog", { name: `${name} is ready` });
  await expect(keyDialog).toBeVisible();
  const key = (await keyDialog.locator(".key").innerText()).trim();
  expect(key).toMatch(/^shpk1_/);
  await expect(keyDialog.getByText("Shown once. You won't see this key again.")).toBeVisible();
  await expect(keyDialog.locator(".code")).toContainText(`${BASE}/api/v1/events`);
  await expect(keyDialog.locator(".code")).toContainText(`Bearer ${key}`);
  // Escape does not lose it: it asks first, and Stay is the default.
  await page.keyboard.press("Escape");
  const ask = page.getByRole("dialog", { name: "Did you copy the key?" });
  await expect(ask).toContainText(`you'll need to issue a new key for ${name}`);
  await expect(ask.getByRole("button", { name: "Stay" })).toBeFocused();
  await ask.getByRole("button", { name: "Stay" }).click();
  await expect(keyDialog).toBeVisible();
  await keyDialog.getByRole("button", { name: "Copy", exact: true }).click();
  await expect(keyDialog.getByRole("button", { name: "Copied" })).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(key);
  await keyDialog.getByRole("button", { name: "Done" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  // The producer is listed, its key only by prefix, and the key works.
  const row = await find(page, name);
  await expect(row).toContainText("Private");
  await row.click();
  await expect(page.getByRole("region", { name })).toContainText("shpk1_");
  expect(await page.content()).not.toContain(key);
  const sent = await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "From the key" }) });
  expect(sent.status).toBe(201);
  void context;
});

test("a name that is taken is said under the field, in the dialog, and nothing is created", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const taken = await createProducer(owner, unique("taken"), "PRIVATE");
  await adminSignIn(page, "#producers");
  await page.getByRole("button", { name: "New producer" }).first().click();
  const dialog = page.getByRole("dialog", { name: "New producer" });
  await dialog.getByLabel("Name").fill(taken.name);
  await dialog.getByRole("button", { name: "Create" }).click();
  await expect(dialog.getByText("That name is taken. Names are shared by everyone on this server.")).toBeVisible();
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Create" })).toBeDisabled();
});

test("a producer opens in the pane with its keys, who sees it and its allowed users; the address keeps it; Escape closes it and focus returns to its row", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const guest = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("pane"), "PRIVATE");
  await adminSignIn(page, "#producers");
  const row = await find(page, producer.name);
  await row.focus();
  await page.keyboard.press("Enter");
  const pane = page.getByRole("region", { name: producer.name });
  await expect(pane).toBeVisible();
  await expect(page).toHaveURL(new RegExp(`#producers/${producer.id}`));
  // Opening the pane moves focus into it.
  await expect(pane.getByRole("heading", { name: producer.name, level: 2 })).toBeFocused();
  await expect(pane).toContainText(owner.name);
  await expect(pane.getByRole("radio", { name: "Private" })).toBeChecked();
  await expect(pane.getByText("Only its owner, until you add someone.")).toBeVisible();
  await expect(pane.getByRole("button", { name: /^Revoke key shpk1_[0-9a-f]{12}…$/ })).toBeVisible();
  // The raw ids are only under Technical details, which is closed.
  await expect(pane.getByText(producer.id)).toHaveCount(0);
  await pane.getByRole("button", { name: "Technical details" }).click();
  await expect(pane.getByText(producer.id)).toBeVisible();
  await expect(pane.getByText(producer.keyId)).toBeVisible();
  void guest;
  await page.keyboard.press("Escape");
  await expect(pane).toHaveCount(0);
  await expect(page).toHaveURL(/#producers(\?.*)?$/);
  await expect(page.getByRole("row", { name: new RegExp(`^${producer.name}`) })).toBeFocused();
  // A reload of #producers/<id> opens it again.
  await page.getByRole("row", { name: new RegExp(`^${producer.name}`) }).click();
  await page.reload();
  await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("region", { name: producer.name })).toBeVisible();
});

test("issuing a key shows it once in a dialog, and revoking one names it and says when it was last used; the only key says so", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("keys"), "PUBLIC");
  await send(producer);
  await open(page, producer.name);
  const pane = page.getByRole("region", { name: producer.name });
  await pane.getByRole("button", { name: `Issue a key for ${producer.name}` }).click();
  const dialog = page.getByRole("dialog", { name: `New key for ${producer.name}` });
  await expect(dialog.getByText("This is its new key. Switch the producer to it, then revoke the old one.")).toBeVisible();
  const fresh = (await dialog.locator(".key").innerText()).trim();
  await dialog.getByRole("button", { name: "Copy and close" }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(pane.getByRole("button", { name: /^Revoke key/ })).toHaveCount(2);
  // The first key was used by the event above; its confirmation says so and the key keeps working until it is revoked.
  const first = pane.getByRole("button", { name: /^Revoke key/ }).first();
  const label = (await first.getAttribute("aria-label")).replace("Revoke key ", "");
  await first.click();
  const confirm = page.getByRole("dialog", { name: "Revoke this key?" });
  await expect(confirm).toContainText(`${label} stops working at once`);
  await expect(confirm).toContainText("It was last used just now.");
  await expect(confirm.getByRole("button", { name: "Cancel" })).toBeFocused();
  await confirm.getByRole("button", { name: `Revoke key ${label}` }).click();
  await expect(pane.getByText(`Key revoked. ${label} no longer works.`)).toBeVisible();
  // The old key is turned away, the new one works.
  expect((await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${producer.apiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "Old" }) })).status).toBe(401);
  expect((await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${fresh}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "New" }) })).status).toBe(201);
  // The one working key left is said to be the only one.
  await pane.getByRole("button", { name: /^Revoke key/ }).click();
  await expect(page.getByRole("dialog", { name: "Revoke the only key?" })).toContainText("nothing can send its events until you issue a new key");
  await page.getByRole("button", { name: "Cancel" }).click();
});

test("disabling asks first and says what its owner will see; the pane says who disabled it; enabling needs no question", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("disable"), "PUBLIC");
  await open(page, producer.name);
  const pane = page.getByRole("region", { name: producer.name });
  await pane.getByRole("button", { name: `Disable ${producer.name}` }).click();
  const dialog = page.getByRole("dialog", { name: `Disable ${producer.name}?` });
  await expect(dialog).toContainText(`${owner.name} will see it as “Disabled by the host”`);
  await dialog.getByRole("button", { name: "Disable", exact: true }).click();
  await expect(pane.getByText("Disabled.")).toBeVisible();
  await expect(pane.getByText(/^Disabled by the host on /)).toBeVisible();
  await expect(pane).toContainText("not working while disabled");
  await expect(page.getByRole("row", { name: new RegExp(`^${producer.name}`) })).toContainText("Disabled");
  await expect(page.getByRole("row", { name: new RegExp(`^${producer.name}`) })).toContainText("1 (off)");
  expect((await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${producer.apiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "Refused" }) })).status).toBeGreaterThanOrEqual(401);
  await pane.getByRole("button", { name: `Enable ${producer.name}` }).click();
  await expect(pane.getByText("Enabled.")).toBeVisible();
  await expect(pane.getByRole("button", { name: `Disable ${producer.name}` })).toBeVisible();
  expect((await fetch(`${BASE}/api/v1/events`, { method: "POST", headers: { Authorization: `Bearer ${producer.apiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "Back" }) })).status).toBe(201);
});

test("a producer its owner disabled says so: Disabled by its owner", async ({ page }) => {
  const owner = await createPerson("MOD");
  const producer = await createProducer(owner, unique("owner-off"), "PRIVATE");
  await asDevice(owner, "POST", `/api/v1/client/producers/${producer.id}/disable`);
  await open(page, producer.name);
  await expect(page.getByRole("region", { name: producer.name }).getByText(/^Disabled by its owner on /)).toBeVisible();
});

test("renaming is a dialog: the new name shows at once, and a name that is taken is said under the field", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("rename"), "PRIVATE");
  const other = await createProducer(owner, unique("other"), "PRIVATE");
  await open(page, producer.name);
  const pane = page.getByRole("region", { name: producer.name });
  await pane.getByRole("button", { name: `Rename ${producer.name}` }).click();
  const dialog = page.getByRole("dialog", { name: "Rename producer" });
  const rename = dialog.getByRole("button", { name: "Rename", exact: true });
  // Off until the name is valid and different.
  await expect(rename).toBeDisabled();
  await dialog.getByLabel("Name").fill(other.name);
  await rename.click();
  await expect(dialog.getByText("That name is taken. Names are shared by everyone on this server.")).toBeVisible();
  const renamed = unique("renamed");
  await dialog.getByLabel("Name").fill(renamed);
  await rename.click();
  await expect(page.getByRole("region", { name: renamed })).toBeVisible();
  await expect(page.getByRole("region", { name: renamed }).getByText(`Renamed to ${renamed}.`)).toBeVisible();
  await find(page, renamed);
  await expect(page.getByRole("row", { name: new RegExp(`^${producer.name}`) })).toHaveCount(0);
});

test("who sees it: public needs no question, private asks and says what happens; the allowed users are added from a menu and removed after a question", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const guest = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("sharing"), "PRIVATE");
  await open(page, producer.name);
  const pane = page.getByRole("region", { name: producer.name });
  await pane.getByRole("button", { name: `Add a user to ${producer.name}` }).click();
  await page.getByRole("menuitem", { name: new RegExp(guest.name) }).first().click();
  await expect(pane.getByText(`${guest.name} added to the list.`)).toBeVisible();
  await expect(pane.getByRole("button", { name: `Remove ${guest.name} from the list` })).toBeVisible();
  await expect(page.getByRole("row", { name: new RegExp(`^${producer.name}`) })).toContainText("Private · 1 person");
  await pane.getByRole("button", { name: `Remove ${guest.name} from the list` }).click();
  const remove = page.getByRole("dialog", { name: `Remove ${guest.name} from ${producer.name}?` });
  await expect(remove).toContainText("have to subscribe again after being added back");
  await remove.getByRole("button", { name: `Remove ${guest.name}` }).click();
  await expect(pane.getByText(`${guest.name} removed from the list.`)).toBeVisible();
  await pane.getByRole("radio", { name: "Public" }).click();
  await expect(pane.getByText("Now public.")).toBeVisible();
  await expect(pane.getByText("Every user can see it and subscribe.")).toBeVisible();
  // Public to private: the control does not move until it is confirmed.
  await pane.getByRole("radio", { name: "Private" }).click();
  const dialog = page.getByRole("dialog", { name: `Make ${producer.name} private?` });
  await expect(dialog).toContainText("they must be added to its list and subscribe again");
  await expect(pane.getByRole("radio", { name: "Public" })).toBeChecked();
  await dialog.getByRole("button", { name: "Make private" }).click();
  await expect(pane.getByText("Now private.")).toBeVisible();
  await expect(pane.getByRole("radio", { name: "Private" })).toBeChecked();
});

test("a change that did not happen is said in the pane with Try again, and the list that failed to load keeps the older one under a banner", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("fail"), "PUBLIC");
  await open(page, producer.name);
  const pane = page.getByRole("region", { name: producer.name });
  let fail = true;
  await page.route(`**/api/v1/admin/producers/${producer.id}`, (route) => (fail && route.request().method() === "PATCH" ? route.fulfill({ status: 500, body: "" }) : route.continue()));
  await pane.getByRole("radio", { name: "Private" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Make private" }).click();
  await expect(pane.getByRole("alert")).toContainText("Could not make it private. SignalHub answered 500. Nothing changed.");
  fail = false;
  await pane.getByRole("button", { name: "Try again" }).click();
  await expect(pane.getByText("Now private.")).toBeVisible();
  // Now the list fails to load: the older list stays, dimmed, with what failed and when it was from.
  await page.route("**/api/v1/admin/producers", (route) => (route.request().method() === "GET" ? route.fulfill({ status: 500, body: "" }) : route.continue()));
  await page.getByRole("button", { name: "Refresh" }).click();
  await expect(page.getByRole("alert").filter({ hasText: "Could not load the producers. SignalHub answered 500. This is the list from" })).toBeVisible();
  await expect(page.getByText(/^Older list · \d\d:\d\d$/)).toBeVisible();
  await expect(page.getByRole("row", { name: new RegExp(`^${producer.name}`) })).toBeVisible();
  await page.unroute("**/api/v1/admin/producers");
  await page.getByRole("alert").getByRole("button", { name: "Try again" }).click();
  await expect(page.getByRole("alert").filter({ hasText: "Could not load the producers" })).toHaveCount(0);
  await expect(page.getByText(/^Updated /)).toBeVisible();
});

test("a dialog keeps focus inside, starts on Cancel, closes with Escape and returns focus to what opened it", async ({ page }) => {
  const owner = await createPerson("BASIC");
  const producer = await createProducer(owner, unique("focus"), "PUBLIC");
  await open(page, producer.name);
  const pane = page.getByRole("region", { name: producer.name });
  const disable = pane.getByRole("button", { name: `Disable ${producer.name}` });
  await disable.click();
  const dialog = page.getByRole("dialog", { name: `Disable ${producer.name}?` });
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
  // Tab goes round the dialog and never leaves it.
  for (let i = 0; i < 5; i += 1) {
    await page.keyboard.press("Tab");
    expect(await page.evaluate(() => document.activeElement.closest("[role=dialog]") !== null)).toBe(true);
  }
  await page.keyboard.press("Shift+Tab");
  expect(await page.evaluate(() => document.activeElement.closest("[role=dialog]") !== null)).toBe(true);
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(disable).toBeFocused();
  // Nothing was disabled.
  await expect(pane.getByRole("button", { name: `Disable ${producer.name}` })).toBeVisible();
});

test("every name, owner and user is shown as text, never as markup", async ({ page }) => {
  const markup = `<img src=x onerror="window.__pwned=1" alt="${unique("owner")}">`;
  const owner = await createPerson("BASIC", markup);
  const producer = await createProducer(owner, unique("xss"), "PUBLIC");
  await open(page, producer.name);
  await expect(page.getByRole("region", { name: producer.name })).toContainText(markup);
  expect(await page.evaluate(() => window.__pwned)).toBeUndefined();
  expect(await page.locator("img").count()).toBe(0);
});
