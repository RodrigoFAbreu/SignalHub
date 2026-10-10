import { BASE, asDevice, browserSession, createPerson, createProducer, operator, publish, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

const IMG = "<img src=x onerror=\"window.__pwned='img'\">";
const SCRIPT = "<script>window.__pwned='script'</script>";

test("every server value is shown as text: nothing in an event, a name or a device is run or parsed as markup", async ({ context, page }) => {
  // Names the person chose are arbitrary text: the user's own, and a device renamed by its owner.
  const person = await createPerson("MOD", `${unique("x")} ${IMG}`);
  const producer = await createProducer(person, unique("evil"), "PUBLIC");
  await asDevice(person, "PATCH", `/api/v1/client/devices/${person.deviceId}`, { name: `${SCRIPT} phone` });
  const event = await publish(producer, {
    title: `${IMG} ${SCRIPT}`,
    message: `<b>bold</b> ${IMG}\n${SCRIPT}`,
    context: "build.42",
    metadata: { note: SCRIPT, nested: { html: IMG } },
    link: `https://example.org/path?q=${encodeURIComponent(IMG)}`,
  });

  // A script address is not a link the server accepts, so the page never has one to open.
  const refused = await fetch(`${BASE}/api/v1/events`, {
    method: "POST",
    headers: { Authorization: `Bearer ${producer.apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ category: "INFO", severity: "NORMAL", title: "x", link: "javascript:window.__pwned='link'" }),
  });
  expect(refused.status).toBe(400);

  await useSession(context, await browserSession(person));
  await page.goto(`/app/#inbox/${event.id}`);
  const detail = page.locator("section.detp");
  await expect(detail.getByRole("heading", { level: 2 })).toContainText("<img src=x onerror=");
  await expect(detail.locator(".body")).toContainText("<b>bold</b>");
  await expect(detail.locator(".body")).toContainText("<script>window.__pwned='script'</script>");
  await expect(detail.locator("pre.metadata")).toContainText("<script>window.__pwned='script'</script>");
  // The link is a link only because it is an http(s) address, and its text is shown as text.
  await expect(detail.getByRole("link", { name: "Open link" })).toHaveAttribute("href", /^https:\/\/example\.org\//);

  // Elsewhere the names appear: the account menu, the rail, People, Devices, Settings.
  await page.getByRole("button", { name: /Account menu/ }).click();
  await expect(page.getByRole("menu")).toContainText("<img src=x onerror=");
  await page.keyboard.press("Escape");
  await page.goto("/app/#settings/devices");
  await expect(page.locator(".device-row", { hasText: "<script>window.__pwned='script'</script> phone" })).toBeVisible();
  // An admin sees the same person in People.
  const viewer = await createPerson("ADMIN");
  const adminPage = await context.browser().newContext();
  await useSession(adminPage, await browserSession(viewer));
  const second = await adminPage.newPage();
  await second.goto("/app/#people");
  await expect(second.locator(".people-list")).toContainText("<img src=x onerror=");
  expect(await second.evaluate(() => ({ pwned: window.__pwned ?? null, images: document.querySelectorAll("img").length }))).toEqual({ pwned: null, images: 0 });
  await adminPage.close();

  const result = await page.evaluate(() => ({
    pwned: window.__pwned ?? null,
    images: document.querySelectorAll("img").length,
    scripts: [...document.querySelectorAll("script")].filter((node) => !node.src).length,
    bold: document.querySelectorAll(".body b").length,
  }));
  expect(result).toEqual({ pwned: null, images: 0, scripts: 0, bold: 0 });
});

test("a link that is not an http(s) address is shown as text, never as a link", async ({ context, page }) => {
  // The server refuses such a link, so the page's own rule is checked on the client's answer.
  const person = await createPerson("BASIC");
  const producer = await createProducer(person, unique("p"), "PUBLIC");
  const event = await publish(producer, { title: "Has a link", link: "https://example.org/ok" });
  await useSession(context, await browserSession(person));
  const hostile = async (route) => {
    const response = await route.fetch();
    const body = await response.json();
    await route.fulfill({ response, json: { ...body, link: "javascript:window.__pwned='link'" } });
  };
  await page.route(`**/api/v1/events/${event.id}`, hostile);
  await page.route(`**/api/v1/events/${event.id}/read`, hostile);
  await page.goto(`/app/#inbox/${event.id}`);
  await expect(page.getByRole("heading", { name: "Has a link" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open link" })).toHaveCount(0);
  await expect(page.locator(".kv")).toContainText("javascript:window.__pwned='link'");
  expect(await page.evaluate(() => window.__pwned ?? null)).toBeNull();
});

test("the operator's token never reaches the page and the page never calls the management API", async ({ context, page, watch }) => {
  const person = await createPerson("ADMIN");
  await useSession(context, await browserSession(person));
  await page.goto("/app/#inbox");
  for (const hash of ["#producers", "#people", "#settings", "#settings/devices", "#inbox"]) {
    await page.goto(`/app/${hash}`);
    await page.waitForLoadState("networkidle");
  }
  expect(watch.requests.filter((url) => url.includes("/api/v1/admin"))).toEqual([]);
  const html = await page.content();
  expect(html).not.toContain(process.env.ADMIN_TOKEN);
  void operator;
});
