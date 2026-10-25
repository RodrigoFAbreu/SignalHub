// Every request the page makes goes through here, to its own origin only. The session is an
// HttpOnly cookie the page cannot read, so it just sends it (`same-origin`); the token for
// changing things comes from GET /api/v1/web/session and is kept in memory, never stored.

const SAFE_METHODS = new Set(["GET", "HEAD"]);

/** A request the server answered with an error, or did not answer (status 0). */
export class ApiError extends Error {
  constructor(status, title, question = null) {
    super(title);
    this.name = "ApiError";
    this.status = status;
    // The state of a question, which a 409 on answering carries.
    this.question = question;
  }

  get offline() {
    return this.status === 0;
  }
}

/** The session is over: 401 on a call that needs it. The page shows the ended screens. */
export class SessionEnded extends Error {
  constructor() {
    super("The session ended");
    this.name = "SessionEnded";
  }
}

let csrfToken = null;
let onSessionEnded = () => {};

export function setCsrfToken(token) {
  csrfToken = token;
}

/** Called once for each 401 of a call that was made with the session. */
export function whenSessionEnds(handler) {
  onSessionEnded = handler;
}

async function problemOf(response) {
  try {
    const body = await response.json();
    if (body && typeof body.title === "string" && body.title) return { title: body.title, question: body.question ?? null };
  } catch {
    // Not a SignalHub error body: a proxy in front of the server may answer anything.
  }
  return { title: `The server answered ${response.status}`, question: null };
}

/**
 * Calls the API and returns the parsed JSON (null for 204). `options.bearer` is the poll secret
 * of a sign-in, and `options.anonymous` marks a call made without a session, whose 401 is not
 * the end of one.
 */
export async function api(method, path, body, options = {}) {
  const headers = { Accept: "application/json" };
  if (!SAFE_METHODS.has(method) && csrfToken) headers["X-SignalHub-CSRF"] = csrfToken;
  if (options.bearer) headers.Authorization = `Bearer ${options.bearer}`;
  const init = { method, headers, credentials: "same-origin", cache: "no-store" };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  let response;
  try {
    response = await fetch(path, init);
  } catch {
    throw new ApiError(0, "Could not reach the server");
  }
  if (response.status === 401 && !options.anonymous) {
    onSessionEnded();
    throw new SessionEnded();
  }
  if (!response.ok) {
    const problem = await problemOf(response);
    throw new ApiError(response.status, problem.title, problem.question);
  }
  const result = response.status === 204 ? null : await response.json();
  if (options.withDate) return { result, date: response.headers.get("Date") };
  return result;
}

const enc = encodeURIComponent;

/** The calls the page makes, by what they are for. Paths are the client API's. */
export const calls = {
  session: () => api("GET", "/api/v1/web/session", undefined, { anonymous: true }),
  signOut: () => api("POST", "/api/v1/web/session/sign-out"),
  startSignIn: () => api("POST", "/api/v1/web/sign-ins", undefined, { anonymous: true, withDate: true }),
  pollSignIn: (id, secret) =>
    api("GET", `/api/v1/web/sign-ins/${enc(id)}`, undefined, { anonymous: true, bearer: secret }),

  server: () => api("GET", "/api/v1/client/server"),

  events: (query) => api("GET", `/api/v1/events?${query}`),
  event: (id) => api("GET", `/api/v1/events/${enc(id)}`),
  markRead: (id) => api("PUT", `/api/v1/events/${enc(id)}/read`),
  markUnread: (id) => api("DELETE", `/api/v1/events/${enc(id)}/read`),
  markReadThrough: (through) => api("POST", "/api/v1/events/read", { through }),
  answer: (id, body) => api("PUT", `/api/v1/events/${enc(id)}/answer`, body),
  addAnswerer: (id, userId) => api("PUT", `/api/v1/client/producers/${enc(id)}/answerers/${enc(userId)}`),
  removeAnswerer: (id, userId) => api("DELETE", `/api/v1/client/producers/${enc(id)}/answerers/${enc(userId)}`),
  unreadCount: () => api("GET", "/api/v1/events/unread-count"),

  visibleProducers: () => api("GET", "/api/v1/client/visible-producers"),
  subscribe: (id) => api("PUT", `/api/v1/client/visible-producers/${enc(id)}/subscription`),
  unsubscribe: (id) => api("DELETE", `/api/v1/client/visible-producers/${enc(id)}/subscription`),

  ownProducers: () => api("GET", "/api/v1/client/producers"),
  ownProducer: (id) => api("GET", `/api/v1/client/producers/${enc(id)}`),
  createProducer: (name, visibility) =>
    api("POST", "/api/v1/client/producers", { name, visibility }),
  updateProducer: (id, changes) => api("PATCH", `/api/v1/client/producers/${enc(id)}`, changes),
  issueKey: (id) => api("POST", `/api/v1/client/producers/${enc(id)}/keys`),
  revokeKey: (id, keyId) =>
    api("POST", `/api/v1/client/producers/${enc(id)}/keys/${enc(keyId)}/revoke`),
  disableProducer: (id) => api("POST", `/api/v1/client/producers/${enc(id)}/disable`),
  enableProducer: (id) => api("POST", `/api/v1/client/producers/${enc(id)}/enable`),
  allowUser: (id, userId) =>
    api("PUT", `/api/v1/client/producers/${enc(id)}/allowed-users/${enc(userId)}`),
  disallowUser: (id, userId) =>
    api("DELETE", `/api/v1/client/producers/${enc(id)}/allowed-users/${enc(userId)}`),

  users: () => api("GET", "/api/v1/client/users"),
  userProducers: (id) => api("GET", `/api/v1/client/users/${enc(id)}/producers`),
  inviteUser: (name, role, deviceName) =>
    api("POST", "/api/v1/client/users", { name, role, ...(deviceName ? { deviceName } : {}) }),
  setRole: (id, role) => api("PATCH", `/api/v1/client/users/${enc(id)}`, { role }),
  pairing: (id) => api("GET", `/api/v1/client/pairings/${enc(id)}`),
  createPairing: (userId, name) => api("POST", "/api/v1/client/pairings", { name, userId }),

  devices: () => api("GET", "/api/v1/client/devices"),
  renameDevice: (id, name) => api("PATCH", `/api/v1/client/devices/${enc(id)}`, { name }),
  revokeDevice: (id) => api("POST", `/api/v1/client/devices/${enc(id)}/revoke`),
  deleteDevice: (id) => api("DELETE", `/api/v1/client/devices/${enc(id)}`),
};
