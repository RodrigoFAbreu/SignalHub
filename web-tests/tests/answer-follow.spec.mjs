// An open question on screen follows its end by itself (R86): the page reads the event again every
// 15 seconds while the tab is visible, and swaps the card to its current state. The clock is the
// test's, so no test waits the 15 seconds.

import { asDevice, asProducer, browserSession, createPerson, createProducer, operator, publish, subscribe, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

const MERGE_OR_HOLD = {
  choices: [
    { id: "merge", label: "Merge", description: "Squash-merge now; CI passed." },
    { id: "hold", label: "Hold" },
  ],
  text: "OPTIONAL",
};

const REREAD_MS = 15_000;
const card = (page) => page.locator(".acard");

// The owner of a producer, signed in, with the question open on screen and the page's clock ours.
async function shown(context, page, { ask = MERGE_OR_HOLD, clockAt } = {}) {
  const owner = await createPerson("MOD");
  const producer = await createProducer(owner, unique("ci"), "PUBLIC");
  const posted = await publish(producer, { title: "Merge R86 into main?", message: "CI passed.", category: "ACTION_REQUIRED", severity: "HIGH", ask });
  await useSession(context, await browserSession(owner));
  await page.clock.install(clockAt ? { time: clockAt } : undefined);
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page).getByRole("radio", { name: "Merge" })).toBeVisible();
  return { owner, producer, posted };
}

const draft = (page) => card(page).getByRole("radio", { name: "Merge" }).check();
const later = (page) => page.clock.runFor(REREAD_MS + 500);

test("a question its producer closes is closed on the card within 15 seconds", async ({ context, page }) => {
  const { producer, posted } = await shown(context, page);
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`, { note: "Answered in the session" });
  await later(page);
  await expect(card(page).locator(".ahead")).toHaveText(`Closed by ${producer.name} · Answered in the session`);
});

test("a question its producer closes while a choice is picked says it closed while you were choosing", async ({ context, page }) => {
  const { producer, posted } = await shown(context, page);
  await draft(page);
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`);
  await later(page);
  await expect(card(page).locator(".ahead")).toHaveText("Closed while you were choosing · nobody can answer it now");
  await expect(card(page)).toContainText(`Your answer wasn't sent. ${producer.name} closed this question.`);
  await expect(card(page).locator("input")).toHaveCount(0);
});

async function answeredElsewhere(context, page) {
  const made = await shown(context, page);
  const ana = await createPerson("BASIC");
  await subscribe(ana, made.producer);
  await asDevice(made.owner, "PUT", `/api/v1/client/producers/${made.producer.id}/answerers/${ana.userId}`);
  await asDevice(ana, "PUT", `/api/v1/events/${made.posted.id}/answer`, { choices: ["hold"] });
  return { ...made, ana };
}

test("an answer from elsewhere shows on the card within 15 seconds", async ({ context, page }) => {
  const { ana } = await answeredElsewhere(context, page);
  await later(page);
  await expect(card(page).locator(".ahead")).toContainText(`${ana.name} answered · Hold`);
  await expect(card(page).locator("input")).toHaveCount(0);
});

test("an answer from elsewhere while a choice is picked says who answered first", async ({ context, page }) => {
  const made = await shown(context, page);
  await draft(page);
  const ana = await createPerson("BASIC");
  await subscribe(ana, made.producer);
  await asDevice(made.owner, "PUT", `/api/v1/client/producers/${made.producer.id}/answerers/${ana.userId}`);
  await asDevice(ana, "PUT", `/api/v1/events/${made.posted.id}/answer`, { choices: ["hold"] });
  await later(page);
  await expect(card(page).locator(".ahead")).toHaveText(`${ana.name} answered first: Hold`);
  await expect(card(page)).toContainText(`Your answer wasn't sent, and ${made.producer.name} has ${ana.name}'s.`);
});

test("a deleted event shows as gone within 15 seconds", async ({ context, page }) => {
  const { posted } = await shown(context, page);
  await operator("DELETE", `/api/v1/admin/events/${posted.id}`);
  await later(page);
  await expect(page.getByText("This isn't here")).toBeVisible();
  await expect(card(page)).toHaveCount(0);
});

test("a deleted event shows as gone within 15 seconds even with a choice picked", async ({ context, page }) => {
  const { posted } = await shown(context, page);
  await draft(page);
  await operator("DELETE", `/api/v1/admin/events/${posted.id}`);
  await later(page);
  await expect(page.getByText("This isn't here")).toBeVisible();
});

// The page's clock runs ten minutes behind the server's, so the card's own timer for the closing
// time would fire ten minutes late: only the re-read can tell the question closed.
async function closesOnTheServer(context, page, picked) {
  const closesAt = new Date(Date.now() + 3000).toISOString();
  const made = await shown(context, page, { ask: { ...MERGE_OR_HOLD, closesAt }, clockAt: new Date(Date.now() - 10 * 60_000) });
  if (picked) await draft(page);
  await new Promise((resolve) => setTimeout(resolve, 4000));
  await later(page);
  return made;
}

test("a question that reached its closing time shows closed within 15 seconds", async ({ context, page }) => {
  const { producer } = await closesOnTheServer(context, page, false);
  await expect(card(page).locator(".ahead")).toHaveText("Closed · nobody answered in time");
  await expect(card(page)).toContainText(`${producer.name} got no answer.`);
});

test("a question that reached its closing time while a choice is picked says it closed while you were choosing", async ({ context, page }) => {
  await closesOnTheServer(context, page, true);
  await expect(card(page).locator(".ahead")).toHaveText("Closed while you were choosing · nobody can answer it now");
});

test("the re-reads pause while the tab is hidden and go on when it is visible again", async ({ context, page }) => {
  const { producer, posted } = await shown(context, page);
  const state = (value) => page.evaluate((v) => Object.defineProperty(document, "visibilityState", { configurable: true, get: () => v }), value);
  await state("hidden");
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`);
  let reads = 0;
  page.on("request", (request) => {
    if (request.url().endsWith(`/api/v1/events/${posted.id}`)) reads += 1;
  });
  await page.clock.runFor(REREAD_MS * 4);
  await page.waitForTimeout(500);
  expect(reads).toBe(0);
  await expect(card(page).getByRole("radio", { name: "Merge" })).toBeVisible();
  // Visible again, without the focus event that would read at once: the next tick reads.
  await state("visible");
  await later(page);
  await expect(card(page).locator(".ahead")).toHaveText(`Closed by ${producer.name}`);
});

test("a failed re-read keeps the card as it is, with no error", async ({ context, page }) => {
  const { posted } = await shown(context, page);
  await card(page).getByLabel("Note (optional)").fill("kept");
  await page.route(`**/api/v1/events/${posted.id}`, (route) => route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ title: "Unavailable" }) }));
  await later(page);
  await page.waitForTimeout(500);
  await expect(card(page).getByLabel("Note (optional)")).toHaveValue("kept");
  await expect(page.locator(".snack")).toHaveCount(0);
});

test("the re-reads stop once the question has ended", async ({ context, page }) => {
  const { producer, posted } = await shown(context, page);
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`);
  await later(page);
  await expect(card(page).locator(".ahead")).toHaveText(`Closed by ${producer.name}`);
  let reads = 0;
  page.on("request", (request) => {
    if (request.url().endsWith(`/api/v1/events/${posted.id}`)) reads += 1;
  });
  await page.clock.runFor(REREAD_MS * 4);
  await page.waitForTimeout(500);
  expect(reads).toBe(0);
});
