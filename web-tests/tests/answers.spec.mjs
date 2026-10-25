import { asDevice, asProducer, browserSession, createPerson, createProducer, publish, subscribe, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

const MERGE_OR_HOLD = {
  choices: [
    { id: "merge", label: "Merge", description: "Squash-merge now; CI passed." },
    { id: "hold", label: "Hold" },
  ],
  text: "OPTIONAL",
};

// The owner of a producer, signed in on the page, and a question on one of its events.
async function scene(context, page, ask = MERGE_OR_HOLD, event = {}) {
  const owner = await createPerson("MOD");
  const producer = await createProducer(owner, unique("ci"), "PUBLIC");
  const posted = await publish(producer, { title: "Merge R82 into main?", message: "CI passed on all 3 checks.", category: "ACTION_REQUIRED", severity: "HIGH", ask, ...event });
  await useSession(context, await browserSession(owner));
  return { owner, producer, posted };
}

const card = (page) => page.locator(".acard");

test("a question is answered by picking and pressing Send answer, and the card turns into the result", async ({ context, page }) => {
  const { producer, posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);

  await expect(card(page).getByText("Your answer", { exact: true })).toBeVisible();
  await expect(card(page)).toContainText(`Pick one. It goes to ${producer.name} and can't be changed once sent.`);
  // The card sits under the message and above the rest.
  await expect(page.locator(".body")).toContainText("CI passed on all 3 checks.");
  await expect(card(page).getByRole("radio", { name: "Merge" })).toHaveAccessibleDescription("Squash-merge now; CI passed.");
  await expect(card(page).getByLabel("Note (optional)")).toBeVisible();
  await expect(card(page)).toContainText("0 / 3000");

  // Choosing sends nothing.
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await expect(card(page).getByRole("button", { name: "Send answer" })).toBeVisible();
  await card(page).getByLabel("Note (optional)").fill("After lunch");
  await card(page).getByRole("button", { name: "Send answer" }).click();

  const title = card(page).locator(".ahead");
  await expect(title).toHaveText(/^You answered · Merge · \d\d:\d\d$/);
  await expect(card(page)).toContainText("Note: After lunch");
  await expect(card(page)).toContainText(`Sent to ${producer.name}.`);
  await expect(title).toBeFocused();
  await expect(page.locator("#live")).toContainText("You answered · Merge");

  // The list says it in words, and the question left the To answer count.
  await expect(page.locator("a.event-row").first()).toContainText("You answered · Merge");
  const state = await asProducer(producer, "GET", `/api/v1/events/${posted.id}/answer`);
  expect(state.state).toBe("ANSWERED");
  expect(state.answer.choices).toEqual(["merge"]);
  expect(state.answer.text).toBe("After lunch");
  expect(state.answer.via).toBe("WEB");
});

test("Enter in the note adds a line, Ctrl+Enter sends from the note", async ({ context, page }) => {
  const { posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Hold" }).check();
  const note = card(page).getByLabel("Note (optional)");
  await note.fill("one");
  await note.press("Enter");
  await note.pressSequentially("two");
  await expect(note).toHaveValue("one\ntwo");
  await expect(card(page).locator(".res")).toHaveCount(0);

  const send = card(page).getByRole("button", { name: "Send answer" });
  await expect(send).toHaveAttribute("aria-keyshortcuts", "Control+Enter Meta+Enter");
  await note.press("Control+Enter");
  await expect(card(page).locator(".ahead")).toHaveText(/^You answered · Hold/);
  await expect(card(page)).toContainText("Note: one two".replace(" ", "\n"));
});

test("nothing picked says why, moves the focus and is the group's description", async ({ context, page }) => {
  const { posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("button", { name: "Send answer" }).click();
  const group = card(page).getByRole("radiogroup", { name: "Your answer" });
  await expect(group).toHaveAccessibleDescription("Pick an answer to send.");
  await expect(group).toHaveAttribute("aria-invalid", "true");
  await expect(card(page).getByRole("radio", { name: "Merge" })).toBeFocused();
  await expect(page.locator('[role="alert"]')).toHaveCount(0);
});

test("a typed question needs text, counts it and flags text over 3000 without cutting it", async ({ context, page }) => {
  const { posted } = await scene(context, page, { text: "REQUIRED" });
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page)).toContainText("Type your answer.");
  const field = card(page).getByLabel("Your answer", { exact: true });
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(field).toBeFocused();
  await expect(field).toHaveAccessibleDescription(/Type an answer to send\./);

  await field.fill("x".repeat(3043));
  await expect(card(page)).toContainText("3043 / 3000");
  await expect(card(page)).toContainText("Too long: 43 characters over the limit.");
  await expect(field).toHaveValue("x".repeat(3043));
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(field).toBeFocused();
  await field.fill("after lunch");
  await field.press("Control+Enter");
  await expect(card(page).locator(".ahead")).toHaveText("You answered · ‘after lunch’");
  await expect(card(page)).toContainText(/\d\d:\d\d · Sent to /);
});

test("an Other row is the last row, shows its field once picked and keeps its text when left", async ({ context, page }) => {
  const { posted } = await scene(context, page, { choices: [{ id: "a", label: "8443", description: "The usual port." }, { id: "b", label: "9443" }], text: "OPTIONAL", textStyle: "OTHER" });
  await page.goto(`/app/#inbox/${posted.id}`);
  const other = card(page).getByLabel("Your answer for Other");
  await expect(other).toBeHidden();
  await card(page).getByRole("radio", { name: "Other" }).check();
  await expect(other).toBeFocused();
  await expect(card(page).getByRole("radio", { name: "Other" })).toHaveAttribute("aria-controls", "other-field");

  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(other).toHaveAccessibleDescription(/Type your answer for Other\./);
  await expect(other).toBeFocused();

  await other.fill("9000, behind the proxy");
  await card(page).getByRole("radio", { name: "8443" }).check();
  await expect(other).toBeHidden();
  await card(page).getByRole("radio", { name: "Other" }).check();
  await expect(other).toHaveValue("9000, behind the proxy");
  await other.press("Control+Enter");
  await expect(card(page).locator(".ahead")).toHaveText(/^You answered · Other · \d\d:\d\d$/);
  await expect(card(page)).toContainText("Other: 9000, behind the proxy");
});

test("a multiple choice takes several checkboxes and says so in the result", async ({ context, page }) => {
  const { posted } = await scene(context, page, { multiple: true, choices: [{ id: "u", label: "Unit tests" }, { id: "l", label: "Lint" }, { id: "t", label: "Types" }], text: "NONE" });
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page)).toContainText("Pick one or more.");
  await expect(card(page).getByLabel("Note (optional)")).toHaveCount(0);
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(card(page).getByRole("group", { name: "Your answer" })).toHaveAccessibleDescription(/Pick at least one answer\./);
  await card(page).getByRole("checkbox", { name: "Unit tests" }).check();
  await card(page).getByRole("checkbox", { name: "Lint" }).check();
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(card(page).locator(".ahead")).toHaveText(/^You answered · Unit tests, Lint · /);
});

test("someone who may only read sees the choices as a disabled list", async ({ context, page }) => {
  const { owner, producer, posted } = await scene(context, page);
  const reader = await createPerson("BASIC");
  await subscribe(reader, producer);
  await useSession(context, await browserSession(reader));
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page).locator(".ahead")).toHaveText(`${owner.name} answers this`);
  await expect(card(page)).toContainText("You can read the question.");
  await expect(card(page).getByText("Merge", { exact: true })).toBeVisible();
  await expect(card(page).locator("input, button, textarea")).toHaveCount(0);
  await expect(page.locator("a.event-row").first()).toContainText(`Waiting for ${owner.name}`);
});

test("when someone answers first, the 409 swaps the card to the winner at once", async ({ context, page }) => {
  const { owner, producer, posted } = await scene(context, page);
  const ana = await createPerson("BASIC");
  await subscribe(ana, producer);
  await asDevice(owner, "PUT", `/api/v1/client/producers/${producer.id}/answerers/${ana.userId}`);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await asDevice(ana, "PUT", `/api/v1/events/${posted.id}/answer`, { choices: ["hold"] });
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(card(page).locator(".ahead")).toHaveText(`${ana.name} answered first: Hold`);
  await expect(card(page)).toContainText(`Your answer wasn't sent, and ${producer.name} has ${ana.name}'s.`);
  await expect(card(page).locator("input")).toHaveCount(0);
});

test("a question its producer closed says so, with the note", async ({ context, page }) => {
  const { producer, posted } = await scene(context, page);
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`, { note: "Answered in the session" });
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page).locator(".ahead")).toHaveText(`Closed by ${producer.name} · Answered in the session`);
  await expect(card(page)).toContainText(`${producer.name} closed this question on`);
  await expect(page.locator("a.event-row").first()).toContainText(`Closed by ${producer.name}`);
});

test("a long close note goes on its own line in curly quotes", async ({ context, page }) => {
  const { producer, posted } = await scene(context, page);
  const note = "Merged by hand after the review in the linked session.";
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`, { note });
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page).locator(".ahead")).toHaveText(`Closed by ${producer.name}`);
  await expect(card(page)).toContainText(`‘${note}’`);
});

test("closed while choosing: the 409 says the answer wasn't sent", async ({ context, page }) => {
  const { producer, posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`);
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(card(page).locator(".ahead")).toHaveText("Closed while you were choosing · nobody can answer it now");
  await expect(card(page)).toContainText(`Your answer wasn't sent. ${producer.name} closed this question.`);
});

test("an open card follows the server when the tab regains focus", async ({ context, page }) => {
  const { producer, posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page).getByRole("radio", { name: "Merge" })).toBeVisible();
  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`);
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  await expect(card(page).locator(".ahead")).toHaveText(`Closed by ${producer.name}`);
});

test("a failed send keeps what was typed and offers Retry", async ({ context, page }) => {
  const { posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await card(page).getByLabel("Note (optional)").fill("kept");
  await page.route("**/api/v1/events/*/answer", (route) => route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ title: "Unavailable" }) }), { times: 1 });
  await card(page).getByRole("button", { name: "Send answer" }).click();
  const snack = page.locator(".snack");
  await expect(snack).toContainText("Answer not sent");
  await expect(card(page).getByLabel("Note (optional)")).toHaveValue("kept");
  await snack.getByRole("button", { name: "Retry" }).click();
  await expect(card(page).locator(".ahead")).toHaveText(/^You answered · Merge/);
});

test("a 403 on send re-reads the event and shows the read-only card", async ({ context, page }) => {
  const { owner, producer, posted } = await scene(context, page);
  const ana = await createPerson("BASIC");
  await subscribe(ana, producer);
  await asDevice(owner, "PUT", `/api/v1/client/producers/${producer.id}/answerers/${ana.userId}`);
  await useSession(context, await browserSession(ana));
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await asDevice(owner, "DELETE", `/api/v1/client/producers/${producer.id}/answerers/${ana.userId}`);
  await card(page).getByRole("button", { name: "Send answer" }).click();
  await expect(card(page)).toContainText("Your answer wasn't sent. You can no longer answer this question.");
  await expect(card(page).locator("input, button")).toHaveCount(0);
});

test("the To answer chip shows its count, filters, and offers Show all events when nothing is left", async ({ context, page }) => {
  const { producer, posted } = await scene(context, page);
  await publish(producer, { title: "Just an update", category: "INFO", severity: "LOW" });
  await page.goto("/app/#inbox");
  const chip = page.getByRole("button", { name: "To answer, 1" });
  await expect(chip).toBeVisible();
  await expect(page.getByRole("link", { name: "Inbox, 2 unread, 1 to answer" })).toBeVisible();
  await chip.click();
  await expect(page.locator("a.event-row")).toHaveCount(1);
  await expect(page).toHaveURL(/toAnswer=1/);
  await expect(page.getByRole("button", { name: "To answer, 1" })).toHaveAttribute("aria-pressed", "true");

  await asProducer(producer, "POST", `/api/v1/events/${posted.id}/answer/close`);
  await page.reload();
  await expect(page.getByText("Nothing to answer")).toBeVisible();
  await page.getByRole("button", { name: "Show all events" }).click();
  await expect(page.locator("a.event-row")).toHaveCount(2);
  // With nothing to answer and the chip off, it is gone.
  await expect(page.getByRole("button", { name: /To answer/ })).toHaveCount(0);
});

test("with everything read, questions to answer make the Inbox badge a dot named for them", async ({ context, page }) => {
  const { posted } = await scene(context, page);
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(page.getByRole("link", { name: "Inbox, 1 to answer" })).toBeVisible();
  await expect(page.locator(".rail .ndot")).toBeVisible();
  await expect(page.locator(".rail .nbadge")).toHaveCount(0);
});

test("Who can answer: the owner adds a person, and removes them after a confirmation", async ({ context, page }) => {
  const { owner, producer } = await scene(context, page);
  const ana = await createPerson("BASIC");
  await subscribe(ana, producer);
  await page.goto(`/app/#producers/${producer.id}`);
  await expect(page.getByText(`${owner.name} (you)`)).toBeVisible();
  await expect(page.getByText("Owner · can always answer")).toBeVisible();
  await expect(page.getByText("Only you can answer this producer's questions.")).toBeVisible();

  await page.getByRole("button", { name: "Add people who can answer" }).click();
  const dialog = page.getByRole("dialog", { name: "Add people who can answer" });
  await expect(dialog).toContainText(`They also need to be subscribed to get its questions.`);
  await expect(dialog.getByRole("button", { name: "Add", exact: true })).toBeDisabled();
  await dialog.getByRole("checkbox", { name: ana.name }).check();
  await dialog.getByRole("button", { name: "Add", exact: true }).click();
  await expect(page.getByText("Can answer its questions")).toBeVisible();

  await page.getByRole("button", { name: `Remove ${ana.name} from Who can answer` }).click();
  const confirm = page.getByRole("dialog", { name: `Remove ${ana.name}?` });
  await expect(confirm).toContainText("Answers " + ana.name + " already gave stay as they are.");
  await confirm.getByRole("button", { name: "Remove" }).click();
  await expect(page.getByText("Only you can answer this producer's questions.")).toBeVisible();
});

test("an owner who unsubscribed is told to stay subscribed to answer", async ({ context, page }) => {
  const { producer } = await scene(context, page);
  await page.goto(`/app/#producers/${producer.id}`);
  await page.getByRole("switch", { name: "Subscribed" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Unsubscribe" }).click();
  await expect(page.getByText("Stay subscribed to answer")).toBeVisible();
  await expect(page.getByText(`While you're unsubscribed, ${producer.name}'s questions don't reach you, and you can't answer them.`)).toBeVisible();
});

test("a question's words are text, never markup", async ({ context, page }) => {
  const { posted } = await scene(context, page, { choices: [{ id: "a", label: "<img src=x onerror=alert(1)>", description: "<b>bold</b>" }, { id: "b", label: "Hold" }], text: "NONE" });
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page).getByText("<img src=x onerror=alert(1)>")).toBeVisible();
  await expect(card(page).getByText("<b>bold</b>")).toBeVisible();
  await expect(card(page).locator("img, b")).toHaveCount(0);
});

test("at phone width the card fills the screen and nothing scrolls sideways", async ({ context, page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const { posted } = await scene(context, page, { choices: [{ id: "a", label: "A label that is long enough to wrap onto a second line of the narrow screen, really", description: "d ".repeat(200) }, { id: "b", label: "Hold" }], text: "OPTIONAL" });
  await page.goto(`/app/#inbox/${posted.id}`);
  await expect(card(page)).toBeVisible();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
  const box = await card(page).boundingBox();
  expect(box.width).toBeLessThanOrEqual(390);
  await expect(card(page).getByRole("button", { name: "Send answer" })).toBeVisible();
});
