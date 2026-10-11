// What the sections have read that other sections use: the users (to choose an owner or a user)
// and the devices (the rail's status button judges pushes by them). Kept in memory only, dropped
// when the operator signs out.

import { CLIENTS, USERS, call } from "./api.js";

const listeners = new Set();

export const store = {
  users: null,
  clients: null,
};

export function onStoreChange(listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function setClients(items) {
  store.clients = items;
  for (const listener of listeners) listener("clients");
}

export function clearStore() {
  store.users = null;
  store.clients = null;
}

/** The users, read again each time a form needs them. */
export async function loadUsers() {
  store.users = (await call("GET", USERS)).items;
  return store.users;
}

export async function loadClients() {
  const items = (await call("GET", CLIENTS)).items;
  setClients(items);
  return items;
}
