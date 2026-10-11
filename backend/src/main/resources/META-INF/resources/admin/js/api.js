// Every request of the page goes to its own origin, with the admin token typed on the sign-in
// screen. The token lives only in this module's closure: it is never stored (not in a cookie,
// not in the browser's storage), never put in an address, and forgotten by signOut().

export const CLIENTS = "/api/v1/admin/clients";
export const PAIRINGS = "/api/v1/admin/pairings";
export const PRODUCERS = "/api/v1/admin/producers";
export const USERS = "/api/v1/admin/users";
export const EVENTS = "/api/v1/events";
export const ADMIN_EVENTS = "/api/v1/admin/events";
export const DELETE_EVENTS = "/api/v1/admin/events/delete";
export const STATUS = "/api/v1/admin/status";
export const INFO = "/q/info";
export const HEALTH = "/q/health";

// A server that does not answer in this long is as good as one that cannot be reached.
const TIMEOUT_MS = 15_000;

let token = null;
let onSessionLost = () => {};

/** The page's one reaction to a 401 on a request made while signed in. */
export function whenSessionLost(handler) {
  onSessionLost = handler;
}

export const signedIn = () => token !== null;

export function forget() {
  token = null;
}

/** A request the page was told to stop because the session ended; nothing more is shown for it. */
export class SessionEnded extends Error {
  constructor() {
    super("Your session ended.");
    this.name = "SessionEnded";
  }
}

/** Why a request failed, in the words the operator reads. `kind` lets a screen choose its state. */
export class ApiError extends Error {
  constructor(message, kind, status) {
    super(message);
    this.name = "ApiError";
    this.kind = kind;
    this.status = status;
  }
}

async function send(method, path, body, bearer) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetch(path, {
      method,
      headers: body
        ? { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" }
        : { Authorization: `Bearer ${bearer}` },
      body: body ? JSON.stringify(body) : undefined,
      cache: "no-store",
      signal: controller.signal,
    });
  } catch {
    throw new ApiError("Could not reach SignalHub.", "unreachable");
  } finally {
    clearTimeout(timer);
  }
}

/** The server's own words for an error: its title, and the violations it names. */
export async function errorTitle(response) {
  try {
    const body = await response.json();
    const details = (body.violations || []).map((violation) => violation.message).join(", ");
    if (body.title) return details ? `${body.title}: ${details}` : body.title;
  } catch {
    // Not JSON: said below by its status alone.
  }
  // Only SignalHub's own errors have a title; a failure outside them, such as a database that is
  // down, is said by its status, so it is never shown as an empty error.
  return `SignalHub answered ${response.status}.`;
}

/**
 * Checks a token with the management API and, only when it works, keeps it. A wrong token never
 * replaces a right one. Throws an ApiError whose kind is `wrong` (401), `off` (404: the server has
 * no admin token set, so the management API does not exist), `unreachable`, or `answered`.
 */
export async function signIn(candidate) {
  const response = await send("GET", CLIENTS, null, candidate);
  if (response.status === 401) throw new ApiError("Wrong admin token", "wrong", 401);
  if (response.status === 404) throw new ApiError("The admin page is switched off on this server.", "off", 404);
  if (!response.ok) throw new ApiError(`SignalHub answered ${response.status}.`, "answered", response.status);
  token = candidate;
}

/**
 * A management request. A 401 ends the session (the token stopped working while in use): the page
 * goes back to the sign-in screen and the request is not repeated.
 */
export async function call(method, path, body) {
  if (token === null) throw new SessionEnded();
  const sent = token;
  const response = await send(method, path, body, sent);
  if (response.status === 401) {
    // Only if it is still the token that failed: a sign-out in the meantime has dealt with it.
    if (token === sent) onSessionLost();
    throw new SessionEnded();
  }
  if (!response.ok) throw new ApiError(await errorTitle(response), "answered", response.status);
  return response.status === 204 ? null : response.json();
}

/**
 * /q/info and /q/health need no token, so none is sent; health answers 503 with its checks when
 * something is down, which is still an answer to show.
 */
export async function probe(path) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let response;
  try {
    response = await fetch(path, { cache: "no-store", signal: controller.signal });
  } catch {
    throw new ApiError("Could not reach SignalHub.", "unreachable");
  } finally {
    clearTimeout(timer);
  }
  try {
    return await response.json();
  } catch {
    throw new ApiError(`SignalHub answered ${response.status}.`, "answered", response.status);
  }
}
