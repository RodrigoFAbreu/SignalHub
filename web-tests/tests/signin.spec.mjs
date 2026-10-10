import { createPerson, phoneApproves } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

function startedSignIn(page) {
  return page.waitForResponse((response) => response.url().endsWith("/api/v1/web/sign-ins") && response.request().method() === "POST");
}

test("a desktop page shows a QR code and a countdown, and opens the inbox once the phone approves", async ({ page }) => {
  const person = await createPerson("BASIC");
  const started = startedSignIn(page);
  await page.goto("/app/");
  const sign = await (await started).json();

  await expect(page.getByRole("heading", { name: "Sign in with your phone" })).toBeVisible();
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  await expect(page.getByText(/Waiting for your phone · [0-3]:\d\d/)).toBeVisible();
  // The QR code holds the link the app opens, with the scan code: never the poll secret.
  expect(sign.scanCode).toMatch(/^shsc1_/);
  expect(JSON.stringify(await page.evaluate(() => document.body.innerText))).not.toContain(sign.pollSecret);

  await phoneApproves(person, sign.code);
  await expect(page.getByRole("heading", { name: `Signed in as ${person.name}` })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Main" })).toBeVisible({ timeout: 10_000 });
  await expect(page).toHaveURL(/#inbox$/);
  await expect(page.getByRole("heading", { name: "Nothing here yet" })).toBeVisible();
});

test("Use a code instead shows the short code, and Back to the QR code returns", async ({ page }) => {
  const person = await createPerson("BASIC");
  const started = startedSignIn(page);
  await page.goto("/app/");
  const sign = await (await started).json();
  await page.getByRole("button", { name: "Use a code instead" }).click();
  await expect(page.getByRole("heading", { name: "Sign in with a code" })).toBeVisible();
  await expect(page.locator(".code")).toHaveText(sign.code);
  await page.getByRole("button", { name: "Back to the QR code" }).click();
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  await phoneApproves(person, sign.code);
  await expect(page.getByRole("navigation", { name: "Main" })).toBeVisible({ timeout: 10_000 });
});

test("at phone width the page shows a typed code and an Open the app link instead of a QR code", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 780 });
  const person = await createPerson("MOD");
  const started = startedSignIn(page);
  await page.goto("/app/");
  const sign = await (await started).json();

  await expect(page.getByRole("heading", { name: "Sign in with the app" })).toBeVisible();
  await expect(page.locator(".code")).toHaveText(sign.code);
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toHaveCount(0);
  const open = page.getByRole("link", { name: "Open the app" });
  await expect(open).toHaveAttribute("href", /^signalhub:\/\/signin\?server=.+&code=shsc1_/);
  const box = await open.boundingBox();
  expect(box.height).toBeGreaterThanOrEqual(48);

  // The typed code, in any case and with or without the dash, is what the app sends.
  await phoneApproves(person, sign.code.replace("-", "").toLowerCase());
  await expect(page.getByRole("navigation", { name: "Main" })).toBeVisible({ timeout: 10_000 });
});

test("a code that runs out is replaced by a new one, and after five refreshes the page stops", async ({ page }) => {
  await page.clock.install();
  const codes = [];
  page.on("response", async (response) => {
    if (response.url().endsWith("/api/v1/web/sign-ins") && response.request().method() === "POST") codes.push((await response.json()).code);
  });
  await page.goto("/app/");
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  for (let refresh = 1; refresh <= 5; refresh += 1) {
    await page.clock.runFor(181_000);
    await expect.poll(() => codes.length, { timeout: 10_000 }).toBe(refresh + 1);
    await expect(page.getByText(/Waiting for your phone · [0-3]:\d\d/)).toBeVisible();
  }
  expect(new Set(codes).size).toBe(6);
  await page.clock.runFor(181_000);
  await expect(page.getByRole("heading", { name: "Still waiting for your phone" })).toBeVisible();
  await page.getByRole("button", { name: "Show a new code" }).click();
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
});

test("a cancel in the app is noticed by the page", async ({ page }) => {
  const person = await createPerson("BASIC");
  const started = startedSignIn(page);
  await page.goto("/app/");
  const sign = await (await started).json();
  await phoneApproves(person, sign.code, { cancel: true });
  await expect(page.getByRole("heading", { name: "Sign-in was cancelled" })).toBeVisible();
  await expect(page.getByText("Nothing was signed in on this browser.")).toBeVisible();
  await page.getByRole("button", { name: "Show a new code" }).click();
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
});

test("when the server cannot be reached the page says so and keeps trying", async ({ page, context }) => {
  await page.route("**/api/v1/web/sign-ins", (route) => route.abort());
  await page.goto("/app/");
  await expect(page.getByRole("heading", { name: "Can't reach SignalHub" })).toBeVisible();
  await page.unroute("**/api/v1/web/sign-ins");
  await page.getByRole("button", { name: "Try now" }).click();
  await expect(page.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  void context;
});

test("a second tab learns that this browser signed in in the first", async ({ context }) => {
  const person = await createPerson("BASIC");
  const first = await context.newPage();
  const second = await context.newPage();
  const started = startedSignIn(first);
  await first.goto("/app/");
  const sign = await (await started).json();
  await second.goto("/app/");
  await expect(second.getByRole("img", { name: /Sign-in QR code/ })).toBeVisible();
  await phoneApproves(person, sign.code);
  await expect(first.getByRole("navigation", { name: "Main" })).toBeVisible({ timeout: 10_000 });
  await expect(second.getByRole("heading", { name: "You're already signed in" })).toBeVisible();
  await second.getByRole("button", { name: "Open the inbox" }).click();
  await expect(second.getByRole("navigation", { name: "Main" })).toBeVisible();
});

test("signing in returns to the address the page was asked for", async ({ page }) => {
  const person = await createPerson("BASIC");
  const started = startedSignIn(page);
  await page.goto("/app/#settings");
  const sign = await (await started).json();
  await phoneApproves(person, sign.code);
  await expect(page.getByRole("heading", { name: "Settings", level: 1 })).toBeVisible({ timeout: 10_000 });
  await expect(page).toHaveURL(/#settings$/);
});
