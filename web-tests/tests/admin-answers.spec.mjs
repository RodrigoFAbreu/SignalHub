import { asDevice, asProducer, createPerson, createProducer, operator, publish, subscribe, unique } from "../support/server.mjs";
import { adminSignIn, expect, test } from "../support/page.mjs";

const ASK = { choices: [{ id: "merge", label: "Merge", description: "Squash-merge now; CI passed." }, { id: "hold", label: "Hold" }], text: "OPTIONAL" };

async function world(ask = ASK, event = {}) {
  const owner = await createPerson("MOD");
  const producer = await createProducer(owner, unique("ci"), "PUBLIC");
  const title = unique("Merge it");
  const sent = await publish(producer, { title, category: "ACTION_REQUIRED", severity: "HIGH", message: "CI passed.", ask, ...event });
  return { owner, producer, sent, title };
}

const open = async (page, producer, id = "") => {
  await adminSignIn(page, `#events${id ? `/${id}` : ""}?producer=${producer.id}`);
  await expect(page.getByRole("heading", { name: "Events", level: 1 })).toBeVisible();
};

const pane = (page) => page.locator(".pane:not(.prompt)");
// The page keeps its token in memory, so a second look goes by the address, never by a new page.
const show = (page, producer, id) => page.evaluate((hash) => { location.hash = hash; }, `#events/${id}?producer=${producer.id}`);

test.describe("desktop", () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test("an open question is read-only text: its rules, its choices, who it waits for", async ({ page }) => {
    const { owner, producer, sent } = await world();
    await open(page, producer, sent.id);
    const box = pane(page).locator(".qbox");
    await expect(box).toContainText("Question");
    await expect(box).toContainText("read-only here");
    await expect(box.locator(".qrules")).toContainText("PickOne");
    await expect(box.locator(".qrules")).toContainText("NoteAllowed, optional");
    await expect(box.locator(".qrules")).toContainText("ClosesNever");
    await expect(box.locator(".qch")).toHaveCount(2);
    await expect(box).toContainText("Squash-merge now; CI passed.");
    await expect(pane(page).locator(".qst.open")).toContainText(`Waiting for an answer · no closing time · ${owner.name} can answer`);
    await expect(pane(page).locator(".qst.open")).toContainText("The admin page cannot answer.");
    // Nothing to press: no radio, no checkbox, no field and no answer button.
    await expect(box.locator("input, textarea, [role=radio], [role=checkbox], button")).toHaveCount(0);
    await expect(pane(page).getByRole("button", { name: /answer/i })).toHaveCount(0);
  });

  test("an answer shows who, when and where, what was chosen, and the note as text", async ({ page }) => {
    const { owner, producer, sent } = await world();
    await asDevice(owner, "PUT", `/api/v1/events/${sent.id}/answer`, { choices: ["hold"], text: "<b>After lunch</b>" });
    await open(page, producer, sent.id);
    await expect(pane(page).locator(".qst.done")).toContainText("Answered");
    await expect(pane(page).locator(".qst.done")).toContainText("Nobody else can answer now.");
    await expect(pane(page).locator(".qst.done")).toHaveAccessibleName("Answered on the web page".replace("on the web page", "in the app"), { timeout: 100 }).catch(() => {});
    const who = pane(page).locator(".qwho");
    await expect(who).toContainText(owner.name);
    await expect(who).toContainText(/\d{1,2} \w{3}, \d\d:\d\d · in the app/);
    await expect(pane(page).locator(".qchose, .kv").filter({ hasText: "Chose" })).toContainText("Hold");
    await expect(pane(page).locator(".qch.pk")).toHaveCount(1);
    await expect(pane(page).locator(".qch.pk")).toContainText("Hold");
    await expect(pane(page).locator(".qch.pk")).toContainText("Picked");
    await expect(pane(page).locator(".qnote")).toContainText(`Note from ${owner.name}`);
    await expect(pane(page).locator(".qnote")).toContainText("<b>After lunch</b>");
    await expect(pane(page).locator(".qnote b")).toHaveCount(0);
  });

  test("closed by its producer says so with the note; a long note goes on its own line", async ({ page }) => {
    const { producer, sent } = await world();
    await asProducer(producer, "POST", `/api/v1/events/${sent.id}/answer/close`, { note: "Answered in the session" });
    await open(page, producer, sent.id);
    await expect(pane(page).locator(".qst.shut b")).toHaveText(`Closed by ${producer.name} · Answered in the session`);
    const long = await world();
    const note = "Merged by hand after the review in the linked session.";
    await asProducer(long.producer, "POST", `/api/v1/events/${long.sent.id}/answer/close`, { note });
    await show(page, long.producer, long.sent.id);
    await expect(pane(page).locator(".qst.shut b")).toHaveText(`Closed by ${long.producer.name}`);
    await expect(pane(page).locator(".qst.shut")).toContainText(`‘${note}’`);
  });

  test("the list marks events that ask, and the Question chip filters them and keeps its value in the address", async ({ page }) => {
    const { owner, producer, sent, title } = await world();
    const answered = await publish(producer, { title: unique("done"), category: "ACTION_REQUIRED", ask: ASK });
    await asDevice(owner, "PUT", `/api/v1/events/${answered.id}/answer`, { choices: ["merge"] });
    const closed = await publish(producer, { title: unique("shut"), category: "ACTION_REQUIRED", ask: ASK });
    await asProducer(producer, "POST", `/api/v1/events/${closed.id}/answer/close`);
    const plain = await publish(producer, { title: unique("plain") });
    await open(page, producer);
    const rows = page.getByRole("grid", { name: "Events" }).getByRole("row");
    await expect(rows.filter({ hasText: title })).toHaveAccessibleName(new RegExp(`, waiting$`));
    await expect(rows.filter({ hasText: answered.title })).toContainText("Answered");
    await expect(rows.filter({ hasText: closed.title })).toContainText("Closed");
    await expect(rows.filter({ hasText: closed.title }).locator(".qmk .ms")).toHaveText("lock");
    await expect(rows.filter({ hasText: plain.title }).locator(".qmk")).toHaveCount(0);
    // Each marker is in its own row, under the title, in the flow of the page (R82b: an older rule
    // took it out of the row and drew them all at one corner).
    for (const row of [rows.filter({ hasText: title }), rows.filter({ hasText: answered.title }), rows.filter({ hasText: closed.title })]) {
      const marker = row.locator(".qmk");
      await expect(marker).toBeVisible();
      await expect(marker).toHaveCSS("position", "static");
      const inside = await marker.evaluate((node) => {
        const box = node.getBoundingClientRect();
        const rowBox = node.closest("[role=row]").getBoundingClientRect();
        const name = node.parentElement.querySelector(".nm").getBoundingClientRect();
        return { within: box.top >= rowBox.top && box.bottom <= rowBox.bottom && box.left >= rowBox.left && box.right <= rowBox.right, below: box.top >= name.bottom - 1, wide: box.width > 40 };
      });
      expect(inside).toEqual({ within: true, below: true, wide: true });
    }

    await page.getByRole("button", { name: "Question", exact: true }).click();
    for (const word of ["Any", "Waiting", "Answered", "Closed", "No question"]) await expect(page.getByRole("menuitemradio", { name: word })).toBeVisible();
    await page.getByRole("menuitemradio", { name: "Waiting" }).click();
    await expect(page).toHaveURL(/question=OPEN/);
    await expect(rows.filter({ hasText: title })).toHaveCount(1);
    await expect(rows.filter({ hasText: plain.title })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Question: Waiting" })).toBeVisible();
    await page.getByRole("button", { name: "Question: Waiting" }).click();
    await page.getByRole("menuitemradio", { name: "No question" }).click();
    await expect(rows.filter({ hasText: plain.title })).toHaveCount(1);
    await expect(rows.filter({ hasText: title })).toHaveCount(0);
    void sent;
  });

  test("deleting an event that asks says it, and a bulk delete counts the questions", async ({ page }) => {
    const { owner, producer, sent, title } = await world();
    await open(page, producer, sent.id);
    await page.getByRole("region", { name: title }).getByRole("button", { name: `Delete event ${title}` }).click();
    const dialog = page.getByRole("dialog", { name: "Delete this event?" });
    await expect(dialog).toContainText(`${title} is waiting for an answer from ${owner.name}. Its question goes with it, and ${producer.name} gets no answer. This cannot be undone.`);
    await dialog.getByRole("button", { name: "Cancel" }).click();

    const plain = await publish(producer, { title: unique("plain") });
    await page.getByRole("button", { name: "Refresh" }).click();
    const rows = page.getByRole("grid", { name: "Events" }).getByRole("row");
    await expect(rows.filter({ hasText: plain.title })).toBeVisible();
    await page.getByRole("checkbox", { name: `Select ${title}` }).click();
    await page.getByRole("checkbox", { name: `Select ${plain.title}` }).click();
    await page.getByRole("toolbar", { name: "Selected events" }).getByRole("button", { name: "Delete 2 events" }).click();
    const bulk = page.getByRole("dialog", { name: "Delete 2 events?" });
    await expect(bulk).toContainText("2 events will be deleted, 1 of them with a question. Their questions and any answers go too. This cannot be undone.");
    await bulk.getByRole("button", { name: "Cancel" }).click();
  });

  test("the rule delete counts the events that ask in its dry run", async ({ page }) => {
    const { producer } = await world();
    await open(page, producer);
    await page.getByRole("button", { name: "More" }).click();
    await page.getByRole("menuitem", { name: "Delete events by rule…" }).click();
    const dialog = page.getByRole("dialog", { name: "Delete events by rule" });
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    await dialog.getByRole("button", { name: "Count events" }).click();
    await expect(dialog).toContainText("1 event will be deleted, 1 of them with a question.");
    await expect(dialog).toContainText("Their questions and any answers go too.");
    await dialog.getByRole("button", { name: "Change rule" }).click();
    await dialog.getByRole("button", { name: "Cancel" }).click();
  });

  test("Send a test event: the section is folded, builds a question, and the snack bar says who was asked", async ({ page }) => {
    const { owner, producer } = await world();
    await open(page, producer);
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    const toggle = dialog.getByRole("button", { name: /Ask for an answer/ });
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await expect(dialog).toContainText("Add choices or a typed answer. Off: the event asks nothing.");
    await dialog.getByLabel("Title").fill("Merge R82 into main?");
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    await expect(dialog).toContainText(`Answers come from ${owner.name}, in the app or on the web page. The admin page cannot answer.`);
    const labels = dialog.getByLabel("Label", { exact: true });
    await labels.nth(0).fill("Merge");
    await expect(dialog).toContainText("ID: merge");
    await dialog.getByRole("button", { name: "Add description" }).first().click();
    await dialog.getByLabel("Description (optional)").first().fill("Squash-merge now; CI passed.");
    await labels.nth(1).fill("Close it");
    await expect(dialog).toContainText("ID: close-it");
    await dialog.getByRole("radiogroup", { name: "Note" }).getByRole("radio", { name: "Optional" }).click();
    await dialog.getByRole("radiogroup", { name: "Closes" }).getByRole("radio", { name: "In" }).click();
    await dialog.getByLabel("Time", { exact: true }).fill("2");
    await expect(dialog).toContainText(/Closes \d+ \w+, \d\d:\d\d, your time\. At most 30 days ahead\./);
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(page.locator(".snack, [role=status]").filter({ hasText: "Sent “Merge R82 into main?”" })).toContainText(`asking ${owner.name}`);

    // The event is a question, with the ids the dialog derived.
    const listed = await operator("GET", `/api/v1/events?producerId=${producer.id}&limit=5`);
    const made = listed.items.find((item) => item.title === "Merge R82 into main?");
    expect(made.ask.choices.map((choice) => choice.id)).toEqual(["merge", "close-it"]);
    expect(made.ask.choices[0].description).toBe("Squash-merge now; CI passed.");
    expect(made.ask.text).toBe("OPTIONAL");
    expect(made.ask.closesAt).not.toBeNull();
    expect(made.answerState).toBe("OPEN");
  });

  test("errors are on the field: the same label twice, a pick of several with one choice, a closing time in the past", async ({ page }) => {
    const { producer } = await world();
    await open(page, producer);
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    await dialog.getByRole("button", { name: /Ask for an answer/ }).click();
    const labels = dialog.getByLabel("Label", { exact: true });
    await labels.nth(0).fill("Merge");
    await labels.nth(1).fill("merge");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toContainText("Another choice is already called Merge. Labels must differ, ignoring capitals.");
    await expect(labels.nth(1)).toBeFocused();
    await labels.nth(1).fill("");
    await dialog.getByRole("radiogroup", { name: "Pick" }).getByRole("radio", { name: "One or more" }).click();
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toContainText("Picking one or more needs at least 2 choices. Add another, or pick One.");
    await dialog.getByRole("radiogroup", { name: "Pick" }).getByRole("radio", { name: "One", exact: true }).click();
    await dialog.getByRole("radiogroup", { name: "Closes" }).getByRole("radio", { name: "At" }).click();
    await dialog.getByLabel("Day").fill("2020-01-01");
    await dialog.getByLabel("Time", { exact: true }).fill("09:00");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toContainText("Pick a time in the future.");
  });

  test("with no choices the question is typed and a note is required; an Other row locks the note to Optional", async ({ page }) => {
    const { producer } = await world();
    await open(page, producer);
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    await dialog.getByRole("button", { name: /Ask for an answer/ }).click();
    await dialog.getByRole("button", { name: "Remove choice 2" }).click();
    await dialog.getByRole("button", { name: "Remove choice 1" }).click();
    await expect(dialog).toContainText("No choices: the answer is typed, and the person must type one.");
    // Frame D1e: the line comes first, then Add choice.
    const line = dialog.getByText("No choices: the answer is typed.", { exact: true });
    const add = dialog.getByRole("button", { name: "Add choice" });
    const [lineBox, addBox] = [await line.boundingBox(), await add.boundingBox()];
    expect(lineBox.y + lineBox.height).toBeLessThanOrEqual(addBox.y + 1);
    await expect(dialog.getByRole("radiogroup", { name: "Pick" })).toHaveCount(0);
    await dialog.getByRole("button", { name: "Add choice" }).click();
    await dialog.getByRole("button", { name: "Add choice" }).click();
    const labels = dialog.getByLabel("Label", { exact: true });
    await labels.nth(0).fill("8443");
    await labels.nth(1).fill("9443");
    const note = dialog.getByRole("radiogroup", { name: "Note" });
    await note.getByRole("radio", { name: "Required" }).click();
    await dialog.getByRole("radiogroup", { name: "Typed answer as" }).getByRole("radio", { name: "Other row" }).click();
    await expect(note.getByRole("radio", { name: "Optional" })).toHaveAttribute("aria-checked", "true");
    await expect(note.getByRole("radio", { name: "None" })).toHaveAttribute("aria-disabled", "true");
    await expect(dialog).toContainText("With an Other row, typing is optional: the person picks a choice or Other.");
  });

  test("Producers shows who can answer, read-only: the owner and the answerers", async ({ page }) => {
    const { owner, producer } = await world();
    const ana = await createPerson("BASIC");
    await subscribe(ana, producer);
    await asDevice(owner, "PUT", `/api/v1/client/producers/${producer.id}/answerers/${ana.userId}`);
    await adminSignIn(page, `#producers/${producer.id}`);
    const section = page.locator(".lab", { hasText: "Who can answer" });
    await expect(section).toContainText("set by the producer's owner");
    const rows = page.locator(".who-row");
    await expect(rows).toHaveCount(2);
    await expect(rows.nth(0)).toContainText(owner.name);
    await expect(rows.nth(0)).toContainText("Owner");
    await expect(rows.nth(1)).toContainText(ana.name);
    await expect(rows.nth(1)).toContainText("Answerer");
    await expect(rows.locator("button, input")).toHaveCount(0);
    await expect(page.getByText("The admin page cannot change it.")).toBeVisible();
  });

  test("a question's words are text, never markup", async ({ page }) => {
    const { producer, sent } = await world({ choices: [{ id: "a", label: "<img src=x onerror=alert(1)>", description: "<b>bold</b>" }, { id: "b", label: "Hold" }], text: "NONE" });
    await open(page, producer, sent.id);
    await expect(pane(page).getByText("<img src=x onerror=alert(1)>")).toBeVisible();
    await expect(pane(page).locator(".qch img, .qch b")).toHaveCount(0);
  });

  test("the dialog's choice rows: a placeholder, a remove button named by its label, and the errors as drawn", async ({ page }) => {
    const { producer } = await world();
    await open(page, producer);
    await page.getByRole("button", { name: "Send a test event" }).first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Producer").selectOption({ label: producer.name });
    await dialog.getByRole("button", { name: /Ask for an answer/ }).click();
    const labels = dialog.getByLabel("Label", { exact: true });
    await expect(labels.nth(0)).toHaveAttribute("placeholder", "For example: Merge");
    await expect(labels.nth(1)).toHaveAttribute("placeholder", "For example: Hold");
    // Empty: named by position; with a label: by the label.
    await expect(dialog.getByRole("button", { name: "Remove choice 1", exact: true })).toBeVisible();
    await labels.nth(0).fill("Merge");
    await labels.nth(1).fill("Hold");
    await expect(dialog.getByRole("button", { name: "Remove choice Merge", exact: true })).toBeVisible();
    await expect(dialog.getByRole("button", { name: "Remove choice Hold", exact: true })).toBeVisible();
    await expect(dialog.getByRole("button", { name: "Remove choice 1", exact: true })).toHaveCount(0);

    // D1i: a choice called Other with an Other row.
    await dialog.getByRole("button", { name: "Add choice" }).click();
    await labels.nth(2).fill("Other");
    await dialog.getByRole("radiogroup", { name: "Note" }).getByRole("radio", { name: "Optional" }).click();
    await dialog.getByRole("radiogroup", { name: "Typed answer as" }).getByRole("radio", { name: "Other row" }).click();
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toContainText("A choice cannot be called Other while the question has an Other row. Rename it, or type the answer as a Note.");
    await dialog.getByRole("radiogroup", { name: "Typed answer as" }).getByRole("radio", { name: "Note" }).click();
    await labels.nth(2).fill("Third");

    // D1c: the duplicate names the earlier choice as it was typed.
    await labels.nth(2).fill("hold");
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toContainText("Another choice is already called Hold. Labels must differ, ignoring capitals.");

    // D1d: at 10, Add choice says why.
    await labels.nth(2).fill("Third");
    for (let n = 3; n < 10; n += 1) {
      await dialog.getByRole("button", { name: "Add choice" }).click();
      await labels.nth(n).fill(`Choice ${n}`);
    }
    await dialog.getByRole("button", { name: "Add choice" }).click({ force: true });
    await expect(dialog).toContainText("At most 10 choices. Remove one to add another.");

    // D1f: one or more with a single choice.
    for (let n = 9; n >= 1; n -= 1) await dialog.getByRole("button", { name: /^Remove choice / }).last().click();
    await dialog.getByRole("radiogroup", { name: "Pick" }).getByRole("radio", { name: "One or more" }).click();
    await dialog.getByRole("button", { name: "Send", exact: true }).click();
    await expect(dialog).toContainText("Picking one or more needs at least 2 choices. Add another, or pick One.");
  });
});

test.describe("phone", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("the question block fits the screen with no sideways scroll, ", async ({ page }) => {
    const { owner, producer, sent } = await world();
    await asDevice(owner, "PUT", `/api/v1/events/${sent.id}/answer`, { choices: ["merge"] });
    await open(page, producer);
    await show(page, producer, sent.id);
    await expect(pane(page).locator(".qbox")).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0);
  });
  test("on a phone each question marker joins its row", async ({ page }) => {
    const { producer, title } = await world();
    await open(page, producer);
    const row = page.getByRole("grid", { name: "Events" }).getByRole("row").filter({ hasText: title });
    const marker = row.locator(".qmk");
    await expect(marker).toBeVisible();
    await expect(marker).toContainText("Waiting");
    const within = await marker.evaluate((node) => {
      const box = node.getBoundingClientRect();
      const rowBox = node.closest("[role=row]").getBoundingClientRect();
      return box.top >= rowBox.top && box.bottom <= rowBox.bottom && box.right <= rowBox.right;
    });
    expect(within).toBe(true);
  });
});
