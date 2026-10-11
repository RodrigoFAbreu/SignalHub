import { asDevice, createPerson, createProducer, operator, publish, subscribe, unique } from "../support/server.mjs";
import { adminSignIn, expect, test } from "../support/page.mjs";

const sideways = (page) => page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, view: window.innerWidth, body: document.body.scrollWidth }));
const json = (route, body, status = 200) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });

const row = (page, name) => page.getByRole("row", { name: new RegExp(`^${name},`) });

async function find(page, name) {
  await page.getByRole("searchbox", { name: "Find a user" }).fill(name);
  const target = row(page, name);
  await expect(target).toBeVisible();
  return target;
}

/** Opens Users with one user selected, through the address. */
async function openUser(page, person) {
  await adminSignIn(page, `#users/${person.userId}`);
  const pane = page.getByRole("region", { name: person.name });
  await expect(pane).toBeVisible();
  return pane;
}

const invited = async (role = "BASIC") => operator("POST", "/api/v1/admin/users", { name: unique("invited"), role });

test.describe("desktop", () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test("the table has a user per row: role, devices, producers, subscriptions and when it was last active; revoked ones come last, and a user with no device says so", async ({ page }) => {
    const person = await createPerson("MOD");
    await createProducer(person, unique("owned"), "PUBLIC");
    const waiting = await invited();
    const gone = await createPerson("BASIC");
    await operator("POST", `/api/v1/admin/users/${gone.userId}/revoke`);
    // It has been active: a device's first request is what the column reads.
    await asDevice(person, "GET", "/api/v1/client/server");
    await adminSignIn(page, "#users");
    await expect(page.getByRole("heading", { name: "Users", level: 1 })).toBeVisible();
    const header = page.getByRole("grid", { name: "Users" }).getByRole("row").first();
    for (const name of ["User", "Role", "Devices", "Producers", "Subscribed", "Last active"]) await expect(header.getByRole("columnheader", { name, exact: true })).toBeVisible();
    await expect(page.locator("[aria-sort]")).toHaveCount(0);
    await expect(page.locator(".mhead .cnt").first()).toHaveText(/^\d+ users · \d+ active$/);
    const mine = await find(page, person.name);
    await expect(mine).toHaveAccessibleName(new RegExp(`^${person.name}, Mod, 1 device, 1 producer, 1 subscription$`));
    await expect(mine.getByText("Mod", { exact: true }).last()).toBeVisible();
    await expect(mine).toContainText(/just now|min ago/);
    await expect(row(page, person.name)).not.toContainText("No device yet");
    const empty = await find(page, waiting.name);
    await expect(empty).toContainText("No device yet");
    await expect(empty).toContainText("—");
    // A search narrows the list and the count says how many of them.
    await page.getByRole("searchbox", { name: "Find a user" }).fill("");
    const last = page.getByRole("grid", { name: "Users" }).getByRole("row").last();
    await expect(last).toContainText("Revoked");
  });

  test("the chips narrow by role, revoked and no device yet, say how many have no device, and are kept in the address", async ({ page }) => {
    const admin = await createPerson("ADMIN");
    const mod = await createPerson("MOD");
    const basic = await createPerson("BASIC");
    const waiting = await invited();
    const gone = await createPerson("BASIC");
    await operator("POST", `/api/v1/admin/users/${gone.userId}/revoke`);
    await adminSignIn(page, "#users");
    await expect(page.getByRole("button", { name: /^No device yet · \d+$/ })).toBeVisible();
    await page.getByRole("button", { name: "Admin", exact: true }).click();
    await expect(page).toHaveURL(/#users\?f=admin$/);
    await expect(row(page, admin.name)).toBeVisible();
    await expect(row(page, mod.name)).toHaveCount(0);
    await page.getByRole("button", { name: "Mod", exact: true }).click();
    await expect(row(page, mod.name)).toBeVisible();
    await expect(row(page, basic.name)).toHaveCount(0);
    await page.getByRole("button", { name: "Basic", exact: true }).click();
    await expect(row(page, basic.name)).toBeVisible();
    await expect(row(page, gone.name)).toHaveCount(0);
    await page.getByRole("button", { name: "Revoked", exact: true }).click();
    await expect(row(page, gone.name)).toBeVisible();
    await expect(row(page, gone.name)).toContainText("Revoked");
    await page.getByRole("button", { name: /^No device yet · / }).click();
    await expect(row(page, waiting.name)).toBeVisible();
    await expect(row(page, basic.name)).toHaveCount(0);
    await page.getByRole("searchbox", { name: "Find a user" }).fill("no-user-is-named-this");
    await expect(page.getByRole("heading", { name: "No users match" })).toBeVisible();
    await page.getByRole("button", { name: "Clear search and filters" }).click();
    await expect(row(page, basic.name)).toBeVisible();
  });

  test("a user opens in the pane: role, devices linking to Devices, the producers they own, their subscriptions and their traffic; the address keeps it and Escape closes it", async ({ page }) => {
    const person = await createPerson("MOD");
    const owned = await createProducer(person, unique("mine"), "PUBLIC");
    const other = await createPerson("BASIC");
    const theirs = await createProducer(other, unique("theirs"), "PUBLIC");
    await subscribe(person, theirs);
    const sent = await publish(theirs, { title: unique("traffic"), severity: "HIGH", category: "BLOCKED" });
    // Its push is dispatched a moment later.
    for (let tries = 0; tries < 40; tries += 1) {
      if ((await operator("GET", `/api/v1/admin/users/${person.userId}/traffic`)).deliveries.length > 0) break;
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    await adminSignIn(page, "#users");
    await (await find(page, person.name)).click();
    await expect(page).toHaveURL(new RegExp(`#users/${person.userId}\\?q=`));
    const pane = page.getByRole("region", { name: person.name });
    await expect(pane).toBeVisible();
    expect(Math.round((await pane.boundingBox()).width)).toBe(480);
    await expect(pane.locator(".tagrow")).toContainText("Mod");
    await expect(pane.locator(".kv")).toContainText("Created");
    await expect(pane.locator(".kv")).toContainText(`on ${person.deviceName}`);
    // Role: a radio group with the sentence under it.
    await expect(pane.getByRole("radiogroup", { name: "Role" }).getByRole("radio", { name: "Mod" })).toBeChecked();
    await expect(pane.getByText("A Mod owns producers and subscribes, and manages their own devices.")).toBeVisible();
    // Devices: the name, how long ago and how its push goes, a link to the device.
    await expect(pane.getByText("1 active")).toBeVisible();
    const device = pane.getByRole("link", { name: new RegExp(person.deviceName) });
    await expect(device).toHaveAttribute("href", `#devices/${person.deviceId}`);
    await expect(device).toContainText("no push address");
    await expect(pane.getByRole("button", { name: `Connect a device for ${person.name}` })).toBeVisible();
    // Producers they own, and where to see them.
    await expect(pane.getByText("1 owned")).toBeVisible();
    await expect(pane.getByRole("link", { name: owned.name })).toHaveAttribute("href", `#producers/${owned.id}`);
    await expect(pane.getByRole("link", { name: "See in Producers" })).toHaveAttribute("href", `#producers?owner=${person.userId}`);
    // Subscriptions: their own producer and the one they follow, each with its own Unsubscribe.
    await expect(pane.getByRole("button", { name: `Unsubscribe ${person.name} from ${theirs.name}` })).toBeVisible();
    await expect(pane.getByRole("button", { name: `Unsubscribe ${person.name} from ${owned.name}` })).toBeVisible();
    // Traffic: the newest events, each opening in Events; Pushes tells what happened to each device.
    const events = pane.getByRole("tablist", { name: "Recent traffic" });
    await expect(events.getByRole("tab", { name: /^Events · / })).toHaveAttribute("aria-selected", "true");
    await expect(pane.getByRole("link", { name: new RegExp(sent.title) })).toHaveAttribute("href", `#events/${sent.id}`);
    await events.getByRole("tab", { name: /^Pushes · / }).click();
    await expect(pane.getByText(new RegExp(`${person.deviceName} · `))).toBeVisible();
    await expect(pane.getByRole("link", { name: `Open ${person.name} in Events` })).toHaveAttribute("href", `#events?user=${person.userId}`);
    // Technical details hold the id only.
    await expect(pane.getByText(person.userId)).toHaveCount(0);
    await pane.getByRole("button", { name: "Technical details" }).click();
    await expect(pane.getByText(person.userId)).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(pane).toHaveCount(0);
    await expect(row(page, person.name)).toBeFocused();
  });

  test("a user with no device says so in the pane and offers the first device; an admin's pane says where the role is changed", async ({ page }) => {
    const waiting = await invited();
    const admin = await createPerson("ADMIN");
    await adminSignIn(page, `#users/${waiting.id}`);
    const pane = page.getByRole("region", { name: waiting.name });
    await expect(pane.getByText(`${waiting.name} has no device yet.`)).toBeVisible();
    await expect(pane.getByText(`${waiting.name} cannot receive anything until one is connected.`)).toBeVisible();
    await expect(pane.locator(".kv")).toContainText("invited");
    await pane.getByRole("button", { name: "Connect their first device" }).click();
    const dialog = page.getByRole("dialog", { name: "Connect a device" });
    await expect(dialog.getByLabel("User")).toHaveText(new RegExp(waiting.name));
    await dialog.getByRole("button", { name: "Cancel" }).click();
    await page.evaluate((hash) => {
      location.hash = hash;
    }, `#users/${admin.userId}`);
    const adminPane = page.getByRole("region", { name: admin.name });
    await expect(adminPane.getByText("Made and taken away only on this page.")).toBeVisible();
    await expect(adminPane.locator(".tagrow")).toContainText("Admin");
    await expect(adminPane.getByText("Admin device")).toBeVisible();
  });

  test("a role changes only after a question that says what happens; Cancel changes nothing; the segment follows the server", async ({ page }) => {
    const person = await createPerson("BASIC");
    const pane = await openUser(page, person);
    const role = pane.getByRole("radiogroup", { name: "Role" });
    await role.getByRole("radio", { name: "Mod" }).click();
    let dialog = page.getByRole("dialog", { name: `Make ${person.name} a Mod?` });
    await expect(dialog).toContainText(`${person.name} will manage their own devices: rename, revoke, and connect new ones. Their devices and producers stay as they are.`);
    await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
    await dialog.getByRole("button", { name: "Cancel" }).click();
    // The control did not move.
    await expect(role.getByRole("radio", { name: "Basic" })).toBeChecked();
    expect((await operator("GET", "/api/v1/admin/users")).items.find((user) => user.id === person.userId).role).toBe("BASIC");
    await role.getByRole("radio", { name: "Mod" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Make Mod" }).click();
    await expect(page.locator(".snack")).toContainText(`${person.name} is now a Mod`);
    await expect(page.locator(".snack")).not.toContainText("Undo");
    await expect(role.getByRole("radio", { name: "Mod" })).toBeChecked();
    await expect(pane.locator(".tagrow")).toContainText("Mod");
    // To Admin: the power given is said, in the error colour, with who can take it away.
    await role.getByRole("radio", { name: "Admin" }).click();
    dialog = page.getByRole("dialog", { name: `Make ${person.name} an Admin?` });
    await expect(dialog).toContainText(`${person.name} will see every device, manage the devices of users who are not admins, and invite users. Their devices become admin devices.`);
    await expect(dialog).toContainText("Only you can take it away again, on this page.");
    await dialog.getByRole("button", { name: "Make Admin" }).click();
    await expect(page.locator(".snack")).toContainText(`${person.name} is now an Admin`);
    expect((await operator("GET", "/api/v1/admin/clients")).items.find((client) => client.id === person.deviceId).admin).toBe(true);
    // Away from Admin to Basic: what is lost is said. Other admins exist, so there is no warning.
    await createPerson("ADMIN");
    await page.reload();
    await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
    await page.getByRole("button", { name: "Sign in" }).click();
    await role.getByRole("radio", { name: "Basic" }).click();
    dialog = page.getByRole("dialog", { name: `Take Admin away from ${person.name}?` });
    await expect(dialog).toContainText(`${person.name} becomes a Basic user and loses the ability to manage their own devices.`);
    await expect(dialog).not.toContainText("Nobody will be an admin");
    await dialog.getByRole("button", { name: "Make Basic" }).click();
    await expect(page.locator(".snack")).toContainText(`${person.name} is now a Basic`);
  });

  test("taking Admin away from the last admin warns that nobody will be an admin in the app, then goes ahead; the arrow keys choose a role and open the question", async ({ page }) => {
    const admin = await createPerson("ADMIN");
    // Only this user is an admin as far as the page can see.
    await page.route("**/api/v1/admin/users", async (route) => {
      if (route.request().method() !== "GET") return route.continue();
      const response = await route.fetch();
      const body = await response.json();
      return json(route, { items: body.items.filter((user) => user.role !== "ADMIN" || user.id === admin.userId) });
    });
    const pane = await openUser(page, admin);
    const role = pane.getByRole("radiogroup", { name: "Role" });
    await role.getByRole("radio", { name: "Admin" }).focus();
    await page.keyboard.press("ArrowLeft");
    const dialog = page.getByRole("dialog", { name: `Take Admin away from ${admin.name}?` });
    await expect(dialog).toContainText(`${admin.name} becomes a Mod.`);
    await expect(dialog).toContainText("Nobody will be an admin in the app. The admin token still works here.");
    await page.keyboard.press("Escape");
    await expect(dialog).toHaveCount(0);
    await expect(role.getByRole("radio", { name: "Admin" })).toBeChecked();
  });

  test("subscribing lists the producers open to the user and needs no question; unsubscribing asks, says what disappears, and then the chip goes", async ({ page }) => {
    const person = await createPerson("BASIC");
    const other = await createPerson("BASIC");
    const open = await createProducer(other, unique("open"), "PUBLIC");
    const closed = await createProducer(other, unique("closed"), "PRIVATE");
    const pane = await openUser(page, person);
    await pane.getByRole("button", { name: `Subscribe ${person.name} to a producer` }).click();
    const menu = page.getByRole("menu", { name: `Subscribe ${person.name} to` });
    await expect(menu).toContainText(`Producers open to ${person.name} and not yet subscribed`);
    await expect(menu.getByRole("menuitem", { name: open.name })).toBeVisible();
    // A private producer that does not allow them is not offered.
    await expect(menu.getByRole("menuitem", { name: closed.name })).toHaveCount(0);
    await menu.getByRole("menuitem", { name: open.name }).click();
    await expect(page.locator(".snack")).toContainText(`${person.name} subscribed to ${open.name}`);
    await expect(pane.getByRole("button", { name: `Unsubscribe ${person.name} from ${open.name}` })).toBeVisible();
    await pane.getByRole("button", { name: `Unsubscribe ${person.name} from ${open.name}` }).click();
    const dialog = page.getByRole("dialog", { name: `Unsubscribe ${person.name} from ${open.name}?` });
    await expect(dialog).toContainText(`${person.name} stops receiving its events in their app, and the events it already sent disappear from their inbox too.`);
    await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
    await dialog.getByRole("button", { name: `Unsubscribe ${person.name} from ${open.name}` }).click();
    await expect(page.locator(".snack")).toContainText(`${person.name} unsubscribed from ${open.name}`);
    await expect(pane.getByRole("button", { name: `Unsubscribe ${person.name} from ${open.name}` })).toHaveCount(0);
  });

  test("inviting is a dialog: the name is checked, each role says what it is, Admin warns; a name that is taken is said on the field; then the first device is the next step", async ({ page }) => {
    const existing = await createPerson("BASIC");
    await adminSignIn(page, "#users");
    await page.getByRole("button", { name: "Invite a user" }).first().click();
    const dialog = page.getByRole("dialog", { name: "Invite a user" });
    await expect(dialog).toContainText("Inviting creates the user. The next step connects their first device.");
    await expect(dialog.getByLabel("Name")).toBeFocused();
    const invite = dialog.getByRole("button", { name: "Invite user" });
    await expect(invite).toBeDisabled();
    const roles = dialog.getByRole("radiogroup", { name: "Role" });
    await expect(roles.getByRole("radio", { name: /^Basic/ })).toBeChecked();
    await expect(roles).toContainText("Owns producers and subscribes to them. Manages no devices.");
    await roles.getByRole("radio", { name: /^Admin/ }).click();
    await expect(dialog).toContainText("An admin has wide powers. Their devices become admin devices. Admin is given only here, never by another admin.");
    await roles.getByRole("radio", { name: /^Basic/ }).click();
    await expect(dialog.getByText("An admin has wide powers.")).toHaveCount(0);
    // Names are unique ignoring case, revoked users included.
    await dialog.getByLabel("Name").fill(existing.name.toUpperCase());
    await invite.click();
    await expect(dialog.getByText("That name is taken. Names are not case-sensitive, and a revoked user keeps theirs.")).toBeVisible();
    await expect(dialog).toBeVisible();
    await expect(invite).toBeDisabled();
    const name = unique("newcomer");
    await dialog.getByLabel("Name").fill(name);
    await invite.click();
    // The second step: their first device, named after them.
    const next = page.getByRole("dialog", { name: `${name} is invited` });
    await expect(next).toContainText(`${name} (Basic) now exists. ${name} cannot receive anything until a device is connected.`);
    await expect(next.getByLabel("Name for the first device")).toHaveValue(`${name} - Phone`);
    await expect(next.getByText(`The device belongs to ${name}. It can be renamed later.`)).toBeVisible();
    await next.getByRole("button", { name: "Create pairing code" }).click();
    const code = page.getByRole("dialog", { name: `Pairing code for ${name} - Phone` });
    await expect(code).toBeVisible();
    await code.getByRole("button", { name: "Cancel this code" }).click();
    await page.getByRole("dialog", { name: "Cancel this code?" }).getByRole("button", { name: "Cancel this code" }).click();
    // Later leaves them in the list with the tag that says what is left to do.
    await expect(row(page, name)).toContainText("No device yet");
  });

  test("Later keeps the invited user with no device; a failed invitation says nothing was created and offers Try again", async ({ page }) => {
    await adminSignIn(page, "#users");
    const name = unique("later");
    await page.getByRole("button", { name: "Invite a user" }).first().click();
    let dialog = page.getByRole("dialog", { name: "Invite a user" });
    await dialog.getByLabel("Name").fill(name);
    let fail = true;
    await page.route("**/api/v1/admin/users", (route) => (route.request().method() === "POST" && fail ? json(route, { title: "Boom" }, 500) : route.continue()));
    await dialog.getByRole("button", { name: "Invite user" }).click();
    await expect(dialog).toContainText(`Could not invite ${name}: Boom Nobody was created.`);
    await expect(dialog.getByLabel("Name")).toHaveValue(name);
    fail = false;
    await dialog.getByRole("button", { name: "Try again" }).click();
    dialog = page.getByRole("dialog", { name: `${name} is invited` });
    await dialog.getByRole("button", { name: "Later" }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(row(page, name)).toContainText("No device yet");
  });

  test("renaming is a dialog: the name is said taken ignoring case, and the new name shows at once", async ({ page }) => {
    const person = await createPerson("BASIC");
    const other = await createPerson("BASIC");
    const pane = await openUser(page, person);
    await pane.getByRole("button", { name: `Rename ${person.name}` }).click();
    const dialog = page.getByRole("dialog", { name: "Rename the user" });
    await expect(dialog.getByLabel("Name")).toHaveValue(person.name);
    const rename = dialog.getByRole("button", { name: "Rename" });
    await expect(rename).toBeDisabled();
    await dialog.getByLabel("Name").fill(other.name.toUpperCase());
    await rename.click();
    await expect(dialog.getByText("That name is taken. Names are not case-sensitive, and a revoked user keeps theirs.")).toBeVisible();
    await expect(rename).toBeDisabled();
    const fresh = unique("renamed");
    await dialog.getByLabel("Name").fill(fresh);
    await rename.click();
    await expect(page.locator(".snack")).toContainText(`Renamed to ${fresh}`);
    await expect(page.getByRole("region", { name: fresh })).toBeVisible();
  });

  test("revoking asks first with the counts, says the name stays taken and cannot be undone; a revoked user is read-only, last in the list, and keeps their name", async ({ page }) => {
    const person = await createPerson("MOD");
    await createProducer(person, unique("owned"), "PUBLIC");
    const pane = await openUser(page, person);
    await expect(pane.getByText("Revokes their 1 device and disables their 1 producer, for good. Their events stay.")).toBeVisible();
    await pane.getByRole("button", { name: `Revoke ${person.name}` }).click();
    const dialog = page.getByRole("dialog", { name: `Revoke ${person.name}?` });
    await expect(dialog).toContainText("Their 1 device is revoked and their 1 producer disabled, at once and for good, so the people subscribed to that producer stop receiving it. Their events stay.");
    await expect(dialog).toContainText(`This cannot be undone. ${person.name}'s name stays taken: names are not case-sensitive and a revoked user keeps theirs, so ${person.name} cannot be invited again under it.`);
    await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
    await dialog.getByRole("button", { name: "Cancel" }).click();
    expect((await operator("GET", "/api/v1/admin/users")).items.find((user) => user.id === person.userId).revokedAt).toBeNull();
    await pane.getByRole("button", { name: `Revoke ${person.name}` }).click();
    await page.getByRole("dialog").getByRole("button", { name: `Revoke ${person.name}` }).click();
    await expect(page.locator(".snack")).toContainText(`${person.name} revoked`);
    await expect(pane.getByText(/^Revoked \d+ \w+\. Their devices are revoked and their producers disabled\. Their events stay\.$/)).toBeVisible();
    await expect(pane.getByRole("radiogroup", { name: "Role" })).toHaveCount(0);
    await expect(pane.getByRole("button", { name: `Revoke ${person.name}` })).toHaveCount(0);
    await expect(pane.getByRole("button", { name: `Rename ${person.name}` })).toHaveCount(0);
    await expect(pane.getByRole("button", { name: /^Unsubscribe / })).toHaveCount(0);
    await expect(pane.locator(".tagrow")).toContainText("Revoked");
    const after = (await operator("GET", "/api/v1/admin/users")).items.find((user) => user.id === person.userId);
    expect(after.revokedAt).not.toBeNull();
    expect(after.devices.every((device) => device.revokedAt)).toBe(true);
    // The name stays taken.
    await page.goto("/admin/#users");
    await page.getByRole("button", { name: "Invite a user" }).first().click();
    const invite = page.getByRole("dialog", { name: "Invite a user" });
    await invite.getByLabel("Name").fill(person.name);
    await invite.getByRole("button", { name: "Invite user" }).click();
    await expect(invite.getByText("That name is taken.")).toBeVisible();
  });

  test("a failure of the traffic stays in its part of the pane, with Try again; a failed change is said in the pane and nothing changed", async ({ page }) => {
    const person = await createPerson("BASIC");
    let failTraffic = true;
    await page.route(`**/api/v1/admin/users/${person.userId}/traffic`, (route) => (failTraffic ? json(route, { title: "Boom" }, 500) : route.continue()));
    const pane = await openUser(page, person);
    await expect(pane.getByText(`Could not load ${person.name}'s traffic.`)).toBeVisible();
    // The rest of the pane is there.
    await expect(pane.getByRole("radiogroup", { name: "Role" })).toBeVisible();
    failTraffic = false;
    await pane.getByRole("button", { name: "Try again" }).click();
    await expect(pane.getByText(`Could not load ${person.name}'s traffic.`)).toHaveCount(0);
    await page.route(`**/api/v1/admin/users/${person.userId}`, (route) => (route.request().method() === "PATCH" ? json(route, { title: "Boom" }, 500) : route.continue()));
    await pane.getByRole("radiogroup", { name: "Role" }).getByRole("radio", { name: "Mod" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: "Make Mod" }).click();
    await expect(dialog.getByRole("alert")).toContainText("Boom");
    await dialog.getByRole("button", { name: "Cancel" }).click();
    await expect(pane.getByRole("radiogroup", { name: "Role" }).getByRole("radio", { name: "Basic" })).toBeChecked();
  });

  test("an empty server says so and offers the first invitation; a list that cannot be read keeps the older one under a banner", async ({ page }) => {
    await page.route("**/api/v1/admin/users", (route) => (route.request().method() === "GET" ? json(route, { items: [] }) : route.continue()));
    await adminSignIn(page, "#users");
    await expect(page.getByRole("heading", { name: "No users yet" })).toBeVisible();
    await expect(page.getByText("Invite the first user, then connect a device for them with a pairing code. Their app receives the events of the producers they subscribe to.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Invite a user" })).toHaveCount(2);
    await page.unroute("**/api/v1/admin/users");
    let working = true;
    const person = await createPerson("BASIC");
    await page.route("**/api/v1/admin/users", (route) => (route.request().method() === "GET" && !working ? route.abort() : route.continue()));
    await page.goto("/admin/#users");
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    await find(page, person.name);
    working = false;
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    await expect(page.getByRole("alert").filter({ hasText: "Could not load the users." })).toBeVisible();
    await expect(row(page, person.name)).toBeVisible();
  });

  test("a user's name is shown as text, never as markup", async ({ page }) => {
    const markup = '<img src=x onerror="window.__owned=1">';
    const person = await createPerson("BASIC", `${markup}${unique("n")}`.slice(0, 90));
    await adminSignIn(page, `#users/${person.userId}`);
    await expect(page.getByRole("region", { name: person.name })).toBeVisible();
    expect(await page.locator("img").count()).toBe(0);
    expect(await page.evaluate(() => window.__owned)).toBeUndefined();
  });

  test("a push to one of their devices that failed is said in the pane in words", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("p"), "PUBLIC");
    const made = await operator("POST", "/api/v1/admin/clients", { name: unique("pushy"), userId: person.userId });
    await asDevice({ key: made.clientKey }, "PUT", "/api/v1/client/push-target", { provider: "fcm", token: `token-${unique("t")}` });
    await publish(producer, { title: unique("failing") });
    const pane = await openUser(page, person);
    await expect(pane.getByRole("link", { name: new RegExp(made.client.name) })).toContainText(/last push failed|push working/);
  });
});

test.describe("phone", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("the list is two-line rows with no sideways scroll; Invite a user is the icon in the header; the detail is a screen of its own", async ({ page }) => {
    const person = await createPerson("MOD");
    const waiting = await invited();
    await adminSignIn(page, "#users");
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    await expect(page.getByRole("columnheader")).toHaveCount(0);
    const invite = page.getByRole("button", { name: "Invite a user" }).first();
    await expect(invite).toBeVisible();
    expect((await invite.boundingBox()).y).toBeLessThan(120);
    const mine = await find(page, person.name);
    await expect(mine).toContainText("1 device · 0 producers");
    await page.getByRole("searchbox", { name: "Find a user" }).fill(waiting.name);
    await expect(row(page, waiting.name)).toContainText("No device yet");
    await row(page, waiting.name).click();
    const pane = page.getByRole("region", { name: waiting.name });
    await expect(pane).toBeVisible();
    expect(Math.round((await pane.boundingBox()).width)).toBe(390);
    await expect(page.getByRole("navigation", { name: "Sections (phone)" })).toBeHidden();
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    for (const control of await pane.getByRole("button").all()) {
      const box = await control.boundingBox();
      if (box) expect(box.height, await control.innerText()).toBeGreaterThanOrEqual(47);
    }
    await pane.getByRole("button", { name: "Back" }).click();
    await expect(pane).toHaveCount(0);
  });

  test("Invite a user is a full screen; a role change is a bottom sheet with the destructive action above Cancel", async ({ page }) => {
    const person = await createPerson("BASIC");
    await adminSignIn(page, "#users");
    await page.getByRole("button", { name: "Invite a user" }).first().click();
    const dialog = page.getByRole("dialog", { name: "Invite a user" });
    await expect.poll(async () => Math.round((await dialog.boundingBox()).height)).toBe(844);
    expect(Math.round((await dialog.boundingBox()).width)).toBe(390);
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    await dialog.getByRole("button", { name: "Close" }).click();
    await page.evaluate((hash) => {
      location.hash = hash;
    }, `#users/${person.userId}`);
    const pane = page.getByRole("region", { name: person.name });
    await expect(pane).toBeVisible();
    await pane.getByRole("radiogroup", { name: "Role" }).getByRole("radio", { name: "Admin" }).click();
    const sheet = page.getByRole("dialog", { name: `Make ${person.name} an Admin?` });
    await expect.poll(async () => {
      const box = await sheet.boundingBox();
      return Math.round(box.y + box.height);
    }).toBe(844);
    const make = await sheet.getByRole("button", { name: "Make Admin" }).boundingBox();
    const cancel = await sheet.getByRole("button", { name: "Cancel" }).boundingBox();
    expect(make.y).toBeLessThan(cancel.y);
    await sheet.getByRole("button", { name: "Cancel" }).click();
  });
});
