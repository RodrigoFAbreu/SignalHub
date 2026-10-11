// The one rule of the server's status (docs/design/users/DESIGN.md, 9.5): every 30 seconds while
// the page is visible it reads /api/v1/admin/status and /q/health, and judges them, and the device
// list when a section has read it, by model.js. The rail's button shows the verdict; Status asks
// for the fuller read (the release, the devices and the newest event) and shows the rows.

import { CLIENTS, EVENTS, HEALTH, INFO, STATUS, call, probe } from "./api.js";
import { assess, railState } from "./model.js";
import { onStoreChange, setClients, store } from "./store.js";

export const CHECK_MS = 30_000;

const listeners = new Set();
// Two looks closer than this are one check (the rail's and Status's at the same moment).
const SAME_CHECK_MS = 15_000;

let timer = null;
let first = true;
let baseline = null;
let outbox = [];
let parts = {};
let readAt = null;
let stale = false;
let refreshFailure = null;
let running = null;
let runningFull = false;
// Whether the Status page is open: it needs the fuller read at every check.
let full = false;

export const signal = {
  state: "checking",
  count: 0,
  stale: false,
  get parts() {
    return parts;
  },
  get readAt() {
    return readAt;
  },
  /** Why the latest check read nothing, when the rows shown are older than it. */
  get failure() {
    return stale ? refreshFailure : null;
  },
  get baseline() {
    return baseline;
  },
  get checking() {
    return running !== null;
  },
  /** The rows and headline for the latest read. */
  assessment() {
    return assess(withDevices(parts), context());
  },
};

function context() {
  return { baseline, outbox: outbox.map((sample) => sample.count), now: Date.now() };
}

// The devices some section has read stand in for a read of their own, so the rail never asks.
function withDevices(read) {
  if (read.clients || !store.clients) return read;
  return { ...read, clients: { ok: true, value: { items: store.clients } } };
}

export function onSignal(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function publish() {
  const verdict = railState(withDevices(parts), context(), first);
  signal.state = verdict.state;
  signal.count = verdict.count;
  signal.stale = stale;
  for (const listener of listeners) listener(signal);
}

const settle = (promise) =>
  promise.then(
    (value) => ({ ok: true, value }),
    (error) => (error.name === "SessionEnded" ? Promise.reject(error) : { ok: false, error }),
  );

/** One check. Reads what the rail needs, and the rest too when the Status page is open. */
export function check({ fullRead = full } = {}) {
  // One check at a time; one that was not the full read is followed by it when it is asked for.
  if (running) return fullRead && !runningFull ? running.then(() => check({ fullRead })) : running;
  runningFull = fullRead;
  const asked = ["status", "health"];
  const requests = [settle(call("GET", STATUS)), settle(probe(HEALTH))];
  if (fullRead) {
    asked.push("info", "clients", "latest");
    requests.push(settle(probe(INFO)), settle(call("GET", CLIENTS)), settle(call("GET", `${EVENTS}?limit=1`)));
  }
  publish();
  running = Promise.all(requests)
    .then((answers) => {
      const next = { ...parts };
      asked.forEach((name, index) => {
        next[name] = answers[index];
      });
      const readSomething = answers.some((answer) => answer.ok);
      if (!readSomething && !first && Object.values(parts).some((part) => part?.ok)) {
        // Nothing answered: the older rows stay, and the button says so with a question mark.
        stale = true;
        refreshFailure = answers.find((answer) => !answer.ok)?.error ?? null;
      } else {
        stale = false;
        refreshFailure = null;
        readAt = new Date();
        parts = next;
        if (parts.clients?.ok) setClientsQuietly(parts.clients.value.items);
        if (parts.status?.ok) {
          baseline ??= parts.status.value.abandonedRetries;
          const sample = { count: parts.status.value.pendingDispatches, at: Date.now() };
          outbox = outbox.length && sample.at - outbox.at(-1).at < SAME_CHECK_MS ? [...outbox.slice(0, -1), sample] : [...outbox, sample].slice(-2);
        }
      }
      first = false;
    })
    .catch(() => {
      // A session that ended is dealt with by the sign-in screen; nothing to show here.
    })
    .finally(() => {
      running = null;
      publish();
    });
  return running;
}

// The device list read by Status is the list the rail judges by: kept without announcing it again.
function setClientsQuietly(items) {
  store.clients = items;
}

export function start() {
  stop();
  first = true;
  baseline = null;
  outbox = [];
  parts = {};
  readAt = null;
  stale = false;
  refreshFailure = null;
  publish();
  check();
  timer = setInterval(() => {
    if (document.visibilityState === "visible") check();
  }, CHECK_MS);
  document.addEventListener("visibilitychange", onVisible);
  unsubscribeStore = onStoreChange(() => publish());
}

let unsubscribeStore = () => {};

function onVisible() {
  if (document.visibilityState === "visible" && timer !== null) check();
}

export function stop() {
  clearInterval(timer);
  timer = null;
  document.removeEventListener("visibilitychange", onVisible);
  unsubscribeStore();
}

/** Status asks for the fuller read while it is open. */
export function setFull(value) {
  full = value;
}

export { setClients };
