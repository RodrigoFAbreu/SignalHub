// Talks to a running SignalHub the way an operator and a phone would, to set tests up: the admin
// token (ADMIN_TOKEN) is used here and only here, through the management API, to make users,
// devices and producers. It is never given to a page. A "phone" approves a browser's sign-in with
// plain HTTP calls and a client key, as the app does.

export const BASE = process.env.SIGNALHUB_URL ?? "http://localhost:8080";
const ADMIN_TOKEN = process.env.ADMIN_TOKEN;

let counter = 0;

/** A name that is new on every run, so tests never meet each other's leftovers. */
export function unique(prefix) {
  counter += 1;
  return `${prefix}-${Date.now().toString(36)}${counter}${Math.random().toString(36).slice(2, 5)}`;
}

async function call(method, path, { body, bearer, headers } = {}) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      Accept: "application/json",
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  const json = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(`${method} ${path} answered ${response.status}: ${text.slice(0, 300)}`);
  }
  return json;
}

function admin(method, path, body) {
  if (!ADMIN_TOKEN) throw new Error("ADMIN_TOKEN is not set: the tests need the operator's token to set up users");
  return call(method, path, { body, bearer: ADMIN_TOKEN });
}

/** A user of this role, and a device (a client key) for them, as an invited person has. */
export async function createPerson(role, name = unique(role.toLowerCase())) {
  const user = await admin("POST", "/api/v1/admin/users", { name, role });
  const registered = await admin("POST", "/api/v1/admin/clients", { name: `${name} - phone`, userId: user.id });
  return { userId: user.id, name, role, deviceId: registered.client.id, key: registered.clientKey, deviceName: `${name} - phone` };
}

/** A producer owned by this user (the operator makes it; the owner is subscribed). */
export async function createProducer(owner, name = unique("producer"), visibility = "PUBLIC") {
  const made = await admin("POST", "/api/v1/admin/producers", { name, visibility, ownerId: owner.userId });
  return { id: made.producer.id, name, apiKey: made.apiKey, keyId: made.keyId };
}

export async function subscribe(person, producer) {
  await call("PUT", `/api/v1/client/visible-producers/${producer.id}/subscription`, { bearer: person.key });
}

/** Publishes an event as a producer. Fields are the public event schema. */
export function publish(producer, event) {
  return call("POST", "/api/v1/events", {
    bearer: producer.apiKey,
    body: { category: "INFO", severity: "NORMAL", title: "Hello", ...event },
  });
}

/** What a device's key may read: its user's view of the client API. */
export function asDevice(person, method, path, body) {
  return call(method, path, { bearer: person.key, body });
}

/** The phone side of a sign-in: look the code up, then approve or cancel. */
export async function phoneApproves(person, code, { cancel = false } = {}) {
  const found = await call("POST", "/api/v1/client/web-sign-ins/lookup", { bearer: person.key, body: { code } });
  await fetch(`${BASE}/api/v1/client/web-sign-ins/${found.id}/${cancel ? "cancel" : "approve"}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${person.key}` },
  }).then((response) => {
    if (response.status !== 204) throw new Error(`the phone's ${cancel ? "cancel" : "approve"} answered ${response.status}`);
  });
  return found;
}

export function operator(method, path, body) {
  return admin(method, path, body);
}

export const FIREFOX_ON_LINUX = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";

/**
 * Signs a browser in without a page, as a phone and a page do together: the cookie value of the
 * new browser, its client id and its CSRF token. For tests about something other than signing in.
 */
export async function browserSession(person, userAgent = FIREFOX_ON_LINUX) {
  const started = await fetch(`${BASE}/api/v1/web/sign-ins`, { method: "POST", headers: { "User-Agent": userAgent } });
  const sign = await started.json();
  await phoneApproves(person, sign.code);
  const polled = await fetch(`${BASE}/api/v1/web/sign-ins/${sign.id}`, { headers: { Authorization: `Bearer ${sign.pollSecret}` } });
  const line = polled.headers.getSetCookie().find((cookie) => cookie.startsWith("__Host-signalhub_session="));
  const value = line.slice("__Host-signalhub_session=".length, line.indexOf(";"));
  const session = await (await fetch(`${BASE}/api/v1/web/session`, { headers: { Cookie: `__Host-signalhub_session=${value}` } })).json();
  return { value, id: session.client.id, csrf: session.csrfToken };
}

/**
 * Puts a browser session in a Playwright context, as the browser holds it after signing in. The
 * context also has the clipboard a person's browser has: a headless Chromium refuses a copy
 * unless it is granted, and the test of a refused copy takes it away on purpose.
 */
export async function useSession(context, session) {
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: new URL(BASE).origin });
  await context.addCookies([{ name: "__Host-signalhub_session", value: session.value, domain: new URL(BASE).hostname, path: "/", httpOnly: true, secure: true, sameSite: "Strict" }]);
}
