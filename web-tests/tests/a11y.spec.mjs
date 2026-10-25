import { browserSession, createPerson, createProducer, publish, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

// The accessible name of a control as a screen reader gets it: aria-label, else the text that is
// not hidden from it (the icon glyphs are).
const NAMES = () => {
  const textOf = (node) => {
    let text = "";
    for (const child of node.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
      else if (child.nodeType === Node.ELEMENT_NODE && child.getAttribute("aria-hidden") !== "true") text += textOf(child);
    }
    return text;
  };
  return [...document.querySelectorAll("button, a[href], [role=switch], [role=radio], [role=menuitem]")]
    .filter((node) => node.getClientRects().length)
    .map((node) => ({ tag: node.tagName.toLowerCase(), name: (node.getAttribute("aria-label") ?? textOf(node)).replace(/\s+/g, " ").trim(), html: node.className }));
};

async function admin(context, page) {
  const person = await createPerson("ADMIN");
  const producer = await createProducer(person, unique("a11y"), "PUBLIC");
  await publish(producer, { title: "An event", category: "INFO", severity: "NORMAL" });
  await useSession(context, await browserSession(person));
  await page.goto("/app/#inbox");
  return { person, producer };
}

test("every control on every screen has an accessible name, and the icon-only ones have the design's", async ({ context, page }) => {
  const { person, producer } = await admin(context, page);
  await expect(page.locator("a.event-row")).toHaveCount(1);
  const screens = ["#inbox", "#producers", `#producers/${producer.id}`, "#producers/new", "#people", "#settings", "#settings/devices"];
  for (const hash of screens) {
    await page.goto(`/app/${hash}`);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(300);
    const controls = await page.evaluate(NAMES);
    expect(controls.length, hash).toBeGreaterThan(3);
    for (const control of controls) expect(control.name, `${hash}: ${control.tag}.${control.html}`).not.toBe("");
  }
  await page.goto("/app/#inbox");
  await expect(page.getByRole("button", { name: "Filter events" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Mark all as read" })).toBeVisible();
  await expect(page.getByRole("button", { name: `Account menu, ${person.name}` })).toBeVisible();
  await expect(page.getByRole("link", { name: "Inbox, 1 unread" })).toBeVisible();
  await page.goto(`/app/#producers/${producer.id}`);
  await expect(page.getByRole("button", { name: `Rename ${producer.name}` })).toBeVisible();
  await expect(page.getByRole("button", { name: /^Revoke key shpk1_.+…$/ })).toBeVisible();
  await page.goto("/app/#producers");
  await expect(page.getByRole("button", { name: `Subscribed to ${producer.name}. Double tap to unsubscribe.` })).toBeVisible();
  await page.goto("/app/#people");
  await expect(page.getByRole("button", { name: "Search people" })).toBeVisible();
  await page.goto("/app/#settings/devices");
  await expect(page.getByRole("button", { name: "Back" })).toBeVisible();
});

test("the segmented button and the switch speak their state; the unavailable Admin segment says why", async ({ context, page }) => {
  const { producer } = await admin(context, page);
  await page.goto(`/app/#producers/${producer.id}`);
  await expect(page.getByRole("radio", { name: "Public" })).toBeChecked();
  await expect(page.getByRole("radio", { name: "Private" })).not.toBeChecked();
  await expect(page.getByRole("switch", { name: "Subscribed" })).toBeChecked();
  const target = await createPerson("BASIC");
  await page.goto("/app/#people");
  await page.getByRole("link", { name: new RegExp(target.name) }).click();
  const adminSegment = page.getByRole("radio", { name: "Admin, not available. Set on the admin page" });
  await expect(adminSegment).toHaveAttribute("aria-disabled", "true");
});

test("keyboard focus has a visible ring, and follows reading order: the rail, the header, then the content", async ({ context, page }) => {
  await admin(context, page);
  await expect(page.locator("a.event-row")).toHaveCount(1);
  const order = [];
  // The rail's four, the account, Filter, Mark all as read, the Unread chip, then the first row.
  for (let i = 0; i < 9; i += 1) {
    await page.keyboard.press("Tab");
    order.push(
      await page.evaluate(() => {
        const textOf = (node) =>
          [...node.childNodes].map((child) => (child.nodeType === Node.TEXT_NODE ? child.textContent : child.nodeType === Node.ELEMENT_NODE && child.getAttribute("aria-hidden") !== "true" ? textOf(child) : "")).join("");
        const node = document.activeElement;
        return (node.getAttribute("aria-label") || textOf(node)).replace(/\s+/g, " ").trim().slice(0, 40);
      }),
    );
  }
  expect(order.slice(0, 4)).toEqual(["Inbox, 1 unread", "Producers", "People", "Settings"]);
  expect(order.findIndex((name) => name.startsWith("Account menu"))).toBeLessThan(order.indexOf("Filter events"));
  expect(order.indexOf("Filter events")).toBeLessThan(order.findIndex((name) => name.startsWith("An event")));
  const ring = await page.evaluate(() => {
    const style = getComputedStyle(document.activeElement);
    return { width: style.outlineWidth, offset: style.outlineOffset, style: style.outlineStyle, color: style.outlineColor, primary: getComputedStyle(document.documentElement).getPropertyValue("--primary").trim() };
  });
  expect(ring.style).toBe("solid");
  expect(ring.width).toBe("2px");
  expect(ring.offset).toBe("2px");
  expect(ring.color).not.toBe("rgba(0, 0, 0, 0)");
});

test("on the sign-in page, Use a code instead comes before the QR code in the focus order", async ({ page }) => {
  await page.goto("/app/");
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("button", { name: "Use a code instead" })).toBeFocused();
  await expect(page.getByRole("img", { name: "Sign-in QR code. To sign in without scanning, use a code instead." })).toBeVisible();
});

test("a dialog starts on Cancel, keeps focus inside, closes on Escape and returns focus to its opener", async ({ context, page }) => {
  await admin(context, page);
  await page.goto("/app/#settings");
  const opener = page.getByRole("button", { name: "Sign out" });
  await opener.focus();
  await opener.press("Enter");
  const dialog = page.getByRole("dialog", { name: "Sign out of this browser?" });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
  for (let i = 0; i < 6; i += 1) {
    await page.keyboard.press("Tab");
    expect(await page.evaluate(() => Boolean(document.activeElement.closest("[role=dialog]")))).toBe(true);
  }
  await page.keyboard.press("Shift+Tab");
  expect(await page.evaluate(() => Boolean(document.activeElement.closest("[role=dialog]")))).toBe(true);
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  await expect(opener).toBeFocused();
});

test("the account menu closes on Escape and returns focus to its button; a menu is reachable by arrow keys", async ({ context, page }) => {
  const { person } = await admin(context, page);
  const button = page.getByRole("button", { name: `Account menu, ${person.name}` });
  await button.focus();
  await button.press("Enter");
  const menu = page.getByRole("menu");
  await expect(menu).toBeVisible();
  await expect(menu).toContainText("Admin · signed in on");
  await expect(page.getByRole("menuitem", { name: "Devices" })).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(page.getByRole("menuitem", { name: "Sign out" })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(menu).toHaveCount(0);
  await expect(button).toBeFocused();
});

test("the key dialog cannot be closed by Escape or by a click outside, and starts on Copy", async ({ context, page }) => {
  await admin(context, page);
  await page.goto("/app/#producers/new");
  await page.getByLabel("Name").fill(unique("key"));
  await page.getByRole("button", { name: "Create" }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog.getByText("Shown once. You won't see this key again.")).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Copy", exact: true })).toBeFocused();
  await page.keyboard.press("Escape");
  await page.mouse.click(5, 5);
  await expect(dialog).toBeVisible();
  await expect(dialog.locator(".keybox")).toContainText("shpk1_");
  await dialog.getByRole("button", { name: "Copy and close" }).click();
  await expect(dialog).toHaveCount(0);
});

test("the light theme follows the browser and renders every token", async ({ browser }) => {
  const context = await browser.newContext({ colorScheme: "light" });
  const page = await context.newPage();
  await page.goto("/app/");
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  const colors = await page.evaluate(() => ({ body: getComputedStyle(document.body).backgroundColor, text: getComputedStyle(document.body).color, card: getComputedStyle(document.querySelector(".card")).backgroundColor }));
  expect(colors.body).toBe("rgb(251, 248, 255)");
  expect(colors.text).toBe("rgb(27, 27, 33)");
  expect(colors.card).toBe("rgb(245, 242, 250)");
  await context.close();
  const dark = await browser.newContext({ colorScheme: "dark" });
  const darkPage = await dark.newPage();
  await darkPage.goto("/app/");
  expect(await darkPage.evaluate(() => getComputedStyle(document.body).backgroundColor)).toBe("rgb(18, 19, 24)");
  await dark.close();
});

test("reduced motion: dialogs fade only, with no scale", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  const person = await createPerson("BASIC");
  await useSession(context, await browserSession(person));
  await page.goto("/app/#settings");
  await page.getByRole("button", { name: "Sign out" }).click();
  const name = await page.locator(".dlg").evaluate((node) => getComputedStyle(node).animationName);
  expect(name).toBe("fade");
  await context.close();
});
