// A question on an event (DESIGN.md section 10): the card that answers it, the result that takes its
// place, the read-only card, and the line an inbox row adds. Everything the server says (a label, a
// description, a name, a note) is rendered as text. SignalHub never interprets a question: the card
// is built from the ask's own choices and text rules.

import { ApiError, SessionEnded, calls } from "./api.js";
import { el, icon, replace } from "./dom.js";
import { clock, possessive, shortDate } from "./format.js";
import { state } from "./state.js";
import { announce, hideSnack, nextId, showSnack } from "./ui.js";

const MAX_TEXT = 3000;
// Past this many characters a typed answer or a close note goes on a line of its own.
const LONG = 40;
const OTHER = "\u0000other";

const codePoints = (text) => [...text].length;
const isMac = () => /Mac|iPhone|iPad/i.test(navigator.platform || navigator.userAgent);

// What the person typed and picked, per event, so a repaint of the screen (marking it unread, a
// refresh) never loses it. Leaving *Other* keeps its text while the event is open.
const drafts = new Map();
// What happened to this person's own attempt: "first" (someone answered first) or "closed".
const attempts = new Map();
// What a 403 on sending turned the card into.
const lostRight = new Set();

let stopTimers = () => {};

/** Stops the card's timers; the inbox calls it when the event screen goes away. */
export function disposeQuestion() {
  stopTimers();
  stopTimers = () => {};
  hideSnack();
}

// ---- Words -----------------------------------------------------------------------------

/** `09:00` today, `17 Oct at 09:00` on another day. */
function whenAt(value, now = new Date()) {
  const date = new Date(value);
  const sameDay = date.toDateString() === now.toDateString();
  return sameDay ? `at ${clock(date)}` : `${shortDate(date, now)} at ${clock(date)}`;
}

const onDay = (value) => `${shortDate(value)} at ${clock(new Date(value))}`;

function names(people) {
  const list = people.map((person) => person.name);
  if (list.length <= 1) return list.join("");
  return `${list.slice(0, -1).join(", ")} or ${list.at(-1)}`;
}

function who(ask) {
  return ask.whoCanAnswer ?? [];
}

/** What an answer picked, in words: the labels of its choices, and `Other` for typed text. */
function pickedWords(event, answer) {
  const ask = event.ask;
  const labels = answer.choices.map((id) => ask.choices.find((choice) => choice.id === id)?.label ?? id);
  const typedOnly = ask.choices.length === 0;
  const other = !typedOnly && ask.textStyle === "OTHER" && answer.text ? answer.text : null;
  if (other !== null) labels.push("Other");
  return {
    labels: labels.join(", "),
    typed: typedOnly ? answer.text : null,
    other,
    note: !typedOnly && ask.textStyle !== "OTHER" ? answer.text : null,
  };
}

/** The text a result gives of an answer: the labels, or the typed text in curly quotes. */
function pickedLabel(words) {
  return words.typed !== null ? `‘${words.typed}’` : words.labels;
}

function isMine(answer) {
  return answer.by.id === state.me?.userId;
}

/** The icon, title and lines a decided question shows, and the same for a read-only one. */
export function resultOf(event) {
  const producer = event.producer.name;
  const attempt = attempts.get(event.id);
  if (event.answerState === "ANSWERED" && event.answer) {
    const { answer } = event;
    const mine = isMine(answer);
    const words = pickedWords(event, answer);
    const time = clock(new Date(answer.at));
    if (attempt === "first") {
      const first = mine ? { title: `You already answered: ${pickedLabel(words)}`, line: "Your new answer wasn't sent." } : { title: `${answer.by.name} answered first: ${pickedLabel(words)}`, line: `${time}. Your answer wasn't sent, and ${producer} has ${possessive(answer.by.name)}.` };
      return { glyph: "info", fill: true, tone: "c-var", title: first.title, lines: [first.line] };
    }
    const subject = mine ? "You" : answer.by.name;
    const sent = `Sent to ${producer}.${mine ? "" : " Nobody else can answer now."}`;
    const tone = mine ? "c-primary" : "c-var";
    if (words.typed !== null) {
      if (codePoints(words.typed) <= LONG) {
        return { glyph: "check_circle", fill: true, tone, title: `${subject} answered · ‘${words.typed}’`, lines: [`${time} · ${sent}`] };
      }
      return { glyph: "check_circle", fill: true, tone, title: `${subject} answered`, lines: [words.typed, `${time} · ${sent}`], textLine: 0 };
    }
    const lines = [];
    if (words.other !== null) lines.push(`Other: ${words.other}`);
    if (words.note !== null) lines.push(`Note: ${words.note}`);
    lines.push(sent);
    return { glyph: "check_circle", fill: true, tone, title: `${subject} answered · ${words.labels} · ${time}`, lines, textLine: words.other !== null || words.note !== null ? 0 : undefined };
  }
  if (event.answerState === "CLOSED") {
    const byProducer = event.closedBy === "PRODUCER";
    const glyph = byProducer ? "lock" : "lock_clock";
    if (attempt === "closed") {
      // The producer's note says why, as on the closed-by-producer card.
      const note = byProducer ? event.closeNote : null;
      const lines = [byProducer ? `Your answer wasn't sent. ${producer} closed this question.` : `Your answer wasn't sent. ${producer} got no answer.`];
      if (note) lines.unshift(`‘${note}’`);
      return { glyph, tone: "c-var", title: "Closed while you were choosing · nobody can answer it now", lines, textLine: note ? 0 : undefined };
    }
    if (!byProducer) {
      return { glyph, tone: "c-var", title: "Closed · nobody answered in time", lines: [`It closed on ${onDay(event.closedAt)}. ${producer} got no answer.`] };
    }
    const note = event.closeNote;
    const closed = `${producer} closed this question on ${onDay(event.closedAt)}.`;
    if (!note) return { glyph, tone: "c-var", title: `Closed by ${producer}`, lines: [closed] };
    if (codePoints(note) <= LONG) return { glyph, tone: "c-var", title: `Closed by ${producer} · ${note}`, lines: [closed] };
    return { glyph, tone: "c-var", title: `Closed by ${producer}`, lines: [`‘${note}’`, closed], textLine: 0 };
  }
  return null;
}

/** The title of the read-only card: who can answer, the owner first. */
function readOnlyTitle(ask) {
  const people = who(ask);
  if (people.length === 0) return "Nobody can answer this now";
  if (people.length === 1) return `${people[0].name} answers this`;
  return `${names(people)} can answer`;
}

/**
 * The line an inbox row adds under its meta line, in words so that the state is never only an
 * icon or a colour: `{glyph, text, quiet}`, or null for an event that asks nothing.
 */
export function questionLine(event) {
  if (!event.ask) return null;
  if (event.answerState === "OPEN") {
    if (event.canAnswer) {
      const closes = event.ask.closesAt ? ` · Closes ${closesLabel(event.ask.closesAt)}` : "";
      return { glyph: "question_answer", text: `To answer${closes}`, quiet: false };
    }
    const people = who(event.ask);
    return { glyph: "hourglass_top", text: people.length ? `Waiting for ${names(people)}` : "Waiting · nobody can answer", quiet: true };
  }
  if (event.answerState === "ANSWERED" && event.answer) {
    const words = pickedWords(event, event.answer);
    return { glyph: "check", text: `${isMine(event.answer) ? "You" : event.answer.by.name} answered · ${pickedLabel(words)}`, quiet: true };
  }
  if (event.answerState === "CLOSED") {
    return event.closedBy === "PRODUCER" ? { glyph: "lock", text: `Closed by ${event.producer.name}`, quiet: true } : { glyph: "lock_clock", text: "Closed · nobody answered", quiet: true };
  }
  return null;
}

/** `09:00` today, `17 Oct 09:00` another day. */
function closesLabel(value) {
  const date = new Date(value);
  return date.toDateString() === new Date().toDateString() ? clock(date) : `${shortDate(date)} ${clock(date)}`;
}

export function lineNode(line) {
  return el("div", { class: `ql${line.quiet ? " v" : ""}` }, icon(line.glyph), el("span", { class: "ql-text", text: line.text }));
}

/** A change that decides whether the card must be painted again, not just kept. */
export function signature(event) {
  return [event.answerState, event.canAnswer, event.answer?.at, event.closedBy, event.ask?.closesAt].join("|");
}

/**
 * A re-read found the question decided. A person with something picked or typed is told their
 * answer wasn't sent (the card a 409 gives); one with nothing in hand sees the plain result.
 */
export function noteLostAttempt(before, fresh) {
  if (before?.id !== fresh.id || before.answerState !== "OPEN" || fresh.answerState === "OPEN") return;
  const draft = drafts.get(fresh.id);
  const inHand = Boolean(draft && (draft.picked.size > 0 || draft.otherOn || draft.note.trim() || draft.other.trim()));
  if (!inHand) return;
  attempts.set(fresh.id, fresh.answerState === "ANSWERED" ? "first" : "closed");
  drafts.delete(fresh.id);
}

// ---- The card --------------------------------------------------------------------------

/**
 * The card under the message. `hooks.changed(event)` is told of a new state of the event (an answer
 * accepted, a 409's winner); `hooks.reread()` reads the event again; `hooks.gone()` says it is not in
 * the inbox any more.
 */
export function answerCard(event, hooks) {
  stopTimers();
  const timers = [];
  stopTimers = () => timers.splice(0).forEach((stop) => stop());
  const card = el("div", { class: "acard" });
  let current = event;

  const open = () => current.answerState === "OPEN";
  const later = (fn, ms) => {
    const id = setTimeout(fn, ms);
    timers.push(() => clearTimeout(id));
  };

  function paint(announced = false) {
    card.className = "acard";
    if (open() && current.canAnswer) form();
    else if (open()) readOnly();
    else result(announced);
    if (open() && current.ask.closesAt) {
      // The state is the server's: re-read when the question closes by its time.
      const ms = Math.min(new Date(current.ask.closesAt).getTime() - Date.now() + 1000, 2 ** 31 - 1);
      later(closeByTime, Math.max(ms, 1000));
    }
  }

  // The question reached its closing time. A person who had picked or typed something is told it
  // closed while they were choosing (the same card a 409 gives); one with nothing in hand sees the
  // plain closed state.
  async function closeByTime() {
    const draft = drafts.get(current.id);
    const inHand = Boolean(draft && (draft.picked.size > 0 || draft.otherOn || draft.note.trim() || draft.other.trim()));
    if (inHand) attempts.set(current.id, "closed");
    const fresh = await hooks.reread();
    if (inHand && fresh?.answerState !== "CLOSED") attempts.delete(current.id);
    else if (inHand) drafts.delete(current.id);
  }

  // ---- A decided question
  function result(announced) {
    const shown = resultOf(current);
    if (!shown) {
      replace(card);
      return;
    }
    const title = el("span", { class: "ahead", tabindex: "-1", text: shown.title });
    replace(
      card,
      el(
        "div",
        { class: "res" },
        icon(shown.glyph, `${shown.fill ? "fill " : ""}${shown.tone}`),
        el("div", { class: "tx" }, title, ...shown.lines.map((line, at) => el("span", { class: `t2${at === shown.textLine ? " wrap" : ""}`, text: line }))),
      ),
    );
    if (announced) {
      announce([shown.title, ...shown.lines].join(". "));
      title.focus({ preventScroll: true });
    }
  }

  // ---- Open, and you may only read it
  function readOnly() {
    const ask = current.ask;
    const rows = ask.choices.map((choice) => readOnlyRow(choice.label, choice.description));
    if (ask.textStyle === "OTHER") rows.push(readOnlyRow("Other", null));
    replace(
      card,
      el(
        "div",
        { class: "res" },
        icon("lock", "c-var"),
        el(
          "div",
          { class: "tx" },
          el("span", { class: "ahead", tabindex: "-1", text: readOnlyTitle(ask) }),
          el("span", { class: "t2", text: "You can read the question." }),
          lostRight.has(current.id) ? el("span", { class: "t2", text: "Your answer wasn't sent. You can no longer answer this question." }) : null,
        ),
      ),
      rows.length ? el("div", { class: "ro", role: "list", "aria-label": "The choices, not selectable" }, rows) : null,
    );
  }

  function readOnlyRow(label, description) {
    return el("div", { class: `rr${description ? " d" : ""}`, role: "listitem" }, el("span", { class: "rg", "aria-hidden": "true" }, icon("remove")), el("div", { class: "rt" }, el("span", { text: label }), description ? el("span", { class: "rd", text: description }) : null));
  }

  // ---- Open, and you may answer
  function form() {
    const ask = current.ask;
    const producer = current.producer.name;
    const hasChoices = ask.choices.length > 0;
    const takesText = ask.text !== "NONE";
    const withOther = hasChoices && takesText && ask.textStyle === "OTHER";
    const withNote = hasChoices && takesText && !withOther;
    const typedOnly = !hasChoices;
    const multiple = ask.multiple;
    const draft = drafts.get(current.id) ?? { picked: new Set(), otherOn: false, note: "", other: "" };
    drafts.set(current.id, draft);
    let sending = false;
    const group = nextId("group");
    const errorId = nextId("pick-error");

    const rule = typedOnly ? "Type your answer." : multiple ? "Pick one or more." : "Pick one.";
    const closes = closesLine(ask, timers);
    const rows = [];
    const rowOf = (choice, value, checked) => {
      const descId = nextId("desc");
      const input = el("input", { type: multiple ? "checkbox" : "radio", name: group, value, "aria-describedby": choice.description ? descId : null, "aria-controls": value === OTHER ? "other-field" : null });
      input.checked = checked;
      const control = multiple ? el("span", { class: "cb", "aria-hidden": "true" }, icon("check")) : el("span", { class: "rb", "aria-hidden": "true" });
      const label = el("label", { class: `rr${choice.description ? " d" : ""}` }, input, control, el("div", { class: "rt" }, el("span", { text: choice.label }), choice.description ? el("span", { class: "rd", id: descId, text: choice.description }) : null));
      input.addEventListener("change", () => picked(input, value));
      return { label, input };
    };
    for (const choice of ask.choices) rows.push(rowOf(choice, choice.id, draft.picked.has(choice.id)));
    let otherRow = null;
    if (withOther) {
      otherRow = rowOf({ label: "Other" }, OTHER, draft.otherOn);
      rows.push(otherRow);
    }
    const pickError = el("div", { class: "perr", id: errorId, hidden: true });
    const list = el("div", { role: multiple ? "group" : "radiogroup", "aria-label": "Your answer", "aria-describedby": errorId }, ...rows.map((row) => row.label));

    const otherField = withOther ? textArea({ label: "Your answer", labelFor: "Your answer for Other", id: "other-field", maxRows: 4, value: draft.other, onInput: (text) => (draft.other = text) }) : null;
    if (otherField) {
      otherField.node.classList.add("other-field");
      otherField.node.hidden = !draft.otherOn;
    }
    const noteField = withNote || typedOnly
      ? textArea({
          label: typedOnly ? "Your answer" : ask.text === "REQUIRED" ? "Note" : "Note (optional)",
          placeholder: typedOnly ? "" : `Add a note for ${producer}`,
          maxRows: typedOnly ? 6 : 4,
          value: draft.note,
          onInput: (text) => (draft.note = text),
        })
      : null;

    function picked(input, value) {
      if (multiple) {
        if (value === OTHER) draft.otherOn = input.checked;
        else if (input.checked) draft.picked.add(value);
        else draft.picked.delete(value);
      } else {
        draft.picked = value === OTHER ? new Set() : new Set([value]);
        draft.otherOn = value === OTHER;
      }
      showPickError(null);
      if (otherField) {
        const wasHidden = otherField.node.hidden;
        otherField.node.hidden = !draft.otherOn;
        if (draft.otherOn && wasHidden) otherField.input.focus();
        if (!draft.otherOn) otherField.setError(null);
      }
    }

    function showPickError(message) {
      pickError.hidden = !message;
      replace(pickError, message ? [icon("error"), el("span", { text: message })] : null);
      if (message) list.setAttribute("aria-invalid", "true");
      else list.removeAttribute("aria-invalid");
    }

    // The checks of the button and of the shortcut, in the page's own words. The first problem
    // moves the focus and is the accessible description of what has it.
    function problem() {
      const text = (value) => value.trim();
      const none = draft.picked.size === 0 && !(withOther && draft.otherOn);
      if (hasChoices && none) {
        return { say: multiple ? "Pick at least one answer." : "Pick an answer to send.", focus: () => (rows.find((row) => row.input.checked) ?? rows[0]).input.focus(), show: showPickError };
      }
      if (withOther && draft.otherOn) {
        if (!text(draft.other)) return { say: "Type your answer for Other.", focus: () => otherField.input.focus(), show: otherField.setError };
        if (codePoints(draft.other) > MAX_TEXT) return { say: tooLong(draft.other), focus: () => otherField.input.focus(), show: otherField.setError };
      }
      if (noteField) {
        const required = typedOnly || ask.text === "REQUIRED";
        if (required && !text(draft.note)) return { say: typedOnly ? "Type an answer to send." : "Type a note to send.", focus: () => noteField.input.focus(), show: noteField.setError };
        if (codePoints(draft.note) > MAX_TEXT) return { say: tooLong(draft.note), focus: () => noteField.input.focus(), show: noteField.setError };
      }
      return null;
    }

    function body() {
      const choices = ask.choices.filter((choice) => draft.picked.has(choice.id)).map((choice) => choice.id);
      const text = withOther ? (draft.otherOn ? draft.other.trim() : "") : noteField ? draft.note.trim() : "";
      return text ? { choices, text } : { choices };
    }

    async function send() {
      if (sending) return;
      const found = problem();
      if (found) {
        found.show(found.say);
        found.focus();
        return;
      }
      setSending(true);
      hideSnack();
      try {
        const answer = await calls.answer(current.id, body());
        // The 200 is the accepted answer: the card swaps at once, without a second read.
        attempts.delete(current.id);
        lostRight.delete(current.id);
        drafts.delete(current.id);
        current = { ...current, answer, answerState: "ANSWERED", canAnswer: false };
        hooks.changed(current);
        paint(true);
      } catch (error) {
        setSending(false);
        if (error instanceof SessionEnded) return;
        await failed(error);
      }
    }

    async function failed(error) {
      if (error instanceof ApiError && error.status === 409 && error.question) {
        // The 409 carries the state: who answered first, or who closed it.
        const q = error.question;
        attempts.set(current.id, q.state === "ANSWERED" ? "first" : "closed");
        drafts.delete(current.id);
        current = { ...current, answer: q.answer ?? null, answerState: q.state, closedBy: q.closedBy ?? null, closedAt: q.closedAt ?? null, closeNote: q.closeNote ?? null, canAnswer: false };
        hooks.changed(current);
        paint(true);
        hooks.reread();
        return;
      }
      if (error instanceof ApiError && error.status === 404) {
        hooks.gone();
        return;
      }
      if (error instanceof ApiError && error.status === 403) {
        // A refusal may be the CSRF token or "not allowed": read the event again to tell.
        lostRight.add(current.id);
        const fresh = await hooks.reread();
        if (fresh && !fresh.canAnswer && fresh.answerState === "OPEN") {
          current = fresh;
          paint(true);
          return;
        }
        lostRight.delete(current.id);
      }
      showSnack({ text: "Answer not sent", action: "Retry", onAction: () => send() });
    }

    function setSending(on) {
      sending = on;
      sendButton.classList.toggle("busy", on);
      if (on) sendButton.setAttribute("aria-busy", "true");
      else sendButton.removeAttribute("aria-busy");
      sendButton.setAttribute("aria-disabled", String(on));
      sendButton.setAttribute("aria-label", on ? "Sending answer" : "Send answer");
      sendLabel.textContent = on ? "Sending" : "Send answer";
      for (const part of [list, noteField?.node, otherField?.node]) part?.classList.toggle("dim", on);
      for (const input of card.querySelectorAll("input, textarea")) input.disabled = on;
      if (on) announce("Sending answer");
    }

    const mac = isMac();
    const hint = `Send answer (${mac ? "Cmd" : "Ctrl"}+Enter)`;
    const sendLabel = el("span", { class: "btn-label", text: "Send answer" });
    const sendButton = el("button", { type: "button", class: "btn btn-f", "aria-keyshortcuts": "Control+Enter Meta+Enter" }, sendLabel);
    sendButton.addEventListener("click", send);
    const tip = el("span", { class: "tip", "aria-hidden": "true", text: hint });

    // Ctrl+Enter (Cmd+Enter on a Mac) sends from anywhere in the card, as the button does, and does
    // not add a line in a text area. It does nothing while an input method composes.
    card.addEventListener("keydown", (key) => {
      if (key.key !== "Enter" || !(key.ctrlKey || key.metaKey) || key.isComposing) return;
      key.preventDefault();
      send();
    });

    replace(
      card,
      closes,
      el("div", { class: "ahead", text: "Your answer" }),
      el("div", { class: "p", text: `${rule} It goes to ${producer} and can't be changed once sent.` }),
      hasChoices ? list : null,
      hasChoices ? pickError : null,
      otherField?.node,
      noteField ? el("div", { class: "note-wrap" }, noteField.node) : null,
      el("div", { class: "send" }, el("div", { class: "send-wrap" }, sendButton, tip)),
    );
    // Typed-only: its problems go under the field, so the list has none to describe.
    if (!hasChoices) pickError.remove();
    if (otherField) otherField.input.setAttribute("aria-label", "Your answer for Other");
    requestAnimationFrame(() => {
      otherField?.refit();
      noteField?.refit();
    });
  }

  paint();
  return card;
}

function tooLong(text) {
  const over = codePoints(text) - MAX_TEXT;
  return `Too long: ${over} ${over === 1 ? "character" : "characters"} over the limit.`;
}

/**
 * *Closes at 09:00*, grey; in the last hour *Closes at 09:00 · in 12 min* in the error colour with a
 * clock icon. The minutes update once a minute and are not announced.
 */
function closesLine(ask, timers) {
  if (!ask.closesAt) return null;
  const text = el("span", { class: "closes-text" });
  const node = el("div", { class: "closes" }, icon("schedule", "ms18"), text);
  const paint = () => {
    const left = new Date(ask.closesAt).getTime() - Date.now();
    const base = `Closes ${whenAt(ask.closesAt)}`;
    const soon = left > 0 && left <= 3_600_000;
    text.textContent = soon ? `${base} · in ${Math.max(1, Math.ceil(left / 60_000))} min` : base;
    node.classList.toggle("soon", soon);
  };
  paint();
  const id = setInterval(paint, 60_000);
  timers.push(() => clearInterval(id));
  return node;
}

/**
 * An outlined text area with its label on the border, a counter, and a message line. It starts at
 * one line and grows to `maxRows`, then scrolls; Enter adds a line. Past 3000 characters the
 * counter and the message turn to the error colour, and the text is never cut.
 */
function textArea({ label, labelFor, id = nextId("area"), placeholder = "", maxRows, value = "", onInput }) {
  const input = el("textarea", { id, rows: "1", placeholder, autocomplete: "off", spellcheck: "true", "aria-describedby": `${id}-help` });
  input.value = value;
  const box = el("div", { class: `tf ta rows-${maxRows}` }, input, el("label", { class: "fl", for: id, text: label }));
  const message = el("span", { class: "hl" });
  const counter = el("span", { class: "cnt", text: `${codePoints(value)} / ${MAX_TEXT}` });
  const help = el("div", { class: "help", id: `${id}-help` }, message, counter);
  const node = el("div", { class: "fieldw" }, box, help);
  let flagged = false;

  const refit = () => {
    // Not laid out yet (the card is built before it is in the page): the next call fits it.
    if (!input.isConnected) return;
    input.style.height = "auto";
    input.style.height = `${input.scrollHeight}px`;
  };
  const api = {
    node,
    input,
    refit,
    setError(text) {
      const failed = Boolean(text);
      box.classList.toggle("err", failed);
      help.classList.toggle("err", failed);
      if (failed) input.setAttribute("aria-invalid", "true");
      else input.removeAttribute("aria-invalid");
      replace(message, failed ? [icon("error"), el("span", { text })] : null);
    },
  };
  input.addEventListener("input", () => {
    onInput?.(input.value);
    refit();
    const length = codePoints(input.value);
    counter.textContent = `${length} / ${MAX_TEXT}`;
    if (length > MAX_TEXT) {
      const say = tooLong(input.value);
      api.setError(say);
      // Said once, politely, as it appears; not on every key after.
      if (!flagged) announce(say);
      flagged = true;
    } else {
      api.setError(null);
      flagged = false;
    }
  });
  return api;
}
