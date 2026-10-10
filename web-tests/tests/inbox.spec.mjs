import { browserSession, createPerson, createProducer, publish, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

// A person with a producer of their own that has published a few events, and a page signed in.
async function inbox(context, page, role = "BASIC") {
  const person = await createPerson(role);
  const producer = await createProducer(person, unique("ci"), "PUBLIC");
  const events = {};
  events.old = await publish(producer, { title: "Deploy to staging done", category: "COMPLETED", severity: "LOW" });
  events.backup = await publish(producer, { title: "Nightly backup finished", category: "INFO", severity: "NORMAL" });
  events.disk = await publish(producer, { title: "Disk almost full on nas-01", category: "BLOCKED", severity: "CRITICAL", metadata: { host: "nas-01", free: "2%" } });
  events.approve = await publish(producer, {
    title: "Your action: approve the release",
    category: "ACTION_REQUIRED",
    severity: "HIGH",
    context: "release-3.0.0",
    message: "The release is waiting at the approval gate.",
    link: "https://example.org/release",
  });
  await useSession(context, await browserSession(person));
  await page.goto("/app/#inbox");
  return { person, producer, events };
}

test("the inbox lists events newest first with their category, severity and producer, and the unread count", async ({ context, page }) => {
  const { producer } = await inbox(context, page);
  const rows = page.locator("a.event-row");
  await expect(rows).toHaveCount(4);
  await expect(rows.first()).toContainText("Your action: approve the release");
  await expect(rows.first()).toContainText(`Action required · High · ${producer.name}`);
  await expect(rows.nth(1)).toContainText("Blocked · Critical");
  await expect(page.getByRole("link", { name: "Inbox, 4 unread" })).toBeVisible();
  await expect(rows.first().getByRole("img", { name: "Unread" })).toBeVisible();
});

test("opening an event shows it beside the list, reads it, and Mark as unread undoes that", async ({ context, page }) => {
  const { events } = await inbox(context, page);
  await page.getByRole("link", { name: /Disk almost full/ }).click();
  await expect(page).toHaveURL(new RegExp(`#inbox/${events.disk.id}$`));
  await expect(page.getByRole("heading", { name: "Disk almost full on nas-01", level: 2 })).toBeVisible();
  await expect(page.locator(".chip", { hasText: "Blocked" })).toBeVisible();
  await expect(page.locator(".chip", { hasText: "Critical" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Inbox, 3 unread" })).toBeVisible();
  // Opaque producer data is shown as the producer sent it, never interpreted.
  await expect(page.locator("pre.metadata")).toContainText('"host": "nas-01"');

  await page.getByRole("button", { name: "Mark as unread" }).click();
  await expect(page.getByRole("button", { name: "Mark as read" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Inbox, 4 unread" })).toBeVisible();
  await page.getByRole("button", { name: "Mark as read" }).click();
  await expect(page.getByRole("link", { name: "Inbox, 3 unread" })).toBeVisible();

  // The address keeps the open event: a reload returns to it.
  await page.reload();
  await expect(page.getByRole("heading", { name: "Disk almost full on nas-01", level: 2 })).toBeVisible();
});

test("Open link opens a web address in a new tab without handing over the opener", async ({ context, page }) => {
  await inbox(context, page);
  await page.getByRole("link", { name: /approve the release/ }).click();
  const open = page.getByRole("link", { name: "Open link" });
  await expect(open).toHaveAttribute("href", "https://example.org/release");
  await expect(open).toHaveAttribute("target", "_blank");
  await expect(open).toHaveAttribute("rel", "noopener noreferrer");
});

test("filters: unread only, a category and a severity, shown as chips that can be removed", async ({ context, page }) => {
  const { events } = await inbox(context, page);
  await page.getByRole("link", { name: /Disk almost full/ }).click();
  await expect(page.getByRole("link", { name: "Inbox, 3 unread" })).toBeVisible();

  await page.getByRole("button", { name: "Filter events" }).click();
  const dialog = page.getByRole("dialog", { name: "Show in the inbox" });
  await dialog.getByRole("switch", { name: "Unread only" }).click();
  await dialog.getByRole("button", { name: "Info", exact: true }).click();
  await dialog.getByRole("button", { name: "Done" }).click();

  await expect(page.locator("a.event-row")).toHaveCount(1);
  await expect(page.locator("a.event-row").first()).toContainText("Nightly backup finished");
  await expect(page).toHaveURL(/unread=1/);
  await expect(page).toHaveURL(/category=INFO/);
  await expect(page.getByRole("button", { name: "Remove filter Unread" })).toBeVisible();
  await page.getByRole("button", { name: "Remove filter Info" }).click();
  // Unread only, and the event opened above (now read) is not in it.
  await expect(page.locator("a.event-row")).toHaveCount(3);
  await expect(page.locator("a.event-row", { hasText: "Disk almost full" })).toHaveCount(0);
  await page.getByRole("button", { name: "Clear", exact: true }).click();
  await expect(page.locator("a.event-row")).toHaveCount(4);
  void events;
});

test("filtering by a producer from its page: See its events", async ({ context, page }) => {
  const { producer } = await inbox(context, page);
  await page.getByRole("link", { name: "Producers" }).click();
  await page.getByRole("link", { name: new RegExp(producer.name) }).click();
  await page.getByRole("button", { name: "See its events" }).click();
  await expect(page).toHaveURL(new RegExp(`#inbox\\?producer=${producer.id}`));
  await expect(page.getByRole("button", { name: `Remove filter ${producer.name}` })).toBeVisible();
  await expect(page.locator("a.event-row")).toHaveCount(4);
});

test("Mark all as read reads every event", async ({ context, page }) => {
  await inbox(context, page);
  await expect(page.getByRole("link", { name: "Inbox, 4 unread" })).toBeVisible();
  await page.getByRole("button", { name: "Mark all as read" }).click();
  await expect(page.getByRole("link", { name: "Inbox", exact: true })).toBeVisible();
  await expect(page.getByRole("img", { name: "Unread" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Mark all as read" })).toBeDisabled();
});

test("an event that is not there says so, beside the list", async ({ context, page }) => {
  await inbox(context, page);
  await page.goto("/app/#inbox/01997d65-c2d1-7a30-8a11-000000000000");
  await expect(page.getByRole("heading", { name: "This isn't here" })).toBeVisible();
  await expect(page.getByText("It may have been deleted, or it isn't one of yours.")).toBeVisible();
  await expect(page.locator("a.event-row")).toHaveCount(4);
  await page.getByRole("button", { name: "Back to the inbox" }).click();
  await expect(page.getByRole("heading", { name: "Select an event" })).toBeVisible();
});

test("at phone width an open event takes the screen, and the bottom bar replaces the rail", async ({ context, page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await inbox(context, page);
  const bar = page.getByRole("navigation", { name: "Main" });
  const box = await bar.boundingBox();
  expect(box.y).toBeGreaterThan(600);
  await page.getByRole("link", { name: /Disk almost full/ }).click();
  await expect(page.getByRole("heading", { name: "Event" })).toBeVisible();
  await expect(page.locator("a.event-row").first()).toBeHidden();
  await page.getByRole("button", { name: "Back" }).click();
  await expect(page.locator("a.event-row")).toHaveCount(4);
  // Marking unread goes back to the list, as in the app.
  await page.getByRole("link", { name: /Nightly backup/ }).click();
  await page.getByRole("button", { name: "Mark as unread" }).click();
  await expect(page.locator("a.event-row")).toHaveCount(4);
});

test("an empty inbox points to the producers", async ({ context, page }) => {
  const person = await createPerson("BASIC");
  await useSession(context, await browserSession(person));
  await page.goto("/app/#inbox");
  await expect(page.getByRole("heading", { name: "Nothing here yet" })).toBeVisible();
  await page.getByRole("button", { name: "Find producers" }).click();
  await expect(page).toHaveURL(/#producers$/);
});
