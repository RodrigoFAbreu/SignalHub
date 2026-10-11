// The admin page's drawings to compare (docs/design/users/source/Admin - *.dc.html): each frame names
// the drawing's page and frame id, and how to put the page in the same state. The page is given the
// drawings' sample data in place of the management API (admin-sample.mjs), so a frame shows the
// drawing's content: only the clock-dependent words and the QR codes differ.
//
//   node visual/compare.mjs A P1 SI1        (no server data and no token are needed, only a running
//                                            SignalHub to serve the page's files)

import { BASE } from "../support/server.mjs";
import { ana, clients, health, mockAdmin, producers, rodrigo, rui, status, users } from "./admin-sample.mjs";

const SHELL = "Admin - Shell and Producers";
const SIGN_IN = "Admin - Status and sign-in";
const STATUS = "Admin - Status";
const STATUS_STATES = "Admin - Status states";
const DEVICES = "Admin - Devices";
const DEVICE_DIALOGS = "Admin - Devices dialogs";
const LIGHT = "Admin - Light theme check";

const url = (hash = "") => `${BASE}/admin/${hash}`;
const TOKEN = "x".repeat(40);

export const producer = (name) => producers.find((candidate) => candidate.name === name);
export const device = (name) => clients.find((candidate) => candidate.name === name);

/** Opens the page, types a token (any: the API is the sample), and waits for what the frame shows. */
export async function signedIn(page, hash, ready = ".main") {
  await page.goto(url(hash));
  await page.fill("#admin-token", TOKEN);
  await page.click("button[type=submit]");
  await page.waitForSelector(ready, { timeout: 15000 });
  await page.waitForTimeout(300);
}

/** The sign-in screen as the frame shows it (nothing typed). */
async function signInScreen(page, hash = "") {
  await mockAdmin(page);
  await page.goto(url(hash));
  await page.waitForSelector(".sic");
  await page.waitForTimeout(200);
}

/** A frame of the admin page: no world, the sample data, a fixed clock. */
const frame = (id, file, option, setup, extra = {}) => ({ id, file, option, world: false, setup, ...extra });

const dialog = (extra = {}) => ({ drawingSelector: ".dlg", size: { width: 1440, height: 900 }, shot: (page) => page.locator("[role=dialog]").screenshot(), ...extra });

export const adminFrames = [
  // ---- Shell and Producers ----------------------------------------------------------------------
  frame("A", SHELL, "A", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#producers/${producer("homelab-monitor").id}`, ".pane h2");
  }),
  frame("P1", SHELL, "P1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#producers?f=quiet", ".tr");
  }),
  frame("P2", SHELL, "P2", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#producers/${producer("garage-door").id}`, ".pane h2");
    await page.getByRole("button", { name: "Technical details" }).click();
  }),
  frame("P3", SHELL, "P3", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#producers/${producer("quarterly-finance-report-generator").id}`, ".pane h2");
  }),
  frame("P4", SHELL, "P4", async (page) => {
    await mockAdmin(page, { producers: () => new Promise(() => {}) });
    await signedIn(page, "#producers", ".skeletons");
  }),
  frame("P5", SHELL, "P5", async (page) => {
    await mockAdmin(page, { producers: [] });
    await signedIn(page, "#producers", ".empty");
  }),
  frame("P6", SHELL, "P6", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#producers?f=quiet&q=greenhouse", ".empty");
  }),

  // ---- Sign in ---------------------------------------------------------------------------------
  frame("SI1", SIGN_IN, "SI1", (page) => signInScreen(page)),
  frame("SI2", SIGN_IN, "SI2", async (page) => {
    await mockAdmin(page, { clients: { __status: 401, body: { title: "Unauthorized" } } });
    await page.goto(url());
    await page.fill("#admin-token", "example-token-not-the-real-one-0001");
    await page.click("button[type=submit]");
    await page.waitForSelector(".tf.err");
    await page.click(".vis");
  }),

  // ---- Status ----------------------------------------------------------------------------------
  frame("ST1", STATUS, "ST1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#status", ".hero");
  }),
  frame("ST2", STATUS, "ST2", async (page) => {
    const failing = clients.map((candidate) => ({ ...candidate, pushStatus: { lastSuccess: null, lastFailure: { at: new Date().toISOString(), eventId: "01997d5e-0000-7000-8000-000000000999", result: "PERMANENT_FAILURE" }, pendingRetries: 0 } }));
    await mockAdmin(page, { clients: failing, status: { ...status, pendingRetries: 148, abandonedRetries: 12 } });
    await signedIn(page, "#status", ".hero");
  }),

  // ---- Devices ---------------------------------------------------------------------------------
  frame("DV1", DEVICES, "DV1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#devices/${device("Rodrigo - Pixel 9").id}`, ".pane h2");
  }),
];

void [ana, rodrigo, rui, health, users];
