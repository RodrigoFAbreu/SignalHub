import { expect, test as base } from "@playwright/test";
import { BASE, phoneApproves } from "./server.mjs";

export { expect };

/**
 * Every test also watches the page: a script error, a Content-Security-Policy violation or a
 * request to another origin fails it. Tests that expect a thing (the CSP test makes a violation
 * on purpose) read `watch` instead of relying on the automatic check.
 */
export const test = base.extend({
  watch: [
    async ({ page }, use) => {
      // `allowedOrigins`: pages a test itself serves (an attacker's page), which the page under test
      // must still never have been asked to load from.
      const watch = { errors: [], violations: [], requests: [], ignoreViolations: false, allowedOrigins: [] };
      page.on("pageerror", (error) => watch.errors.push(String(error)));
      page.on("console", (message) => {
        const text = message.text();
        // A refused request (401 while signed out, 404 for a missing event) is logged by the
        // browser as an error of its own; what matters is the page's scripts and the policy.
        if (message.type() === "error" && !text.startsWith("Failed to load resource")) {
          watch.errors.push(text);
        }
        if (/Content Security Policy|Refused to/i.test(text)) watch.violations.push(text);
      });
      page.on("request", (request) => watch.requests.push(request.url()));
      await page.addInitScript(() => {
        window.__violations = [];
        document.addEventListener("securitypolicyviolation", (event) => {
          window.__violations.push(`${event.violatedDirective} ${event.blockedURI}`);
        });
      });
      await use(watch);
      const inPage = await page.evaluate(() => window.__violations ?? []).catch(() => []);
      if (!watch.ignoreViolations) {
        expect(watch.violations, "Content-Security-Policy violations in the console").toEqual([]);
        expect(inPage, "securitypolicyviolation events").toEqual([]);
      }
      expect(watch.errors, "script errors").toEqual([]);
      const others = watch.requests.filter((url) => {
        if (url.startsWith("data:") || url.startsWith("blob:") || url.startsWith("about:")) return false;
        const origin = new URL(url).origin;
        return origin !== new URL(BASE).origin && !watch.allowedOrigins.includes(origin);
      });
      expect(others, "requests to another origin").toEqual([]);
    },
    { auto: true },
  ],
});

/** Opens the page, takes the sign-in the page started, and approves it from the person's phone. */
export async function signIn(page, person, hash = "") {
  const started = page.waitForResponse((response) => response.url().endsWith("/api/v1/web/sign-ins") && response.request().method() === "POST");
  await page.goto(`/app/${hash}`);
  const sign = await (await started).json();
  await phoneApproves(person, sign.code);
  await expect(page.getByRole("navigation", { name: "Main" })).toBeVisible({ timeout: 20_000 });
  return sign;
}

/** The session cookie, as the browser holds it. */
export async function sessionCookie(page) {
  const cookies = await page.context().cookies();
  return cookies.find((cookie) => cookie.name === "__Host-signalhub_session");
}
