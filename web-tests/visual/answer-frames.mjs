// The drawings of answering an event on the users' web page (docs/design/users/source/Web -
// Answering an event.dc.html), compared with the page. Like the admin page's frames they ask for no
// sample world (`world: false`): the page is served the drawings' own people and events by mocked
// answers, so the frames need no empty database and show the same words every time.

import { BASE } from "../support/server.mjs";

const FILE = "Web - Answering an event";
const url = (hash = "") => `${BASE}/app/${hash}`;

const ME = { id: "01997d5e-0000-7000-8000-00000000bbbb", name: "Rodrigo" };
const ANA = { id: "01997d5e-0000-7000-8000-00000000cccc", name: "Ana" };
const RUI = { id: "01997d5e-0000-7000-8000-00000000dddd", name: "Rui" };
const OPEN_ID = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b";

const at = (daysAgo, hour, minute) => {
  const date = new Date();
  date.setDate(date.getDate() - daysAgo);
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
};

// The drawing's "Received 2026-10-16 18:50" and "closed on 17 Oct at 09:00" are fixed times; the page
// shows what the mocked data says, so these are the dates of the drawing.
const RECEIVED = new Date(2026, 9, 16, 18, 50).toISOString();
const CLOSED_AT = new Date(2026, 9, 17, 9, 0).toISOString();
const CLOSED_BY_PRODUCER_AT = new Date(2026, 9, 17, 8, 41).toISOString();

const choice = (label, description = null, id = label.toLowerCase().replace(/[^a-z0-9]+/g, "-")) => ({ id, label, description });

const MERGE = [choice("Merge", "Squash-merge now; CI passed."), choice("Hold")];
const CHECKS = [
  choice("Unit tests", "About 2 minutes."),
  choice("Integration tests", "Starts the database; about 8 minutes."),
  choice("Lint"),
  choice("Security scan", "Checks dependencies against known advisories. Runs after the other checks."),
];
const PORT = [choice("8443", "The usual HTTPS port behind the proxy."), choice("9443")];
const LONG_LABEL = "Merge now, tag 3.4.1 and deploy it to staging, then to production after all of its smoke tests pass.";
const LONG_DESCRIPTION = `${"This squash-merges the branch into main, creates the tag 3.4.1 and starts the staging deploy. ".repeat(10)}`.slice(0, 1000);

function ask(choices, { multiple = false, text = choices.length ? "OPTIONAL" : "REQUIRED", textStyle = choices.length && text !== "NONE" ? "NOTE" : null, closesAt = null, who = [ME] } = {}) {
  return { choices, multiple, text, textStyle, closesAt, whoCanAnswer: who };
}

/** An event as the server serves it to this page. */
function event(o) {
  const asking = o.ask !== undefined && o.ask !== null;
  return {
    id: o.id,
    producer: { id: "01997d5e-0000-7000-8000-000000000001", name: o.producer ?? "ci-pipeline" },
    context: null,
    category: o.category ?? "ACTION_REQUIRED",
    severity: o.severity ?? "NORMAL",
    title: o.title,
    message: o.message ?? null,
    metadata: {},
    link: o.link ?? null,
    occurredAt: null,
    createdAt: o.at,
    readAt: o.unread ? null : o.at,
    ask: o.ask ?? null,
    answer: o.answer ?? null,
    answerState: asking ? (o.state ?? "OPEN") : null,
    closedBy: o.closedBy ?? null,
    closedAt: o.closedAt ?? null,
    closeNote: o.closeNote ?? null,
    canAnswer: asking && (o.state ?? "OPEN") === "OPEN" ? Boolean(o.can) : false,
  };
}

const answered = (by, choices, text = null, time = [19, 2]) => ({ choices, text, by, via: "WEB", at: at(0, ...time) });

const MERGE_LINK = "https://example.org/pipelines/r82";

/** The open event of a frame. */
const openEvent = (o = {}) =>
  event({ id: OPEN_ID, title: "Merge R82 into main?", severity: "HIGH", message: "CI passed on all 3 checks. 3 files changed.", link: MERGE_LINK, at: RECEIVED, ask: ask(MERGE, { closesAt: at(0, 9, 0) }), can: true, ...o });

/** The list of the drawings: the open event first, then the same rows in every frame. */
function rows(open) {
  return [
    open,
    event({ id: "r2", title: "Which backup should I restore?", category: "BLOCKED", severity: "HIGH", producer: "backup-jobs", at: at(0, 18, 20), ask: ask([choice("Last night"), choice("Last week")]), can: true }),
    event({ id: "r3", title: "Merge R81 into main?", at: at(0, 17, 40), ask: ask(MERGE), state: "ANSWERED", answer: answered(ME, ["merge"]) }),
    event({ id: "r4", title: "Restart the proxy?", producer: "homelab-monitor", at: at(0, 16, 5), ask: ask(MERGE), state: "ANSWERED", answer: answered(ANA, ["hold"], null, [18, 55]) }),
    event({ id: "r5", title: "Deploy window for R80?", at: at(1, 9, 0), ask: ask(MERGE), state: "CLOSED", closedBy: "TIME", closedAt: CLOSED_AT }),
    event({ id: "r6", title: "Nightly backup finished", category: "COMPLETED", severity: "LOW", producer: "backup-jobs", at: at(1, 3, 0), unread: true }),
    event({ id: "r7", title: "Weekly report is ready", category: "INFO", producer: "ana-reports", at: at(2, 8, 0), unread: true }),
    event({ id: "r8", title: "Publish the weekly report?", producer: "ana-reports", at: at(3, 8, 0), ask: ask(MERGE, { who: [ANA] }) }),
  ];
}

async function mockPage(page, { open, list, person = ME, role = "ADMIN", unread = 2, toAnswer = 2 }) {
  const json = (body, status = 200) => (route) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(body) });
  const events = [open, ...list.filter((e) => e.id !== open.id)];
  await page.route("**/api/v1/web/session", json({
    csrfToken: "sample-csrf",
    client: { id: "01997d5e-0000-7000-8000-00000000aaaa", name: "Firefox on Linux", kind: "BROWSER", admin: role === "ADMIN", user: { id: person.id, name: person.name, role }, createdAt: new Date(Date.now() - 86_400_000).toISOString(), expiresAt: new Date(Date.now() + 29 * 86_400_000).toISOString(), lastActiveAt: null, revokedAt: null },
  }));
  await page.route("**/api/v1/events/unread-count", json({ unread, toAnswer }));
  await page.route(/\/api\/v1\/events\?/, async (route) => {
    const query = new URL(route.request().url()).searchParams;
    const shown = query.get("toAnswer") === "true" ? events.filter((e) => e.answerState === "OPEN" && e.canAnswer) : events;
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ items: shown, nextCursor: null }) });
  });
  await page.route(/\/api\/v1\/events\/[^/?]+\/read$/, (route) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(open) }));
  await page.route(/\/api\/v1\/events\/(?!unread-count)[^/?]+$/, (route) => {
    const id = route.request().url().split("/").pop();
    return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(events.find((e) => e.id === id) ?? open) });
  });
  await page.route("**/api/v1/client/visible-producers", json({ items: [] }));
}

async function ready(page, hash) {
  await page.goto(url(hash));
  await page.waitForSelector("nav.rail", { timeout: 15000, state: "attached" });
  await page.waitForSelector(".acard, a.event-row:visible", { timeout: 15000 });
  await page.waitForTimeout(400);
}

/** The event pane of the drawings' turn 1: the event open beside the list. */
const pane = (open, options = {}) => async (page) => {
  await mockPage(page, { open, list: rows(open), ...options });
  await ready(page, `#inbox/${open.id}`);
  if (options.after) await options.after(page);
};

const typed = (text) => async (page) => {
  await page.locator(".acard textarea").first().fill(text);
};

function eventFrame(id, option, label, open, options = {}, extra = {}) {
  return { id: `AW${id}`, file: FILE, option, world: false, setup: pane(open, options), ...extra };
}

const TYPED_ASK = ask([], { text: "REQUIRED" });
const typedEvent = (o = {}) => openEvent({ title: "What should the R82 release notes say?", message: "Write one or two lines for the changelog.", link: null, ask: TYPED_ASK, ...o });
const portEvent = (a, o = {}) => openEvent({ title: "Which port should staging use?", severity: "NORMAL", message: "The proxy can forward either port.", link: null, ask: a, ...o });
const checksEvent = (a, o = {}) => openEvent({ title: "Which checks should run on R82?", severity: "NORMAL", message: "Pick what to include in this run.", link: null, ask: a, ...o });
const WHO_RA = [ME, ANA];

export const answerFrames = [
  eventFrame("1a", "1a", "single choice with a description", openEvent({ ask: ask(MERGE, { closesAt: at(0, 9, 0) }) }), { after: async (page) => { await page.locator(".acard input").first().check(); } }),
  eventFrame("1b", "1b", "multiple choice with descriptions", checksEvent(ask(CHECKS, { multiple: true })), { after: async (page) => { await page.locator(".acard input").nth(0).check(); await page.locator(".acard input").nth(1).check(); } }),
  eventFrame("1c", "1c", "a typed question only", typedEvent(), { after: async (page) => { await typed("Answers can now carry a note. Sending twice is harmless.")(page); } }),
  eventFrame("1e", "1e", "you answered", openEvent({ state: "ANSWERED", can: false, answer: answered(ME, ["merge"], "After lunch") })),
  eventFrame("1f", "1f", "someone else answered", openEvent({ state: "ANSWERED", can: false, answer: answered(ANA, ["hold"], null, [18, 55]) })),
  eventFrame("1g", "1g", "closed with no answer", openEvent({ title: "Deploy window for R80?", message: "Open until 09:00.", link: null, severity: "NORMAL", state: "CLOSED", closedBy: "TIME", closedAt: CLOSED_AT })),
  eventFrame("1h", "1h", "open, but you may not answer", openEvent({ can: false, ask: ask(MERGE, { who: WHO_RA }) }), { person: RUI, role: "BASIC" }),
  eventFrame("1j", "1j", "someone answered first", openEvent({ state: "ANSWERED", can: false, answer: answered(ANA, ["hold"], null, [18, 55]) }), { after: null }),
  eventFrame("1k", "1k", "it closes soon", openEvent({ title: "Deploy window for R80?", message: "Open until 09:00.", link: null, severity: "NORMAL", ask: ask([choice("Deploy now"), choice("Deploy tomorrow")], { text: "NONE", closesAt: new Date(Date.now() + 12 * 60_000).toISOString() }) })),
  eventFrame("1l", "1l", "the text is too long", typedEvent(), { after: async (page) => { await typed("Answers can now carry a note. Sending twice is harmless. ".repeat(60).slice(0, 3043))(page); await page.getByRole("button", { name: "Send answer" }).click(); } }),
  eventFrame("1n", "1n", "keyboard: the focus ring", openEvent({ ask: ask(MERGE, { closesAt: at(0, 9, 0) }) }), { after: async (page) => { await page.locator(".acard input").first().check(); await page.keyboard.press("Tab"); await page.keyboard.press("Shift+Tab"); } }),
  eventFrame("1m", "1m", "nothing picked", openEvent({ ask: ask(MERGE, { text: "NONE" }) }), { after: async (page) => { await page.getByRole("button", { name: "Send answer" }).click(); } }),
  eventFrame("1o", "1o", "light theme", openEvent(), {}, { scheme: "light" }),
  eventFrame("1q", "1q", "you answered a typed question", typedEvent({ state: "ANSWERED", can: false, answer: answered(ME, [], "after lunch") })),
  eventFrame("1r", "1r", "an Other row, picked", portEvent(ask(PORT, { textStyle: "OTHER" })), { after: async (page) => { await page.getByRole("radio", { name: "Other" }).check(); await page.getByLabel("Your answer for Other").fill("9000, behind the proxy"); } }),
  eventFrame("1r3", "1r3", "Other picked, field empty", portEvent(ask(PORT, { textStyle: "OTHER" })), { after: async (page) => { await page.getByRole("radio", { name: "Other" }).check(); await page.getByRole("button", { name: "Send answer" }).click(); } }),
  eventFrame("1s", "1s", "you answered with Other", portEvent(ask(PORT, { textStyle: "OTHER" }), { state: "ANSWERED", can: false, answer: answered(ME, [], "9000, behind the proxy") })),
  eventFrame("1t", "1t", "closed by the producer", openEvent({ state: "CLOSED", can: false, closedBy: "PRODUCER", closedAt: CLOSED_BY_PRODUCER_AT, closeNote: "Answered in the session" })),
  eventFrame("1t2", "1t2", "closed by the producer, a long note", openEvent({ state: "CLOSED", can: false, closedBy: "PRODUCER", closedAt: CLOSED_BY_PRODUCER_AT, closeNote: "Merged by hand after the review in the linked session; the release notes were updated there too." })),
  eventFrame("1u", "1u", "a 100-character label and a 1000-character description", openEvent({ ask: ask([choice(LONG_LABEL, LONG_DESCRIPTION, "merge"), choice("Hold")]) })),

  // ---- The inbox (turn 2)
  ...[
    ["2a", "2a", {}, { unread: 3, toAnswer: 2 }],
    ["2b", "2b", { hash: "#inbox?toAnswer=1" }, { unread: 0, toAnswer: 2 }],
  ].map(([id, option, { hash = `#inbox/${OPEN_ID}` }, counts]) => ({
    id: `AW${id}`,
    file: FILE,
    option,
    world: false,
    setup: async (page) => {
      const open = openEvent({ unread: id === "2a" });
      await mockPage(page, { open, list: rows(open), ...counts });
      await ready(page, hash);
    },
  })),
  {
    id: "AW2c",
    file: FILE,
    option: "2c",
    world: false,
    setup: async (page) => {
      const open = openEvent();
      await mockPage(page, { open, list: [], unread: 3, toAnswer: 0 });
      await page.goto(url("#inbox?toAnswer=1"));
      await page.waitForSelector(".empty", { timeout: 15000 });
      await page.waitForTimeout(400);
    },
  },

  // ---- The phone (turn 3)
  {
    id: "AW3a",
    file: FILE,
    option: "3a",
    world: false,
    setup: async (page) => {
      const open = openEvent();
      await mockPage(page, { open, list: rows(open), unread: 2, toAnswer: 2 });
      await ready(page, "#inbox");
    },
  },
  {
    id: "AW3b",
    file: FILE,
    option: "3b",
    world: false,
    setup: pane(openEvent()),
  },
  {
    id: "AW3c",
    file: FILE,
    option: "3c",
    world: false,
    setup: pane(openEvent({ state: "ANSWERED", can: false, answer: answered(ME, ["merge"], "After lunch") })),
  },
];

