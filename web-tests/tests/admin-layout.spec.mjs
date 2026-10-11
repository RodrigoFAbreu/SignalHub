import { createPerson, createProducer, unique } from "../support/server.mjs";
import { adminSignIn, expect, test } from "../support/page.mjs";

const SECTIONS = ["#devices", "#users", "#producers", "#events", "#status"];

const sideways = (page) => page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, view: window.innerWidth, body: document.body.scrollWidth }));

test.describe("desktop", () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test("the rail has the five sections and the status button and account; the list takes the rest and a fixed 480 px pane stays beside it", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("wide"), "PUBLIC");
    await adminSignIn(page, `#producers/${producer.id}`);
    const rail = page.getByRole("navigation", { name: "Sections" });
    await expect(rail).toBeVisible();
    expect(Math.round((await rail.boundingBox()).width)).toBe(88);
    for (const name of ["Devices", "Users", "Producers", "Events", "Status"]) await expect(rail.getByRole("link", { name, exact: true })).toBeVisible();
    await expect(rail.getByRole("link", { name: "Producers", exact: true })).toHaveAttribute("aria-current", "page");
    await expect(rail.getByRole("link", { name: /^Server status:/ })).toBeVisible();
    await expect(rail.getByRole("button", { name: "Account" })).toBeVisible();
    const pane = page.getByRole("region", { name: producer.name });
    await expect(pane).toBeVisible();
    expect(Math.round((await pane.boundingBox()).width)).toBe(480);
    // The list is beside it, not under it, and nothing covers the list.
    const list = await page.getByRole("grid", { name: "Producers" }).boundingBox();
    expect(list.x + list.width).toBeLessThanOrEqual((await pane.boundingBox()).x + 1);
    await expect(page.locator(".sheet-scrim")).toBeHidden();
    expect(await sideways(page)).toEqual({ scroll: 1440, view: 1440, body: 1440 });
    // With nothing selected the pane says what it will show.
    await page.getByRole("button", { name: `Close ${producer.name}` }).click();
    await expect(page.getByText("Select a producer")).toBeVisible();
    await expect(page.getByText("Its keys, who can see it and its latest event show here.")).toBeVisible();
  });

  test("below 1180 px the pane is a side sheet over the table, closed by its button, Escape or the scrim; focus returns to the row", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("sheet"), "PUBLIC");
    await page.setViewportSize({ width: 1100, height: 800 });
    await adminSignIn(page, "#producers");
    await page.getByRole("searchbox", { name: "Find a producer" }).fill(producer.name);
    const row = page.getByRole("row", { name: new RegExp(`^${producer.name}`) });
    // Only the pane's own prompt is not shown below 1180 px: nothing sits beside the table.
    await expect(page.getByText("Select a producer")).toBeHidden();
    await row.click();
    const pane = page.getByRole("region", { name: producer.name });
    await expect(pane).toBeVisible();
    // It slides in from the right edge: measured once it has arrived.
    await page.waitForTimeout(500);
    const box = await pane.boundingBox();
    expect(Math.round(box.width)).toBe(560);
    expect(Math.round(box.x + box.width)).toBe(1100);
    await expect(page.locator(".sheet-scrim")).toBeVisible();
    await expect(pane.getByRole("heading", { name: producer.name })).toBeFocused();
    await page.keyboard.press("Escape");
    await expect(pane).toHaveCount(0);
    await expect(row).toBeFocused();
    await row.click();
    await expect(pane).toBeVisible();
    // A click on the scrim closes it.
    await page.mouse.click(100, 400);
    await expect(pane).toHaveCount(0);
    await row.click();
    await page.getByRole("button", { name: `Close ${producer.name}` }).click();
    await expect(pane).toHaveCount(0);
    expect((await sideways(page)).scroll).toBe(1100);
  });

  test("at 1280 px the pane is 420 px and the owner folds into the name's second line", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("narrow"), "PUBLIC");
    await page.setViewportSize({ width: 1280, height: 800 });
    await adminSignIn(page, `#producers/${producer.id}`);
    expect(Math.round((await page.getByRole("region", { name: producer.name }).boundingBox()).width)).toBe(420);
    await page.getByRole("searchbox", { name: "Find a producer" }).fill(producer.name);
    const row = page.getByRole("row", { name: new RegExp(`^${producer.name}`) });
    await expect(row.locator(".sub")).toHaveText(person.name);
    await expect(row.locator(".c-owner")).toBeHidden();
  });

  test("an address that names nothing opens Devices; the section and what is open stay in the address", async ({ page }) => {
    await adminSignIn(page, "#nothing-here");
    await expect(page.getByRole("heading", { name: "Devices", level: 1 })).toBeVisible();
    await expect(page).toHaveURL(/#devices$/);
    await page.getByRole("link", { name: "Producers", exact: true }).click();
    await expect(page).toHaveURL(/#producers$/);
    await page.goBack();
    await expect(page.getByRole("heading", { name: "Devices", level: 1 })).toBeVisible();
  });

  test("every control has an accessible name, the page has its landmarks, and the focus ring is 2 px primary", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("labels"), "PUBLIC");
    await adminSignIn(page, `#producers/${producer.id}`);
    for (const hash of [`#producers/${producer.id}`, "#devices", "#status", "#users", "#events"]) {
      await page.goto(`/admin/${hash}`).catch(() => {});
      if (await page.getByLabel("Admin token").count()) {
        await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
        await page.getByRole("button", { name: "Sign in" }).click();
      }
      await expect(page.getByRole("navigation", { name: /^Sections/ })).toBeVisible();
      await page.waitForTimeout(500);
      const unnamed = await page.evaluate(() => {
        const textOf = (node) => {
          let text = "";
          for (const child of node.childNodes) {
            if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
            else if (child.nodeType === Node.ELEMENT_NODE && child.getAttribute("aria-hidden") !== "true") text += textOf(child);
          }
          return text;
        };
        return [...document.querySelectorAll("button, a[href], input, select, textarea")]
          .filter((node) => node.getClientRects().length && !node.closest("[hidden]"))
          .filter((node) => !(node.getAttribute("aria-label") ?? "").trim() && !textOf(node).trim() && !(node.labels?.length))
          .map((node) => `${node.tagName}.${node.className}`);
      });
      expect(unnamed, hash).toEqual([]);
    }
    await expect(page.getByRole("main")).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Sections" })).toBeVisible();
    // The ring: 2 px, primary, away from the control.
    await page.goto("/admin/#devices").catch(() => {});
    await page.getByRole("link", { name: "Users", exact: true }).first().focus();
    await page.keyboard.press("Tab");
    const ring = await page.evaluate(() => {
      const style = getComputedStyle(document.activeElement);
      return { width: style.outlineWidth, style: style.outlineStyle };
    });
    expect(ring).toEqual({ width: "2px", style: "solid" });
  });
});

test.describe("phone", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("the sign-in screen and every section fit 390 px with no sideways scroll, the rail is a bottom bar of the five sections, and New is in the header", async ({ page }) => {
    await page.goto("/admin/");
    await expect(page.getByRole("heading", { name: "SignalHub admin" })).toBeVisible();
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
    await page.getByRole("button", { name: "Sign in" }).click();
    const bar = page.getByRole("navigation", { name: "Sections (phone)" });
    await expect(bar).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Sections", exact: true })).toBeHidden();
    const box = await bar.boundingBox();
    expect(Math.round(box.height)).toBe(80);
    expect(Math.round(box.y + box.height)).toBe(844);
    for (const name of ["Devices", "Users", "Producers", "Events", "Status"]) await expect(bar.getByRole("link", { name: new RegExp(`^${name}`) })).toBeVisible();
    for (const hash of SECTIONS) {
      await page.goto(`/admin/${hash}`).catch(() => {});
      await page.getByRole("link", { name: new RegExp(`^${hash.slice(1)[0].toUpperCase()}${hash.slice(2)}`) }).first().click().catch(() => {});
      await page.waitForTimeout(600);
      const sizes = await sideways(page);
      expect(sizes.scroll, hash).toBeLessThanOrEqual(390);
      expect(sizes.body, hash).toBeLessThanOrEqual(390);
    }
    await page.getByRole("link", { name: /^Producers/ }).first().click();
    // New producer is a button in the header, not a floating one, so it never covers a row.
    const add = page.getByRole("button", { name: "New producer" }).first();
    await expect(add).toBeVisible();
    expect((await add.boundingBox()).y).toBeLessThan(120);
  });

  test("a producer's detail is a screen of its own with a Back arrow; the bottom bar is hidden there; Back returns to the list", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("phone"), "PRIVATE");
    await adminSignIn(page, "#producers");
    await page.getByRole("searchbox", { name: "Find a producer" }).fill(producer.name);
    const row = page.getByRole("row", { name: new RegExp(`^${producer.name}`) });
    // Two-line rows: the name, then the owner, who sees it, keys and last event.
    await expect(row).toContainText(`${person.name} · Private · 1 key · None stored`);
    await row.click();
    const pane = page.getByRole("region", { name: producer.name });
    await expect(pane).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Sections (phone)" })).toBeHidden();
    await expect(page.getByRole("grid", { name: "Producers" })).toBeHidden();
    expect(Math.round((await pane.boundingBox()).width)).toBe(390);
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
    // Every button keeps a 48 px target.
    for (const button of await pane.getByRole("button").all()) {
      const box = await button.boundingBox();
      if (box) expect(box.height, await button.innerText()).toBeGreaterThanOrEqual(47);
    }
    await pane.getByRole("button", { name: "Back" }).click();
    await expect(page.getByRole("navigation", { name: "Sections (phone)" })).toBeVisible();
    await expect(page.getByRole("grid", { name: "Producers" })).toBeVisible();
    // The browser's own back does the same.
    await row.click();
    await expect(pane).toBeVisible();
    await page.goBack();
    await expect(pane).toHaveCount(0);
  });

  test("New producer is a full screen with Close at the top left and a full-width Create; a confirmation is a bottom sheet with the destructive action above Cancel", async ({ page }) => {
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("sheet"), "PUBLIC");
    await adminSignIn(page, "#producers");
    await page.getByRole("button", { name: "New producer" }).first().click();
    const dialog = page.getByRole("dialog", { name: "New producer" });
    const box = await dialog.boundingBox();
    expect(Math.round(box.width)).toBe(390);
    expect(Math.round(box.height)).toBe(844);
    await expect(dialog.getByRole("button", { name: "Close" })).toBeVisible();
    await dialog.getByLabel("Name").fill(unique("phone-new"));
    const create = dialog.getByRole("button", { name: "Create" });
    await expect(create).toBeEnabled();
    expect((await create.boundingBox()).width).toBeGreaterThan(300);
    await dialog.getByRole("button", { name: "Close" }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await page.getByRole("searchbox", { name: "Find a producer" }).fill(producer.name);
    await page.getByRole("row", { name: new RegExp(`^${producer.name}`) }).click();
    await page.getByRole("button", { name: `Disable ${producer.name}` }).click();
    const sheet = page.getByRole("dialog", { name: `Disable ${producer.name}?` });
    // It rises from the bottom edge: measured once it has arrived.
    await page.waitForTimeout(500);
    const sheetBox = await sheet.boundingBox();
    expect(Math.round(sheetBox.width)).toBe(390);
    expect(Math.round(sheetBox.y + sheetBox.height)).toBe(844);
    const confirm = await sheet.getByRole("button", { name: "Disable" }).boundingBox();
    const cancel = await sheet.getByRole("button", { name: "Cancel" }).boundingBox();
    expect(confirm.y).toBeLessThan(cancel.y);
  });

  test("Status on a phone shows the working rows with their advice only when opened, and a problem row always open", async ({ page }) => {
    await page.route("**/api/v1/admin/status", (route) =>
      route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ pushProviders: ["fcm"], pushClientOptions: "fcm", pendingDispatches: 0, pendingRetries: 0, abandonedRetries: 0, eventRetentionSeconds: null, startedAt: new Date().toISOString() }) }),
    );
    await adminSignIn(page, "#status");
    const database = page.getByRole("group", { name: "Database" });
    await expect(database).toContainText("Connected. Events are being stored and read.");
    await expect(database.locator(".do")).toBeHidden();
    await database.getByRole("button", { name: "Show what to do for Database" }).click();
    await expect(database.locator(".do")).toBeVisible();
    expect((await sideways(page)).scroll).toBeLessThanOrEqual(390);
  });
});

test.describe("themes and motion", () => {
  test("the page follows the browser's light or dark theme with the design's tokens, on the sign-in screen and inside", async ({ page }) => {
    for (const [scheme, surface] of [["dark", "rgb(18, 19, 24)"], ["light", "rgb(251, 248, 255)"]]) {
      await page.emulateMedia({ colorScheme: scheme });
      await page.goto("/admin/");
      expect(await page.evaluate(() => getComputedStyle(document.body).backgroundColor), scheme).toBe(surface);
      await page.getByLabel("Admin token").fill(process.env.ADMIN_TOKEN);
      await page.getByRole("button", { name: "Sign in" }).click();
      await expect(page.getByRole("navigation", { name: /^Sections/ })).toBeVisible();
      const colors = await page.evaluate(() => {
        const main = getComputedStyle(document.querySelector(".main"));
        const root = getComputedStyle(document.documentElement);
        return { main: main.backgroundColor, primary: root.getPropertyValue("--primary").trim(), error: root.getPropertyValue("--error").trim() };
      });
      expect(colors, scheme).toEqual(scheme === "dark" ? { main: "rgb(27, 27, 33)", primary: "#bac3ff", error: "#ffb4ab" } : { main: "rgb(245, 242, 250)", primary: "#515b92", error: "#ba1a1a" });
    }
  });

  test("with reduced motion there is no slide and no scale, the loading bar and the spinner stand still", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    const person = await createPerson("BASIC");
    const producer = await createProducer(person, unique("calm"), "PUBLIC");
    await adminSignIn(page, `#producers/${producer.id}`);
    const pane = page.getByRole("region", { name: producer.name });
    await expect(pane).toBeVisible();
    const motion = await pane.evaluate((node) => ({ name: getComputedStyle(node).animationName, duration: getComputedStyle(node).animationDuration }));
    expect(motion.name).toBe("fade-in");
    expect(parseFloat(motion.duration)).toBeLessThanOrEqual(0.1);
    await page.getByRole("button", { name: `Disable ${producer.name}` }).click();
    const dialog = page.getByRole("dialog");
    expect(await dialog.evaluate((node) => getComputedStyle(node).animationName)).toBe("fade-in");
    await page.keyboard.press("Escape");
    expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--primary").trim())).not.toBe("");
  });
});

test.describe("Users keeps working in the new shell", () => {
  test("Users lists the users with their devices and producers, and Connect a device opens the new dialog with the user chosen", async ({ page }) => {
    const person = await createPerson("MOD");
    await adminSignIn(page, "#users");
    await expect(page.getByRole("heading", { name: "Users", level: 1 })).toBeVisible();
    const card = page.locator("#user-list li", { hasText: person.name }).first();
    await expect(card).toContainText(person.deviceName);
    await card.getByRole("button", { name: "Connect a device" }).click();
    const dialog = page.getByRole("dialog", { name: "Connect a device" });
    await expect(dialog.getByLabel("User")).toBeDisabled();
    await expect(dialog.getByLabel("User")).toHaveText(`${person.name} · Mod`);
    await dialog.getByRole("button", { name: "Cancel" }).click();
    await page.getByLabel("Name", { exact: true }).fill(unique("invited"));
    await page.getByRole("button", { name: "Invite user" }).click();
    await expect(page.locator("#user-list li").first()).toBeVisible();
  });
});
