// The two dialogs of the Events header: Send a test event and Delete events by rule. Both are
// dialogs (a full screen on a phone), never a form under the list. Their confirming actions are
// text buttons; the destructive one is in the error colour and carries the count the server gave.

import { DELETE_EVENTS, PRODUCERS, call } from "./api.js";
import { el, icon } from "./dom.js";
import { askSection } from "./ask-form.js";
import { CATEGORIES, SEVERITIES, addDays, dayString } from "./event-filters.js";
import { QUESTIONS_GO_TOO } from "./question.js";
import { openDialog, segmented, selectField, textField } from "./ui.js";

const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._:/-]*$/;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** 1 Oct 2026: a day with its year, as the dialog says which midnight it means. */
const longDay = (day) => {
  const [year, month, date] = day.split("-").map(Number);
  return `${date} ${MONTHS[month - 1]} ${year}`;
};

export const eventCount = (count) => `${count.toLocaleString("en")} ${count === 1 ? "event" : "events"}`;

/** The leading day of midnight, in this browser's time zone, as an instant. */
const midnight = (day) => new Date(`${day}T00:00`).toISOString();

// ---- Send a test event -------------------------------------------------------------------------

/**
 * `producers`: the producers the page knows. Only enabled ones are offered, as a disabled producer
 * could not publish its own event either. `onSent(event)` is told the stored event.
 */
export function sendTestEvent({ producers, preset, onSent }) {
  const enabled = producers.filter((producer) => !producer.disabledAt);
  const producer = selectField({
    label: "Producer",
    options: enabled.map((item) => ({ value: item.id, text: item.name })),
    value: enabled.some((item) => item.id === preset) ? preset : undefined,
    hint: enabled.length === 0 ? "No producer is enabled. Enable one in Producers first." : undefined,
  });
  if (enabled.length === 0) producer.select.disabled = true;
  const title = textField({ label: "Title", value: "Test event", maxlength: 400 });
  const message = textField({ label: "Message (optional)", value: "Sent from the admin page." });
  let severity = "HIGH";
  const severitySlot = el("div", { class: "sev-slot" });
  const drawSeverity = () => {
    severitySlot.replaceChildren(
      el("div", { class: "t2 seg-label", text: "Severity" }),
      segmented({
        label: "Severity",
        value: severity,
        options: SEVERITIES.map((item) => ({ value: item.value, label: item.text })),
        onChange: (value) => {
          severity = value;
          drawSeverity();
          severitySlot.querySelector("[aria-checked='true']").focus();
        },
      }),
    );
  };
  drawSeverity();
  const category = selectField({ label: "Category", options: CATEGORIES.map((item) => ({ value: item.value, text: item.text })), value: "INFO" });
  const context = textField({ label: "Context (optional)" });
  const link = textField({ label: "Link (optional)", type: "url", hint: "https://" });
  const metadata = textField({ label: "Metadata (optional, a JSON object)", mono: true, multiline: true, hint: "Shown with the event and never interpreted." });
  metadata.box.classList.add("tfa");
  // Who a question would go to: the chosen producer's owner and the people its owner named.
  const asking = () => {
    const chosen = producers.find((item) => item.id === producer.select.value);
    if (!chosen) return [];
    const people = [chosen.owner, ...(chosen.answerers ?? [])].filter(Boolean);
    return people.filter((person, at) => people.findIndex((other) => other.id === person.id) === at);
  };
  const ask = askSection({ who: asking });
  producer.select.addEventListener("change", () => ask.refreshWho());

  const content = el(
    "div",
    {},
    el("p", { class: "p small-p", text: "Stored and pushed as the producer you choose, through every device's own settings." }),
    producer.node,
    title.node,
    message.node,
    el("div", { class: "row2" }, severitySlot, category.node),
    el("div", { class: "row2" }, context.node, link.node),
    metadata.node,
    ask.node,
  );

  // The first thing wrong, on its field; the dialog stays open with what was typed.
  function problems() {
    const found = [];
    const mark = (field, text) => {
      field.setError(text);
      if (text) found.push(field.input ?? field.select);
    };
    const name = title.input.value.trim();
    mark(title, !name ? "Give it a title." : name.length > 200 ? "Use 200 characters or fewer." : "");
    mark(message, message.input.value.length > 4000 ? "Use 4000 characters or fewer." : "");
    const where = context.input.value.trim();
    mark(context, where.length > 200 ? "Use 200 characters or fewer." : where && !IDENTIFIER.test(where) ? "Use letters, numbers and . _ : / - only, starting with a letter or number." : "");
    const url = link.input.value.trim();
    mark(link, url && !/^https?:\/\/\S+$/i.test(url) ? "The link must be a web address starting with http:// or https://." : url.length > 2000 ? "Use 2000 characters or fewer." : "");
    const raw = metadata.input.value.trim();
    let parsed;
    let metaText = "";
    if (raw) {
      try {
        parsed = JSON.parse(raw);
        if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) metaText = "Metadata must be a JSON object, such as {“run”: 42}.";
      } catch {
        metaText = "Metadata is not valid JSON.";
      }
    }
    mark(metadata, metaText);
    const asked = ask.read();
    found.push(...asked.problems);
    return { found, parsed, asked: asked.ask };
  }

  function request(parsed, asked) {
    const body = { category: category.select.value, severity, title: title.input.value.trim() };
    for (const [name, field] of [["message", message], ["context", context], ["link", link]]) {
      const value = field.input.value.trim();
      if (value) body[name] = value;
    }
    if (parsed) body.metadata = parsed;
    if (asked) body.ask = asked;
    return body;
  }

  const dialog = openDialog({
    title: "Send a test event",
    content,
    wide: true,
    variant: "full",
    focusNode: producer.select,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Send",
        value: true,
        className: "confirm",
        keepOpen: true,
        disabled: enabled.length === 0,
        busyLabel: "Sending…",
        run: async (controller) => {
          const { found, parsed, asked } = problems();
          if (found.length) {
            found[0].focus();
            return;
          }
          const sent = await call("POST", `${PRODUCERS}/${producer.select.value}/events`, request(parsed, asked));
          controller.close(true);
          onSent(sent);
        },
      },
    ],
  });
  void dialog;
}

// ---- Delete events by rule -----------------------------------------------------------------------

/** `onDeleted(count)` is told how many the server deleted. */
export function deleteByRule({ producers, onDeleted }) {
  const producer = selectField({
    label: "Producer",
    options: [{ value: "", text: "Any producer" }, ...producers.map((item) => ({ value: item.id, text: item.name }))],
    value: "",
  });
  const before = textField({ label: "Received before", type: "date" });
  const presets = el("div", { class: "pre" });
  const help = el("div", { class: "help hint-line" });
  const slot = el("div", {});
  const content = el(
    "div",
    {},
    el("p", { class: "p small-p", text: "Delete every event that matches. Choose a producer, a day or both. Nothing is deleted until you confirm the count." }),
    producer.node,
    before.node,
    presets,
    help,
    slot,
  );

  const chooseDay = (day) => {
    before.input.value = day;
    refresh();
  };
  const today = dayString(new Date());
  const yearAgo = new Date();
  yearAgo.setFullYear(yearAgo.getFullYear() - 1);
  for (const [label, day] of [
    ["Older than 30 days", addDays(today, -30)],
    ["Older than 90 days", addDays(today, -90)],
    ["Older than 1 year", dayString(yearAgo)],
  ]) {
    presets.append(el("button", { type: "button", class: "fc", on: { click: () => chooseDay(day) } }, el("span", { text: label })));
  }

  const rule = () => ({ producerId: producer.select.value, day: before.input.value });
  const body = () => {
    const { producerId, day } = rule();
    const request = {};
    if (producerId) request.producerId = producerId;
    if (day) request.createdBefore = midnight(day);
    return request;
  };
  const named = () => producers.find((item) => item.id === producer.select.value)?.name;
  const which = () => {
    const { day } = rule();
    return [named() ? `of ${named()}` : null, day ? `received before ${longDay(day)}` : null].filter(Boolean).join(" ");
  };

  let counting = null;

  function refresh() {
    const { producerId, day } = rule();
    const ready = Boolean(producerId || day);
    help.classList.toggle("err", !ready);
    help.textContent = ready ? "Midnight (00:00) in your browser's time zone. Type the date or pick a preset." : "Choose a producer, a day or both.";
    if (counting) counting.disabled = !ready;
  }

  function ruleStep() {
    slot.replaceChildren();
    producer.select.disabled = false;
    before.input.disabled = false;
    for (const node of presets.children) node.disabled = false;
    presets.hidden = false;
    help.hidden = false;
    const actions = [
      { label: "Cancel", value: false, className: "cancel" },
      { label: "Count events", value: true, className: "confirm", keepOpen: true, busyLabel: "Counting…", run: count },
    ];
    dialog.replace({ title: "Delete events by rule", content, actions, focusNode: producer.select });
    counting = actions[1].node;
    refresh();
  }

  function lock() {
    producer.select.disabled = true;
    before.input.disabled = true;
    for (const node of presets.children) node.disabled = true;
    presets.hidden = true;
    help.hidden = true;
  }

  async function count() {
    const { count: found, asking } = await call("POST", DELETE_EVENTS, { ...body(), dryRun: true });
    lock();
    if (found === 0) {
      slot.replaceChildren(
        el("div", { class: "warn" }, icon("check_circle"), el("div", {}, el("b", { text: "Nothing to delete." }), el("br"), `No event ${which()} was found.`)),
      );
      dialog.replace({
        content,
        actions: [
          { label: "Change rule", value: false, run: async () => ruleStep(), keepOpen: true },
          { label: "Close", value: true },
        ],
        initialFocus: true,
      });
      return;
    }
    slot.replaceChildren(
      el(
        "div",
        { class: "warn danger" },
        icon("delete_forever"),
        el("div", {}, el("b", { text: `${eventCount(found)} will be deleted${asking ? `, ${asking.toLocaleString("en")} of them with a question` : ""}.` }), el("br"), `Every event ${which()}, with its waiting pushes and delivery records.${asking ? ` ${QUESTIONS_GO_TOO}` : ""} This cannot be undone.`),
      ),
    );
    dialog.replace({
      content,
      actions: [
        { label: "Change rule", value: false, run: async () => ruleStep(), keepOpen: true },
        {
          label: `Delete ${eventCount(found)}`,
          value: true,
          kind: "text-error",
          className: "confirm",
          busyLabel: "Deleting…",
          retryLabel: "Try again",
          run: async () => {
            const deleted = await call("POST", DELETE_EVENTS, body());
            onDeleted(deleted.count);
          },
        },
      ],
    });
  }

  before.input.addEventListener("input", refresh);
  producer.select.addEventListener("change", refresh);
  const dialog = openDialog({
    title: "Delete events by rule",
    content,
    wide: false,
    variant: "full",
    focusNode: producer.select,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      { label: "Count events", value: true, className: "confirm", keepOpen: true, busyLabel: "Counting…", run: count, disabled: true },
    ],
  });
  counting = dialog.actions.at(-1).node;
  refresh();
}
