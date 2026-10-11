// The admin page's drawings to compare (docs/design/users/source/Admin - *.dc.html): each frame names
// the drawing's page and frame id, and how to put the page in the same state. The page is given the
// drawings' sample data in place of the management API (admin-sample.mjs), so a frame shows the
// drawing's content: only the clock-dependent words and the QR codes differ.
//
//   node visual/compare.mjs A P1 SI1        (no server data and no token are needed, only a running
//                                            SignalHub to serve the page's files)

import { BASE } from "../support/server.mjs";
import { NOW, drawnUsers, ana, clients, deliveries, eventClients, events, health, mockAdmin, otherDeliveries, producers, rodrigo, rui, status, users } from "./admin-sample.mjs";

const SHELL = "Admin - Shell and Producers";
const SIGN_IN = "Admin - Status and sign-in";
const STATUS = "Admin - Status";
const STATUS_STATES = "Admin - Status states";
const DEVICES = "Admin - Devices";
const DEVICE_DIALOGS = "Admin - Devices dialogs";
const LIGHT = "Admin - Light theme check";
const USERS = "Admin - Users";
const USER_DIALOGS = "Admin - Users dialogs";
const EVENTS = "Admin - Events";
const EVENT_STATES = "Admin - Events states";
const EVENT_DIALOGS = "Admin - Events dialogs";

const url = (hash = "") => `${BASE}/admin/${hash}`;
const TOKEN = "x".repeat(40);

/** A piece of the page on its own: the detail pane, at the height of its drawing. */
const pane = (height, selector = ".st2") => ({ drawingSelector: selector, size: { width: 1440, height: height + 8 }, shot: (page) => page.locator(".pane:not(.prompt)").screenshot() });

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

  // ---- Events ----------------------------------------------------------------------------------
  frame("EA", EVENTS, "A", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
  }),
  frame("E1", EVENTS, "E1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
    await page.waitForSelector(".push-row .t2");
  }, pane(840)),
  frame("E2", EVENTS, "E2", async (page) => {
    await mockAdmin(page, { clients: eventClients });
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
    await page.getByRole("tab", { name: /^Pushes/ }).click();
  }, pane(840)),
  frame("E2b", EVENTS, "E2b", async (page) => {
    await mockAdmin(page, { deliveries: otherDeliveries });
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
    await page.getByRole("tab", { name: /^Pushes/ }).click();
  }, pane(700)),
  frame("E3", EVENTS, "E3", async (page) => {
    await mockAdmin(page, { clients: eventClients });
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
    await page.getByRole("tab", { name: /^Pushes/ }).click();
    await page.getByRole("button", { name: "Technical details" }).click();
  }, pane(1180)),
  frame("E4", EVENTS, "E4", async (page) => {
    await mockAdmin(page, { deliveries: { items: [], users: [] } });
    await signedIn(page, `#events/${events[7].id}`, ".pane h2");
    await page.getByRole("tab", { name: /^Pushes/ }).click();
  }, pane(520)),
  frame("E5", EVENTS, "E5", async (page) => {
    await mockAdmin(page, { deliveries: { __status: 500, body: { title: "Internal Server Error" } } });
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
    await page.getByRole("tab", { name: /^Pushes/ }).click();
  }, pane(520)),
  frame("Q1", EVENTS, "Q1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
  }),
  frame("Q2", EVENTS, "Q2", async (page) => {
    await mockAdmin(page);
    await signedIn(page, `#events/${events[1].id}`, ".pane h2");
  }),
  frame("Q3", EVENTS, "Q3", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    await page.getByRole("dialog").getByLabel("Producer").selectOption({ label: "ci-pipeline" });
  }),
  frame("Q4", EVENTS, "Q4", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events?severity=CRITICAL&read=false", ".tr");
    await page.getByRole("button", { name: /^Filters/ }).click();
    await page.waitForTimeout(400);
  }),

  frame("S1", EVENT_STATES, "S1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    for (const index of [0, 1, 2]) await page.getByRole("checkbox", { name: `Select ${events[index].title}` }).click();
  }, { size: { width: 1440, height: 688 } }),
  frame("S2", EVENT_STATES, "S2", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    for (const index of [0, 1, 2]) await page.getByRole("checkbox", { name: `Select ${events[index].title}` }).click();
    await page.getByRole("button", { name: "Delete 3 events" }).click();
    await page.waitForTimeout(300);
  }, { size: { width: 1440, height: 688 } }),
  frame("S3", EVENT_STATES, "S3", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "More" }).click();
  }, { size: { width: 1440, height: 688 } }),
  frame("S4", EVENT_STATES, "S4", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events?severity=HIGH,CRITICAL", ".tr");
    await page.getByRole("button", { name: /^Severity/ }).click();
  }, { size: { width: 1440, height: 688 } }),
  frame("S4b", EVENT_STATES, "S4b", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events?from=2026-10-01&before=2026-10-08", ".tr");
    await page.getByRole("button", { name: /^Received/ }).click();
  }, { size: { width: 1440, height: 688 } }),
  frame("S5", EVENT_STATES, "S5", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events?read=false&severity=CRITICAL", ".tr");
  }, { size: { width: 1440, height: 688 } }),
  frame("L1", EVENT_STATES, "L1", async (page) => {
    await mockAdmin(page, { eventList: () => new Promise(() => {}) });
    await signedIn(page, "#events", ".skeletons");
  }, { size: { width: 1440, height: 688 } }),
  frame("L2", EVENT_STATES, "L2", async (page) => {
    await mockAdmin(page, { eventList: { items: [], nextCursor: null, total: 0 } });
    await signedIn(page, "#events", ".empty");
  }, { size: { width: 1440, height: 688 } }),
  frame("L3", EVENT_STATES, "L3", async (page) => {
    await mockAdmin(page, { eventList: { items: [], nextCursor: null, total: 0 } });
    await signedIn(page, `#events?read=false&severity=CRITICAL&producer=${producers.find((item) => item.name === "homelab-monitor").id}`, ".empty");
  }, { size: { width: 1440, height: 688 } }),
  frame("L4", EVENT_STATES, "L4", async (page) => {
    let calls = 0;
    const { listEvents } = await import("./admin-sample.mjs");
    await mockAdmin(page, { eventList: (request) => ((calls += 1) === 1 ? listEvents(request.url()) : "abort") });
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Refresh", exact: true }).click();
    await page.waitForSelector(".bn.err");
  }, { size: { width: 1440, height: 688 } }),
  frame("L5", EVENT_STATES, "L5", async (page) => {
    await mockAdmin(page, { eventList: "abort" });
    await signedIn(page, "#events", ".empty");
  }, { size: { width: 1440, height: 688 } }),
  frame("F1", EVENT_STATES, "F1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    for (const index of [0, 1, 2]) await page.getByRole("checkbox", { name: `Select ${events[index].title}` }).click();
    await page.getByRole("button", { name: "Delete 3 events" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Delete 3 events" }).click();
    await page.waitForSelector(".snack");
  }, { size: { width: 1440, height: 688 } }),
  frame("F2", EVENT_STATES, "F2", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.locator(".th .cbc").focus();
    await page.keyboard.press("Tab");
  }, { size: { width: 1440, height: 688 } }),

  frame("D1", EVENT_DIALOGS, "D1", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    await page.getByRole("dialog").getByLabel("Producer").selectOption({ label: "ci-pipeline" });
  }, dialog({ drawingSelector: ".dlg" })),
  frame("D2", EVENT_DIALOGS, "D2", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByLabel("Context (optional)").fill("signalhub-web");
    await box.getByLabel("Metadata (optional, a JSON object)").fill('{"branch": main, "run": 42}');
    await box.getByRole("button", { name: "Send", exact: true }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("D2b", EVENT_DIALOGS, "D2b", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByRole("button", { name: "Send", exact: true }).click();
    await page.waitForSelector(".snack");
  }, { size: { width: 1440, height: 688 } }),
  frame("D6", EVENT_DIALOGS, "D6", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Delete events by rule…" }).click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByLabel("Received before").fill("2026-10-01");
  }, dialog({ drawingSelector: ".dlg" })),
  frame("D3", EVENT_DIALOGS, "D3", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Delete events by rule…" }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("D4", EVENT_DIALOGS, "D4", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Delete events by rule…" }).click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByLabel("Received before").fill("2026-10-01");
    await box.getByRole("button", { name: "Count events" }).click();
    await page.waitForSelector(".warn.danger");
  }, dialog({ drawingSelector: ".dlg" })),
  frame("D5", EVENT_DIALOGS, "D5", async (page) => {
    await mockAdmin(page, { deleteCount: 0 });
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Delete events by rule…" }).click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByLabel("Received before").fill("2026-10-01");
    await box.getByRole("button", { name: "Count events" }).click();
    await page.waitForSelector(".dlg .warn");
  }, dialog({ drawingSelector: ".dlg" })),

  // ---- Users -----------------------------------------------------------------------------------
  frame("U1", USERS, "U1", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
    await page.waitForSelector(".tabs2");
  }),
  frame("U3", USERS, "U3", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[1].id}`, ".pane h2");
  }, pane(640, ".pst")),
  frame("U4", USERS, "U4", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[2].id}`, ".pane h2");
  }, pane(640, ".pst")),
  frame("US1", USERS, "US1", async (page) => {
    await mockAdmin(page, { users: () => new Promise(() => {}) });
    await signedIn(page, "#users", ".skeletons");
  }, { size: { width: 1440, height: 600 } }),
  frame("US2", USERS, "US2", async (page) => {
    await mockAdmin(page, { users: [] });
    await signedIn(page, "#users", ".empty");
  }, { size: { width: 1440, height: 600 } }),
  frame("US3", USERS, "US3", async (page) => {
    await mockAdmin(page, { users: drawnUsers.slice(0, 1).concat(drawnUsers.slice(2, 4)), traffic: { __status: 500, body: { title: "Boom" } } });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
  }, { size: { width: 1440, height: 600 } }),
  frame("PU1", USERS, "PU1", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, "#users", ".tr");
  }),
  frame("PU2", USERS, "PU2", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
  }),
  frame("UD1", USER_DIALOGS, "UD1", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, "#users", ".tr");
    await page.getByRole("button", { name: "Invite a user" }).first().click();
    await page.getByRole("dialog").getByLabel("Name").fill("Marta");
  }, dialog({ drawingSelector: ".dlg" })),
  frame("UD1b", USER_DIALOGS, "UD1b", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, "#users", ".tr");
    await page.getByRole("button", { name: "Invite a user" }).first().click();
    await page.getByRole("dialog").getByLabel("Name").fill("Marta");
    await page.getByRole("radio", { name: /^Admin/ }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("UC1", USER_DIALOGS, "UC1", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[3].id}`, ".pane h2");
    await page.getByRole("radio", { name: "Mod" }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("UC2", USER_DIALOGS, "UC2", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
    await page.getByRole("radio", { name: "Admin" }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("UC4", USER_DIALOGS, "UC4", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
    await page.getByRole("button", { name: "Unsubscribe Ana from ci-pipeline" }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("UC6", USER_DIALOGS, "UC6", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
    await page.getByRole("button", { name: "Revoke Ana" }).click();
  }, dialog({ drawingSelector: ".dlg" })),
  frame("UC7", USER_DIALOGS, "UC7", async (page) => {
    await mockAdmin(page, { users: drawnUsers });
    await signedIn(page, `#users/${drawnUsers[0].id}`, ".pane h2");
    await page.getByRole("button", { name: "Rename Ana" }).click();
  }, dialog({ drawingSelector: ".dlg" })),
];

void [ana, rodrigo, rui, health, users, NOW];
