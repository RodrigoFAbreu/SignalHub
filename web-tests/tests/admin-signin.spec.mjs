import { expect, test, adminSignIn } from "../support/page.mjs";

const TOKEN = process.env.ADMIN_TOKEN;
const WRONG = "x".repeat(40);

test("the first screen asks for the token, keeps Sign in off until it has 32 characters, and shows it only when asked", async ({ page }) => {
  await page.goto("/admin/");
  await expect(page.getByRole("heading", { name: "SignalHub admin", level: 1 })).toBeVisible();
  await expect(page.getByText("served only on this server's own port")).toBeVisible();
  const field = page.getByLabel("Admin token");
  // The field has the keyboard.
  await expect(field).toBeFocused();
  await expect(field).toHaveAttribute("type", "password");
  const signIn = page.getByRole("button", { name: "Sign in" });
  await expect(signIn).toBeDisabled();
  await field.fill("short-token");
  await expect(page.getByText("At least 32 characters; this one has 11.")).toBeVisible();
  await expect(signIn).toBeDisabled();
  await field.fill(WRONG);
  await expect(page.getByText("At least 32 characters")).toHaveCount(0);
  await expect(signIn).toBeEnabled();
  // The eye shows and hides it, named for what it does.
  await page.getByRole("button", { name: "Show the token" }).click();
  await expect(field).toHaveAttribute("type", "text");
  await page.getByRole("button", { name: "Hide the token" }).click();
  await expect(field).toHaveAttribute("type", "password");
  // Tab order: the field, the eye, Sign in.
  await field.focus();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("button", { name: "Show the token" })).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(signIn).toBeFocused();
});

test("a wrong token is said in words, keeps the token in the field and locks nothing", async ({ page }) => {
  await page.goto("/admin/#producers");
  const field = page.getByLabel("Admin token");
  await field.fill(WRONG);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("alert").filter({ hasText: "Wrong admin token" })).toBeVisible();
  await expect(page.getByText("SIGNALHUB_ADMIN_TOKEN in the server's .env")).toBeVisible();
  await expect(field).toHaveValue(WRONG);
  // No retry counter and no delay: the same screen, ready for another try.
  await expect(page.getByRole("button", { name: "Sign in" })).toBeEnabled();
  await expect(page.locator("#signin")).not.toContainText("attempt");
  // Typing again clears what was said about the last try.
  await field.fill(`${WRONG}1`);
  await expect(page.getByText("Wrong admin token")).toHaveCount(0);
});

test("the token goes in, the section in the address stays, and nothing is kept in the browser", async ({ page, context }) => {
  await adminSignIn(page, "#status");
  await expect(page).toHaveURL(/\/admin\/#status$/);
  await expect(page.getByRole("heading", { name: "Status", level: 1 })).toBeVisible();
  // Not in storage, not in a cookie, not in the address.
  const stored = await page.evaluate(() => ({ local: JSON.stringify(localStorage), session: JSON.stringify(sessionStorage), cookie: document.cookie, href: location.href }));
  for (const where of Object.values(stored)) expect(where).not.toContain(TOKEN);
  expect(await context.cookies()).toEqual([]);
  expect(await page.content()).not.toContain(TOKEN);
  // A reload asks again, and the address still names the section.
  await page.reload();
  await expect(page.getByLabel("Admin token")).toBeVisible();
  await expect(page).toHaveURL(/#status$/);
});

test("the management API being off says what to do, and offers to reload", async ({ page }) => {
  await page.route("**/api/v1/admin/clients", (route) => route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ title: "Not Found", status: 404 }) }));
  await page.goto("/admin/");
  await page.getByLabel("Admin token").fill(WRONG);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByText("The admin page is switched off on this server.")).toBeVisible();
  await expect(page.getByText("Set SIGNALHUB_ADMIN_TOKEN in the server's .env")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign in" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Reload this page" })).toBeVisible();
  await expect(page.getByText("Not available")).toBeVisible();
});

test("a server that cannot be reached, or answers 503, keeps the token and says what to check", async ({ page }) => {
  let mode = "down";
  await page.route("**/api/v1/admin/clients", (route) => (mode === "down" ? route.abort() : mode === "503" ? route.fulfill({ status: 503, body: "" }) : route.continue()));
  await page.goto("/admin/");
  const field = page.getByLabel("Admin token");
  await field.fill(TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByText("Could not reach SignalHub.")).toBeVisible();
  await expect(page.getByText("docker compose ps")).toBeVisible();
  await expect(field).toHaveValue(TOKEN);
  mode = "503";
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(page.getByText("SignalHub answered 503.")).toBeVisible();
  await expect(page.getByText("read the server's log")).toBeVisible();
  mode = "ok";
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(page.getByRole("navigation", { name: /^Sections/ })).toBeVisible();
});

test("while signing in the field is off and the button waits, so a second press is impossible", async ({ page }) => {
  let release;
  const held = new Promise((resolve) => {
    release = resolve;
  });
  await page.route("**/api/v1/admin/clients", async (route) => {
    await held;
    await route.continue();
  });
  await page.goto("/admin/");
  await page.getByLabel("Admin token").fill(TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("button", { name: "Signing in…" })).toBeDisabled();
  await expect(page.getByLabel("Admin token")).toBeDisabled();
  await expect(page.getByText("Checking the token with the server…")).toBeVisible();
  release();
  await expect(page.getByRole("navigation", { name: /^Sections/ })).toBeVisible();
});

test("signing out asks first, forgets the token and says so; the address goes back to /admin/", async ({ page }) => {
  await adminSignIn(page, "#producers");
  await page.getByRole("button", { name: "Account" }).click();
  const menu = page.getByRole("menu", { name: "Account" });
  await expect(menu).toContainText("admin token");
  await expect(menu.getByText(/^SignalHub /)).toBeVisible();
  await expect(menu.getByRole("menuitem", { name: /Server status/ })).toBeVisible();
  // Escape closes the menu and returns focus to the avatar.
  await page.keyboard.press("Escape");
  await expect(page.getByRole("button", { name: "Account" })).toBeFocused();
  await page.getByRole("button", { name: "Account" }).click();
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  const dialog = page.getByRole("dialog", { name: "Sign out of the admin page?" });
  await expect(dialog).toBeVisible();
  // Focus starts on Cancel; nothing is lost by it.
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeFocused();
  await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(page.getByRole("navigation", { name: /^Sections/ })).toBeVisible();
  await page.getByRole("button", { name: "Account" }).click();
  await page.getByRole("menuitem", { name: "Sign out" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByText("You signed out.")).toBeVisible();
  await expect(page.getByText("This page forgot the token. Nothing else changed on the server.")).toBeVisible();
  await expect(page).toHaveURL(/\/admin\/$/);
  await expect(page.getByLabel("Admin token")).toBeFocused();
  await expect(page.getByRole("button", { name: "Sign in" })).toBeDisabled();
  // And it works again with the token.
  await page.getByLabel("Admin token").fill(TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("navigation", { name: /^Sections/ })).toBeVisible();
});

test("a token that stops working in use sends the page to sign-in, and the same place comes back after it", async ({ page }) => {
  await adminSignIn(page, "#producers");
  await expect(page.getByRole("grid", { name: "Producers" }).or(page.getByText("No producers yet"))).toBeVisible();
  // The server now answers 401 to the management API (the token was changed).
  await page.route("**/api/v1/admin/producers", (route) => route.fulfill({ status: 401, contentType: "application/json", body: JSON.stringify({ title: "Unauthorized", status: 401 }) }));
  await page.getByRole("button", { name: "Refresh" }).click();
  await expect(page.getByText("Your session ended.")).toBeVisible();
  await expect(page.getByText("You will come back to the Producers section, where you were.")).toBeVisible();
  await expect(page).toHaveURL(/#producers$/);
  // Neutral, not an error of the operator's: no "Wrong admin token".
  await expect(page.getByText("Wrong admin token")).toHaveCount(0);
  await page.unroute("**/api/v1/admin/producers");
  await page.getByLabel("Admin token").fill(TOKEN);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("heading", { name: "Producers", level: 1 })).toBeVisible();
  await expect(page).toHaveURL(/#producers$/);
});
