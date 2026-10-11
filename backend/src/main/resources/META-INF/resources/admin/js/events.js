// Events, as the admin page showed them before the next item rebuilds this section: a page at a time,
// filtered, an event opened at #events/<id> to read it, see how its push went to each device and mark
// it read or unread, deleting one, a selection, or a producer's or older events after a confirmation
// with their count, and sending a test event as a producer. Names and event contents come from the
// server and are always set as text, never as HTML; an event's link is only ever opened by the
// operator, in a new tab, never followed by the page.

import { ADMIN_EVENTS, DELETE_EVENTS, EVENTS, PRODUCERS, USERS, call } from "./api.js";
import { ID as EVENT_ID } from "./router.js";
import { $, LABELS, ROLES, ago, button, element, hideLegacy, outcome, showError, showLegacy, time, toast } from "./legacy.js";

const EVENT_PAGE = 25;
// The listing's filters, by the field that sets each; the same as the app's inbox.
const EVENT_FILTERS = {
  producerId: "filter-producer",
  category: "filter-category",
  severity: "filter-severity",
  userId: "filter-user",
  relation: "filter-relation",
  read: "filter-read",
};
// The server accepts only these schemes; checked again so no other link is ever made clickable.
const WEB_LINK = /^https?:\/\//i;

// The cursor of each events page read so far, the first page having none, and the next one's.
let eventPages = [null];
let nextEventCursor = null;
let shownEvent = null;
// The users, for the user filter.
let users = [];
// The IDs of the events ticked on the page shown; a page read again starts with none.
let selected = new Set();

async function loadUsers() {
  users = (await call("GET", USERS)).items;
}

$("refresh-events").addEventListener("click", () => refreshEvents());

for (const id of Object.values(EVENT_FILTERS)) {
  // Other filters, other events: back to the newest page.
  $(id).addEventListener("change", () => {
    eventPages = [null];
    refreshEvents();
  });
}
$("older-events").addEventListener("click", () => {
  eventPages.push(nextEventCursor);
  refreshEvents();
});
$("newer-events").addEventListener("click", () => {
  eventPages.pop();
  refreshEvents();
});
$("toggle-read").addEventListener("click", () => toggleRead());
$("delete-event").addEventListener("click", () => deleteShownEvent());
$("refresh-deliveries").addEventListener("click", () => {
  if (shownEvent) refreshDeliveries(shownEvent.id);
});
$("delete-selected").addEventListener("click", () => deleteSelected());
$("delete-events").addEventListener("submit", (event) => {
  event.preventDefault();
  deleteMatching();
});
$("send-event").addEventListener("submit", (event) => {
  event.preventDefault();
  sendTestEvent();
});

// The list, or one event when the address names one. Producers links here with ?producer=<id>, to
// see that producer's events.
async function showEvents(eventId, producerId) {
  const one = EVENT_ID.test(eventId || "");
  $("event-browser").hidden = one;
  $("event-details").hidden = !one;
  if (one) return openEvent(eventId);
  await refreshProducerChoices();
  const choice = $("filter-producer");
  if (EVENT_ID.test(producerId || "") && [...choice.options].some((option) => option.value === producerId)) {
    choice.value = producerId;
    eventPages = [null];
  }
  return refreshEvents();
}

async function refreshEvents() {
  showError("events-error", null);
  // Until this page is in, so a second click cannot step twice from the same one.
  $("older-events").disabled = true;
  $("newer-events").disabled = true;
  selected = new Set();
  showSelection();
  const query = new URLSearchParams({ limit: String(EVENT_PAGE) });
  // Which of a user's producers means nothing without the user.
  $("filter-relation").disabled = !$("filter-user").value;
  for (const [name, id] of Object.entries(EVENT_FILTERS)) {
    if ($(id).value && !$(id).disabled) query.set(name, $(id).value);
  }
  const cursor = eventPages[eventPages.length - 1];
  if (cursor) query.set("cursor", cursor);
  try {
    const page = await call("GET", `${EVENTS}?${query}`);
    nextEventCursor = page.nextCursor;
    renderEvents(page.items);
  } catch (e) {
    nextEventCursor = null;
    $("event-list").replaceChildren();
    showError("events-error", e.message);
  }
  $("older-events").disabled = !nextEventCursor;
  $("newer-events").disabled = eventPages.length === 1;
}

// The producer filter and the Delete events form offer every producer, and the test event every
// enabled one, keeping the one chosen.
async function refreshProducerChoices() {
  let producers;
  try {
    producers = (await call("GET", PRODUCERS)).items;
    await loadUsers();
  } catch {
    return; // The filter keeps what it had; the list says what went wrong, if anything did.
  }
  for (const [id, none, offered] of [
    ["filter-producer", "All producers", producers],
    ["delete-producer", "Any producer", producers],
    // A disabled producer could not publish the event itself, so the server refuses it.
    ["send-producer", "Choose a producer", producers.filter((p) => !p.disabledAt)],
    // Revoked users keep their events, so the operator can still look at them.
    ["filter-user", "All users", users],
  ]) {
    const select = $(id);
    const chosen = select.value;
    const options = offered.map((p) => new Option(p.revokedAt ? `${p.name} (revoked)` : p.name, p.id));
    select.replaceChildren(new Option(none, ""), ...options);
    select.value = offered.some((p) => p.id === chosen) ? chosen : "";
  }
}

function renderEvents(events) {
  const list = $("event-list");
  list.replaceChildren(...events.map(eventCard));
  if (events.length === 0) list.append(element("li", "empty", "No events."));
}

function eventCard(event) {
  const item = element("li", event.readAt ? "event" : "event unread");
  const title = element("h3");
  const box = element("input");
  box.type = "checkbox";
  box.setAttribute("aria-label", `Select "${event.title}"`);
  box.addEventListener("change", () => {
    if (box.checked) selected.add(event.id);
    else selected.delete(event.id);
    showSelection();
  });
  const link = element("a", null, event.title);
  link.href = `#events/${event.id}`;
  title.append(box, " ", link, " ", ...badges(event));
  item.append(title);
  const where = [event.producer.name, event.context].filter(Boolean).join(" · ");
  item.append(element("p", "meta", `${where} · ${time(event.createdAt)} (${ago(event.createdAt)})`));
  return item;
}

function badges(event) {
  const list = [
    // Only high and critical stand out, so Unread is the one blue badge.
    element("span", `badge muted severity-${event.severity.toLowerCase()}`, label(event.severity)),
    element("span", "badge muted", label(event.category)),
  ];
  if (!event.readAt) list.push(element("span", "badge", "Unread"));
  return list;
}

// A value this page does not know yet (a later release may add one) is shown as it is.
function label(value) {
  return LABELS[value] || value;
}

async function openEvent(eventId) {
  showError("event-error", null);
  $("event-body").hidden = true;
  $("event-deliveries").replaceChildren();
  shownEvent = null;
  try {
    renderEvent(await call("GET", `${EVENTS}/${eventId}`));
  } catch (e) {
    showError("event-error", e.message);
    return;
  }
  await refreshDeliveries(eventId);
}

async function refreshDeliveries(eventId) {
  showError("deliveries-error", null);
  try {
    renderDeliveries(await call("GET", `${ADMIN_EVENTS}/${eventId}/deliveries`));
  } catch (e) {
    $("event-deliveries").replaceChildren();
    showError("deliveries-error", e.message);
  }
}

// One entry per user the event reached, by name (a user with records who has since unsubscribed
// follows them), each with one line per device in the order the devices were first tried: how
// the latest attempt went and when, then the earlier attempts, if any. The records are oldest
// first.
function renderDeliveries({ items, users: reached }) {
  const byUser = new Map(reached.map((u) => [u.id, { name: u.name, owner: u.owner, devices: new Map() }]));
  for (const record of items) {
    if (!byUser.has(record.userId)) {
      byUser.set(record.userId, { name: record.userName, owner: false, devices: new Map(), left: true });
    }
    const devices = byUser.get(record.userId).devices;
    if (!devices.has(record.clientId)) devices.set(record.clientId, []);
    devices.get(record.clientId).push(record);
  }
  const list = $("event-deliveries");
  list.replaceChildren(...[...byUser.values()].map(recipient));
  if (byUser.size === 0) {
    list.append(element("li", "empty", "No user receives it: nobody is subscribed to its producer."));
  }
}

function recipient(user) {
  const item = element("li", "recipient");
  const title = element("strong", null, user.name);
  item.append(title);
  if (user.owner) item.append(" ", element("span", "badge muted", "Owner"));
  if (user.left) item.append(" ", element("span", "badge muted", "No longer subscribed"));
  const devices = element("ul", "deliveries");
  devices.append(...[...user.devices.values()].map(deliveryLine));
  if (user.devices.size === 0) {
    devices.append(element("li", "empty", "None: its push is not dispatched yet, or the user has no device."));
  }
  item.append(devices);
  return item;
}

function deliveryLine(attempts) {
  const last = attempts[attempts.length - 1];
  const item = element("li", `delivery outcome-${last.outcome.toLowerCase()}`);
  item.append(
    element("strong", null, last.clientName),
    `: ${outcome(last)}, ${time(last.at)} (${ago(last.at)})`,
  );
  if (attempts.length > 1) {
    const earlier = attempts.slice(0, -1).map((a) => `${a.attempt}. ${outcome(a)}`);
    item.append(element("p", "meta", `Attempt ${last.attempt}; before: ${earlier.join("; ")}`));
  }
  return item;
}

function renderEvent(event) {
  shownEvent = event;
  $("event-title").textContent = event.title;
  $("event-badges").replaceChildren(...badges(event));
  $("event-message").textContent = event.message || "";
  $("event-message").hidden = !event.message;

  const facts = $("event-facts");
  facts.replaceChildren();
  const fact = (name, value) => facts.append(element("dt", null, name), element("dd", null, value));
  fact("Producer", event.producer.name);
  fact("Category", label(event.category));
  fact("Severity", label(event.severity));
  if (event.context) fact("Context", event.context);
  fact("Happened", event.occurredAt ? time(event.occurredAt) : "Not given");
  fact("Received", `${time(event.createdAt)} (${ago(event.createdAt)})`);
  if (event.link) facts.append(element("dt", null, "Link"), linkTo(event.link));
  fact("Read", event.readAt ? time(event.readAt) : "Unread");
  fact("ID", event.id);

  $("event-metadata").textContent = JSON.stringify(event.metadata, null, 2);
  $("toggle-read").textContent = event.readAt ? "Mark as unread" : "Mark as read";
  $("event-body").hidden = false;
}

// Opened only by the operator's click, in a new tab that cannot reach back to this page and is
// told nothing of where it came from.
function linkTo(url) {
  const cell = element("dd");
  if (!WEB_LINK.test(url)) {
    cell.textContent = url;
    return cell;
  }
  const link = element("a", null, url);
  link.href = url;
  link.target = "_blank";
  link.rel = "noopener noreferrer";
  cell.append(link);
  return cell;
}

async function toggleRead() {
  const event = shownEvent;
  if (!event) return;
  showError("event-error", null);
  try {
    renderEvent(await call(event.readAt ? "DELETE" : "PUT", `${EVENTS}/${event.id}/read`));
  } catch (e) {
    showError("event-error", e.message);
  }
}

function showSelection() {
  $("delete-selected").disabled = selected.size === 0;
  $("selection-count").textContent = selected.size ? `${eventCount(selected.size)} selected` : "";
}

function eventCount(count) {
  return `${count} event${count === 1 ? "" : "s"}`;
}

// One event, named in the confirmation; then back to the list it came from, read again.
async function deleteShownEvent() {
  const event = shownEvent;
  if (!event) return;
  if (!confirm(`Delete the event "${event.title}"? It is gone for good.`)) return;
  showError("event-error", null);
  try {
    await call("DELETE", `${ADMIN_EVENTS}/${event.id}`);
  } catch (e) {
    showError("event-error", e.message);
    return;
  }
  toast(`Deleted the event "${event.title}".`);
  location.hash = "#events";
}

function deleteSelected() {
  const ids = [...selected];
  if (ids.length === 0) return;
  deleteEvents(
    { ids },
    (count) => `Delete the ${eventCount(count)} selected? They are gone for good.`,
    "events-error",
  );
}

// By producer, by day or both; a day is from midnight in this browser's time zone.
async function deleteMatching() {
  showError("delete-events-error", null);
  const producer = $("delete-producer");
  const day = $("delete-before").value;
  const request = {};
  if (producer.value) request.producerId = producer.value;
  if (day) request.createdBefore = new Date(`${day}T00:00`).toISOString();
  if (!request.producerId && !request.createdBefore) {
    return showError("delete-events-error", "Choose a producer, a day or both.");
  }
  const which = [
    producer.value ? `of "${producer.selectedOptions[0].text}"` : null,
    day ? `received before ${day}` : null,
  ].filter(Boolean);
  const deleted = await deleteEvents(
    request,
    (count) => `Delete ${eventCount(count)} ${which.join(" ")}? They are gone for good.`,
    "delete-events-error",
  );
  if (deleted) $("delete-events").reset();
}

// Asks the server first how many events the request deletes (a dry run, which deletes none), says
// so in the confirmation, and only then deletes them; the list is read again afterwards. Whether
// any were deleted.
async function deleteEvents(request, question, errorId) {
  showError(errorId, null);
  try {
    const { count } = await call("POST", DELETE_EVENTS, { ...request, dryRun: true });
    if (count === 0) {
      toast("No events to delete.");
      return false;
    }
    if (!confirm(question(count))) return false;
    const deleted = await call("POST", DELETE_EVENTS, request);
    toast(`Deleted ${eventCount(deleted.count)}.`);
  } catch (e) {
    showError(errorId, e.message);
    return false;
  }
  await refreshEvents();
  return true;
}

// Published as the producer chosen, stored and pushed as its own event would be; once sent, it is
// linked from here, to open and delete it, and the list is read again. The form keeps its values,
// so the same event can be sent again.
async function sendTestEvent() {
  showError("send-event-error", null);
  $("send-event-result").hidden = true;
  let sent;
  try {
    sent = await call("POST", `${PRODUCERS}/${$("send-producer").value}/events`, testEvent());
  } catch (e) {
    return showError("send-event-error", e.message);
  }
  const link = element("a", null, "Open it");
  link.href = `#events/${sent.id}`;
  $("send-event-result").replaceChildren(`Sent "${sent.title}" as "${sent.producer.name}". `, link);
  $("send-event-result").hidden = false;
  await refreshEvents();
}

// The fields a producer sends, the optional ones only when filled in; the server validates them
// as it does a producer's.
function testEvent() {
  const request = {
    category: $("send-category").value,
    severity: $("send-severity").value,
    title: $("send-title").value.trim(),
  };
  for (const [name, id] of [
    ["message", "send-message"],
    ["context", "send-context"],
    ["link", "send-link"],
  ]) {
    const value = $(id).value.trim();
    if (value) request[name] = value;
  }
  const metadata = $("send-metadata").value.trim();
  if (metadata) request.metadata = jsonObject(metadata);
  return request;
}

function jsonObject(text) {
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new Error("Metadata is not valid JSON.");
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Metadata must be a JSON object, such as {\"run\": 42}.");
  }
  return value;
}


export const eventsSection = {
  mount({ route }) {
    showLegacy("events");
    showEvents(route.id, route.query.get("producer"));
  },
  update(route) {
    showEvents(route.id, route.query.get("producer"));
  },
  unmount() {
    hideLegacy();
  },
};
