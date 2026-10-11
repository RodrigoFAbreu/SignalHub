// Users, as the admin page showed them before the next item rebuilds this section: the list, the
// devices, producers and subscriptions of each user, their traffic, inviting, renaming, roles and
// revoking, with the browser's own confirmations. The Connect a device button leads to the Devices
// section's dialog, where the user is already chosen.

import { PRODUCERS, USERS, call } from "./api.js";
import { connectDevice as openConnect } from "./pairing.js";
import { $, ROLES, ago, button, element, hideLegacy, outcome, showError, showLegacy, time } from "./legacy.js";

// The users as the last refresh read them.
let users = [];

$("refresh-users").addEventListener("click", () => refreshUsers());

$("invite").addEventListener("submit", async (event) => {
  event.preventDefault();
  showError("invite-error", null);
  try {
    await call("POST", USERS, { name: $("invite-name").value.trim(), role: $("invite-role").value });
    $("invite").reset();
    await refreshUsers();
  } catch (e) {
    showError("invite-error", e.message);
  }
});


async function loadUsers() {
  users = (await call("GET", USERS)).items;
}

// Offers the users the filter keeps, keeping the one chosen, else the first.
function fillUserChoice(select, keep) {
  const chosen = select.value;
  const offered = users.filter(keep);
  select.replaceChildren(...offered.map((u) => new Option(`${u.name} (${ROLES[u.role]})`, u.id)));
  if (offered.some((u) => u.id === chosen)) select.value = chosen;
}

async function refreshUsers() {
  showError("users-error", null);
  try {
    await loadUsers();
    const producers = (await call("GET", PRODUCERS)).items;
    renderUsers(users, producers);
  } catch (e) {
    showError("users-error", e.message);
  }
}

// Shows the list as the server has it afterwards, whether the change worked or not.
async function changeUser(action) {
  let failure = null;
  try {
    await action();
  } catch (e) {
    failure = e.message;
  }
  await refreshUsers();
  if (failure) showError("users-error", failure);
}

function renderUsers(all, producers) {
  const list = $("user-list");
  // Active users first, in the order they were invited.
  const sorted = [...all].sort((a, b) => (a.revokedAt ? 1 : 0) - (b.revokedAt ? 1 : 0));
  list.replaceChildren(...sorted.map((user) => userCard(user, producers)));
  if (sorted.length === 0) list.append(element("li", "empty", "No users."));
}

function userCard(user, producers) {
  const item = element("li", user.revokedAt ? "device revoked" : "device");
  const title = element("h3", null, user.name);
  title.append(" ", element("span", user.role === "ADMIN" ? "badge" : "badge muted", ROLES[user.role]));
  if (user.revokedAt) title.append(" ", element("span", "badge muted", "Revoked"));
  item.append(title);

  const facts = element("dl");
  const fact = (name, value) => facts.append(element("dt", null, name), element("dd", null, value));
  const names = (list) => (list.length === 0 ? "None" : list.map((x) => x.name).join(", "));
  fact(
    "Devices",
    names(user.devices.filter((d) => !d.revokedAt)) +
      (user.devices.some((d) => d.revokedAt) ? ` (${user.devices.filter((d) => d.revokedAt).length} revoked)` : ""),
  );
  fact("Producers", names(user.producers));
  fact("Subscriptions", names(user.subscriptions));
  fact("Invited", time(user.createdAt));
  if (user.revokedAt) fact("Revoked", time(user.revokedAt));
  fact("ID", user.id);
  item.append(facts);
  item.append(trafficOf(user));

  if (user.revokedAt) return item;

  // A producer the user sees, and is not subscribed to yet, can be subscribed to here.
  const subscribed = new Set(user.subscriptions.map((s) => s.id));
  const open = producers.filter(
    (p) =>
      !subscribed.has(p.id) &&
      (p.visibility === "PUBLIC" || p.owner.id === user.id || p.allowedUsers.some((a) => a.id === user.id)),
  );
  const actions = element("div", "actions");
  actions.append(
    button("Connect a device", () => connectDevice(user)),
    button("Rename", () => renameUser(user)),
  );
  const role = element("select");
  role.setAttribute("aria-label", `Role of "${user.name}"`);
  for (const [value, text] of Object.entries(ROLES)) role.append(new Option(text, value));
  role.value = user.role;
  actions.append(role, button("Set role", () => setRole(user, role.value)));
  actions.append(button("Revoke", () => revokeUser(user), "danger"));
  item.append(actions);

  const subscriptions = element("div", "actions");
  for (const s of user.subscriptions) {
    subscriptions.append(
      button(`Unsubscribe from ${s.name}`, () =>
        changeUser(() => call("DELETE", `${USERS}/${user.id}/subscriptions/${s.id}`)),
      ),
    );
  }
  if (open.length > 0) {
    const choice = element("select");
    choice.setAttribute("aria-label", `Producer to subscribe "${user.name}" to`);
    choice.append(...open.map((p) => new Option(p.name, p.id)));
    subscriptions.append(
      choice,
      button("Subscribe", () =>
        changeUser(() => call("PUT", `${USERS}/${user.id}/subscriptions/${choice.value}`)),
      ),
    );
  }
  item.append(subscriptions);
  return item;
}

// A user's recent events and deliveries, read when asked for (and again by the Refresh next to
// them), so the list of users stays cheap.
function trafficOf(user) {
  const panel = element("div", "traffic");
  const heading = element("div", "actions");
  const body = element("div");
  body.hidden = true;
  const toggle = button("Show traffic", async () => {
    body.hidden = !body.hidden;
    toggle.textContent = body.hidden ? "Show traffic" : "Hide traffic";
    if (!body.hidden) await loadTraffic(user, body);
  });
  heading.append(toggle);
  panel.append(heading, body);
  return panel;
}

async function loadTraffic(user, body) {
  body.replaceChildren(element("p", "meta", "Loading…"));
  try {
    renderTraffic(user, body, await call("GET", `${USERS}/${user.id}/traffic`));
  } catch (e) {
    body.replaceChildren(element("p", "error", e.message));
  }
}

function renderTraffic(user, body, traffic) {
  const events = element("ul", "keys");
  for (const e of traffic.events) {
    const line = element("li");
    const link = element("a", null, e.title);
    link.href = `#events/${e.id}`;
    line.append(link, ` · ${e.producer.name} · ${time(e.createdAt)} (${ago(e.createdAt)})`);
    events.append(line);
  }
  if (traffic.events.length === 0) events.append(element("li", "empty", "No events."));
  const deliveries = element("ul", "deliveries");
  for (const d of traffic.deliveries) {
    const line = element("li", `delivery outcome-${d.outcome.toLowerCase()}`);
    const link = element("a", null, d.eventTitle);
    link.href = `#events/${d.eventId}`;
    line.append(element("strong", null, d.clientName), `: ${outcome(d)}, `, link, `, ${time(d.at)} (${ago(d.at)})`);
    deliveries.append(line);
  }
  if (traffic.deliveries.length === 0) deliveries.append(element("li", "empty", "No deliveries."));
  body.replaceChildren(
    element("h4", null, `Events of ${user.name}'s producers and subscriptions, newest first`),
    events,
    element("h4", null, "Pushes to their devices, newest first"),
    deliveries,
    button("Refresh traffic", () => loadTraffic(user, body)),
  );
}

function renameUser(user) {
  const name = prompt(`New name for "${user.name}":`, user.name);
  if (name === null || name.trim() === "" || name.trim() === user.name) return;
  changeUser(() => call("PATCH", `${USERS}/${user.id}`, { name: name.trim() }));
}

function setRole(user, role) {
  if (role === user.role) return;
  const question =
    role === "ADMIN"
      ? `Make "${user.name}" an admin? All their devices become admin devices, and they can manage every device that is not an admin's.`
      : user.role === "ADMIN"
        ? `Take admin rights away from "${user.name}"? Their devices stop being admin devices.`
        : `Make "${user.name}" ${ROLES[role]}?`;
  if (!confirm(question)) return;
  changeUser(() => call("PATCH", `${USERS}/${user.id}`, { role }));
}

function revokeUser(user) {
  const question = `Revoke "${user.name}"? All their devices are revoked and their producers disabled, at once and for good. Their events stay.`;
  if (!confirm(question)) return;
  changeUser(() => call("POST", `${USERS}/${user.id}/revoke`));
}

// The Devices section's dialog, with this user already chosen.
function connectDevice(user) {
  openConnect({ user });
}


export const usersSection = {
  mount() {
    showLegacy("users");
    refreshUsers();
  },
  update() {},
  unmount() {
    hideLegacy();
  },
};
