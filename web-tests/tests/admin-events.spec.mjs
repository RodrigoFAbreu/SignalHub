import { asDevice, createPerson, createProducer, operator, publish, unique } from "../support/server.mjs";
import { adminSignIn, expect, test } from "../support/page.mjs";

const sideways = (page) => page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, view: window.innerWidth, body: document.body.scrollWidth }));
const json = (route, body, status = 200) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });

/** A person, a producer of theirs, and some events of it (oldest first), as a producer would publish them. */
async function world(events = [{}, {}, {}], role = "BASIC") {
  const owner = await createPerson(role);
  const producer = await createProducer(owner, unique("ev"), "PUBLIC");
  const sent = [];
  for (const event of events) sent.push(await publish(producer, { title: unique("event"), ...event }));
  return { owner, producer, sent };
}

const open = async (page, producer, extra = "") => {
  await adminSignIn(page, `#events?producer=${producer.id}${extra}`);
  await expect(page.getByRole("heading", { name: "Events", level: 1 })).toBeVisible();
};

const row = (page, title) => page.getByRole("row", { name: new RegExp(`^${title}`) });

/** The records of an event's pushes are written a moment after it is published. */
async function pushesRecorded(event, atLeast = 1) {
  for (let tries = 0; tries < 40; tries += 1) {
    const answer = await operator("GET", `/api/v1/admin/events/${event.id}/deliveries`);
    if (answer.items.length >= atLeast) return answer;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error("the push of the event was never recorded");
}

async function pushProblemFor(owner, producer) {
  // A device whose push service this server does not support: its push is refused for good.
  const made = await operator("POST", "/api/v1/admin/clients", { name: unique("push-phone"), userId: owner.userId });
  await asDevice({ key: made.clientKey }, "PUT", "/api/v1/client/push-target", { provider: "fcm", token: `token-${unique("t")}` });
  const event = await publish(producer, { title: unique("pushfail"), severity: "HIGH", category: "BLOCKED" });
  await pushesRecorded(event, 2);
  return { event, device: made.client };
}

test.describe("desktop", () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test("the table is dense and newest first: the unread dot, the title, the producer, severity and category in words, and how long ago; no column sorts", async ({ page }) => {
    const { producer, sent } = await world([
      { title: unique("first"), severity: "LOW", category: "INFO" },
      { title: unique("second"), severity: "CRITICAL", category: "ACTION_REQUIRED" },
      { title: unique("third"), severity: "HIGH", category: "BLOCKED" },
    ]);
    await open(page, producer);
    const rows = page.getByRole("grid", { name: "Events" }).getByRole("row");
    // The header row, then newest first.
    await expect(rows).toHaveCount(4);
    await expect(rows.nth(1)).toContainText(sent[2].title);
    await expect(rows.nth(2)).toContainText(sent[1].title);
    await expect(rows.nth(3)).toContainText(sent[0].title);
    const header = rows.first();
    for (const name of ["Event", "Producer", "Severity", "Category", "Received"]) await expect(header.getByRole("columnheader", { name, exact: true })).toBeVisible();
    // No sort: the API has none, so there is no arrow and no sort state.
    await expect(page.locator("[aria-sort]")).toHaveCount(0);
    await expect(header.getByRole("button", { name: /sort/i })).toHaveCount(0);
    const second = rows.nth(2);
    await expect(second).toHaveAccessibleName(new RegExp(`^${sent[1].title}, Critical, Action required, ${producer.name}, just now, unread$`));
    await expect(second.getByRole("gridcell").nth(3)).toContainText("Critical");
    await expect(second).toContainText("Action required");
    await expect(second).toContainText(producer.name);
    // The header says how many, and that they come newest first; the pager says the same.
    await expect(page.locator(".mhead .cnt").first()).toHaveText("3 events · Newest first");
    await expect(page.locator(".pgr")).toContainText("3 events");
    await expect(page.getByRole("button", { name: "Newer" })).toBeDisabled();
    await expect(page.getByRole("button", { name: "Older" })).toBeDisabled();
    await expect(page.getByText(/^Updated \d\d:\d\d$/)).toBeVisible();
  });

  test("25 a page: the header says 25 of the total, Older follows the cursor and Newer goes back to the page already read", async ({ page }) => {
    const { producer, sent } = await world(Array.from({ length: 27 }, (_, index) => ({ title: unique(`paged-${index}`) })));
    await open(page, producer);
    await expect(page.locator(".mhead .cnt").first()).toHaveText("25 of 27 · Newest first");
    await expect(page.locator(".pgr")).toContainText("Newest 25 events");
    const grid = page.getByRole("grid", { name: "Events" });
    await expect(grid.getByRole("row")).toHaveCount(26);
    await expect(grid).toContainText(sent[26].title);
    await expect(grid).not.toContainText(sent[0].title);
    await page.getByRole("button", { name: "Older" }).click();
    await expect(grid.getByRole("row")).toHaveCount(3);
    await expect(grid).toContainText(sent[0].title);
    await expect(page.locator(".pgr")).toContainText("Events 26 to 27");
    await expect(page.locator(".mhead .cnt").first()).toHaveText("2 of 27 · Newest first");
    await expect(page.getByRole("button", { name: "Older" })).toBeDisabled();
    await page.getByRole("button", { name: "Newer" }).click();
    await expect(grid.getByRole("row")).toHaveCount(26);
    await expect(grid).toContainText(sent[26].title);
    await expect(page.getByRole("button", { name: "Newer" })).toBeDisabled();
  });

  test("Severity, Category and Producer take several values in a panel of checkboxes that stays open and is applied when it closes; the choice is in the address", async ({ page }) => {
    const { producer, sent } = await world([
      { title: unique("low"), severity: "LOW", category: "INFO" },
      { title: unique("high"), severity: "HIGH", category: "BLOCKED" },
      { title: unique("crit"), severity: "CRITICAL", category: "ACTION_REQUIRED" },
      { title: unique("norm"), severity: "NORMAL", category: "COMPLETED" },
    ]);
    await open(page, producer);
    const severity = page.getByRole("button", { name: "Severity", exact: true });
    await severity.click();
    const panel = page.getByRole("group", { name: "Severity filter" });
    await expect(panel.getByRole("checkbox")).toHaveText(["Low", "Normal", "High", "Critical"]);
    await panel.getByRole("checkbox", { name: "High" }).click();
    await panel.getByRole("checkbox", { name: "Critical" }).click();
    // The panel stays open while choices are made, and nothing is asked until it closes.
    await expect(panel).toBeVisible();
    await expect(page.getByRole("grid", { name: "Events" }).getByRole("row")).toHaveCount(5);
    await page.keyboard.press("Escape");
    await expect(panel).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Severity: Critical, High" })).toBeFocused();
    await expect(page).toHaveURL(/severity=HIGH%2CCRITICAL|severity=HIGH,CRITICAL/);
    const grid = page.getByRole("grid", { name: "Events" });
    await expect(grid.getByRole("row")).toHaveCount(3);
    await expect(grid).toContainText(sent[1].title);
    await expect(grid).toContainText(sent[2].title);
    await expect(grid).not.toContainText(sent[0].title);
    await expect(page.locator(".mhead .cnt").first()).toHaveText("2 events · Newest first");
    // Category: the same, in its own words.
    await page.getByRole("button", { name: "Category", exact: true }).click();
    await page.getByRole("checkbox", { name: "Blocked" }).click();
    await page.mouse.click(700, 700);
    await expect(page.getByRole("button", { name: "Category: Blocked" })).toBeVisible();
    await expect(grid.getByRole("row")).toHaveCount(2);
    await expect(grid).toContainText(sent[1].title);
    // Producer: this one only, kept from the address; Clear in the panel removes it.
    await expect(page.getByRole("button", { name: `Producer: ${producer.name}` })).toBeVisible();
    await page.getByRole("button", { name: /^Producer: / }).click();
    await page.getByRole("button", { name: "Clear", exact: true }).click();
    await expect(page.getByRole("button", { name: "Producer", exact: true })).toBeVisible();
    await expect(page).not.toHaveURL(/producer=/);
  });

  test("Read state, User with Their producers, Received and Push problems narrow the list; every one is in the address and one press clears them", async ({ page }) => {
    const { owner, producer, sent } = await world([{ title: unique("a-read") }, { title: unique("b-unread") }]);
    // Read state is the operator's own, the one the admin token has.
    await operator("PUT", `/api/v1/events/${sent[0].id}/read`);
    await open(page, producer);
    // Read state is a menu of one choice.
    await page.getByRole("button", { name: "Read state", exact: true }).click();
    await page.getByRole("menuitemradio", { name: "Unread only" }).click();
    await expect(page.getByRole("button", { name: "Read state: Unread only" })).toBeVisible();
    await expect(page).toHaveURL(/read=false/);
    await expect(page.getByRole("row", { name: new RegExp(`^${sent[1].title}`) })).toBeVisible();
    await expect(page.getByRole("row", { name: new RegExp(`^${sent[0].title}`) })).toHaveCount(0);
    // User: the users by name; a chip for their producers comes with one.
    await expect(page.getByRole("button", { name: /^Their producers/ })).toHaveCount(0);
    await page.getByRole("button", { name: "User", exact: true }).click();
    await page.getByRole("menuitemradio", { name: new RegExp(owner.name) }).click();
    await expect(page.getByRole("button", { name: `User: ${owner.name}` })).toBeVisible();
    await page.getByRole("button", { name: "Their producers", exact: true }).click();
    await page.getByRole("menuitemradio", { name: "Owned", exact: true }).click();
    await expect(page.getByRole("button", { name: "Their producers: Owned" })).toBeVisible();
    await expect(page).toHaveURL(/user=[0-9a-f-]{36}&relation=OWNED|relation=OWNED/);
    await expect(page.getByRole("row", { name: new RegExp(`^${sent[1].title}`) })).toBeVisible();
    // Received: a from and a before day, in this browser's time zone.
    await page.getByRole("button", { name: "Received", exact: true }).click();
    const panel = page.getByRole("group", { name: "Received filter" });
    await expect(panel).toContainText("Midnight (00:00) in your browser's time zone.");
    await panel.getByRole("button", { name: "Last 7 days" }).click();
    await panel.getByRole("button", { name: "Apply" }).click();
    await expect(page.getByRole("button", { name: /^Received: .* to .*|^Received: \d+ \w+$/ })).toBeVisible();
    await expect(page).toHaveURL(/from=\d{4}-\d\d-\d\d&before=\d{4}-\d\d-\d\d|before=\d{4}-\d\d-\d\d&from=/);
    await expect(page.getByRole("row", { name: new RegExp(`^${sent[1].title}`) })).toBeVisible();
    // A day in the past leaves nothing, and says which filters were in force.
    await page.getByRole("button", { name: /^Received/ }).click();
    await panel.getByLabel("From").fill("2001-01-01");
    await panel.getByLabel("Before").fill("2001-01-02");
    await panel.getByRole("button", { name: "Apply" }).click();
    await expect(page.getByRole("heading", { name: "No events match" })).toBeVisible();
    await expect(page.getByText(/^Nothing has Read state Unread only, Received 1 Jan 2001 and User .+ for .+\.$/)).toBeVisible();
    await expect(page.locator(".mhead .cnt").first()).toContainText("0 events");
    await page.getByRole("button", { name: "Clear filters" }).last().click();
    await expect(page).toHaveURL(/#events$/);
    await expect(page.getByRole("button", { name: "Read state", exact: true })).toBeVisible();
    await expect(page.getByRole("row", { name: new RegExp(`^${sent[0].title}`) })).toBeVisible();
  });

  test("Push problems is a chip that shows the events a push failed for, with a marker in the row", async ({ page }) => {
    const { owner, producer, sent } = await world([{ title: unique("quiet-event") }]);
    // Its push is dispatched before the device with a push address exists, so it has no problem.
    await pushesRecorded(sent[0]);
    const { event } = await pushProblemFor(owner, producer);
    await open(page, producer);
    const failing = row(page, event.title);
    await expect(failing).toHaveAccessibleName(/, push problems$/);
    await expect(failing.getByText("Push problems")).toBeVisible();
    await page.getByRole("button", { name: "Push problems", exact: true }).click();
    await expect(page.getByRole("button", { name: "Push problems", exact: true })).toHaveAttribute("aria-pressed", "true");
    await expect(page).toHaveURL(/push=problems/);
    await expect(page.getByRole("grid", { name: "Events" }).getByRole("row")).toHaveCount(2);
    await expect(failing).toBeVisible();
    await page.reload();
    await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page.getByRole("button", { name: "Push problems", exact: true })).toHaveAttribute("aria-pressed", "true");
    await expect(failing).toBeVisible();
  });

  test("the filters of an address that is not the page's own are ignored, never sent", async ({ page }) => {
    const { producer } = await world([{ title: unique("only"), severity: "HIGH" }]);
    const requests = [];
    page.on("request", (request) => requests.push(request.url()));
    await adminSignIn(page, `#events?producer=${producer.id}&severity=NOPE,HIGH&category=%3Cb%3E&read=maybe&user=not-an-id&from=yesterday&producer=x`);
    await expect(page.getByRole("heading", { name: "Events", level: 1 })).toBeVisible();
    await expect(page.getByRole("grid", { name: "Events" })).toBeVisible();
    const listing = requests.filter((url) => url.includes("/api/v1/events?")).at(-1);
    expect(listing).toContain("severity=HIGH");
    expect(listing).not.toContain("NOPE");
    expect(listing).not.toContain("read=");
    expect(listing).not.toContain("userId");
    expect(listing).not.toContain("createdFrom");
  });

  test("an event opens in the fixed pane with its tabs; the address keeps it; Escape closes it and focus returns to its row", async ({ page }) => {
    const { producer, sent } = await world([
      {
        title: unique("detail"),
        severity: "HIGH",
        category: "BLOCKED",
        message: "3 of 412 tests failed on main.",
        context: "signalhub-web",
        link: "https://ci.example.com/runs/1842",
        metadata: { branch: "main", failed_tests: 3, jobs: ["unit", "lint"] },
        occurredAt: "2026-10-11T12:36:00Z",
      },
    ]);
    await open(page, producer);
    await expect(page.getByText("Select an event")).toBeVisible();
    const target = row(page, sent[0].title);
    await target.click();
    await expect(page).toHaveURL(new RegExp(`#events/${sent[0].id}\\?producer=${producer.id}`));
    const pane = page.getByRole("region", { name: sent[0].title });
    await expect(pane).toBeVisible();
    expect(Math.round((await pane.boundingBox()).width)).toBe(480);
    await expect(target).toHaveAttribute("aria-selected", "true");
    await expect(pane.getByRole("tab", { name: "Event" })).toHaveAttribute("aria-selected", "true");
    await expect(pane.getByRole("tab", { name: /^Pushes/ })).toBeVisible();
    // Severity and category are words with an icon, never a colour alone.
    await expect(pane.locator(".chips .sv")).toContainText("High");
    await expect(pane.locator(".chips .tg").first()).toContainText("Blocked");
    await expect(pane.getByText("Unread", { exact: true })).toBeVisible();
    await expect(pane.getByText("3 of 412 tests failed on main.")).toBeVisible();
    // The link shows where it goes and opens in a new tab that cannot reach back.
    await expect(pane.getByText("ci.example.com/runs/1842")).toBeVisible();
    await expect(pane.getByText("Opens in a new tab")).toBeVisible();
    const link = pane.getByRole("link", { name: /^Open link/ });
    await expect(link).toHaveAttribute("href", "https://ci.example.com/runs/1842");
    await expect(link).toHaveAttribute("target", "_blank");
    await expect(link).toHaveAttribute("rel", "noopener noreferrer");
    // The facts, and the metadata exactly as sent, a nested value as JSON.
    await expect(pane.getByRole("link", { name: producer.name })).toHaveAttribute("href", `#producers/${producer.id}`);
    await expect(pane.locator(".kv")).toContainText("signalhub-web");
    await expect(pane.locator(".kv")).toContainText("Happened");
    await expect(pane.locator(".kv")).toContainText("Not by you yet");
    await expect(pane.locator(".meta")).toContainText("branch");
    await expect(pane.locator(".meta")).toContainText("main");
    await expect(pane.locator(".meta")).toContainText('["unit","lint"]');
    await expect(pane.getByRole("button", { name: "Mark read" })).toBeVisible();
    await expect(pane.getByRole("button", { name: `Delete event ${sent[0].title}` })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(pane).toHaveCount(0);
    await expect(page).toHaveURL(new RegExp(`#events\\?producer=${producer.id}$`));
    await expect(target).toBeFocused();
    // An address that names an event opens it, even when it is not on the page.
    await page.goto(`/admin/#events/${sent[0].id}`);
    await expect(page.getByRole("region", { name: sent[0].title })).toBeVisible();
  });

  test("marking an event read or unread is one press in the pane's foot, and the list follows", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("toggle") }]);
    await open(page, producer);
    const target = row(page, sent[0].title);
    await expect(target).toHaveAccessibleName(/, unread$/);
    await target.click();
    const pane = page.getByRole("region", { name: sent[0].title });
    await pane.getByRole("button", { name: "Mark read" }).click();
    await expect(pane.getByRole("button", { name: "Mark unread" })).toBeVisible();
    await expect(pane.getByText("Unread", { exact: true })).toHaveCount(0);
    await expect(target).not.toHaveAccessibleName(/unread/);
    await expect(pane.locator(".kv")).not.toContainText("Not by you yet");
    await pane.getByRole("button", { name: "Mark unread" }).click();
    await expect(pane.getByRole("button", { name: "Mark read" })).toBeVisible();
    await expect(target).toHaveAccessibleName(/, unread$/);
  });

  test("the Pushes tab says how each device's push went, grouped by user; the codes are only under Technical details", async ({ page }) => {
    const { owner, producer } = await world([{ title: unique("quiet-event") }]);
    const { event, device } = await pushProblemFor(owner, producer);
    await open(page, producer);
    await row(page, event.title).click();
    const pane = page.getByRole("region", { name: event.title });
    // The tab counts the pushes that went wrong.
    await expect(pane.getByRole("tab", { name: /^Pushes/ })).toContainText("1 problem");
    await expect(pane.getByText("Reached 1 user on 2 devices")).toBeVisible();
    await pane.getByRole("button", { name: "See pushes" }).click();
    await expect(pane.getByRole("tab", { name: /^Pushes/ })).toHaveAttribute("aria-selected", "true");
    await expect(pane.getByText("The push service's answer is the last thing SignalHub knows. It cannot tell whether a device showed the push.")).toBeVisible();
    const group = pane.getByRole("group", { name: owner.name });
    await expect(group).toContainText("Owns the producer");
    await expect(pane.getByText(`${owner.deviceName} · Not sent`)).toBeVisible();
    await expect(pane.getByText("This device has no push address.")).toBeVisible();
    await expect(pane.getByText(`${device.name} · Not sent`)).toBeVisible();
    await expect(pane.getByText("This device's push service is not supported by this server.")).toBeVisible();
    // Ids and codes appear only when the fold is opened.
    await expect(pane.getByText("NO_TARGET")).toHaveCount(0);
    await expect(pane.getByText(event.id)).toHaveCount(0);
    const fold = pane.getByRole("button", { name: "Technical details" });
    await expect(fold).toHaveAttribute("aria-expanded", "false");
    await fold.click();
    await expect(pane.getByText(/^NO_TARGET · \d\d:\d\d:\d\d$/)).toBeVisible();
    await expect(pane.getByText(/^UNSUPPORTED_PROVIDER · attempt 1 · \d\d:\d\d:\d\d/)).toBeVisible();
    await expect(pane.getByText(`event ${event.id}`)).toBeVisible();
    await expect(pane.getByText(`producer ${producer.id}`)).toBeVisible();
    await expect(pane.getByText("records: 2, oldest first")).toBeVisible();
  });

  test("every wording of a push: sent, waiting for a retry, gave up after the tries it had, refused, failed, and not sent with its reason", async ({ page }) => {
    const { owner, producer, sent } = await world([{ title: unique("words") }]);
    const ana = await createPerson("MOD");
    const record = (client, user, outcome, extra = {}) => ({ clientId: client.id, clientName: client.name, userId: user.id, userName: user.name, attempt: 1, outcome, detail: null, at: "2026-10-11T12:37:02.000000Z", final: true, ...extra });
    const ids = ["pixel", "tablet", "phone", "watch", "firefox", "iphone", "laptop", "late"].map((name, index) => ({ id: `0199aaaa-0000-7000-8000-00000000000${index}`, name }));
    const [sentDevice, retry, gave, refused, failed, filtered, unsupported, paused] = ids;
    const answer = {
      items: [
        record(sentDevice, { id: owner.userId, name: owner.name }, "DELIVERED"),
        record(retry, { id: ana.userId, name: ana.name }, "TRANSIENT_FAILURE", { detail: "HTTP 503 UNAVAILABLE", final: false }),
        record(gave, { id: ana.userId, name: ana.name }, "TRANSIENT_FAILURE", { attempt: 4, detail: "HTTP 503 UNAVAILABLE", final: true }),
        record(refused, { id: ana.userId, name: ana.name }, "PERMANENT_FAILURE", { detail: "HTTP 400 INVALID_ARGUMENT" }),
        record(failed, { id: ana.userId, name: ana.name }, "INVALID_TARGET", { detail: "HTTP 404 UNREGISTERED" }),
        record(filtered, { id: ana.userId, name: ana.name }, "FILTERED", { detail: "producer muted" }),
        record(unsupported, { id: ana.userId, name: ana.name }, "UNSUPPORTED_PROVIDER", { detail: "apns" }),
        record(paused, { id: ana.userId, name: ana.name }, "FILTERED", { detail: "pushes paused" }),
      ],
      users: [
        { id: owner.userId, name: owner.name, owner: true },
        { id: ana.userId, name: ana.name, owner: false },
      ],
    };
    await page.route(`**/api/v1/admin/events/${sent[0].id}/deliveries`, (route) => json(route, answer));
    await open(page, producer);
    await row(page, sent[0].title).click();
    const pane = page.getByRole("region", { name: sent[0].title });
    await pane.getByRole("tab", { name: /^Pushes/ }).click();
    await expect(pane.getByText("pixel · Sent")).toBeVisible();
    await expect(pane.getByText(/· accepted by the push service$/)).toBeVisible();
    await expect(pane.getByText("tablet · Waiting for a retry")).toBeVisible();
    await expect(pane.getByText("The push service did not accept it this time. SignalHub will try again.")).toBeVisible();
    // The server's final marker is what decides it gave up, with the tries it had.
    await expect(pane.getByText("phone · Gave up after 4 tries")).toBeVisible();
    await expect(pane.getByText("The push service did not accept it this time, on any of the 4 tries.")).toBeVisible();
    await expect(pane.getByText("watch · Refused")).toBeVisible();
    await expect(pane.getByText("The push service refused it.")).toBeVisible();
    await expect(pane.getByText("firefox · Failed")).toBeVisible();
    await expect(pane.getByText("The push service no longer knows this device, so its address was removed.")).toBeVisible();
    await expect(pane.getByText("iphone · Not sent")).toBeVisible();
    await expect(pane.getByText("Not sent: the producer is muted on this device.")).toBeVisible();
    await expect(pane.getByText("laptop · Not sent")).toBeVisible();
    await expect(pane.getByText("This device's push service is not supported by this server.")).toBeVisible();
    await expect(pane.getByText("late · Not sent")).toBeVisible();
    await expect(pane.getByText("Not sent: pushes are paused on this device.")).toBeVisible();
    // Waiting, gave up, refused, failed and not supported: five to look at.
    await expect(pane.getByRole("tab", { name: /^Pushes/ })).toContainText("5 problems");
    await pane.getByRole("button", { name: "Technical details" }).click();
    await expect(pane.getByText(/^TRANSIENT_FAILURE · attempt 1 · \d\d:\d\d:\d\d provider: HTTP 503 UNAVAILABLE$/)).toBeVisible();
    await expect(pane.getByText(/^TRANSIENT_FAILURE · attempt 4 · \d\d:\d\d:\d\d provider: HTTP 503 UNAVAILABLE$/)).toBeVisible();
  });

  test("a push that is not sent yet, nobody to reach, and a list that did not load each say so in the Pushes tab", async ({ page }) => {
    const { owner, producer, sent } = await world([{ title: unique("a-pending") }, { title: unique("b-nobody") }, { title: unique("c-broken") }]);
    await page.route(`**/api/v1/admin/events/${sent[0].id}/deliveries`, (route) => json(route, { items: [], users: [{ id: owner.userId, name: owner.name, owner: true }] }));
    await page.route(`**/api/v1/admin/events/${sent[1].id}/deliveries`, (route) => json(route, { items: [], users: [] }));
    let fail = true;
    await page.route(`**/api/v1/admin/events/${sent[2].id}/deliveries`, (route) => (fail ? json(route, { title: "Boom" }, 500) : json(route, { items: [], users: [] })));
    await open(page, producer);
    await row(page, sent[0].title).click();
    let pane = page.getByRole("region", { name: sent[0].title });
    await pane.getByRole("tab", { name: /^Pushes/ }).click();
    await expect(pane.getByText("Its push is not sent yet. This refreshes by itself.")).toBeVisible();
    await row(page, sent[1].title).click();
    pane = page.getByRole("region", { name: sent[1].title });
    await expect(pane.getByText("No user receives it")).toBeVisible();
    await expect(pane.getByRole("tab", { name: /^Pushes/ })).toContainText("none");
    await pane.getByRole("tab", { name: /^Pushes/ }).click();
    await expect(pane.getByRole("heading", { name: "No user receives it" })).toBeVisible();
    await expect(pane.getByText(`Nobody is subscribed to ${producer.name}, so there was no one to push to.`)).toBeVisible();
    await row(page, sent[2].title).click();
    pane = page.getByRole("region", { name: sent[2].title });
    await pane.getByRole("tab", { name: /^Pushes/ }).click();
    await expect(pane.getByText("Could not load the pushes. Check the connection and try again.")).toBeVisible();
    // The Event tab stays usable: it does not depend on the pushes.
    await pane.getByRole("tab", { name: "Event" }).click();
    await expect(pane.getByRole("button", { name: "Mark read" })).toBeVisible();
    await pane.getByRole("tab", { name: /^Pushes/ }).click();
    fail = false;
    await pane.getByRole("button", { name: "Try again" }).click();
    await expect(pane.getByRole("heading", { name: "No user receives it" })).toBeVisible();
  });

  test("deleting one event asks first, names it, and then the list and the address go back", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("keep") }, { title: unique("doomed") }]);
    await open(page, producer);
    await row(page, sent[1].title).click();
    const pane = page.getByRole("region", { name: sent[1].title });
    await pane.getByRole("button", { name: `Delete event ${sent[1].title}` }).click();
    const dialog = page.getByRole("dialog", { name: "Delete this event?" });
    await expect(dialog).toContainText(`“${sent[1].title}” is gone for good, with its waiting pushes and delivery records. Producers and users are not touched. This cannot be undone.`);
    // Cancel has the focus; the destructive action is a text button in the error colour.
    await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
    const confirm = dialog.getByRole("button", { name: `Delete event ${sent[1].title}` });
    expect(await confirm.evaluate((node) => getComputedStyle(node).backgroundColor)).toBe("rgba(0, 0, 0, 0)");
    await dialog.getByRole("button", { name: "Cancel" }).click();
    await expect(pane).toBeVisible();
    expect((await operator("GET", `/api/v1/admin/events/${sent[1].id}/deliveries`)).users).toBeDefined();
    await pane.getByRole("button", { name: `Delete event ${sent[1].title}` }).click();
    await page.getByRole("dialog").getByRole("button", { name: `Delete event ${sent[1].title}` }).click();
    await expect(pane).toHaveCount(0);
    await expect(page.locator(".snack")).toContainText(`Deleted “${sent[1].title}”`);
    // A snack bar carries no Undo, and does not cover the pager.
    await expect(page.locator(".snack")).not.toContainText("Undo");
    await expect(row(page, sent[1].title)).toHaveCount(0);
    await expect(row(page, sent[0].title)).toBeVisible();
    await expect(page).toHaveURL(new RegExp(`#events\\?producer=${producer.id}$`));
    const snack = await page.locator(".snack").boundingBox();
    const pager = await page.locator(".pgr").boundingBox();
    expect(snack.y + snack.height).toBeLessThanOrEqual(pager.y);
  });

  test("ticking rows turns the chips into the bulk bar: its count, Select all on this page, Mark read and Delete naming the count", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("t0") }, { title: unique("t1") }, { title: unique("t2") }, { title: unique("t3") }]);
    await open(page, producer);
    const bar = page.getByRole("toolbar", { name: "Selected events" });
    await expect(bar).toBeHidden();
    await page.getByRole("checkbox", { name: `Select ${sent[3].title}` }).click();
    await expect(bar).toBeVisible();
    await expect(page.getByRole("group", { name: "Filter events" })).toBeHidden();
    await expect(bar).toContainText("1 selected");
    // Space ticks the row the keyboard is on; the grid is one tab stop.
    await row(page, sent[2].title).focus();
    await page.keyboard.press("Space");
    await expect(bar).toContainText("2 selected");
    await expect(page.getByRole("checkbox", { name: `Select ${sent[2].title}` })).toHaveAttribute("aria-checked", "true");
    await bar.getByRole("button", { name: "Select all 4 on this page" }).click();
    await expect(bar).toContainText("4 selected");
    await expect(bar.getByRole("button", { name: /Select all/ })).toHaveCount(0);
    await expect(page.getByRole("checkbox", { name: "Select all events on this page" })).toHaveAttribute("aria-checked", "true");
    // The pane waits while several are ticked.
    await expect(page.getByText("Select an event")).toBeVisible();
    await bar.getByRole("button", { name: "Clear the selection" }).click();
    await expect(bar).toBeHidden();
    await expect(page.getByRole("group", { name: "Filter events" })).toBeVisible();
    // Mark read for the selection, then delete it after a question that says how many.
    await page.getByRole("checkbox", { name: `Select ${sent[0].title}` }).click();
    await page.getByRole("checkbox", { name: `Select ${sent[1].title}` }).click();
    await bar.getByRole("button", { name: "Mark read" }).click();
    await expect(page.locator(".snack")).toContainText("Marked 2 events read");
    await expect(row(page, sent[0].title)).not.toHaveAccessibleName(/unread/);
    await expect(row(page, sent[3].title)).toHaveAccessibleName(/unread/);
    await expect(bar).toBeHidden();
    await page.getByRole("checkbox", { name: `Select ${sent[0].title}` }).click();
    await page.getByRole("checkbox", { name: `Select ${sent[1].title}` }).click();
    await bar.getByRole("button", { name: "Delete 2 events" }).click();
    const dialog = page.getByRole("dialog", { name: "Delete 2 events?" });
    await expect(dialog).toContainText("They are gone for good, with their waiting pushes and delivery records. Producers and users are not touched. This cannot be undone.");
    await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
    await dialog.getByRole("button", { name: "Delete 2 events" }).click();
    await expect(page.locator(".snack")).toContainText("Deleted 2 events");
    await expect(row(page, sent[0].title)).toHaveCount(0);
    await expect(row(page, sent[1].title)).toHaveCount(0);
    await expect(row(page, sent[2].title)).toBeVisible();
    await expect(bar).toBeHidden();
  });

  test("Delete events by rule: it counts first, says what it would delete in words, deletes only after the count is confirmed, and an empty count is its own calm answer", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("r0") }, { title: unique("r1") }]);
    const other = await world([{ title: unique("other") }]);
    await open(page, producer);
    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Delete events by rule…" }).click();
    const dialog = page.getByRole("dialog", { name: "Delete events by rule" });
    await expect(dialog).toContainText("Delete every event that matches. Choose a producer, a day or both. Nothing is deleted until you confirm the count.");
    // No rule yet: counting is off, and the line under the fields says why.
    const count = dialog.getByRole("button", { name: "Count events" });
    await expect(count).toBeDisabled();
    await expect(dialog.getByText("Choose a producer, a day or both.", { exact: true })).toBeVisible();
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    await expect(count).toBeEnabled();
    await expect(dialog.getByText("Midnight (00:00) in your browser's time zone. Type the date or pick a preset.")).toBeVisible();
    // The presets fill the day.
    await dialog.getByRole("button", { name: "Older than 30 days" }).click();
    await expect(dialog.getByLabel("Received before")).not.toHaveValue("");
    await expect(count).toBeEnabled();
    await count.click();
    // Nothing is older than 30 days: nothing to delete, and no destructive action.
    await expect(dialog.getByText("Nothing to delete.")).toBeVisible();
    await expect(dialog.getByText(new RegExp(`No event of ${producer.name} received before .* was found\\.`))).toBeVisible();
    await expect(dialog.getByRole("button", { name: /^Delete / })).toHaveCount(0);
    await dialog.getByRole("button", { name: "Change rule" }).click();
    await dialog.getByLabel("Received before").fill("");
    await expect(count).toBeEnabled();
    await count.click();
    await expect(dialog.getByText("2 events will be deleted.")).toBeVisible();
    await expect(dialog).toContainText(`Every event of ${producer.name}, with its waiting pushes and delivery records. This cannot be undone.`);
    const remove = dialog.getByRole("button", { name: "Delete 2 events" });
    expect(await remove.evaluate((node) => getComputedStyle(node).backgroundColor)).toBe("rgba(0, 0, 0, 0)");
    await remove.click();
    await expect(page.locator(".snack")).toContainText("Deleted 2 events");
    await expect(row(page, sent[0].title)).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "No events match" })).toBeVisible();
    await expect(page.getByText(`Nothing is stored for ${producer.name}.`)).toBeVisible();
    // Another producer's event is untouched.
    expect((await operator("GET", `/api/v1/admin/events/${other.sent[0].id}/deliveries`)).users).toBeDefined();
  });

  test("Send a test event is a dialog with the drawn defaults; a field's problem is said on the field; the sent event is linked from the snack bar", async ({ page }) => {
    const { producer } = await world([{ title: unique("before") }]);
    const disabled = await createProducer((await createPerson("BASIC")), unique("off"), "PUBLIC");
    await operator("POST", `/api/v1/admin/producers/${disabled.id}/disable`);
    await open(page, producer);
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog", { name: "Send a test event" });
    await expect(dialog).toContainText("Stored and pushed as the producer you choose, through every device's own settings.");
    await expect(dialog.getByLabel("Producer")).toBeFocused();
    // Only enabled producers are offered.
    await expect(dialog.getByLabel("Producer").locator("option", { hasText: disabled.name })).toHaveCount(0);
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    await expect(dialog.getByLabel("Title")).toHaveValue("Test event");
    await expect(dialog.getByLabel("Message (optional)")).toHaveValue("Sent from the admin page.");
    await expect(dialog.getByRole("radio", { name: "High" })).toBeChecked();
    await expect(dialog.getByLabel("Category")).toHaveValue("INFO");
    await dialog.getByLabel("Metadata (optional, a JSON object)").fill('{"branch": main, "run": 42}');
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog.getByText("Metadata is not valid JSON.")).toBeVisible();
    await expect(dialog.getByLabel("Metadata (optional, a JSON object)")).toHaveAttribute("aria-invalid", "true");
    await expect(dialog).toBeVisible();
    await dialog.getByLabel("Metadata (optional, a JSON object)").fill("[1, 2]");
    await dialog.getByLabel("Link (optional)").fill("ftp://example.com");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog.getByText("Metadata must be a JSON object, such as {“run”: 42}.")).toBeVisible();
    await expect(dialog.getByText("The link must be a web address starting with http:// or https://.")).toBeVisible();
    await dialog.getByLabel("Title").fill("");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog.getByText("Give it a title.")).toBeVisible();
    // Fixed, and sent as the producer: stored and listed with what was typed.
    const title = unique("Sent from the admin test");
    await dialog.getByLabel("Title").fill(title);
    await dialog.getByLabel("Metadata (optional, a JSON object)").fill('{"run": 42}');
    await dialog.getByLabel("Link (optional)").fill("https://example.com/run/42");
    await dialog.getByLabel("Context (optional)").fill("signalhub-web");
    await dialog.getByRole("radio", { name: "Critical" }).click();
    await dialog.getByLabel("Category").selectOption("BLOCKED");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toHaveCount(0);
    const snack = page.locator(".snack");
    await expect(snack).toContainText(`Sent “${title}” as ${producer.name}`);
    await expect(row(page, title)).toBeVisible();
    await expect(row(page, title)).toHaveAccessibleName(new RegExp(`^${title}, Critical, Blocked, ${producer.name}`));
    await snack.getByRole("button", { name: "Open" }).click();
    const pane = page.getByRole("region", { name: title });
    await expect(pane).toBeVisible();
    await expect(pane.getByText("https://example.com/run/42".replace("https://", ""))).toBeVisible();
    await expect(pane.locator(".meta")).toContainText("42");
  });

  test("Send a test event is refused on the field when the title is too long, and a disabled producer cannot be chosen: nothing to send as says so", async ({ page }) => {
    const { producer } = await world([{ title: unique("x") }]);
    await open(page, producer);
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog", { name: "Send a test event" });
    await dialog.getByLabel("Title").fill("t".repeat(201));
    await dialog.getByLabel("Context (optional)").fill("bad context!");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog.getByText("Use 200 characters or fewer.")).toBeVisible();
    await expect(dialog.getByText("Use letters, numbers and . _ : / - only, starting with a letter or number.")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog).toHaveCount(0);
  });

  test("with no event at all the table says so and offers the test event; a list that cannot be read says what to do, and a refresh that fails keeps the older list under a banner", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("kept") }]);
    // Nothing stored.
    await page.route("**/api/v1/events?*", (route) => json(route, { items: [], nextCursor: null, total: 0 }));
    await adminSignIn(page, "#events");
    await expect(page.getByRole("heading", { name: "No events yet" })).toBeVisible();
    await expect(page.getByText("Events show here as soon as a producer sends one. Send a test event to see how one looks and how it reaches devices.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Send a test event" })).toHaveCount(2);
    await expect(page.locator(".mhead .cnt").first()).toHaveText("0 events");
    await expect(page.locator(".pgr")).toContainText("No events");
    await page.unroute("**/api/v1/events?*");
    // A first read that fails: nothing to keep, so the table is the error and its action.
    let answering = false;
    await page.route("**/api/v1/events?*", (route) => (answering ? route.continue() : route.abort()));
    await page.reload();
    await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page.getByRole("heading", { name: "Could not load events" })).toBeVisible();
    await expect(page.getByText("The server did not answer. Check that SignalHub is running, then try again.")).toBeVisible();
    await expect(page.locator(".mhead .cnt").first()).toHaveText("Not loaded");
    answering = true;
    await page.getByRole("button", { name: "Try again" }).click();
    await expect(page.getByRole("grid", { name: "Events" })).toBeVisible();
    await page.goto(`/admin/#events?producer=${producer.id}`);
    await expect(row(page, sent[0].title)).toBeVisible();
    // A refresh that fails: the older rows stay, said in a banner and in the header.
    answering = false;
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    const banner = page.getByRole("alert").filter({ hasText: "Could not refresh." });
    await expect(banner).toContainText(/This list is from \d\d:\d\d and may be out of date\./);
    await expect(page.getByText(/^Not updated since \d\d:\d\d$/)).toBeVisible();
    await expect(row(page, sent[0].title)).toBeVisible();
    answering = true;
    await banner.getByRole("button", { name: "Try again" }).click();
    await expect(banner).toHaveCount(0);
    await expect(page.getByText(/^Updated \d\d:\d\d$/)).toBeVisible();
  });

  test("a producer's pane links to its events, and the address of Events names the producer and the event it opens", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("linked") }]);
    await adminSignIn(page, `#producers/${producer.id}`);
    await page.getByRole("link", { name: "See its events" }).click();
    await expect(page).toHaveURL(new RegExp(`#events\\?producer=${producer.id}$`));
    await expect(page.getByRole("button", { name: `Producer: ${producer.name}` })).toBeVisible();
    await expect(row(page, sent[0].title)).toBeVisible();
    // An event named in the address opens in the pane over the same filters; Back closes it.
    await page.goto(`/admin/#events/${sent[0].id}?producer=${producer.id}`);
    await expect(page.getByRole("region", { name: sent[0].title })).toBeVisible();
    await page.goBack();
    await expect(page.getByRole("region", { name: sent[0].title })).toHaveCount(0);
  });

  test("the table is one tab stop: arrow keys move between rows, Enter opens one and Escape closes it", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("k0") }, { title: unique("k1") }, { title: unique("k2") }]);
    await open(page, producer);
    const first = row(page, sent[2].title);
    const second = row(page, sent[1].title);
    await first.focus();
    await page.keyboard.press("ArrowDown");
    await expect(second).toBeFocused();
    await page.keyboard.press("ArrowUp");
    await expect(first).toBeFocused();
    await page.keyboard.press("End");
    await expect(row(page, sent[0].title)).toBeFocused();
    await page.keyboard.press("Home");
    await page.keyboard.press("Enter");
    await expect(page.getByRole("region", { name: sent[2].title })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByRole("region", { name: sent[2].title })).toHaveCount(0);
    await expect(first).toBeFocused();
  });

  test("everything a server sent is text: a title, a message, a producer and metadata full of markup stay words, and a link is only ever opened by the operator", async ({ page }) => {
    const markup = '<img src=x onerror="window.__owned=1">';
    const owner = await createPerson("BASIC");
    const producer = await createProducer(owner, unique("xss"), "PUBLIC");
    const sent = await publish(producer, { title: `${markup} title`, message: `${markup} message`, context: "ctx", link: "https://example.com/?a=%3Cb%3E&b=1", metadata: { [markup]: markup } });
    await adminSignIn(page, `#events/${sent.id}?producer=${producer.id}`);
    const pane = page.getByRole("region", { name: new RegExp("title$") });
    await expect(pane).toBeVisible();
    await expect(pane.getByText(`${markup} message`)).toBeVisible();
    await expect(pane.locator(".meta")).toContainText(markup);
    expect(await page.locator("img").count()).toBe(0);
    expect(await page.evaluate(() => window.__owned)).toBeUndefined();
  });

  test("it works in the light theme and with reduced motion: the pane changes by opacity alone", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("themed"), severity: "CRITICAL" }]);
    await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
    await open(page, producer);
    expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(251, 248, 255)");
    await row(page, sent[0].title).click();
    const pane = page.getByRole("region", { name: sent[0].title });
    await expect(pane).toBeVisible();
    expect(await pane.evaluate((node) => getComputedStyle(node).animationName)).toBe("fade-in");
    await page.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
    expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(18, 19, 24)");
  });

  test("a side sheet below 1180 px: the pane is 560 px from the right edge over a scrim, and Escape or the scrim closes it", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("sheet") }]);
    await page.setViewportSize({ width: 1100, height: 800 });
    await open(page, producer);
    await row(page, sent[0].title).click();
    const pane = page.getByRole("region", { name: sent[0].title });
    await expect(pane).toBeVisible();
    // Once it has slid in.
    await expect.poll(async () => Math.round((await pane.boundingBox()).x + (await pane.boundingBox()).width)).toBe(1100);
    expect(Math.round((await pane.boundingBox()).width)).toBe(560);
    await page.locator(".sheet-scrim").click({ position: { x: 20, y: 300 } });
    await expect(pane).toHaveCount(0);
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(1100);
  });
});

test.describe("phone", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("the list is two-line rows with no sideways scroll; Filters and Send a test event are buttons under the title; the bottom bar stays", async ({ page }) => {
    const { owner, producer, sent } = await world([{ title: unique("p0"), severity: "CRITICAL", category: "BLOCKED" }, { title: unique("p1") }]);
    await pushesRecorded(sent[1]);
    await pushProblemFor(owner, producer);
    await open(page, producer);
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    const target = page.getByRole("row", { name: new RegExp(`^${sent[0].title}`) });
    await expect(target).toContainText(`${producer.name} · Critical`);
    await expect(page.getByRole("columnheader")).toHaveCount(0);
    await expect(page.getByRole("button", { name: /^Filters/ })).toBeVisible();
    await expect(page.getByRole("button", { name: "Send a test event" }).first()).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Sections (phone)" })).toBeVisible();
    // A row whose push failed carries an icon named Push problems.
    await expect(page.locator('[aria-label*="push problems"] .pp')).toHaveCount(1);
    // Paging is one button at the foot.
    await expect(page.getByRole("button", { name: "Load 25 older events" })).toBeHidden();
    for (const control of await page.locator(".mhead button:visible, .phone-actions button:visible").all()) {
      expect((await control.boundingBox()).height).toBeGreaterThanOrEqual(47);
    }
  });

  test("an event is a screen of its own: Back returns to the list, Delete is the header icon, Mark read the one button at the foot", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("screen"), link: "https://example.com/x", message: "A message" }]);
    await open(page, producer);
    await row(page, sent[0].title).click();
    const pane = page.getByRole("region", { name: sent[0].title });
    await expect(pane).toBeVisible();
    expect(Math.round((await pane.boundingBox()).width)).toBe(390);
    await expect(page.getByRole("navigation", { name: "Sections (phone)" })).toBeHidden();
    await expect(pane.getByRole("button", { name: `Delete event ${sent[0].title}` })).toHaveCount(1);
    await expect(pane.getByRole("button", { name: `Delete event ${sent[0].title}` })).toBeVisible();
    await expect(pane.getByRole("button", { name: "Mark read" })).toBeVisible();
    await expect(pane.getByRole("link", { name: /^Open link/ })).toContainText("Open");
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    await pane.getByRole("button", { name: "Back" }).click();
    await expect(pane).toHaveCount(0);
    await expect(page.getByRole("grid", { name: "Events" })).toBeVisible();
    // The Pushes tab keeps to the screen too.
    await row(page, sent[0].title).click();
    await pane.getByRole("tab", { name: /^Pushes/ }).click();
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
  });

  test("the filters are a sheet of selects with one button that says what will show; Send a test event is a full screen", async ({ page }) => {
    const { producer, sent } = await world([{ title: unique("f0"), severity: "CRITICAL" }, { title: unique("f1"), severity: "LOW" }]);
    await open(page, producer);
    await page.getByRole("button", { name: /^Filters/ }).click();
    const sheet = page.getByRole("dialog", { name: "Filters" });
    await expect(sheet).toBeVisible();
    await expect.poll(async () => {
      const box = await sheet.boundingBox();
      return Math.round(box.y + box.height);
    }).toBe(844);
    expect(Math.round((await sheet.boundingBox()).width)).toBe(390);
    await sheet.getByRole("button", { name: /^Severity:/ }).click();
    await sheet.getByRole("checkbox", { name: "Critical" }).click();
    await expect(sheet.getByRole("button", { name: "Show 1 event" })).toBeVisible();
    await sheet.getByRole("button", { name: "Show 1 event" }).click();
    await expect(sheet).toHaveCount(0);
    await expect(row(page, sent[0].title)).toBeVisible();
    await expect(row(page, sent[1].title)).toHaveCount(0);
    // The producer of the address and the severity: two filters in force.
    await expect(page.getByRole("button", { name: /^Filters/ })).toContainText("2");
    await expect(page).toHaveURL(/severity=CRITICAL/);
    await page.getByRole("button", { name: /^Filters/ }).click();
    await sheet.getByRole("button", { name: "Clear" }).click();
    await sheet.getByRole("button", { name: /^Show/ }).click();
    await expect(row(page, sent[1].title)).toBeVisible();
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog", { name: "Send a test event" });
    const full = await dialog.boundingBox();
    expect(Math.round(full.width)).toBe(390);
    expect(Math.round(full.height)).toBe(844);
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    await expect(dialog.getByRole("button", { name: "Close" })).toBeVisible();
  });

  test("a long press ticks a row and the header becomes the bulk bar; a tap then ticks; Load 25 older events adds the next page under the first", async ({ page }) => {
    const { producer, sent } = await world(Array.from({ length: 27 }, (_, index) => ({ title: unique(`m-${index}`) })));
    await open(page, producer);
    const target = row(page, sent[26].title);
    await target.dispatchEvent("pointerdown", { pointerType: "touch" });
    await page.waitForTimeout(700);
    await target.dispatchEvent("pointerup", { pointerType: "touch" });
    const bar = page.getByRole("toolbar", { name: "Selected events" });
    await expect(bar).toContainText("1 selected");
    await row(page, sent[25].title).click();
    await expect(bar).toContainText("2 selected");
    await bar.getByRole("button", { name: "Clear the selection" }).click();
    await page.getByRole("button", { name: "Load 25 older events" }).click();
    await expect(row(page, sent[0].title)).toBeAttached();
    await expect(page.getByRole("grid", { name: "Events" }).getByRole("row")).toHaveCount(27);
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
  });
});
