// What the whole page shares: who is signed in, and a few counts. Held in memory only; the
// session itself is a cookie the page cannot read.

export const state = {
  /** `{userId, name, role, clientId, clientName, createdAt, expiresAt}` once signed in. */
  me: null,
  unread: null,
  /** Open questions this person may answer: the inbox's second count. */
  toAnswer: null,
  server: null,
  listeners: new Set(),
};

export const isAdmin = () => state.me?.role === "ADMIN";

export function setMe(session) {
  const { client } = session;
  state.me = {
    userId: client.user.id,
    name: client.user.name,
    role: client.user.role,
    clientId: client.id,
    clientName: client.name,
    createdAt: client.createdAt,
    expiresAt: client.expiresAt,
  };
}

/** Subscribes to changes of the shared state; returns the way to stop. */
export function onChange(listener) {
  state.listeners.add(listener);
  return () => state.listeners.delete(listener);
}

export function setUnread(count) {
  if (state.unread === count) return;
  state.unread = count;
  for (const listener of state.listeners) listener("unread");
}

export function setToAnswer(count) {
  if (state.toAnswer === count) return;
  state.toAnswer = count;
  for (const listener of state.listeners) listener("toAnswer");
}

export function setRole(role) {
  if (!state.me || state.me.role === role) return;
  state.me.role = role;
  for (const listener of state.listeners) listener("role");
}

/** What the shell does when the session ends or the person signs out; set by main.js. */
export const hooks = {
  signedOut: () => {},
};
