// How an event's pushes went, in the words of the page (docs/design/admin/WALKTHROUGH.md, 3.5): one
// line per device, the latest record of each, grouped by the users the event reached. Pure data in,
// plain data out: the pane draws it. A delivery gives up only when the server's `final` marker says
// no further attempt will be made; it is "Waiting for a retry" while tries remain.

import { severityOf } from "./event-filters.js";

const TRIES_LIMIT = 5;

/** The state of one device's latest record: its words, icon, tone and whether it is a problem. */
export function wording(record, { client, minimum } = {}) {
  const browser = client?.kind === "BROWSER";
  switch (record.outcome) {
    case "DELIVERED":
      return { key: "sent", glyph: "check_circle", tone: "ok", title: "Sent", reason: "accepted by the push service", problem: false };
    case "NO_TARGET":
      return { key: "notSent", glyph: "block", tone: "no", title: "Not sent", reason: browser ? "This browser has no push address." : "This device has no push address.", problem: false };
    case "FILTERED":
      return { key: "notSent", glyph: "do_not_disturb_on", tone: "no", title: "Not sent", reason: filteredReason(record.detail, minimum), problem: false };
    case "UNSUPPORTED_PROVIDER":
      return { key: "notSent", glyph: "block", tone: "no", title: "Not sent", reason: "This device's push service is not supported by this server.", problem: true };
    case "INVALID_TARGET":
      return { key: "failed", glyph: "error", tone: "bad", title: "Failed", reason: "The push service no longer knows this device, so its address was removed.", problem: true };
    case "PERMANENT_FAILURE":
      return { key: "refused", glyph: "error", tone: "bad", title: "Refused", reason: "The push service refused it.", problem: true };
    case "TRANSIENT_FAILURE":
      return gaveUp(record)
        ? { key: "gaveUp", glyph: "error", tone: "bad", title: `Gave up after ${record.attempt} ${record.attempt === 1 ? "try" : "tries"}`, reason: `The push service did not accept it this time, on any of the ${record.attempt} tries.`, problem: true }
        : { key: "waiting", glyph: "schedule", tone: "wait", title: "Waiting for a retry", reason: "The push service did not accept it this time. SignalHub will try again.", problem: true };
    default:
      // An outcome a later release adds is shown as it is.
      return { key: "other", glyph: "help", tone: "no", title: record.outcome, reason: record.detail ?? "", problem: false };
  }
}

function gaveUp(record) {
  return record.final === true || (record.final === undefined && record.attempt >= TRIES_LIMIT);
}

// The device's own settings said why it was not sent; the minimum severity is read from its settings.
function filteredReason(detail, minimum) {
  if (detail === "pushes paused") return "Not sent: pushes are paused on this device.";
  if (detail === "category muted") return "Not sent: the category is muted on this device.";
  if (detail === "producer muted") return "Not sent: the producer is muted on this device.";
  if (detail === "below the minimum severity") {
    const level = minimum ? severityOf(minimum)?.text : null;
    return level ? `Its push settings skip events below ${level}.` : "Its push settings skip events below its minimum severity.";
  }
  return detail ? `Not sent: ${detail}.` : "Its push settings kept it from this device.";
}

/**
 * The recipients: `answer` is the deliveries answer (`items` oldest first, `users` the ones it
 * reached). Each has its devices in the order they were first tried, each with the latest record,
 * and the earlier ones kept for Technical details. The owner comes first, then by name.
 */
export function recipients(answer, clients = []) {
  const byId = new Map(clients.map((client) => [client.id, client]));
  const people = new Map(answer.users.map((user) => [user.id, { id: user.id, name: user.name, owner: user.owner, left: false, devices: new Map() }]));
  for (const record of answer.items) {
    if (!people.has(record.userId)) people.set(record.userId, { id: record.userId, name: record.userName, owner: false, left: true, devices: new Map() });
    const devices = people.get(record.userId).devices;
    if (!devices.has(record.clientId)) devices.set(record.clientId, { id: record.clientId, name: record.clientName, records: [] });
    devices.get(record.clientId).records.push(record);
  }
  const list = [...people.values()].sort((a, b) => Number(b.owner) - Number(a.owner) || a.name.localeCompare(b.name));
  for (const person of list) {
    person.devices = [...person.devices.values()].map((device) => {
      const client = byId.get(device.id);
      const last = device.records.at(-1);
      return { ...device, last, words: wording(last, { client, minimum: client?.pushPreferences?.minimumSeverity }) };
    });
  }
  return list;
}

/** The counts the Pushes tab and the Event tab's summary row tell: users, devices, problems. */
export function summary(list) {
  const devices = list.flatMap((person) => person.devices);
  const count = (key) => devices.filter((device) => device.words.key === key).length;
  const parts = [
    [count("sent"), "sent"],
    [count("waiting"), "waiting for a retry"],
    [count("failed") + count("refused"), "failed"],
    [count("gaveUp"), "gave up"],
    [count("notSent"), "not sent"],
  ].filter(([number]) => number > 0);
  return {
    users: list.length,
    devices: devices.length,
    problems: devices.filter((device) => device.words.problem).length,
    line: parts.map(([number, text]) => `${number} ${text}`).join(" · "),
  };
}
