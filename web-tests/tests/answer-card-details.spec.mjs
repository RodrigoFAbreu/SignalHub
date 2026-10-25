// The small mismatches the test of answering an event (R82b) found on the answer card of the users'
// page: the tooltip, the note field's label, the result's focus ring, and a question that closes by
// its own time.

import { browserSession, createPerson, createProducer, publish, unique, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

const MERGE_OR_HOLD = {
  choices: [
    { id: "merge", label: "Merge", description: "Squash-merge now; CI passed." },
    { id: "hold", label: "Hold" },
  ],
  text: "OPTIONAL",
};

async function scene(context, ask = MERGE_OR_HOLD) {
  const owner = await createPerson("MOD");
  const producer = await createProducer(owner, unique("ci"), "PUBLIC");
  const posted = await publish(producer, { title: "Merge R82 into main?", message: "CI passed on all 3 checks.", category: "ACTION_REQUIRED", severity: "HIGH", ask });
  await useSession(context, await browserSession(owner));
  return { owner, producer, posted };
}

const card = (page) => page.locator(".acard");

test("the Send answer tooltip sits below the button and never covers the error line above it", async ({ context, page }) => {
  const { posted } = await scene(context);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await card(page).getByLabel("Note (optional)").fill("x".repeat(3043));
  const send = card(page).getByRole("button", { name: "Send answer" });
  await send.click();
  await expect(card(page)).toContainText("Too long: 43 characters over the limit.");
  // The mouse stays on the button after the click, so the tip is showing.
  const tip = card(page).locator(".tip");
  await expect(tip).toHaveCSS("opacity", "1");
  const tipBox = await tip.boundingBox();
  const buttonBox = await send.boundingBox();
  const errorBox = await card(page).locator(".hl").boundingBox();
  expect(tipBox.y).toBeGreaterThanOrEqual(buttonBox.y + buttonBox.height);
  expect(tipBox.y).toBeGreaterThanOrEqual(errorBox.y + errorBox.height);
});

test("a note past four lines scrolls inside the field, its text never under the label", async ({ context, page }) => {
  const { posted } = await scene(context);
  await page.goto(`/app/#inbox/${posted.id}`);
  const note = card(page).getByLabel("Note (optional)");
  await note.fill("a line\n".repeat(12));
  const fieldBox = await card(page).locator(".tf.ta").boundingBox();
  const labelBox = await card(page).locator(".tf.ta .fl").boundingBox();
  const textBox = await note.boundingBox();
  // The text area starts below the label's bottom edge, so scrolled text is clipped there.
  expect(textBox.y).toBeGreaterThanOrEqual(labelBox.y + labelBox.height);
  expect(textBox.y + textBox.height).toBeLessThanOrEqual(fieldBox.y + fieldBox.height);
  expect(await note.evaluate((node) => node.scrollHeight > node.clientHeight)).toBe(true);
  // Up to four lines the field still grows to fit its text.
  await note.fill("one\ntwo");
  expect((await note.boundingBox()).height).toBe(48);
});

test("the focus ring of the result title has room around the text", async ({ context, page }) => {
  const { posted } = await scene(context);
  await page.goto(`/app/#inbox/${posted.id}`);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  // By keyboard, as the shortcut is: the radio, Tab to the note, then Ctrl+Enter.
  await page.keyboard.press("Tab");
  await expect(card(page).getByLabel("Note (optional)")).toBeFocused();
  await page.keyboard.press("Control+Enter");
  const title = card(page).locator(".ahead");
  await expect(title).toBeFocused();
  const room = await title.evaluate((node) => {
    const style = getComputedStyle(node);
    const text = document.createRange();
    text.selectNodeContents(node);
    const box = node.getBoundingClientRect();
    const glyphs = text.getBoundingClientRect();
    return { ring: style.outlineStyle !== "none" && style.outlineWidth === "2px", left: glyphs.left - box.left, top: glyphs.top - box.top };
  });
  expect(room.ring).toBe(true);
  expect(room.left).toBeGreaterThanOrEqual(8);
  expect(room.top).toBeGreaterThanOrEqual(3);
});

async function closesSoon(context, page, seconds = 4) {
  const closesAt = new Date(Date.now() + seconds * 1000).toISOString();
  const made = await scene(context, { ...MERGE_OR_HOLD, closesAt });
  await page.goto(`/app/#inbox/${made.posted.id}`);
  return made;
}

test("a question that closes by its time while a choice is picked says it closed while you were choosing", async ({ context, page }) => {
  await closesSoon(context, page);
  await card(page).getByRole("radio", { name: "Merge" }).check();
  await expect(card(page).locator(".ahead")).toHaveText("Closed while you were choosing · nobody can answer it now", { timeout: 20000 });
  await expect(card(page)).toContainText("Your answer wasn't sent.");
  await expect(card(page).getByRole("button", { name: "Send answer" })).toHaveCount(0);
});

test("a question that closes by its time while a note is typed says it closed while you were choosing", async ({ context, page }) => {
  await closesSoon(context, page);
  await card(page).getByLabel("Note (optional)").fill("after lunch");
  await expect(card(page).locator(".ahead")).toHaveText("Closed while you were choosing · nobody can answer it now", { timeout: 20000 });
});

test("a question that closes by its time with nothing picked or typed shows the plain closed state", async ({ context, page }) => {
  const { producer } = await closesSoon(context, page);
  await expect(card(page).locator(".ahead")).toHaveText("Closed · nobody answered in time", { timeout: 20000 });
  await expect(card(page)).toContainText(`${producer.name} got no answer.`);
});
