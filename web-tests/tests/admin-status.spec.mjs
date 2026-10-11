import { expect, test } from "../support/page.mjs";

test.beforeEach(async ({ context, baseURL }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: new URL(baseURL).origin });
});

const HEALTH_UP = { status: "UP", checks: [{ name: "Database connections health check", status: "UP", data: { "<default>": "UP" } }] };
const HEALTH_DOWN = { status: "DOWN", checks: [{ name: "Database connections health check", status: "DOWN" }] };
const NOW = () => new Date().toISOString();

const device = (name, { failed = false, address = true, retries = 0 } = {}) => ({
  id: crypto.randomUUID(),
  name,
  admin: false,
  kind: "DEVICE",
  user: { id: crypto.randomUUID(), name: "Ana", role: "MOD" },
  createdAt: NOW(),
  lastActiveAt: NOW(),
  expiresAt: null,
  revokedAt: null,
  pushTarget: address ? { provider: "fcm", updatedAt: NOW() } : null,
  pushPreferences: {},
  pushStatus: {
    lastSuccess: failed ? null : { at: NOW(), eventId: crypto.randomUUID() },
    lastFailure: failed ? { at: NOW(), eventId: crypto.randomUUID(), result: "PERMANENT_FAILURE" } : null,
    pendingRetries: retries,
  },
});

/** Answers what Status reads from `world`, which a test changes between looks. */
async function mockServer(page, world) {
  const json = (route, body, status = 200) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
  await page.route("**/q/health", (route) => (world.health === "abort" ? route.abort() : json(route, world.health, world.health.status === "UP" ? 200 : 503)));
  await page.route("**/q/info", (route) => (world.info === "abort" ? route.abort() : json(route, world.info)));
  await page.route("**/api/v1/admin/status", (route) => (world.status === "abort" ? route.abort() : world.status === "500" ? route.fulfill({ status: 500, body: "" }) : json(route, world.status)));
  // The first read of the device list is the sign-in's own: the real server answers it.
  let signedIn = false;
  await page.route("**/api/v1/admin/clients", (route) => {
    if (!signedIn) {
      signedIn = true;
      return route.continue();
    }
    return world.clients === "abort" ? route.abort() : json(route, { items: world.clients });
  });
  await page.route("**/api/v1/events?limit=1", (route) => (world.latest === "abort" ? route.abort() : json(route, { items: world.latest, nextCursor: null })));
}

const calm = () => ({
  health: HEALTH_UP,
  info: { signalhub: { version: "3.8.0", revision: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678" } },
  status: { pushProviders: ["fcm"], pushClientOptions: "fcm", pendingDispatches: 0, pendingRetries: 0, abandonedRetries: 0, eventRetentionSeconds: 31_536_000, startedAt: new Date(Date.now() - 8 * 86_400_000).toISOString() },
  clients: [device("Rodrigo - Pixel 9"), device("Ana - Galaxy Tab")],
  latest: [{ id: crypto.randomUUID(), title: "Rain expected at 15:00", createdAt: NOW(), producer: { id: crypto.randomUUID(), name: "weather-alerts" } }],
});

async function openStatus(page, world) {
  await mockServer(page, world);
  await page.goto("/admin/#status");
  await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "Status", level: 1 })).toBeVisible();
}

test("when everything works, Status says so in words and an icon, and the rail's button agrees", async ({ page }) => {
  await openStatus(page, calm());
  await expect(page.getByRole("heading", { name: "SignalHub is working" })).toBeVisible();
  await expect(page.getByText("Events are being stored and pushes are going out. Nothing needs attention.")).toBeVisible();
  const button = page.getByRole("link", { name: "Server status: working" });
  await expect(button).toBeVisible();
  await expect(button).toContainText("Working");
  for (const row of ["Database", "Push service", "Events waiting to be pushed", "Pushes waiting for a retry", "Devices whose last push failed"]) {
    await expect(page.getByRole("group", { name: row })).toContainText("Working");
  }
  await expect(page.getByRole("group", { name: "Version" })).toContainText("3.8.0 · revision a1b2c3d");
  await expect(page.getByRole("group", { name: "Last event received" })).toContainText("from weather-alerts: Rain expected at 15:00");
  // Running since comes from the status response: its date and how long ago.
  await expect(page.getByRole("group", { name: "Running since" })).toContainText("8 days");
  await expect(page.getByRole("group", { name: "Event retention" })).toContainText("Events older than 365 days are deleted by themselves.");
  await expect(page.getByText("Nothing is changed on this page: settings are in the server's .env and take effect after a restart.")).toBeVisible();
  // The fold is closed until it is asked for, and its raw values are not secret.
  await expect(page.locator("#status-tech")).toHaveCount(0);
  await page.getByRole("button", { name: "Technical details" }).click();
  await expect(page.locator("#status-tech")).toContainText("signalhub.revision");
  await expect(page.locator("#status-tech")).toContainText("a1b2c3d4e5f60718293a4b5c6d7e8f9012345678");
  await expect(page.locator("#status-tech")).not.toContainText(process.env.ADMIN_TOKEN);
  await page.getByRole("button", { name: "Copy the technical details" }).click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toContain("GET /q/health");
});

test("a failing push service and given-up retries need attention: the problems come first, with words, and the rail says Check", async ({ page }) => {
  const world = calm();
  await openStatus(page, world);
  await expect(page.getByRole("heading", { name: "SignalHub is working" })).toBeVisible();
  // Every device with a push address now failed its last push, and retries were given up since the page opened.
  world.clients = [device("Rodrigo - Pixel 9", { failed: true }), device("Ana - Galaxy Tab", { failed: true }), device("Rui - iPhone 15", { failed: true })];
  world.status = { ...world.status, pendingRetries: 148, abandonedRetries: 12 };
  await page.getByRole("button", { name: "Refresh the status" }).click();
  await expect(page.getByRole("heading", { name: "SignalHub needs attention" })).toBeVisible();
  await expect(page.getByText("Events are still being received and stored, but pushes to phones are failing. 2 things to look at:")).toBeVisible();
  await expect(page.getByRole("heading", { name: /NEEDS ATTENTION · 2/i })).toBeVisible();
  const push = page.getByRole("group", { name: "Push service" });
  await expect(push).toContainText("Needs attention");
  await expect(push).toContainText("every device with a push address failed its last push (3 of 3)");
  const retries = page.getByRole("group", { name: "Pushes waiting for a retry" });
  await expect(retries).toContainText("148 waiting · 12 given up since you opened this page");
  await expect(retries).toContainText("Needs attention");
  // One device's failure is a row warning, never the headline: here it is under Worth a look.
  await expect(page.getByRole("heading", { name: /WORTH A LOOK · 1/i })).toBeVisible();
  await expect(page.getByRole("group", { name: "Devices whose last push failed" })).toContainText("3 devices' last push failed: Rodrigo - Pixel 9, Ana - Galaxy Tab, Rui - iPhone 15");
  // The rail says it from every section.
  const rail = page.getByRole("link", { name: "Server status: needs attention, 2 things" });
  await expect(rail).toContainText("Check");
  await page.getByRole("link", { name: "Producers", exact: true }).first().click();
  await expect(page.getByRole("link", { name: "Server status: needs attention, 2 things" })).toBeVisible();
});

test("the headline's chips go to their rows, and the devices row opens Devices with Push problems chosen", async ({ page }) => {
  const world = calm();
  world.status = { ...world.status, pushProviders: [] };
  world.clients = [device("Rodrigo - Pixel 9", { failed: true }), device("Ana - Galaxy Tab")];
  await openStatus(page, world);
  await expect(page.getByRole("heading", { name: "SignalHub needs attention" })).toBeVisible();
  await expect(page.getByText("Events are still being received and stored, but nothing is pushed to phones. 1 thing to look at:")).toBeVisible();
  await page.getByRole("button", { name: "Push service" }).click();
  await expect(page.getByRole("group", { name: "Push service" })).toBeFocused();
  await expect(page.getByRole("group", { name: "Push service" })).toContainText("Not set up: nothing is pushed.");
  await page.getByRole("link", { name: "Open Devices" }).click();
  await expect(page).toHaveURL(/#devices\?f=problems$/);
  await expect(page.getByRole("button", { name: /^Push problems/ })).toHaveAttribute("aria-pressed", "true");
});

test("a database that is down is the first thing said", async ({ page }) => {
  const world = calm();
  world.health = HEALTH_DOWN;
  await openStatus(page, world);
  await expect(page.getByText("Events cannot be stored or read right now. 1 thing to look at:")).toBeVisible();
  await expect(page.getByRole("group", { name: "Database" })).toContainText("Not connected. SignalHub cannot store or read events right now.");
  await expect(page.getByRole("group", { name: "Database" })).toContainText("docker compose ps");
});

test("events waiting to be pushed need attention only above 20 and when they did not fall over two checks", async ({ page }) => {
  await page.clock.install();
  const world = calm();
  world.status = { ...world.status, pendingDispatches: 96 };
  await openStatus(page, world);
  // One look is not enough to say it is not falling.
  await expect(page.getByRole("heading", { name: "SignalHub is working" })).toBeVisible();
  world.status = { ...world.status, pendingDispatches: 148 };
  await page.clock.fastForward(31_000);
  await expect(page.getByRole("group", { name: "Events waiting to be pushed" })).toContainText("148 events waiting, up from 96 at the check before.");
  await expect(page.getByRole("heading", { name: "SignalHub needs attention" })).toBeVisible();
  // Falling, even above 20, is working.
  world.status = { ...world.status, pendingDispatches: 30 };
  await page.clock.fastForward(31_000);
  await expect(page.getByRole("heading", { name: "SignalHub is working" })).toBeVisible();
});

test("a part that cannot be read says so in words and counts as something to look at; the others are still shown", async ({ page }) => {
  const world = calm();
  world.status = "500";
  await openStatus(page, world);
  await expect(page.getByRole("heading", { name: "SignalHub needs attention" })).toBeVisible();
  await expect(page.getByRole("group", { name: "Pushes waiting for a retry" })).toContainText("Could not read: SignalHub answered 500.");
  await expect(page.getByRole("group", { name: "Pushes waiting for a retry" })).toContainText("Could not read");
  await expect(page.getByRole("group", { name: "Database" })).toContainText("Working");
});

test("when nothing can be read, Status says it cannot tell, keeps no guess, and the rail says Unknown", async ({ page }) => {
  const world = calm();
  world.health = "abort";
  world.info = "abort";
  world.status = "abort";
  world.clients = "abort";
  world.latest = "abort";
  await openStatus(page, world);
  await expect(page.getByRole("heading", { name: "Cannot tell if SignalHub is working" })).toBeVisible();
  await expect(page.getByText("The status could not be read: SignalHub did not answer. It is trying again every 30 seconds.")).toBeVisible();
  await expect(page.getByRole("heading", { name: "WHAT TO CHECK" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Server status: unknown" })).toContainText("Unknown");
  await expect(page.getByRole("button", { name: "Try again" })).toBeVisible();
});

test("the rail's button looks again every 30 seconds while the page is visible, from any section, and never reads the device list itself", async ({ page }) => {
  await page.clock.install();
  const world = calm();
  const reads = { status: 0, clients: 0 };
  await mockServer(page, world);
  await page.route("**/api/v1/admin/status", async (route) => {
    reads.status += 1;
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(world.status) });
  });
  await page.route("**/api/v1/admin/clients", async (route) => {
    reads.clients += 1;
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: world.clients }) });
  });
  await page.goto("/admin/#producers");
  await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "Producers", level: 1 })).toBeVisible();
  await expect(page.getByRole("link", { name: "Server status: working" })).toBeVisible();
  const first = reads.status;
  expect(first).toBeGreaterThan(0);
  // Sign-in read the device list; the rail does not read it again.
  const clientReads = reads.clients;
  await page.clock.fastForward(31_000);
  await expect.poll(() => reads.status).toBeGreaterThan(first);
  expect(reads.clients).toBe(clientReads);
  world.health = HEALTH_DOWN;
  await page.clock.fastForward(31_000);
  await expect(page.getByRole("link", { name: "Server status: needs attention, 1 thing" })).toBeVisible();
});

test("the rail says Checking until the first answer, and never claims Working before it", async ({ page }) => {
  let release;
  const held = new Promise((resolve) => {
    release = resolve;
  });
  await page.route("**/api/v1/admin/status", async (route) => {
    await held;
    await route.continue();
  });
  await page.goto("/admin/");
  await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("link", { name: "Server status: checking" })).toContainText("Checking");
  release();
  await expect(page.getByRole("link", { name: /^Server status: (working|needs attention)/ })).toBeVisible();
});
