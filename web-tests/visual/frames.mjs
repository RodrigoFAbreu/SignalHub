// The drawings to compare: each frame names the drawing's option (6a, 7b, ...), which of the
// option's frames it is, who is signed in, and how to put the page in the same state.

import { BASE } from "../support/server.mjs";

const SIGN_IN = "Web - Sign in";
const INBOX = "Web - Inbox and producers";
const SETTINGS = "Web - Settings, people and states";

const url = (hash = "") => `${BASE}/app/${hash}`;
const NONE = "00000000-0000-7000-8000-000000000000";

/** Waits until the signed-in page shows its first content. */
async function open(page, hash, ready = "nav.rail") {
  await page.goto(url(hash));
  await page.waitForSelector(ready, { timeout: 15000 });
  await page.waitForTimeout(500);
}

async function ruiSubscribes(world) {
  for (const name of ["ana-reports", "backup-jobs"]) {
    await fetch(`${BASE}/api/v1/client/visible-producers/${world.producers[name].id}/subscription`, { method: "PUT", headers: { Authorization: `Bearer ${world.people.rui.key}` } });
  }
}

// ---- The sign-in API, as a phone and the server would drive it ---------------------------------

const sampleSignIn = (extra = {}) => ({
  id: "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b",
  pollSecret: "shsp1_EXAMPLE-not-a-secret-000000000000000000000",
  code: "K7Q-4MX",
  scanCode: "shsc1_EXAMPLE-not-a-code0000",
  uri: null,
  browserName: "Firefox on Linux",
  ...extra,
});

async function mockSignIn(page, { lifetimeMs = 161_000, poll = "PENDING", start } = {}) {
  let starts = 0;
  await page.route("**/api/v1/web/sign-ins", async (route) => {
    starts += 1;
    if (start) return start(route, starts);
    return route.fulfill({
      status: 201,
      contentType: "application/json",
      headers: { Date: new Date().toUTCString() },
      body: JSON.stringify(sampleSignIn({ expiresAt: new Date(Date.now() + lifetimeMs).toISOString() })),
    });
  });
  await page.route("**/api/v1/web/sign-ins/*", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ state: poll }) }));
}

const SESSION = (name, role, expiresAt) => ({
  csrfToken: "sample-csrf",
  client: { id: "01997d5e-0000-7000-8000-00000000aaaa", name: "Firefox on Linux", kind: "BROWSER", admin: role === "ADMIN", user: { id: "01997d5e-0000-7000-8000-00000000bbbb", name, role }, createdAt: new Date(Date.now() - 86_400_000).toISOString(), expiresAt, lastActiveAt: null, revokedAt: null },
});

async function mockSession(page, { name = "Rodrigo", role = "ADMIN", expiresAt = new Date(Date.now() + 29 * 86_400_000).toISOString() } = {}) {
  await page.route("**/api/v1/web/session", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(SESSION(name, role, expiresAt)) }));
}

const unauthorized = (route) => route.fulfill({ status: 401, contentType: "application/json", body: JSON.stringify({ title: "Unauthorized", status: 401 }) });

async function signInPage(page, options) {
  await mockSignIn(page, options);
  await page.goto(url());
  await page.waitForSelector(".card");
  await page.waitForTimeout(300);
}

// ---- A session that ends -------------------------------------------------------------------------

async function endedWhileUsing(page, { expired }) {
  await mockSession(page, { expiresAt: expired ? new Date(Date.now() - 1000).toISOString() : undefined });
  await page.route("**/api/v1/events**", unauthorized);
  await page.route("**/api/v1/client/visible-producers", unauthorized);
  await mockSignIn(page);
  await page.goto(url("#inbox"));
}

export const frames = [
  // ---- Sign in (6) --------------------------------------------------------------------------------
  { id: "6a", file: SIGN_IN, option: "6a", setup: (page) => signInPage(page) },
  {
    id: "6a2",
    file: SIGN_IN,
    option: "6a2",
    setup: async (page) => {
      // The code runs out, and the next one is slow to arrive.
      await mockSignIn(page, {
        lifetimeMs: 1500,
        start: async (route, count) => {
          if (count === 1) {
            return route.fulfill({ status: 201, contentType: "application/json", headers: { Date: new Date().toUTCString() }, body: JSON.stringify(sampleSignIn({ expiresAt: new Date(Date.now() + 1500).toISOString() })) });
          }
          await new Promise((resolve) => setTimeout(resolve, 20000));
          return route.abort();
        },
      });
      await page.goto(url());
      await page.waitForSelector(".qrover", { timeout: 8000 });
    },
  },
  {
    id: "6a4",
    file: SIGN_IN,
    option: "6a4",
    settle: 100,
    setup: async (page) => {
      await mockSignIn(page, { poll: "SIGNED_IN" });
      await mockSession(page);
      await page.goto(url());
      await page.waitForSelector(".okmark");
    },
  },
  {
    id: "6a5",
    file: SIGN_IN,
    option: "6a5",
    setup: async (page) => {
      await signInPage(page);
      await page.getByRole("button", { name: "Use a code instead" }).click();
    },
  },
  { id: "6d", file: SIGN_IN, option: "6d", index: 0, setup: (page) => signInPage(page) },
  { id: "6e-1", file: SIGN_IN, option: "6e", index: 0, setup: async (page) => { await mockSignIn(page, { poll: "CANCELLED" }); await page.goto(url()); await page.waitForSelector("text=Sign-in was cancelled"); } },
  {
    id: "6e-2",
    file: SIGN_IN,
    option: "6e",
    index: 1,
    setup: async (page) => {
      await mockSignIn(page, { start: (route) => route.fulfill({ status: 429, contentType: "application/json", body: JSON.stringify({ title: "Too many sign-ins in progress", status: 429 }) }) });
      await page.goto(url());
      await page.waitForSelector("text=Too many tries");
    },
  },
  {
    id: "6e-3",
    file: SIGN_IN,
    option: "6e",
    index: 2,
    setup: async (page) => {
      await mockSignIn(page, { start: (route) => route.abort() });
      await page.goto(url());
      await page.waitForSelector("text=Can't reach SignalHub");
    },
  },
  {
    id: "6e-4",
    file: SIGN_IN,
    option: "6e",
    index: 3,
    setup: async (page) => {
      // Five refreshes with nobody approving: each code lives under a second.
      await mockSignIn(page, { lifetimeMs: 300 });
      await page.goto(url());
      await page.waitForSelector("text=Still waiting for your phone", { timeout: 20000 });
    },
  },
  {
    id: "6e-5",
    file: SIGN_IN,
    option: "6e",
    index: 4,
    setup: async (page, world, context) => {
      await mockSignIn(page);
      await page.goto(url());
      await page.waitForSelector(".card");
      // From now on this browser has a session (another tab signed it in).
      await mockSession(page);
      const other = await context.newPage();
      await other.goto(url("#inbox"));
      await other.evaluate(() => { window.__channel = new BroadcastChannel("signalhub-session"); window.__channel.postMessage({ type: "signed-in" }); });
      await page.bringToFront(); await page.waitForSelector("text=already signed in");
    },
  },
  { id: "6f-1", file: SIGN_IN, option: "6f", index: 0, setup: async (page) => { await endedWhileUsing(page, { expired: true }); await page.waitForSelector(".banner"); } },
  {
    id: "6f-2",
    file: SIGN_IN,
    option: "6f",
    index: 1,
    setup: async (page) => {
      await endedWhileUsing(page, { expired: true });
      await page.getByRole("button", { name: "Sign in again" }).click();
      await page.waitForSelector(".card");
    },
  },
  {
    id: "6f-3",
    file: SIGN_IN,
    option: "6f",
    index: 2,
    settle: 0,
    setup: async (page) => {
      await endedWhileUsing(page, { expired: false });
      await page.waitForSelector(".checking");
    },
  },
  {
    id: "6f-4",
    file: SIGN_IN,
    option: "6f",
    index: 3,
    setup: async (page) => {
      await endedWhileUsing(page, { expired: false });
      await page.waitForSelector(".card");
    },
  },
  {
    id: "6f-5",
    file: SIGN_IN,
    option: "6f",
    index: 4,
    setup: async (page, world, context) => {
      await mockSession(page);
      await page.route("**/api/v1/events**", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [], nextCursor: null }) }));
      await page.route("**/api/v1/events/unread-count", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ unread: 0 }) }));
      await page.route("**/api/v1/client/**", (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: [] }) }));
      await page.goto(url("#inbox"));
      await page.waitForSelector("nav.rail");
      const other = await context.newPage();
      await other.goto(url("#inbox"));
      await other.evaluate(() => { window.__channel = new BroadcastChannel("signalhub-session"); window.__channel.postMessage({ type: "signed-out" }); });
      await page.bringToFront(); await page.waitForSelector("text=You signed out in another tab.");
    },
  },

  // ---- The web page: inbox and producers (7) ------------------------------------------------------
  {
    id: "7a",
    file: INBOX,
    option: "7a",
    persona: "rodrigo",
    setup: async (page, world) => {
      await open(page, `#inbox/${world.events.approve}`, ".event-row");
      await page.keyboard.press("Shift");
      await page.getByRole("button", { name: "Mark as unread" }).focus();
    },
  },
  {
    id: "7b",
    file: INBOX,
    option: "7b",
    persona: "rodrigo",
    setup: async (page, world) => {
      await open(page, `#producers/${world.producers["homelab-monitor"].id}`, ".prow");
      await page.waitForSelector("text=Keys");
      await page.getByRole("button", { name: "Account menu, Rodrigo" }).click();
    },
  },
  { id: "7c", file: INBOX, option: "7c", persona: "rodrigo", setup: (page) => open(page, "#inbox", ".event-row") },
  {
    id: "7d",
    file: INBOX,
    option: "7d",
    persona: "rodrigo",
    setup: async (page) => {
      await open(page, "#producers", ".prow");
      await page.getByRole("button", { name: "Account menu, Rodrigo" }).click();
    },
  },
  { id: "7e", file: INBOX, option: "7e", persona: "rodrigo", setup: async (page, world) => { await open(page, `#producers/${world.producers["homelab-monitor"].id}`, ".detp .lab"); } },
  {
    id: "7f-1",
    file: INBOX,
    option: "7f",
    index: 0,
    persona: "rodrigo",
    setup: async (page) => {
      await open(page, "#producers/new", "form");
      await page.getByLabel("Name").fill("weather-station-2");
    },
  },
  { id: "7f-2", file: INBOX, option: "7f", index: 1, persona: "rodrigo", setup: async (page, world) => { await open(page, `#producers/${world.producers["ana-reports"].id}`, ".detp .switch-row"); } },
  { id: "7h-1", file: INBOX, option: "7h", index: 0, persona: "rodrigo", setup: async (page, world) => { await open(page, `#producers/${world.producers["weather-station"].id}`, ".detp .lab"); } },
  { id: "7h-2", file: INBOX, option: "7h", index: 1, persona: "rodrigo", setup: async (page, world) => { await open(page, `#producers/${world.producers["ci-pipeline"].id}`, ".detp .lab"); } },
  // ---- Settings, people and states (8) ------------------------------------------------------------
  { id: "8a", file: SETTINGS, option: "8a", persona: "rodrigo", setup: async (page) => { await open(page, "#settings"); await page.waitForSelector("text=Server version"); } },
  {
    id: "8b-1",
    file: SETTINGS,
    option: "8b",
    index: 0,
    persona: "rui",
    setup: async (page) => {
      await open(page, "#settings");
      await page.getByRole("button", { name: "Account menu, Rui" }).click();
      await page.getByRole("menuitem", { name: "Sign out" }).click();
      await page.waitForSelector("[role=dialog]");
    },
  },
  { id: "8b-2", file: SETTINGS, option: "8b", index: 1, persona: "rui", setup: async (page) => { await open(page, "#settings"); await page.waitForSelector("text=Chrome on Linux, signed", { timeout: 1000 }).catch(() => {}); } },
  { id: "8c-1", file: SETTINGS, option: "8c", index: 0, persona: "rui", setup: async (page) => { await open(page, "#settings/devices"); await page.waitForSelector(".device-row"); } },
  {
    id: "8c-2",
    file: SETTINGS,
    option: "8c",
    index: 1,
    persona: "rui",
    setup: async (page) => {
      await open(page, "#settings/devices");
      await page.waitForSelector(".device-row");
      await page.getByRole("button", { name: "Revoke Chrome on Windows" }).click();
      await page.waitForSelector("[role=dialog]");
    },
  },
  { id: "8c2", file: SETTINGS, option: "8c2", persona: "rodrigo", setup: async (page) => { await open(page, "#settings/devices"); await page.waitForSelector(".device-row"); } },
  {
    id: "8d-1",
    file: SETTINGS,
    option: "8d",
    index: 0,
    persona: "rodrigo",
    setup: async (page, world) => {
      await open(page, `#people/${world.people.ana.id}`, ".prow");
      await page.waitForSelector("text=ana-reports");
    },
  },
  {
    id: "8d-2",
    file: SETTINGS,
    option: "8d",
    index: 1,
    persona: "rodrigo",
    setup: async (page) => {
      await open(page, "#people", ".prow");
      await page.getByRole("button", { name: "Invite" }).click();
      await page.getByLabel("Their name").fill("Marta");
    },
  },
  {
    id: "8d-3",
    file: SETTINGS,
    option: "8d",
    index: 2,
    persona: "rodrigo",
    setup: async (page) => {
      await open(page, "#people", ".prow");
      await page.getByRole("button", { name: "Invite" }).click();
      await page.getByLabel("Their name").fill(`Marta B${Date.now() % 10000}`);
      await page.getByRole("button", { name: "Make invitation" }).click();
      await page.waitForSelector(".linkbox");
    },
  },
  {
    id: "8e-1",
    file: SETTINGS,
    option: "8e",
    index: 0,
    persona: "rodrigo",
    contextOptions: { permissions: ["clipboard-read", "clipboard-write"] },
    setup: async (page) => {
      await open(page, "#producers/new", "form");
      await page.getByLabel("Name").fill(`homelab-monitor-${Date.now() % 100000}`);
      await page.getByRole("button", { name: "Create" }).click();
      await page.waitForSelector(".keybox");
      await page.getByRole("button", { name: "Copy", exact: true }).click();
      await page.waitForSelector("text=Copied");
    },
  },
  {
    id: "8e-2",
    file: SETTINGS,
    option: "8e",
    index: 1,
    persona: "rodrigo",
    setup: async (page, world) => {
      await page.addInitScript(() => {
        Object.defineProperty(navigator, "clipboard", { value: { writeText: () => Promise.reject(new Error("denied")) } });
      });
      await open(page, `#producers/${world.producers["homelab-monitor"].id}`, ".prow");
      await page.getByRole("button", { name: "New key" }).click();
      await page.waitForSelector(".keybox");
      await page.getByRole("button", { name: "Copy", exact: true }).click();
      await page.waitForSelector("text=This browser did not allow copying");
    },
  },
  { id: "8f-1", file: SETTINGS, option: "8f", index: 0, persona: "rui", setup: async (page) => { await open(page, "#inbox", ".empty"); } },
  { id: "8f-2", file: SETTINGS, option: "8f", index: 1, persona: "rui", setup: async (page) => { await open(page, `#inbox/${NONE}`, ".empty"); } },
  {
    // From here on Rui has something in the inbox: one unread event of a public producer.
    id: "7g",
    file: INBOX,
    option: "7g",
    persona: "rui",
    setup: async (page, world) => {
      await ruiSubscribes(world);
      await open(page, "#inbox", ".event-row");
    },
  },
  {
    id: "8f-3",
    file: SETTINGS,
    option: "8f",
    index: 2,
    persona: "rui",
    setup: async (page, world, context) => {
      await ruiSubscribes(world);
      await open(page, "#inbox", ".event-row");
      await context.setOffline(true);
      await page.evaluate(() => window.dispatchEvent(new Event("online")));
      await page.waitForSelector(".banner");
    },
  },
  {
    id: "8f-4",
    file: SETTINGS,
    option: "8f",
    index: 3,
    persona: "rui",
    setup: async (page) => {
      await page.route("**/api/v1/events?*", (route) => route.abort());
      await open(page, "#inbox", ".empty");
    },
  },
  { id: "8g-1", file: SETTINGS, option: "8g", index: 0, persona: "rui", setup: (page) => open(page, "#inbox", ".event-row") },
  { id: "8g-2", file: SETTINGS, option: "8g", index: 1, persona: "rui", setup: (page) => open(page, `#inbox/${NONE}`, ".empty") },
  { id: "8h", file: SETTINGS, option: "8h", persona: "rui", setup: (page) => open(page, "#people", ".empty") },
];
