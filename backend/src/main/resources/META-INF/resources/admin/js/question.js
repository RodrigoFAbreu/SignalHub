// A question on an event, as the operator reads it (DESIGN.md 10.7): the marker of a list row, and in
// the event pane the question as text, its state and its answer. The operator never answers (the
// admin token acts for no user), so nothing here is a control; the choices are a list with a dash or
// a check, never a radio button. Everything the server sent is set as text.

import { el, icon } from "./dom.js";
import { clock, shortDate } from "./format.js";
import { avatar, tag } from "./ui.js";

// Past this many characters a producer's close note goes on a line of its own, as in the app.
const LONG_NOTE = 40;

const commaDate = (iso) => `${shortDate(iso)}, ${clock(iso)}`;
const onDate = (iso) => `${shortDate(iso)} at ${clock(iso)}`;

/** Rodrigo, Rodrigo or Ana, Rodrigo, Ana or Rui: the owner first, as the server lists them. */
export function names(people) {
  const list = people.map((person) => person.name);
  if (list.length <= 1) return list.join("");
  return `${list.slice(0, -1).join(", ")} or ${list.at(-1)}`;
}

/** The words of a list marker, and the glyph, or null for an event that asks nothing. */
export function markerOf(event) {
  if (!event.ask) return null;
  if (event.answerState === "ANSWERED") return { word: "Answered", glyph: "check", kind: "ans" };
  if (event.answerState === "CLOSED") return { word: "Closed", glyph: event.closedBy === "PRODUCER" ? "lock" : "lock_clock", kind: "shut" };
  return { word: "Waiting", glyph: "hourglass_top", kind: "" };
}

/** The marker under a row's title: one word with an icon, so it reads without colour. */
export function markerNode(event) {
  const marker = markerOf(event);
  if (!marker) return null;
  return el("span", { class: `qm${marker.kind ? ` ${marker.kind}` : ""}` }, icon(marker.glyph), marker.word);
}

function rule(ask) {
  const pick = ask.choices.length === 0 ? "No choices, typed answer" : ask.multiple ? "One or more" : "One";
  let note = "Not allowed";
  if (ask.choices.length === 0 || ask.text === "REQUIRED") note = "Required";
  else if (ask.text === "OPTIONAL") note = ask.textStyle === "OTHER" ? "Other row, optional" : "Allowed, optional";
  return [pick, note];
}

function closesText(ask) {
  return ask.closesAt ? commaDate(ask.closesAt) : "Never";
}

/** Who the question waits for, in words: from `whoCanAnswer`, never "an admin" or "the operator". */
function whoWords(ask) {
  const people = ask.whoCanAnswer ?? [];
  if (people.length === 0) return "nobody can answer it now";
  return `${names(people)} can answer`;
}

function closesShort(ask) {
  if (!ask.closesAt) return "no closing time";
  const date = new Date(ask.closesAt);
  return date.toDateString() === new Date().toDateString() ? `closes ${clock(date)}` : `closes ${commaDate(ask.closesAt)}`;
}

const choiceRow = (label, description, picked) =>
  el(
    "div",
    { class: `qch${picked ? " pk" : ""}` },
    icon(picked ? "check" : "remove"),
    el("div", { class: "tx" }, el("span", { class: "t1", text: label }), description ? el("span", { class: "t2", text: description }) : null),
    picked ? tag("Picked", "outlined") : null,
  );

/** The question as text: its rules and each choice, the chosen ones marked. */
function questionBox(event) {
  const { ask, answer } = event;
  const [pick, note] = rule(ask);
  const chosen = new Set(answer?.choices ?? []);
  const rows = ask.choices.map((choice) => choiceRow(choice.label, choice.description, chosen.has(choice.id)));
  // An Other row is the last row, with no description; picked when the answer carries its text.
  if (ask.textStyle === "OTHER") rows.push(choiceRow("Other", null, Boolean(answer?.text)));
  return el(
    "div",
    { class: "qbox", role: "group", "aria-label": "Question, read-only here" },
    el("div", { class: "qhd" }, icon("help"), "Question", el("span", { class: "cnt", text: "read-only here" })),
    el("div", { class: "qrules" }, el("b", { text: "Pick" }), el("span", { text: pick }), el("b", { text: "Note" }), el("span", { text: note }), el("b", { text: "Closes" }), el("span", { text: closesText(ask) })),
    ...rows,
  );
}

function stateBox(event) {
  const { ask } = event;
  const box = (kind, glyph, title, lines, label) =>
    el("div", { class: `qst ${kind}`, role: label ? "group" : "status", "aria-label": label ?? null }, icon(glyph), el("div", { class: "tx" }, el("b", { text: title }), ...lines.map((line) => el("span", { class: "t2", text: line }))));
  if (event.answerState === "OPEN") {
    const names_ = names(ask.whoCanAnswer ?? []);
    return box(
      "open",
      "hourglass_top",
      `Waiting for an answer · ${closesShort(ask)} · ${whoWords(ask)}`,
      [names_ ? `Answers come from ${names_}, in the app or on the web page. The admin page cannot answer.` : "Nobody can answer it now. The admin page cannot answer."],
    );
  }
  if (event.answerState === "ANSWERED") {
    return box("done", "check_circle", "Answered", ["Nobody else can answer now."], `Answered ${viaWords(event.answer.via)}`);
  }
  if (event.closedBy === "PRODUCER") {
    const by = event.producer.name;
    const note = event.closeNote;
    const closed = `${by} closed this question on ${onDate(event.closedAt)}. Nobody can answer it now.`;
    if (!note) return box("shut", "lock", `Closed by ${by}`, [closed]);
    if ([...note].length <= LONG_NOTE) return box("shut", "lock", `Closed by ${by} · ${note}`, [closed]);
    return box("shut", "lock", `Closed by ${by}`, [`‘${note}’`, closed]);
  }
  return box("shut", "lock_clock", "Closed · nobody answered in time", [`It closed on ${onDate(event.closedAt)}. Nobody can answer it now.`]);
}

const viaWords = (via) => (via === "WEB" ? "on the web page" : "in the app");

/** Who answered, when and where, what was chosen, and the note in a box of its own. */
function answerBlock(event, userOf) {
  const { ask, answer } = event;
  const parts = [el("div", { class: "lab", text: "Answer" })];
  const known = userOf(answer.by.id);
  const where = `${commaDate(answer.at)} · ${viaWords(answer.via)}`;
  if (known?.revokedAt) {
    parts.push(
      el("div", { class: "qwho" }, avatar(answer.by.name, { tint: true }), answer.by.name, tag("Revoked", "outlined")),
      el("div", { class: "t2 qdate", text: where }),
      el("div", { class: "qrev", text: `${answer.by.name} was revoked on ${shortDate(known.revokedAt)}. The name and the answer stay as they were when it was given.` }),
    );
  } else {
    parts.push(el("div", { class: "qwho" }, avatar(answer.by.name, { tint: true }), answer.by.name, el("span", { class: "t2", text: where })));
  }
  const labels = answer.choices.map((id) => ask.choices.find((choice) => choice.id === id)?.label ?? id);
  const typedOnly = ask.choices.length === 0;
  const other = !typedOnly && ask.textStyle === "OTHER" && answer.text;
  if (other) labels.push("Other");
  if (labels.length) parts.push(el("div", { class: "kv qchose" }, el("b", { text: "Chose" }), el("span", { text: labels.join(", ") })));
  if (answer.text) {
    const title = typedOnly ? `Answer typed by ${answer.by.name}` : other ? `Other typed by ${answer.by.name}` : `Note from ${answer.by.name}`;
    parts.push(el("div", { class: "qnote" }, el("span", { class: "t2", text: title }), answer.text));
  }
  return parts;
}

/** What the Event tab adds under the message and the link: the question, its state and its answer. */
export function questionParts(event, userOf) {
  if (!event.ask) return [];
  const parts = [questionBox(event), stateBox(event)];
  if (event.answerState === "ANSWERED" && event.answer) parts.push(...answerBlock(event, userOf));
  return parts;
}

/**
 * The body of the confirmation that deletes one event that asks: who is waiting for it, or that its
 * answer goes too. Null for an event that asks nothing, which keeps the usual body.
 */
export function deleteWords(event) {
  if (!event.ask) return null;
  if (event.answerState === "OPEN") {
    const people = event.ask.whoCanAnswer ?? [];
    const waiting = people.length ? `is waiting for an answer from ${names(people)}` : "is waiting for an answer";
    return `${event.title} ${waiting}. Its question goes with it, and ${event.producer.name} gets no answer. This cannot be undone.`;
  }
  const answered = event.answerState === "ANSWERED" && event.answer ? `Its question and ${event.answer.by.name}'s answer are deleted too.` : "Its question is deleted too.";
  return `“${event.title}” is gone for good. ${answered} This cannot be undone.`;
}

/** How many of the events a bulk delete takes ask a question, in the count line's words; null for none. */
export function askingCount(asking) {
  return asking ? `${asking.toLocaleString("en")} of them with a question` : null;
}

export const QUESTIONS_GO_TOO = "Their questions and any answers go too.";
