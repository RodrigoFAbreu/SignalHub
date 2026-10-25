// Events: a dense table of what the producers sent, newest first, a page of 25 at a time, with filter
// chips and a fixed detail pane for the selected event. The listing is read by the management API's
// own cursor and filters (no search, no sort), so a filter starts over from the newest page and
// Newer goes back through the pages already read. A chosen filter and the open event are in the
// address. Everything the server sends is set as text.

import { DELETE_EVENTS, EVENTS, PRODUCERS, STATUS, SessionEnded, call } from "./api.js";
import { el, icon } from "./dom.js";
import { deleteByRule, eventCount, sendTestEvent } from "./event-dialogs.js";
import { CATEGORIES, QUESTIONS, READ_STATES, RELATIONS, SEVERITIES, categoryOf, describe, emptyFilters, filterCount, fromQuery, isFiltered, rangeText, severityOf, toApi, toQuery, valuesText } from "./event-filters.js";
import { createEventPane, severityChip } from "./event-pane.js";
import { askingWords } from "./ask-form.js";
import { QUESTIONS_GO_TOO, askingCount, markerNode, markerOf } from "./question.js";
import { clock, duration, shortDate } from "./format.js";
import { ID, go, hashFor, keepAddress } from "./router.js";
import { setDetailOpen } from "./shell.js";
import { loadClients, loadUsers } from "./store.js";
import { announce, banner, button, checkRow, chip, confirmDialog, emptyState, iconButton, openDialog, openMenu, openPanel, phone, skeletonRows, snack, textField } from "./ui.js";

const PAGE = 25;
const REFRESH_MS = 30_000;
const LONG_PRESS_MS = 500;

/** 3 min, 2 h, then the day: the table's Received column. */
function received(iso, now = Date.now()) {
  const age = Math.max(0, now - Date.parse(iso));
  if (age < 60_000) return "now";
  if (age < 3_600_000) return `${Math.round(age / 60_000)} min`;
  if (age < 86_400_000) return `${Math.round(age / 3_600_000)} h`;
  return shortDate(iso);
}

const number = (value) => value.toLocaleString("en");

// ---- State ---------------------------------------------------------------------------------------

let host = null;
let nodes = null;
let pane = null;
let filters = emptyFilters();
let selectedId = null;
// The cursor of each page read so far, the first having none; the last is the page shown.
let cursors = [null];
let items = null;
let nextCursor = null;
let total = null;
let loadedAt = null;
let failure = null;
let loading = false;
let ticked = new Set();
let timer = null;
let sequence = 0;
let restoreFocus = null;
let pressTimer = null;
let swallowClick = false;
// Whether older events were added under the first page (a phone): a refresh would drop them.
let appended = false;
// What the filters and the dialogs offer: read when the section opens.
let producers = [];
let users = [];
let retention = null;

const names = {
  producer: (id) => producers.find((item) => item.id === id)?.name ?? "a producer",
  user: (id) => users.find((item) => item.id === id)?.name ?? "a user",
};

const query = () => toQuery(filters);
const addressFor = (id) => hashFor("events", id, query());

// ---- Reading -------------------------------------------------------------------------------------

function listParams(cursor) {
  const params = toApi(filters);
  params.set("limit", String(PAGE));
  params.set("total", "true");
  if (cursor) params.set("cursor", cursor);
  return params;
}

/** Reads the page shown again. `first` starts over from the newest page. */
async function reload({ first = false } = {}) {
  if (!nodes) return;
  if (first) {
    cursors = [null];
    ticked = new Set();
  }
  const mine = ++sequence;
  loading = true;
  appended = false;
  paintHead();
  paintTable();
  try {
    const page = await call("GET", `${EVENTS}?${listParams(cursors.at(-1))}`);
    if (mine !== sequence || !nodes) return;
    items = page.items;
    nextCursor = page.nextCursor;
    total = page.total ?? null;
    failure = null;
    loadedAt = new Date();
    // What was ticked stays ticked only while the event is on the page.
    const present = new Set(items.map((item) => item.id));
    ticked = new Set([...ticked].filter((id) => present.has(id)));
    const shown = items.find((item) => item.id === selectedId);
    if (shown) pane?.follow(shown);
  } catch (error) {
    if (mine !== sequence || !nodes || error.name === "SessionEnded" || error instanceof SessionEnded) return;
    failure = error;
  }
  loading = false;
  paintAll();
}

async function readLookups() {
  const results = await Promise.allSettled([call("GET", PRODUCERS), loadUsers(), loadClients(), call("GET", STATUS)]);
  if (!nodes) return;
  if (results[0].status === "fulfilled") producers = results[0].value.items;
  if (results[1].status === "fulfilled") users = results[1].value;
  if (results[3].status === "fulfilled") retention = results[3].value.eventRetentionSeconds ?? null;
  paintChips();
  paintTable();
  paintHead();
}

// ---- Building ------------------------------------------------------------------------------------

function build() {
  const count = el("span", { class: "cnt", "aria-live": "polite" });
  const stamp = el("span", { class: "cnt small keep" });
  const refresh = iconButton("refresh", "Refresh", () => reload());
  const send = button("Send a test event", { kind: "tonal", glyph: "science", onClick: () => openSend(), className: "primary" });
  const more = iconButton("more_vert", "More", () => openMore(more));
  const head = el("div", { class: "mhead" }, el("h1", { text: "Events", tabindex: "-1" }), count, el("span", { class: "sp" }), stamp, refresh, send, more);
  const phoneBar = el("div", { class: "phone-actions" });
  const chips = el("div", { class: "fchips", role: "group", "aria-label": "Filter events" });
  const tools = el("div", { class: "tools" }, chips);
  const bulk = el("div", { class: "bulk", role: "toolbar", "aria-label": "Selected events", hidden: true });
  const bar = el("div", { class: "prog", role: "progressbar", "aria-label": "Loading events", hidden: true });
  const slot = el("div", { class: "banner-slot" });
  const table = el("div", { class: "tbl" });
  const pager = el("div", { class: "pgr" });
  const left = el("div", { class: "left" }, head, phoneBar, tools, bulk, bar, slot, table, pager);
  const scrim = el("div", { class: "sheet-scrim", hidden: true, on: { click: () => closePane() } });
  const prompt = el("div", { class: "pane prompt" }, emptyState({ glyph: "inbox", title: "Select an event", body: "Its message, link, metadata and how its push went show here." }));
  const cols = el("div", { class: "cols ev" }, left, scrim, pane.node, prompt);
  return { count, stamp, refresh, send, more, head, phoneBar, chips, tools, bulk, bar, slot, table, pager, scrim, prompt, left, cols };
}

// ---- Painting ------------------------------------------------------------------------------------

function paintAll() {
  paintHead();
  paintChips();
  paintBulk();
  paintTable();
  paintPager();
  paintPane();
}

function countText() {
  if (items === null) return failure ? "Not loaded" : "Loading…";
  if (total === 0 || items.length === 0) return "0 events";
  if (total !== null) {
    const base = items.length === total && cursors.length === 1 ? eventCount(total) : `${number(items.length)} of ${number(total)}`;
    return `${base} · Newest first`;
  }
  return items.length === 0 ? "0 events" : "Newest first";
}

function stampText() {
  if (items === null) return failure ? "Not updated" : "";
  if (failure) return `Not updated since ${clock(loadedAt)}`;
  return loading ? "Updating…" : `Updated ${clock(loadedAt)}`;
}

function paintHead() {
  if (!nodes) return;
  nodes.count.textContent = countText();
  nodes.stamp.textContent = stampText();
  nodes.bar.hidden = !loading;
  nodes.refresh.disabled = loading && items === null;
  paintPhoneBar();
}

function paintPhoneBar() {
  const active = filterCount(filters);
  nodes.phoneBar.replaceChildren(
    el("button", { type: "button", class: "btn-o sm filters-btn", on: { click: () => openFiltersSheet() } }, icon("tune"), "Filters", active ? el("span", { class: "tg p", text: String(active) }) : null),
    button("Send a test event", { kind: "tonal", glyph: "science", onClick: () => openSend(), className: "sm" }),
  );
}

// A chip with several values: a panel of checkboxes that stays open, applied when it closes.
function multiChip({ key, prefix, options, selected, set }) {
  const labels = options.filter((option) => selected.includes(option.value)).map((option) => option.text);
  const sorted = key === "severity" ? [...labels].reverse() : labels;
  const on = selected.length > 0;
  const node = chip({
    label: on ? `${prefix}: ${valuesText(sorted)}` : prefix,
    on,
    menu: true,
    onClick: () => {
      let draft = [...selected];
      const content = options.length
        ? [
            ...options.map((option) =>
              checkRow({
                label: option.text,
                checked: draft.includes(option.value),
                onChange: (checked) => {
                  draft = checked ? [...draft, option.value] : draft.filter((value) => value !== option.value);
                },
              }),
            ),
            el("button", { type: "button", class: "btn-x clear-row", on: { click: () => { draft = []; panel.close(); } } }, "Clear"),
          ]
        : [el("div", { class: "mu info-row" }, el("span", { text: `No ${prefix.toLowerCase()} to choose from.` }))];
      const panel = openPanel(node, {
        label: `${prefix} filter`,
        content,
        width: 240,
        onClose: () => {
          const same = draft.length === selected.length && draft.every((value) => selected.includes(value));
          if (!same) set(draft);
        },
      });
    },
  });
  node.setAttribute("aria-haspopup", "true");
  node.dataset.key = key;
  if (on) node.prepend(icon("check", "ms18"));
  return node;
}

function singleChip({ key, prefix, options, value, any, set }) {
  const current = options.find((option) => option.value === value && value !== "");
  const node = chip({
    label: current ? `${prefix}: ${current.text}` : prefix,
    on: Boolean(current),
    menu: true,
    onClick: () =>
      openMenu(node, {
        placement: "below-start",
        label: `${prefix} filter`,
        narrow: true,
        items: [
          ...(any ? [{ label: any, selected: !value, onSelect: () => set("") }] : []),
          ...options.filter((option) => option.value !== "" || !any).map((option) => ({ label: option.text, sub: option.sub, selected: option.value === value, onSelect: () => set(option.value) })),
        ],
      }),
  });
  node.dataset.key = key;
  if (current) node.prepend(icon("check", "ms18"));
  return node;
}

function receivedChip() {
  const range = rangeText(filters);
  const node = chip({
    label: range ? `Received: ${range}` : "Received",
    on: Boolean(range),
    menu: true,
    onClick: () => openReceived(node),
  });
  node.setAttribute("aria-haspopup", "true");
  node.dataset.key = "received";
  if (range) node.prepend(icon("check", "ms18"));
  return node;
}

function paintChips() {
  if (!nodes) return;
  const group = nodes.chips;
  const userOptions = users.map((item) => ({ value: item.id, text: item.name, sub: item.revokedAt ? "Revoked" : null }));
  const pushChip = chip({ label: "Push problems", on: filters.push, onClick: () => setFilters({ push: !filters.push }, "push") });
  pushChip.dataset.key = "push";
  const list = [
    singleChip({ key: "read", prefix: "Read state", options: READ_STATES, value: filters.read, set: (value) => setFilters({ read: value }, "read") }),
    multiChip({ key: "severity", prefix: "Severity", options: SEVERITIES, selected: filters.severity, set: (value) => setFilters({ severity: value }, "severity") }),
    singleChip({ key: "question", prefix: "Question", options: QUESTIONS, value: filters.question, set: (value) => setFilters({ question: value }, "question") }),
    pushChip,
    multiChip({ key: "producer", prefix: "Producer", options: [...producers].sort((a, b) => a.name.localeCompare(b.name)).map((item) => ({ value: item.id, text: item.name })), selected: filters.producer, set: (value) => setFilters({ producer: value }, "producer") }),
    multiChip({ key: "category", prefix: "Category", options: CATEGORIES, selected: filters.category, set: (value) => setFilters({ category: value }, "category") }),
    singleChip({ key: "user", prefix: "User", options: userOptions, value: filters.user, any: "Any user", set: (value) => setFilters({ user: value, relation: "" }, "user") }),
  ];
  // Which of a user's producers means nothing without the user: its chip comes with one.
  if (filters.user) {
    list.push(singleChip({ key: "relation", prefix: "Their producers", options: RELATIONS, value: filters.relation, set: (value) => setFilters({ relation: value }, "relation") }));
  }
  list.push(receivedChip());
  if (isFiltered(filters)) {
    const clear = el("button", { type: "button", class: "fc plain", on: { click: () => clearFilters() } }, "Clear filters");
    clear.dataset.key = "clear";
    list.push(clear);
  }
  const focused = document.activeElement?.dataset?.key;
  group.replaceChildren(...list);
  if (focused) group.querySelector(`[data-key='${focused}']`)?.focus({ preventScroll: true });
}

function paintBulk() {
  if (!nodes) return;
  const count = ticked.size;
  nodes.bulk.hidden = count === 0;
  nodes.tools.hidden = count > 0;
  nodes.left.classList.toggle("selecting", count > 0);
  if (count === 0) {
    nodes.bulk.replaceChildren();
    return;
  }
  const every = items.length > 0 && items.every((item) => ticked.has(item.id));
  nodes.bulk.replaceChildren(
    iconButton("close", "Clear the selection", () => clearSelection()),
    el("span", { class: "bulk-count", text: `${count} selected` }),
    every ? null : button(`Select all ${items.length} on this page`, { kind: "text", onClick: () => selectAll(), className: "select-all" }),
    el("span", { class: "sp" }),
    button("Mark read", { kind: "text", glyph: "mark_email_read", onClick: () => markTickedRead() }),
    button("Delete", { kind: "text-error", glyph: "delete", ariaLabel: `Delete ${eventCount(count)}`, onClick: () => deleteTicked() }),
  );
}

function paintPager() {
  if (!nodes) return;
  let text = "";
  if (items === null) text = failure ? "Not loaded" : "Loading…";
  else if (items.length === 0) text = "No events";
  else if (cursors.length > 1) {
    const start = (cursors.length - 1) * PAGE + 1;
    text = `Events ${number(start)} to ${number(start + items.length - 1)}`;
  } else text = nextCursor ? `Newest ${items.length} events` : eventCount(items.length);
  nodes.pager.replaceChildren(
    el("span", { class: "pgr-text", text }),
    el("span", { class: "sp" }),
    button("Newer", { kind: "outlined", glyph: "chevron_left", disabled: cursors.length === 1 || loading, onClick: () => page(-1), className: "sm" }),
    el(
      "button",
      { type: "button", class: "btn-o sm older", disabled: !nextCursor || loading, on: { click: () => (phone() ? loadMore() : page(1)) } },
      el("span", { class: "w-wide", text: "Older" }),
      el("span", { class: "w-phone", text: `Load ${PAGE} older events` }),
      icon("chevron_right"),
    ),
  );
}

// On a phone the older events are added under the ones shown, as a list is read there.
async function loadMore() {
  const mine = ++sequence;
  loading = true;
  paintHead();
  paintPager();
  try {
    const more = await call("GET", `${EVENTS}?${listParams(nextCursor)}`);
    if (mine !== sequence || !nodes) return;
    items = [...items, ...more.items];
    nextCursor = more.nextCursor;
    total = more.total ?? total;
    appended = true;
  } catch (error) {
    if (mine !== sequence || !nodes || error.name === "SessionEnded") return;
    snack(`Could not load older events. ${error.message}`, { label: "Try again", onClick: () => loadMore() });
  }
  loading = false;
  paintAll();
}

function page(step) {
  if (step > 0) cursors = [...cursors, nextCursor];
  else cursors = cursors.slice(0, -1);
  ticked = new Set();
  reload();
  nodes.table.scrollTop = 0;
}

// ---- The table -----------------------------------------------------------------------------------

function paintTable() {
  if (!nodes) return;
  const table = nodes.table;
  const focusedRow = document.activeElement?.closest?.(".tr")?.dataset.id ?? null;
  nodes.slot.replaceChildren();
  if (items === null && failure === null) {
    table.replaceChildren(headerRow(), skeletonRows(5));
    table.setAttribute("aria-busy", "true");
    return;
  }
  table.removeAttribute("aria-busy");
  if (items === null) {
    const unreachable = failure.kind === "unreachable";
    table.replaceChildren(
      headerRow(),
      emptyState({
        glyph: "cloud_off",
        title: "Could not load events",
        body: unreachable ? "The server did not answer. Check that SignalHub is running, then try again." : failure.message,
        action: button("Try again", { kind: "tonal", glyph: "refresh", onClick: () => reload() }),
      }),
    );
    return;
  }
  if (failure) {
    nodes.slot.append(banner({ glyph: "error", error: true, role: "alert", text: `Could not refresh. This list is from ${clock(loadedAt)} and may be out of date.`, actions: [button("Try again", { onClick: () => reload() })] }));
  }
  if (items.length === 0) {
    table.replaceChildren(headerRow(), emptyList());
    return;
  }
  const rows = items.map((item) => buildRow(item));
  const grid = el("div", { role: "grid", "aria-label": "Events", "aria-rowcount": String(items.length + 1) }, headerRow(), ...rows);
  const stop = rows.find((row) => row.getAttribute("aria-selected") === "true") ?? rows[0];
  stop.tabIndex = 0;
  grid.addEventListener("keydown", onGridKey);
  table.replaceChildren(grid);
  if (focusedRow) table.querySelector(`.tr[data-id='${focusedRow}']`)?.focus({ preventScroll: true });
}

function emptyList() {
  if (isFiltered(filters)) {
    return emptyState({ glyph: "filter_alt_off", title: "No events match", body: describe(filters, names), action: button("Clear filters", { kind: "tonal", onClick: () => clearFilters() }) });
  }
  const kept = retention ? ` Events older than ${duration(retention)} are removed.` : "";
  return emptyState({
    glyph: "inbox",
    title: "No events yet",
    body: `Events show here as soon as a producer sends one. Send a test event to see how one looks and how it reaches devices.${kept}`,
    action: button("Send a test event", { kind: "tonal", glyph: "science", onClick: () => openSend() }),
  });
}

function checkbox(checked, label, mixed = false, onClick) {
  const box = el("span", { class: `cb${checked || mixed ? " on" : ""}` }, checked ? icon("check") : mixed ? icon("remove") : null);
  const node = el("button", { type: "button", class: "cbc", role: "checkbox", "aria-checked": mixed ? "mixed" : String(checked), "aria-label": label, tabindex: "-1" }, box);
  node.addEventListener("click", (event) => {
    event.stopPropagation();
    onClick();
  });
  return node;
}

function headerRow() {
  const all = items !== null && items.length > 0 && items.every((item) => ticked.has(item.id));
  const some = ticked.size > 0 && !all;
  const select = checkbox(all, "Select all events on this page", some, () => (all ? clearSelection() : selectAll()));
  select.tabIndex = items && items.length ? 0 : -1;
  return el(
    "div",
    { class: "th gE", role: "row" },
    el("span", { role: "columnheader", class: "c-box" }, select),
    el("span", { role: "columnheader", text: "Event" }),
    el("span", { role: "columnheader", class: "c-producer", text: "Producer" }),
    el("span", { role: "columnheader", class: "c-severity", text: "Severity" }),
    el("span", { role: "columnheader", class: "c-category", text: "Category" }),
    el("span", { role: "columnheader", class: "c-received", text: "Received" }),
  );
}

const pushProblem = (item) => item.push === "FAILED" || item.push === "GAVE_UP";

function buildRow(item) {
  const unread = !item.readAt;
  const checked = ticked.has(item.id);
  const severity = severityOf(item.severity);
  const category = categoryOf(item.category);
  const problem = pushProblem(item);
  const age = received(item.createdAt);
  const marker = markerOf(item);
  const label = `${item.title}, ${severity?.text ?? item.severity}, ${category?.text ?? item.category}, ${item.producer.name}, ${age === "now" ? "just now" : age}${unread ? ", unread" : ""}${problem ? ", push problems" : ""}${marker ? `, ${marker.word.toLowerCase()}` : ""}`;
  const row = el(
    "div",
    { class: `tr gE${unread ? " unr" : ""}${checked ? " chk" : ""}`, id: `row-${item.id}`, role: "row", tabindex: "-1", "aria-selected": String(item.id === selectedId), "aria-label": label, data: { id: item.id } },
    el("span", { role: "gridcell", class: "c-box" }, checkbox(checked, `Select ${item.title}`, false, () => toggle(item.id))),
    el(
      "span",
      { class: "nmc", role: "gridcell" },
      unread ? el("span", { class: "ud" }) : el("span", { class: "udz" }),
      icon(category?.glyph ?? "info", `cic s-${severity?.tone ?? "low"}`),
      el("span", { class: "nm", text: item.title }),
      markerNode(item),
      problem ? el("span", { class: "pp" }, icon("error"), el("span", { class: "pp-w", text: "Push problems" })) : null,
    ),
    el("span", { role: "gridcell", class: "cell nm-var c-producer", text: item.producer.name }),
    el("span", { role: "gridcell", class: "c-severity" }, severityChip(item.severity)),
    el("span", { role: "gridcell", class: "cell c-category", text: category?.text ?? item.category }),
    el("span", { role: "gridcell", class: "cell c-received", text: age }),
    el("span", { class: "m2", "aria-hidden": "true", text: `${item.producer.name} · ${severity?.text ?? item.severity} · ${age}` }),
  );
  row.addEventListener("click", () => {
    if (swallowClick) {
      swallowClick = false;
      return;
    }
    // While rows are ticked on a phone, a tap ticks.
    if (phone() && ticked.size > 0) toggle(item.id);
    else openEvent(item.id);
  });
  // A long press ticks a row on a phone, and turns the header into the bulk bar.
  row.addEventListener("pointerdown", (event) => {
    swallowClick = false;
    if (!phone() || event.pointerType === "mouse") return;
    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      swallowClick = true;
      toggle(item.id);
    }, LONG_PRESS_MS);
  });
  for (const stop of ["pointerup", "pointercancel", "pointermove", "pointerleave"]) row.addEventListener(stop, () => clearTimeout(pressTimer));
  row.addEventListener("contextmenu", (event) => {
    if (phone()) event.preventDefault();
  });
  return row;
}

function onGridKey(event) {
  const rows = [...nodes.table.querySelectorAll(".tr")];
  const at = rows.indexOf(document.activeElement);
  if (at < 0) return;
  let next = null;
  if (event.key === "ArrowDown") next = rows[Math.min(rows.length - 1, at + 1)];
  else if (event.key === "ArrowUp") next = rows[Math.max(0, at - 1)];
  else if (event.key === "Home") next = rows[0];
  else if (event.key === "End") next = rows.at(-1);
  else if (event.key === "Enter") {
    event.preventDefault();
    openEvent(rows[at].dataset.id);
    return;
  } else if (event.key === " ") {
    event.preventDefault();
    toggle(rows[at].dataset.id);
    return;
  }
  if (!next) return;
  event.preventDefault();
  for (const row of rows) row.tabIndex = row === next ? 0 : -1;
  next.focus();
}

// ---- Selection -----------------------------------------------------------------------------------

function toggle(id) {
  if (ticked.has(id)) ticked.delete(id);
  else ticked.add(id);
  afterSelection();
}

function selectAll() {
  ticked = new Set(items.map((item) => item.id));
  afterSelection();
}

function clearSelection() {
  ticked = new Set();
  afterSelection();
}

function afterSelection() {
  const row = document.activeElement?.closest?.(".tr")?.dataset.id;
  paintBulk();
  paintTable();
  paintPane();
  if (row) nodes.table.querySelector(`.tr[data-id='${row}']`)?.focus({ preventScroll: true });
  announce(ticked.size ? `${ticked.size} selected` : "Selection cleared");
}

async function markTickedRead() {
  const ids = [...ticked];
  const results = await Promise.allSettled(ids.map((id) => call("PUT", `${EVENTS}/${id}/read`)));
  const failed = results.filter((result) => result.status === "rejected" && result.reason?.name !== "SessionEnded").length;
  for (const result of results) {
    if (result.status !== "fulfilled") continue;
    const at = items?.findIndex((item) => item.id === result.value.id) ?? -1;
    if (at >= 0) items[at] = { ...items[at], ...result.value, push: items[at].push };
  }
  if (failed) {
    snack(`Could not mark ${failed} of ${eventCount(ids.length)} read.`, { label: "Try again", onClick: () => markTickedRead() });
  } else {
    snack(`Marked ${eventCount(ids.length)} read`);
    ticked = new Set();
  }
  paintBulk();
  paintTable();
}

// The selection is rows of the page being shown, so which ask is known without asking the server.
function deleteTickedWords(ids) {
  const asking = items.filter((item) => ids.includes(item.id) && item.ask).length;
  const usual = "They are gone for good, with their waiting pushes and delivery records. Producers and users are not touched. This cannot be undone.";
  if (!asking) return usual;
  return `${eventCount(ids.length)} will be deleted, ${askingCount(asking)}. ${QUESTIONS_GO_TOO} This cannot be undone.`;
}

function deleteTicked() {
  const ids = [...ticked];
  return confirmDialog({
    title: `Delete ${eventCount(ids.length)}?`,
    message: deleteTickedWords(ids),
    action: `Delete ${eventCount(ids.length)}`,
    destructive: true,
    busyLabel: "Deleting…",
    retryLabel: "Try again",
    run: async () => {
      const done = await call("POST", DELETE_EVENTS, { ids });
      ticked = new Set();
      snack(`Deleted ${eventCount(done.count)}`);
      if (selectedId && ids.includes(selectedId)) go(addressFor(null));
      await reload();
    },
  });
}

// ---- Filters -------------------------------------------------------------------------------------

function setFilters(change, focusKey) {
  filters = { ...filters, ...change };
  keepAddress(addressFor(selectedId));
  ticked = new Set();
  reload({ first: true });
  paintChips();
  if (focusKey) nodes.chips.querySelector(`[data-key='${focusKey}']`)?.focus({ preventScroll: true });
}

function clearFilters() {
  filters = emptyFilters();
  keepAddress(addressFor(selectedId));
  reload({ first: true });
  paintChips();
  nodes.chips.querySelector("[data-key='read']")?.focus({ preventScroll: true });
}

// The Received panel: a from and a before day, in this browser's time zone, with presets.
function openReceived(anchor) {
  const from = textField({ label: "From", type: "date", value: filters.from });
  const before = textField({ label: "Before", type: "date", value: filters.before });
  const help = el("div", { class: "help", text: "Midnight (00:00) in your browser's time zone. Events on the day before “Before” are included; the day itself is not." });
  const apply = () => {
    if (from.input.value && before.input.value && before.input.value <= from.input.value) {
      before.setError("Before must be a day after From.");
      return;
    }
    panel.close();
    setFilters({ from: from.input.value, before: before.input.value }, "received");
  };
  const today = new Date();
  const dayOf = (offset) => {
    const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);
    return [date.getFullYear(), String(date.getMonth() + 1).padStart(2, "0"), String(date.getDate()).padStart(2, "0")].join("-");
  };
  const preset = (label, start) =>
    el("button", { type: "button", class: "fc", on: { click: () => { from.input.value = dayOf(start); before.input.value = dayOf(1); before.setError(""); } } }, el("span", { text: label }));
  const panel = openPanel(anchor, {
    label: "Received filter",
    width: 320,
    content: el(
      "div",
      { class: "received-panel" },
      el("div", { class: "t1", text: "Received" }),
      el("div", { class: "pdates" }, from.node, before.node),
      help,
      el("div", { class: "pre" }, preset("Today", 0), preset("Last 7 days", -6), preset("Last 30 days", -29)),
      el(
        "div",
        { class: "panel-acts" },
        button("Clear", { kind: "text", onClick: () => { panel.close(); setFilters({ from: "", before: "" }, "received"); } }),
        button("Apply", { kind: "text", onClick: apply }),
      ),
    ),
  });
}

// ---- The phone's filters sheet -------------------------------------------------------------------

function openFiltersSheet() {
  let draft = { ...filters };
  const open = new Set();
  const slot = el("div", { class: "sheet-fields" });
  const clear = button("Clear", { kind: "text", className: "sheet-clear", onClick: () => { draft = emptyFilters(); draw(); } });
  const confirm = { label: "Show events", value: true, kind: "filled", className: "confirm" };
  let counter = 0;

  // What the button says it will show: the listing asked for one event and its total.
  async function recount() {
    const mine = ++counter;
    try {
      const answer = await call("GET", `${EVENTS}?${new URLSearchParams([...toApi(draft), ["limit", "1"], ["total", "true"]])}`);
      if (mine !== counter) return;
      const text = answer.total === 0 ? "No events" : `Show ${eventCount(answer.total)}`;
      dialog.node.querySelector(".confirm .btn-label").textContent = text;
    } catch {
      // The button keeps its plain words.
    }
  }

  const field = (key, name, value, body) => {
    const expanded = open.has(key);
    return [
      el("button", { type: "button", class: `sel2${expanded ? " on" : ""}`, "aria-expanded": String(expanded), "aria-label": `${name}: ${value}`, on: { click: () => { if (open.has(key)) open.delete(key); else open.add(key); draw(); } } }, el("i", { text: name }), el("span", { text: value }), icon(expanded ? "arrow_drop_up" : "arrow_drop_down", "ms18")),
      expanded ? el("div", { class: "sel-body" }, body) : null,
    ];
  };

  // A choice redraws the sheet (the fields say what is chosen) and the focus stays on the choice.
  const checks = (options, key) =>
    options.map((option) => {
      const id = `${key}:${option.value}`;
      const node = checkRow({
        label: option.text,
        checked: draft[key].includes(option.value),
        onChange: (checked) => {
          draft = { ...draft, [key]: checked ? [...draft[key], option.value] : draft[key].filter((value) => value !== option.value) };
          draw();
          slot.querySelector(`[data-id='${id}']`)?.focus({ preventScroll: true });
        },
      });
      node.dataset.id = id;
      return node;
    });

  const radios = (options, key) =>
    options.map((option) => {
      const on = draft[key] === option.value;
      return el("button", { type: "button", role: "radio", "aria-checked": String(on), class: "mu", on: { click: () => { draft = { ...draft, [key]: option.value, ...(key === "user" ? { relation: "" } : {}) }; draw(); } } }, icon(on ? "radio_button_checked" : "radio_button_unchecked", "ms18"), el("span", { text: option.text }));
    });

  function draw() {
    const sever = draft.severity.length ? valuesText([...SEVERITIES.filter((item) => draft.severity.includes(item.value)).map((item) => item.text)].reverse()) : "All severities";
    const rangeNow = rangeText(draft);
    const userName = draft.user ? names.user(draft.user) : "All users";
    const rows = [
      ...field("producer", "Producer", draft.producer.length ? valuesText(draft.producer.map(names.producer)) : "All producers", checks([...producers].sort((a, b) => a.name.localeCompare(b.name)).map((item) => ({ value: item.id, text: item.name })), "producer")),
      ...field("user", "User", userName, radios([{ value: "", text: "All users" }, ...users.map((item) => ({ value: item.id, text: item.name }))], "user")),
      ...field("severity", "Severity", sever, checks(SEVERITIES, "severity")),
      ...field("category", "Category", draft.category.length ? valuesText(CATEGORIES.filter((item) => draft.category.includes(item.value)).map((item) => item.text)) : "All categories", checks(CATEGORIES, "category")),
      ...field("read", "Read state", READ_STATES.find((item) => item.value === draft.read).text, radios(READ_STATES, "read")),
      ...field("question", "Question", QUESTIONS.find((item) => item.value === draft.question).text, radios(QUESTIONS, "question")),
      ...field("received", "Received", rangeNow || "Any time", receivedFields()),
      pushRow(),
    ];
    slot.replaceChildren(...rows.filter(Boolean));
    recount();
  }

  function pushRow() {
    const node = checkRow({
      label: "Push problems only",
      checked: draft.push,
      onChange: (checked) => {
        draft = { ...draft, push: checked };
        draw();
        slot.querySelector("[data-id='push']")?.focus({ preventScroll: true });
      },
    });
    node.dataset.id = "push";
    return node;
  }

  function receivedFields() {
    const from = textField({ label: "From", type: "date", value: draft.from, onInput: (value) => { draft = { ...draft, from: value }; recount(); } });
    const before = textField({ label: "Before", type: "date", value: draft.before, onInput: (value) => { draft = { ...draft, before: value }; recount(); } });
    return el("div", { class: "pdates" }, from.node, before.node);
  }

  const dialog = openDialog({
    title: "Filters",
    content: el("div", {}, clear, slot),
    variant: "sheet",
    actions: [
      { ...confirm, run: async () => { filters = draft; keepAddress(addressFor(selectedId)); reload({ first: true }); paintChips(); } },
    ],
    initialFocus: true,
  });
  draw();
}

// ---- Header actions ------------------------------------------------------------------------------

function openMore(anchor) {
  openMenu(anchor, {
    label: "More",
    items: [
      { glyph: "refresh", label: "Refresh now", onSelect: () => reload() },
      { glyph: "delete_sweep", label: "Delete events by rule…", danger: true, onSelect: () => openDeleteByRule() },
    ],
  });
}

function openSend() {
  const preset = filters.producer.length === 1 ? filters.producer[0] : undefined;
  sendTestEvent({
    producers,
    preset,
    onSent: async (sent) => {
      const asked = askingWords(sent.ask?.whoCanAnswer ?? []);
      snack(`Sent “${sent.title}” as ${sent.producer.name}${asked ? `, ${asked}` : ""}`, { label: "Open", onClick: () => go(hashFor("events", sent.id, query())) });
      cursors = [null];
      await reload();
    },
  });
}

function openDeleteByRule() {
  deleteByRule({
    producers,
    onDeleted: async (count) => {
      snack(`Deleted ${eventCount(count)}`);
      if (selectedId) go(addressFor(null));
      ticked = new Set();
      cursors = [null];
      await reload();
    },
  });
}

// ---- The pane ------------------------------------------------------------------------------------

function openEvent(id) {
  restoreFocus = id;
  go(addressFor(id));
}

function closePane() {
  if (!selectedId) return;
  restoreFocus = selectedId;
  go(addressFor(null));
}

function paintPane() {
  if (!nodes) return;
  const showing = selectedId !== null && ticked.size === 0;
  setDetailOpen(showing);
  nodes.scrim.hidden = !showing;
  nodes.prompt.hidden = showing || (items !== null && items.length === 0 && failure === null);
  for (const row of nodes.table.querySelectorAll(".tr")) row.setAttribute("aria-selected", String(row.dataset.id === selectedId));
  if (!showing) {
    pane.hide();
    return;
  }
  pane.show(selectedId, items?.find((item) => item.id === selectedId) ?? null);
  nodes.table.querySelector(`.tr[data-id='${selectedId}']`)?.scrollIntoView?.({ block: "nearest" });
}

function onKey(event) {
  if (event.key !== "Escape" || !selectedId) return;
  if (document.querySelector(".scrim, .menu")) return;
  event.preventDefault();
  closePane();
}

function onVisible() {
  if (document.visibilityState === "visible" && nodes) reload();
}

function readRoute(route) {
  filters = fromQuery(route.query);
  selectedId = route.id && ID.test(route.id) ? route.id : null;
}

// ---- Section -------------------------------------------------------------------------------------

export const eventsSection = {
  mount({ container, route }) {
    host = container;
    pane = createEventPane({
      producerOwner: (id) => producers.find((item) => item.id === id)?.owner.name ?? null,
      close: closePane,
      user: (id) => users.find((item) => item.id === id) ?? null,
      onRead: (event) => {
        const at = items?.findIndex((item) => item.id === event.id) ?? -1;
        if (at >= 0) items[at] = { ...items[at], ...event, push: items[at].push };
        paintTable();
      },
      onDeleted: async (event) => {
        snack(`Deleted “${event.title}”`);
        go(addressFor(null));
        await reload();
      },
    });
    items = null;
    failure = null;
    appended = false;
    total = null;
    loadedAt = null;
    loading = false;
    cursors = [null];
    ticked = new Set();
    producers = [];
    users = [];
    retention = null;
    readRoute(route);
    nodes = build();
    host.replaceChildren(nodes.cols);
    host.hidden = false;
    paintAll();
    document.addEventListener("keydown", onKey);
    document.addEventListener("visibilitychange", onVisible);
    timer = setInterval(() => {
      if (document.visibilityState === "visible" && !document.querySelector(".scrim, .menu") && ticked.size === 0 && !loading && !appended) reload();
    }, REFRESH_MS);
    readLookups();
    reload();
  },
  update(route) {
    const before = selectedId;
    const wasQuery = String(query());
    readRoute(route);
    if (String(query()) !== wasQuery) {
      ticked = new Set();
      reload({ first: true });
    }
    paintChips();
    paintHead();
    paintPane();
    if (before && !selectedId && restoreFocus) {
      nodes.table.querySelector(`.tr[data-id='${restoreFocus}']`)?.focus({ preventScroll: true });
      restoreFocus = null;
    }
  },
  unmount() {
    clearInterval(timer);
    clearTimeout(pressTimer);
    document.removeEventListener("keydown", onKey);
    document.removeEventListener("visibilitychange", onVisible);
    pane?.hide();
    host = null;
    nodes = null;
    pane = null;
    items = null;
    sequence += 1;
    setDetailOpen(false);
  },
};
