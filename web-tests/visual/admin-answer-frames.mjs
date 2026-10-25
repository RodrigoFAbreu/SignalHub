// The admin page's drawings of questions and answers (docs/design/users/source/Admin - Questions and
// answers.dc.html), served the drawings' own events by mocked answers like the other admin frames.

import { NOW, ana, events, mockAdmin, producers, rodrigo } from "./admin-sample.mjs";
import { signedIn } from "./admin-frames.mjs";

const FILE = "Admin - Questions and answers";
const frame = (id, option, setup, extra = {}) => ({ id, file: FILE, option, world: false, setup, ...extra });
const pane = (height) => ({ drawingSelector: ".st2", size: { width: 1440, height: height + 8 }, shot: (page) => page.locator(".pane:not(.prompt)").screenshot() });

const CLOCK = new Date("2026-10-16T19:12:00");
const at = (text) => new Date(text).toISOString();
const MERGE = [{ id: "merge", label: "Merge", description: "Squash-merge now; CI passed." }, { id: "hold", label: "Hold", description: null }];
const ask = (choices, o = {}) => ({ choices, multiple: false, text: choices.length ? "OPTIONAL" : "REQUIRED", textStyle: choices.length ? "NOTE" : null, closesAt: at("2026-10-17T09:00:00"), whoCanAnswer: [rodrigo, ana], ...o });

/** An event of ci-pipeline that asks, as the listing and the pane read it. */
function question(o = {}) {
  const base = events[2];
  return {
    ...base,
    id: o.id ?? "01997d5e-0000-7000-8000-000000009001",
    title: o.title ?? "Merge R82 into main?",
    message: o.message ?? "CI passed. 3 files changed.",
    category: "ACTION_REQUIRED",
    severity: o.severity ?? "HIGH",
    createdAt: o.createdAt ?? at("2026-10-16T19:00:00"),
    readAt: o.readAt ?? null,
    push: "SENT",
    producer: { id: producers.find((item) => item.name === (o.producer ?? "ci-pipeline")).id, name: o.producer ?? "ci-pipeline" },
    ask: o.ask ?? ask(MERGE),
    answer: o.answer ?? null,
    answerState: o.state ?? "OPEN",
    closedBy: o.closedBy ?? null,
    closedAt: o.closedAt ?? null,
    closeNote: o.closeNote ?? null,
    canAnswer: false,
  };
}

const dialogShot = { drawingSelector: ".dlg", size: { width: 1440, height: 1500 }, shot: (page) => page.locator("[role=dialog]").screenshot() };
const answer = (by, choices, text, via, time) => ({ choices, text, by, via, at: at(time) });

async function open(page, event, data = {}) {
  await mockAdmin(page, { eventDetail: event, ...data });
  await page.clock.setFixedTime(CLOCK);
  await signedIn(page, `#events/${event.id}`, ".pane h2");
  await page.waitForTimeout(200);
}

/** The test dialog of Events with its *Ask for an answer* section open (D1a's state). */
async function askDialog(page) {
  await mockAdmin(page);
  await signedIn(page, "#events", ".tr");
  await page.getByRole("button", { name: "Send a test event" }).first().click();
  const box = page.getByRole("dialog");
  await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
  await box.getByRole("button", { name: /Ask for an answer/ }).click();
  return box;
}

export const adminAnswerFrames = [
  frame("AQ1", "Q1", (page) => open(page, question()), pane(960)),
  frame("AQ1b", "Q1b", (page) => open(page, question({ state: "ANSWERED", answer: answer(ana, ["hold"], "After lunch, the deploy window is busy.", "APP", "2026-10-16T19:02:00") })), pane(1040)),
  frame("AQ1c", "Q1c", (page) => open(page, question({ title: "What goes in release 3.9?", message: null, severity: "NORMAL", producer: "ci-pipeline", state: "ANSWERED", ask: ask([{ id: "b", label: "Backend", description: null }, { id: "c", label: "Client app", description: null }, { id: "p", label: "Python package", description: "The SDK and the signalhub command." }, { id: "d", label: "Docs", description: null }], { multiple: true, text: "NONE", closesAt: null }), answer: answer(rodrigo, ["b", "p"], null, "WEB", "2026-10-16T21:15:00") })), pane(900)),
  frame("AQ1d", "Q1d", (page) => open(page, question({ title: "Which port should staging use?", message: null, severity: "NORMAL", state: "ANSWERED", ask: ask([], { closesAt: at("2026-10-18T12:00:00") }), answer: answer(ana, [], "8443, behind the proxy.", "APP", "2026-10-17T08:41:00") })), pane(640)),
  frame("AQ1e", "Q1e", (page) => open(page, question({ title: "Merge R81 into main?", message: "CI passed. 2 files changed.", state: "CLOSED", closedBy: "TIME", closedAt: at("2026-10-15T09:00:00"), ask: ask([{ id: "merge", label: "Merge", description: null }, { id: "hold", label: "Hold", description: null }], { text: "NONE", closesAt: at("2026-10-15T09:00:00") }) })), pane(780)),
  frame("AQ1h", "Q1h", (page) => open(page, question({ state: "CLOSED", closedBy: "PRODUCER", closedAt: at("2026-10-17T08:41:00"), closeNote: "Answered in the session" })), pane(860)),
  frame("AQ1g", "Q1g", (page) => open(page, question({ state: "ANSWERED", answer: answer(ana, ["hold"], "After lunch, the deploy window is busy.", "APP", "2026-10-16T19:02:00") })), { ...pane(1040), scheme: "light" }),
  frame("AQ3", "Q3", async (page) => {
    await open(page, question());
    await page.getByRole("region", { name: "Merge R82 into main?" }).getByRole("button", { name: "Delete event Merge R82 into main?" }).click();
    await page.waitForTimeout(300);
  }, { drawingSelector: ".st2", size: { width: 1440, height: 900 }, shot: (page) => page.locator("[role=dialog]").screenshot() }),

  frame("AD1q", "D1q", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    await page.getByRole("dialog").getByLabel("Producer").selectOption({ label: "ci-pipeline" });
  }, dialogShot),
  frame("AD1a", "D1a", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByRole("button", { name: /Ask for an answer/ }).click();
  }, dialogShot),
  frame("AD1b", "D1b", async (page) => {
    await mockAdmin(page);
    await signedIn(page, "#events", ".tr");
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const box = page.getByRole("dialog");
    await box.getByLabel("Producer").selectOption({ label: "ci-pipeline" });
    await box.getByRole("button", { name: /Ask for an answer/ }).click();
    const labels = box.getByLabel("Label", { exact: true });
    await labels.nth(0).fill("Merge");
    await box.getByRole("button", { name: "Add description" }).first().click();
    await box.getByLabel("Description (optional)").first().fill("Squash-merge now; CI passed.");
    await labels.nth(1).fill("Hold");
    await box.getByRole("button", { name: "Add choice" }).click();
    await box.getByLabel("Label", { exact: true }).nth(2).fill("Close it");
    await box.getByRole("radiogroup", { name: "Note" }).getByRole("radio", { name: "Optional" }).click();
    await box.getByRole("radiogroup", { name: "Closes" }).getByRole("radio", { name: "In" }).click();
  }, dialogShot),
  // ---- The test dialog's errors and the list (R82b follow-up: their words, order and markers)
  frame("AD1c", "D1c", async (page) => {
    const box = await askDialog(page);
    const labels = box.getByLabel("Label", { exact: true });
    await labels.nth(0).fill("Merge");
    await labels.nth(1).fill("Hold");
    await box.getByRole("button", { name: "Add choice" }).click();
    await labels.nth(2).fill("hold");
    await box.getByRole("button", { name: "Send", exact: true }).click();
  }, dialogShot),
  frame("AD1d", "D1d", async (page) => {
    const box = await askDialog(page);
    const labels = box.getByLabel("Label", { exact: true });
    for (let n = 0; n < 10; n += 1) {
      if (n >= 2) await box.getByRole("button", { name: "Add choice" }).click();
      await labels.nth(n).fill(["Backend", "Client app", "Python package", "Docs", "CI", "Release", "Examples", "Design", "Tests", "Security"][n]);
    }
    await box.getByRole("button", { name: "Add choice" }).click({ force: true });
  }, dialogShot),
  frame("AD1e", "D1e", async (page) => {
    const box = await askDialog(page);
    await box.getByRole("button", { name: "Remove choice 2" }).click();
    await box.getByRole("button", { name: "Remove choice 1" }).click();
  }, dialogShot),
  frame("AD1f", "D1f", async (page) => {
    const box = await askDialog(page);
    await box.getByLabel("Label", { exact: true }).nth(0).fill("Backend");
    await box.getByRole("button", { name: "Remove choice Backend" }).click();
    await box.getByRole("button", { name: "Add choice" }).click();
    await box.getByLabel("Label", { exact: true }).nth(0).fill("Backend");
    await box.getByRole("button", { name: "Remove choice 2" }).click();
    await box.getByRole("radiogroup", { name: "Pick" }).getByRole("radio", { name: "One or more" }).click();
    await box.getByRole("button", { name: "Send", exact: true }).click();
  }, dialogShot),
  frame("AD1i", "D1i", async (page) => {
    const box = await askDialog(page);
    const labels = box.getByLabel("Label", { exact: true });
    await labels.nth(0).fill("Merge");
    await labels.nth(1).fill("Hold");
    await box.getByRole("button", { name: "Add choice" }).click();
    await labels.nth(2).fill("Other");
    await box.getByRole("radiogroup", { name: "Note" }).getByRole("radio", { name: "Optional" }).click();
    await box.getByRole("radiogroup", { name: "Typed answer as" }).getByRole("radio", { name: "Other row" }).click();
    await box.getByRole("button", { name: "Send", exact: true }).click();
  }, dialogShot),
  frame("AL1", "L1", async (page) => {
    const items = [
      question({ title: "Merge R82 into main?" }),
      question({ id: "01997d5e-0000-7000-8000-000000009002", title: "Which port should staging use?", state: "ANSWERED", answer: answer(ana, ["hold"], null, "APP", "2026-10-16T19:02:00") }),
      question({ id: "01997d5e-0000-7000-8000-000000009003", title: "Deploy window for R80?", state: "CLOSED", closedBy: "TIME", closedAt: at("2026-10-15T09:00:00") }),
      question({ id: "01997d5e-0000-7000-8000-000000009004", title: "Restart the proxy?", state: "CLOSED", closedBy: "PRODUCER", closedAt: at("2026-10-15T08:41:00") }),
      events[0],
    ];
    await mockAdmin(page, { eventList: { items, nextCursor: null } });
    await page.clock.setFixedTime(CLOCK);
    await signedIn(page, "#events", ".tr");
    await page.waitForTimeout(300);
  }, { size: { width: 1440, height: 900 } }),
];
