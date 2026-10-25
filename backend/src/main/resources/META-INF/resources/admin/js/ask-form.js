// The "Ask for an answer" section of Send a test event (DESIGN.md 10.7): it builds the question a
// producer would send, with the same rules the API checks and the same id rule as the SDK and the
// command. Folded by default, so a plain test event is as short as before; nothing in it is sent
// while it is folded. The operator never answers, so this only asks.

import { el, icon, replace } from "./dom.js";
import { clock } from "./format.js";
import { names } from "./question.js";
import { iconButton, nextId, segmented, selectField, textField } from "./ui.js";

const MAX_CHOICES = 10;
const EXAMPLES = ["Merge", "Hold"];
const MAX_LABEL = 100;
const MAX_DESCRIPTION = 1000;
const ID_ROOM = 60; // of the server's 64, leaving room for a "-2" ... "-10" suffix
const MAX_DAYS = 30;
const UNITS = [
  { value: "minutes", text: "minutes", ms: 60_000 },
  { value: "hours", text: "hours", ms: 3_600_000 },
  { value: "days", text: "days", ms: 86_400_000 },
];

/** The id of each label, as the SDK and the command derive it: see `derive_choice_ids` in the SDK. */
export function deriveIds(labels) {
  const ids = [];
  labels.forEach((label, index) => {
    const base = label
      .normalize("NFKD")
      .replace(/[^\x00-\x7f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, ID_ROOM)
      .replace(/-+$/g, "");
    const root = base || `choice-${index + 1}`;
    let candidate = root;
    for (let suffix = 2; ids.includes(candidate); suffix += 1) candidate = `${root}-${suffix}`;
    ids.push(candidate);
  });
  return ids;
}

const count = (text, limit) => `${[...text].length} / ${limit}`;

const dayAndTime = (date) => {
  const two = (n) => String(n).padStart(2, "0");
  return { day: `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`, time: `${two(date.getHours())}:${two(date.getMinutes())}` };
};

const when = (date) => `${date.getDate()} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.getMonth()]}, ${clock(date)}`;

/**
 * `who()` says who can answer the chosen producer (its owner and answerers, `[{name}]`). Returns the
 * section's `node`, `refreshWho()` for when the producer changes, and `read()`: `{ask, problems}`
 * where `ask` is the body's `ask` (null when folded or empty) and `problems` are the controls to
 * focus, first one first, each already showing its error.
 */
export function askSection({ who }) {
  const state = {
    open: false,
    choices: [{ label: "", description: "", showDescription: false }, { label: "", description: "", showDescription: false }],
    multiple: false,
    note: "NONE",
    style: "NOTE",
    closes: "NEVER",
    amount: "2",
    unit: "hours",
    atDay: "",
    atTime: "",
  };
  const node = el("div", { class: "ask" });
  let refs = {};

  const toggleId = nextId("ask-toggle");

  // ---- What the section knows
  const labelsText = () => state.choices.map((choice) => choice.label.trim());
  const dirty = () => state.choices.some((choice) => choice.label.trim() || choice.description.trim()) || state.multiple || state.note !== "NONE" || state.closes !== "NEVER";

  function closesAt() {
    if (state.closes === "IN") {
      const unit = UNITS.find((item) => item.value === state.unit);
      const amount = Number(state.amount);
      if (!Number.isFinite(amount) || amount <= 0) return null;
      return new Date(Date.now() + amount * unit.ms);
    }
    if (state.closes === "AT" && state.atDay && state.atTime) return new Date(`${state.atDay}T${state.atTime}`);
    return null;
  }

  function closesLine() {
    const date = closesAt();
    return date && !Number.isNaN(date.getTime()) ? `Closes ${when(date)}, your time. At most ${MAX_DAYS} days ahead.` : `At most ${MAX_DAYS} days ahead.`;
  }

  // ---- Drawing
  function draw() {
    refs = { labels: [], descriptions: [], infos: [], closesLine: null, closesField: null, pickError: null };
    const focused = document.activeElement?.dataset?.key ?? null;
    const head = el(
      "button",
      { type: "button", class: "askf", id: toggleId, "aria-expanded": String(state.open), "data-key": "toggle" },
      icon(state.open ? "expand_less" : "expand_more", "c-var"),
      el("div", { class: "tx" }, "Ask for an answer", el("span", { class: "t2", id: `${toggleId}-line` }, headLine())),
    );
    head.addEventListener("click", () => {
      state.open = !state.open;
      draw();
      node.querySelector("[data-key='toggle']").focus();
    });
    const parts = [head];
    if (state.open) parts.push(...body());
    replace(node, ...parts);
    infos();
    if (focused) node.querySelector(`[data-key='${focused}']`)?.focus({ preventScroll: true });
  }

  function headLine() {
    if (state.open) {
      const people = who();
      const text = people.length ? names(people) : "";
      return text ? `Answers come from ${text}, in the app or on the web page. The admin page cannot answer.` : "Nobody can answer it now. The admin page cannot answer.";
    }
    return dirty() ? "Not sent: the section is folded." : "Add choices or a typed answer. Off: the event asks nothing.";
  }

  function body() {
    const parts = [el("div", { class: "alab alab-top", text: "Choices" })];
    state.choices.forEach((choice, at) => parts.push(...choiceRows(choice, at)));
    if (state.choices.length === 0) parts.push(el("div", { class: "cinfo", text: "No choices: the answer is typed." }));
    parts.push(addRow());
    if (state.choices.length > 0) parts.push(el("div", { class: "alab", text: "Pick" }), pickControl());
    parts.push(el("div", { class: "alab", text: "Note" }));
    if (state.choices.length === 0) {
      parts.push(el("div", { class: "cinfo", text: "No choices: the answer is typed, and the person must type one." }));
    } else {
      parts.push(noteControl());
      if (state.style === "OTHER" && state.note !== "NONE") {
        parts.push(el("div", { class: "help", text: "With an Other row, typing is optional: the person picks a choice or Other." }));
      } else if (state.note === "OPTIONAL") {
        parts.push(el("div", { class: "help", text: "A note is text the person may add: 1 to 3000 characters." }));
      } else if (state.note === "REQUIRED") {
        parts.push(el("div", { class: "help", text: "A note is text the person must add: 1 to 3000 characters." }));
      }
      if (state.note !== "NONE") {
        parts.push(el("div", { class: "alab", text: "Typed answer as" }), segmented({ label: "Typed answer as", value: state.style, options: [{ value: "NOTE", label: "Note" }, { value: "OTHER", label: "Other row" }], onChange: (value) => change(() => { state.style = value; if (value === "OTHER") state.note = "OPTIONAL"; }, "style") }));
        parts[parts.length - 1].dataset.key = "style";
      }
    }
    parts.push(el("div", { class: "alab", text: "Closes" }), closesControl(), ...closesFields());
    return parts;
  }

  function change(mutate, key) {
    mutate();
    draw();
    if (key) node.querySelector(`[data-key='${key}'] [aria-checked='true'], [data-key='${key}']`)?.focus({ preventScroll: true });
  }

  function choiceRows(choice, at) {
    const label = textField({ label: "Label", value: choice.label, onInput: (value) => { choice.label = value; renameRemove(); infos(); } });
    label.input.placeholder = `For example: ${EXAMPLES[at % EXAMPLES.length]}`;
    label.input.dataset.key = `label-${at}`;
    // Named by the label as it is typed; by the position only while the label is empty.
    const removeName = () => `Remove choice ${choice.label.trim() || at + 1}`;
    const renameRemove = () => remove.setAttribute("aria-label", removeName());
    const remove = iconButton("close", removeName(), () => change(() => state.choices.splice(at, 1), null));
    const info = el("div", { class: "cinfo" });
    refs.labels[at] = label;
    refs.infos[at] = info;
    const rows = [el("div", { class: "crow" }, label.node, remove), info];
    if (choice.showDescription || choice.description) {
      const description = textField({ label: "Description (optional)", value: choice.description, onInput: (value) => { choice.description = value; infos(); } });
      description.input.dataset.key = `description-${at}`;
      refs.descriptions[at] = description;
      rows.push(el("div", { class: "cdesc" }, description.node));
    }
    return rows;
  }

  // The counts and the ids under the labels: changed in place, as the person types.
  function infos() {
    const ids = deriveIds(labelsText().map((text) => text));
    state.choices.forEach((choice, at) => {
      const info = refs.infos[at];
      if (!info) return;
      const text = choice.label.trim();
      const add = el("button", { type: "button", class: "btn-x", text: "Add description", on: { click: () => change(() => { choice.showDescription = true; }, `description-${at}`) } });
      const withDescription = choice.showDescription || choice.description;
      replace(
        info,
        text ? `ID: ${ids[at]}` : "The ID comes from the label, as you type.",
        el("span", { class: "sp" }),
        el("span", { text: count(choice.label, MAX_LABEL) }),
        withDescription ? null : add,
      );
      const help = refs.descriptions[at]?.node.querySelector(".help");
      if (help && !help.classList.contains("err")) help.textContent = count(choice.description, MAX_DESCRIPTION);
    });
    if (refs.closesLine) refs.closesLine.textContent = closesLine();
  }

  function addRow() {
    const full = state.choices.length >= MAX_CHOICES;
    const add = el("button", { type: "button", class: `btn-x${full ? " dis" : ""}`, "aria-disabled": full ? "true" : null, "data-key": "add" }, icon("add"), "Add choice");
    const note = el("span", { class: "t2", text: `${state.choices.length} of ${MAX_CHOICES}` });
    const error = el("div", { class: "cinfo err", role: "alert", hidden: true });
    add.addEventListener("click", () => {
      if (full) {
        replace(error, icon("error"), `At most ${MAX_CHOICES} choices. Remove one to add another.`);
        error.hidden = false;
        return;
      }
      change(() => state.choices.push({ label: "", description: "", showDescription: false }), `label-${state.choices.length}`);
    });
    return el("div", {}, el("div", { class: "addc" }, add, note), error);
  }

  function pickControl() {
    const control = segmented({ label: "Pick", value: state.multiple ? "MANY" : "ONE", options: [{ value: "ONE", label: "One" }, { value: "MANY", label: "One or more" }], onChange: (value) => change(() => (state.multiple = value === "MANY"), "pick") });
    control.dataset.key = "pick";
    const error = el("div", { class: "cinfo err", hidden: true });
    refs.pickError = error;
    return el("div", {}, control, error);
  }

  function noteControl() {
    const locked = state.style === "OTHER";
    const control = segmented({
      label: "Note",
      value: state.note,
      options: [
        { value: "NONE", label: "None", dim: locked },
        { value: "OPTIONAL", label: "Optional" },
        { value: "REQUIRED", label: "Required", dim: locked },
      ],
      onChange: (value) => change(() => (state.note = value), "note"),
    });
    control.dataset.key = "note";
    return control;
  }

  function closesControl() {
    const control = segmented({ label: "Closes", value: state.closes, options: [{ value: "NEVER", label: "Never" }, { value: "IN", label: "In" }, { value: "AT", label: "At" }], onChange: (value) => change(() => (state.closes = value), "closes") });
    control.dataset.key = "closes";
    return control;
  }

  function closesFields() {
    if (state.closes === "NEVER") return [];
    const line = el("div", { class: "help", text: closesLine() });
    refs.closesLine = line;
    if (state.closes === "IN") {
      const amount = textField({ label: "Time", value: state.amount, type: "number", onInput: (value) => { state.amount = value; infos(); } });
      amount.input.min = "1";
      amount.input.dataset.key = "amount";
      const unit = selectField({ label: "Unit", options: UNITS.map(({ value, text }) => ({ value, text })), value: state.unit, onChange: (value) => { state.unit = value; infos(); } });
      refs.closesField = amount;
      return [el("div", { class: "row2" }, amount.node, unit.node), line];
    }
    const day = textField({ label: "Day", value: state.atDay, type: "date", onInput: (value) => { state.atDay = value; infos(); } });
    const time = textField({ label: "Time", value: state.atTime, type: "time", onInput: (value) => { state.atTime = value; infos(); } });
    day.input.dataset.key = "day";
    refs.closesField = day;
    return [el("div", { class: "row2" }, day.node, time.node), line];
  }

  // ---- What is sent
  function read() {
    if (!state.open) return { ask: null, problems: [] };
    const problems = [];
    const flag = (field, text, control = field.input) => {
      field.setError(text);
      if (text) problems.push(control);
    };
    const kept = state.choices.map((choice, at) => ({ choice, at })).filter(({ choice }) => choice.label.trim() || choice.description.trim());
    // Rows left empty are no choices: with nothing else asked the event asks nothing. Removing every
    // row, on the other hand, makes it a typed question.
    if (kept.length === 0 && state.choices.length > 0) return { ask: null, problems: [] };
    const ids = deriveIds(kept.map(({ choice }) => choice.label.trim()));
    const seen = new Map();
    kept.forEach(({ choice, at }) => {
      const field = refs.labels[at];
      const text = choice.label.trim();
      let message = "";
      if (!text) message = "Give the choice a label.";
      else if ([...text].length > MAX_LABEL) message = `Use ${MAX_LABEL} characters or fewer.`;
      else if (/[\u0000-\u001f\u007f]/.test(text)) message = "A label has no line breaks.";
      else if (seen.has(text.toLowerCase())) message = `Another choice is already called ${seen.get(text.toLowerCase())}. Labels must differ, ignoring capitals.`;
      else if (state.style === "OTHER" && state.note !== "NONE" && text.toLowerCase() === "other") message = "A choice cannot be called Other while the question has an Other row. Rename it, or type the answer as a Note.";
      if (!seen.has(text.toLowerCase())) seen.set(text.toLowerCase(), text);
      flag(field, message);
      const description = refs.descriptions[at];
      if (description) flag(description, [...choice.description].length > MAX_DESCRIPTION ? `Use ${MAX_DESCRIPTION} characters or fewer.` : "");
    });
    if (state.multiple && kept.length > 0 && kept.length < 2 && refs.pickError) {
      replace(refs.pickError, icon("error"), "Picking one or more needs at least 2 choices. Add another, or pick One.");
      refs.pickError.hidden = false;
      problems.push(node.querySelector("[data-key='pick'] [aria-checked='true']"));
    }
    const date = closesAt();
    if (state.closes !== "NEVER") {
      let message = "";
      if (!date || Number.isNaN(date.getTime())) message = state.closes === "IN" ? "Give a number above zero." : "Pick a day and a time.";
      else if (date.getTime() <= Date.now()) message = "Pick a time in the future.";
      else if (date.getTime() > Date.now() + MAX_DAYS * 86_400_000) message = `At most ${MAX_DAYS} days ahead. The latest is ${when(new Date(Date.now() + MAX_DAYS * 86_400_000))}.`;
      if (message && refs.closesField) flag(refs.closesField, message);
    }
    if (problems.length) return { ask: null, problems };
    const typed = kept.length === 0;
    const ask = {};
    if (!typed) {
      ask.choices = kept.map(({ choice }, index) => ({ id: ids[index], label: choice.label.trim(), ...(choice.description.trim() ? { description: choice.description } : {}) }));
      if (state.multiple) ask.multiple = true;
      ask.text = state.note;
      if (state.note !== "NONE") ask.textStyle = state.style;
    } else {
      ask.choices = [];
      ask.text = "REQUIRED";
    }
    if (state.closes !== "NEVER") ask.closesAt = date.toISOString();
    return { ask, problems: [] };
  }

  draw();
  return {
    node,
    read,
    refreshWho() {
      const line = node.querySelector(`#${toggleId}-line`);
      if (line) line.textContent = headLine();
    },
  };
}

/** `asking Rodrigo and Ana`, from who the question went to; null when it went to nobody. */
export function askingWords(people) {
  const list = people.map((person) => person.name);
  if (list.length === 0) return null;
  const text = list.length === 1 ? list[0] : `${list.slice(0, -1).join(", ")} and ${list.at(-1)}`;
  return `asking ${text}`;
}
