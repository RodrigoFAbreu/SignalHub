"use strict";

// The admin page (docs/architecture.md#the-admin-page), in sections kept in the address's fragment:
// Devices lists every client with its user, changes them, deletes revoked ones, and creates
// pairings for a user shown as a QR code until they are used or expire; Users lists every user with
// their devices, producers and subscriptions, invites them, renames them, sets their role (admin
// included, which only this page does), subscribes them to producers and revokes them; Producers
// lists every producer with its owner and who sees it, creates them for a user, edits their
// visibility and allow-list, issues and revokes their keys, and disables and enables them; Events lists events a
// page at a time, filtered, and opens one (#events/<id>) to read it, see how its push went to each
// device and mark it read or unread, deletes one, a selection, or a producer's or older events,
// after a confirmation with their count, and sends a test event as a producer, linked once sent;
// Status sums up whether SignalHub is working, from /q/info, /q/health and the management API.
// The admin token lives only in this closure; it is never stored, and every request goes to this
// same origin. A new producer key is shown once and dropped when the operator is done with it.
// Names and event contents come from the server and are always set as text, never as HTML; an
// event's link is only ever opened by the operator, in a new tab, never followed by the page.
(() => {
  const CLIENTS = "/api/v1/admin/clients";
  const PAIRINGS = "/api/v1/admin/pairings";
  const PRODUCERS = "/api/v1/admin/producers";
  const USERS = "/api/v1/admin/users";
  const EVENTS = "/api/v1/events";
  const ADMIN_EVENTS = "/api/v1/admin/events";
  const DELETE_EVENTS = "/api/v1/admin/events/delete";
  const STATUS = "/api/v1/admin/status";
  const INFO = "/q/info";
  const HEALTH = "/q/health";
  const SECTIONS = ["devices", "users", "producers", "events", "status"];
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
  // Canonical IDs only, so nothing typed into the address becomes another request path.
  const EVENT_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  // The server accepts only these schemes; checked again so no other link is ever made clickable.
  const WEB_LINK = /^https?:\/\//i;
  const LABELS = {
    ACTION_REQUIRED: "Action required",
    BLOCKED: "Blocked",
    COMPLETED: "Completed",
    INFO: "Info",
    LOW: "Low",
    NORMAL: "Normal",
    HIGH: "High",
    CRITICAL: "Critical",
  };
  // How a delivery record's attempt went, as the operator reads it.
  const OUTCOMES = {
    DELIVERED: "Delivered",
    FILTERED: "Filtered out by its push preferences",
    NO_TARGET: "Not sent: no push target",
    UNSUPPORTED_PROVIDER: "Not sent: push provider not configured",
    INVALID_TARGET: "Push target rejected, and removed",
    TRANSIENT_FAILURE: "Temporary failure",
    PERMANENT_FAILURE: "Failed",
  };
  const ROLES = { BASIC: "Basic", MOD: "Mod", ADMIN: "Admin" };
  // An enabled producer with no event for this long is marked quiet, so one that stopped stands out.
  const QUIET_DAYS = 7;
  const DAY_S = 24 * 60 * 60;
  const DAY_MS = DAY_S * 1000;
  const QR_SIZE = 320;
  // Asked only while a code is shown; one owner's page, so a few seconds late is fine.
  const POLL_MS = 2500;
  const TOAST_MS = 8000;
  const $ = (id) => document.getElementById(id);

  let token = null;
  let timer = null;
  let poller = null;
  let current = null;
  let toastTimer = null;
  // The cursor of each events page read so far, the first page having none, and the next one's.
  let eventPages = [null];
  let nextEventCursor = null;
  let shownEvent = null;
  // The users as the last section that needed them read them; the choices of owner and user.
  let users = [];
  // The IDs of the events ticked on the page shown; a page read again starts with none.
  let selected = new Set();

  $("unlock").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("error", null);
    try {
      await call("GET", CLIENTS, null, $("token").value.trim());
      // Kept only once it has worked, so a wrong token never replaces a right one.
      token = $("token").value.trim();
      $("token").value = "";
      $("unlock").hidden = true;
      $("admin").hidden = false;
      showSection();
    } catch (e) {
      showError("error", e.message);
    }
  });

  window.addEventListener("hashchange", () => {
    if (token) showSection();
  });

  $("refresh").addEventListener("click", () => refresh());
  $("refresh-users").addEventListener("click", () => refreshUsers());
  $("refresh-producers").addEventListener("click", () => refreshProducers());
  $("refresh-events").addEventListener("click", () => refreshEvents());
  $("refresh-status").addEventListener("click", () => refreshStatus());

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

  $("create").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("pair-error", null);
    try {
      const pairing = await call("POST", PAIRINGS, {
        name: $("name").value.trim(),
        userId: $("pair-user").value,
      });
      // The app pairs only from a link, and the link needs the server's public address.
      if (!pairing.uri) {
        throw new Error("No pairing link: set SIGNALHUB_PUBLIC_URL on the server to its public address.");
      }
      show(pairing);
    } catch (e) {
      showError("pair-error", e.message);
    }
  });

  $("create-producer").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("create-producer-error", null);
    try {
      const issued = await call("POST", PRODUCERS, {
        name: $("producer-name").value.trim(),
        ownerId: $("producer-owner").value,
        visibility: $("producer-visibility").value,
      });
      $("create-producer").reset();
      showKey(issued);
      await refreshProducers();
    } catch (e) {
      showError("create-producer-error", e.message);
    }
  });

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

  $("copy-key").addEventListener("click", () => copyFrom($("new-key-value"), "key", keyStatus));
  $("new-key-done").addEventListener("click", () => hideKey());

  $("copy-link").addEventListener("click", () => copyLink());
  $("copy-image").addEventListener("click", () => copyImage());
  $("download").addEventListener("click", () => download());

  async function call(method, path, body, withToken = token) {
    let response;
    try {
      response = await fetch(path, {
        method,
        headers: body
          ? { Authorization: `Bearer ${withToken}`, "Content-Type": "application/json" }
          : { Authorization: `Bearer ${withToken}` },
        body: body ? JSON.stringify(body) : undefined,
        cache: "no-store",
      });
    } catch {
      throw new Error("Could not reach SignalHub.");
    }
    if (response.status === 401) throw new Error("Wrong admin token.");
    if (response.status === 404 && (path === CLIENTS || path === PRODUCERS)) {
      throw new Error("The management API is off: set SIGNALHUB_ADMIN_TOKEN on the server.");
    }
    if (!response.ok) throw new Error(await errorTitle(response));
    return response.status === 204 ? null : response.json();
  }

  async function errorTitle(response) {
    try {
      const body = await response.json();
      const details = (body.violations || []).map((v) => v.message).join(", ");
      if (body.title) return details ? `${body.title}: ${details}` : body.title;
    } catch {
      // Not JSON: said below by its status alone.
    }
    // Only SignalHub's own errors have a title; a failure outside them, such as a database that
    // is down, is said by its status, so it is never shown as an empty error.
    return `SignalHub answered ${response.status}.`;
  }

  // --- Sections --------------------------------------------------------------------------------

  // Shows the section named in the address, Devices when it names none, and reads its list again.
  // Events may name an event too: #events/<id>.
  function showSection() {
    const [first, eventId] = location.hash.slice(1).split("/");
    const name = SECTIONS.find((section) => first === section) || SECTIONS[0];
    for (const node of document.querySelectorAll("#admin > [data-section]")) {
      node.hidden = node.dataset.section !== name;
    }
    for (const link of document.querySelectorAll("#sections a")) {
      if (link.dataset.section === name) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
    if (name === "events") return showEvents(eventId);
    if (name === "status") return refreshStatus();
    if (name === "users") return refreshUsers();
    return name === "producers" ? refreshProducers() : refresh();
  }

  // --- Devices ---------------------------------------------------------------------------------

  async function refresh() {
    showError("devices-error", null);
    try {
      render((await call("GET", CLIENTS)).items);
      await loadUsers();
      fillUserChoice($("pair-user"), (user) => !user.revokedAt);
    } catch (e) {
      showError("devices-error", e.message);
    }
  }

  // Shows the list as the server has it afterwards, whether the change worked or not.
  async function change(action) {
    let failure = null;
    try {
      await action();
    } catch (e) {
      failure = e.message;
    }
    await refresh();
    if (failure) showError("devices-error", failure);
  }

  function render(clients) {
    // Active devices first, newest first, as the owner looks for the one just paired.
    const sorted = [...clients].sort(
      (a, b) => (a.revokedAt ? 1 : 0) - (b.revokedAt ? 1 : 0) || b.createdAt.localeCompare(a.createdAt),
    );
    const list = $("device-list");
    list.replaceChildren(...sorted.map(device));
    if (sorted.length === 0) list.append(element("li", "empty", "No devices yet."));
  }

  function device(client) {
    const item = element("li", client.revokedAt ? "device revoked" : "device");
    const title = element("h3", null, client.name);
    if (client.admin) title.append(" ", element("span", "badge", "Admin device"));
    if (client.revokedAt) title.append(" ", element("span", "badge muted", "Revoked"));
    item.append(title);

    const facts = element("dl");
    const fact = (name, value) => facts.append(element("dt", null, name), element("dd", null, value));
    fact("User", `${client.user.name} (${ROLES[client.user.role] || client.user.role})`);
    fact("Created", time(client.createdAt));
    if (client.revokedAt) fact("Revoked", time(client.revokedAt));
    fact(
      "Push target",
      client.pushTarget ? `${client.pushTarget.provider}, set ${time(client.pushTarget.updatedAt)}` : "None",
    );
    const status = client.pushStatus;
    fact(
      "Last push",
      status.lastSuccess ? `${time(status.lastSuccess.at)}, event ${status.lastSuccess.eventId}` : "None yet",
    );
    fact(
      "Last failure",
      status.lastFailure
        ? `${time(status.lastFailure.at)}, ${status.lastFailure.result}, event ${status.lastFailure.eventId}`
        : "None",
    );
    fact("Waiting for a retry", String(status.pendingRetries));
    fact("ID", client.id);
    item.append(facts);

    // A revoked client never changes; it can only be deleted. An active one must be revoked first.
    const actions = element("div", "actions");
    if (client.revokedAt) {
      actions.append(button("Delete", () => remove(client), "danger"));
    } else {
      actions.append(
        button("Rename", () => rename(client)),
        button("Revoke", () => revoke(client), "danger"),
      );
    }
    item.append(actions);
    return item;
  }

  function rename(client) {
    const name = prompt(`New name for "${client.name}":`, client.name);
    if (name === null || name.trim() === "" || name.trim() === client.name) return;
    change(() => update(client, { name: name.trim() }));
  }

  function revoke(client) {
    const what = client.admin ? "admin device" : "device";
    if (!confirm(`Revoke the ${what} "${client.name}"? It stops working at once, for good.`)) return;
    change(() => call("POST", `${CLIENTS}/${client.id}/revoke`));
  }

  function remove(client) {
    if (!confirm(`Delete the revoked device "${client.name}"? It leaves this list for good.`)) return;
    change(() => call("DELETE", `${CLIENTS}/${client.id}`));
  }

  function update(client, changes) {
    return call("PATCH", `${CLIENTS}/${client.id}`, changes);
  }

  function time(iso) {
    return new Date(iso).toLocaleString();
  }

  function ago(iso) {
    const minutes = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000));
    if (minutes < 1) return "just now";
    if (minutes < 60) return plural(minutes, "minute");
    if (minutes < 60 * 24) return plural(Math.round(minutes / 60), "hour");
    return plural(Math.round(minutes / (60 * 24)), "day");
  }

  function plural(count, unit) {
    return `${count} ${unit}${count === 1 ? "" : "s"} ago`;
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function button(text, onClick, className = "secondary") {
    const node = element("button", className, text);
    node.type = "button";
    node.addEventListener("click", onClick);
    return node;
  }

  // --- Users -----------------------------------------------------------------------------------

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

  // A pairing code for a new device of the user, shown in Devices.
  async function connectDevice(user) {
    const name = prompt(`Name of the new device of "${user.name}":`, "New device");
    if (name === null || name.trim() === "") return;
    try {
      const pairing = await call("POST", PAIRINGS, { name: name.trim(), userId: user.id });
      if (!pairing.uri) {
        throw new Error("No pairing link: set SIGNALHUB_PUBLIC_URL on the server to its public address.");
      }
      location.hash = "#devices";
      show(pairing);
    } catch (e) {
      showError("users-error", e.message);
    }
  }

  // --- Producers -------------------------------------------------------------------------------

  async function refreshProducers() {
    showError("producers-error", null);
    try {
      await loadUsers();
      fillUserChoice($("producer-owner"), (user) => !user.revokedAt);
      renderProducers((await call("GET", PRODUCERS)).items);
    } catch (e) {
      showError("producers-error", e.message);
    }
  }

  // Shows the list as the server has it afterwards, whether the change worked or not.
  async function changeProducer(action) {
    let failure = null;
    try {
      await action();
    } catch (e) {
      failure = e.message;
    }
    await refreshProducers();
    if (failure) showError("producers-error", failure);
  }

  function renderProducers(producers) {
    // By name, as the server lists them; a quiet one stands out by its badge.
    const list = $("producer-list");
    list.replaceChildren(...producers.map(producer));
    if (producers.length === 0) list.append(element("li", "empty", "No producers yet."));
  }

  function quiet(producer) {
    if (producer.disabledAt) return false;
    return !producer.lastEventAt || Date.now() - Date.parse(producer.lastEventAt) > QUIET_DAYS * DAY_MS;
  }

  function producer(p) {
    const item = element("li", p.disabledAt ? "producer disabled" : "producer");
    const title = element("h3", null, p.name);
    if (p.disabledAt) title.append(" ", element("span", "badge muted", "Disabled"));
    if (quiet(p)) title.append(" ", element("span", "badge warn", "Quiet"));
    item.append(title);

    const facts = element("dl");
    const fact = (name, value) => facts.append(element("dt", null, name), element("dd", null, value));
    // Only events still stored count: retention may have deleted older ones.
    fact("Owner", p.owner.name);
    fact("Who sees it", p.visibility === "PUBLIC" ? "Every user" : "Its owner and the users allowed on it");
    fact("Last event", p.lastEventAt ? `${time(p.lastEventAt)} (${ago(p.lastEventAt)})` : "None stored");
    fact("Created", time(p.createdAt));
    if (p.disabledAt) fact("Disabled", time(p.disabledAt));
    fact("ID", p.id);
    item.append(facts);

    item.append(element("h4", null, "Keys"));
    const keys = element("ul", "keys");
    // Valid keys first, newest first, as the one just issued is the one looked for.
    const sorted = [...p.keys].sort(
      (a, b) => (a.revokedAt ? 1 : 0) - (b.revokedAt ? 1 : 0) || b.createdAt.localeCompare(a.createdAt),
    );
    keys.append(...sorted.map((key) => apiKey(p, key)));
    if (sorted.length === 0) keys.append(element("li", "empty", "No keys."));
    item.append(keys);

    item.append(element("h4", null, "Allowed users"));
    item.append(allowList(p));

    const actions = element("div", "actions");
    actions.append(
      button("Issue a key", () => issueKey(p)),
      button(p.visibility === "PUBLIC" ? "Make private" : "Make public", () => toggleVisibility(p)),
      p.disabledAt
        ? button("Enable", () => changeProducer(() => call("POST", `${PRODUCERS}/${p.id}/enable`)))
        : button("Disable", () => disable(p), "danger"),
    );
    item.append(actions);
    return item;
  }

  // Who is allowed on a private producer besides its owner; kept, without effect, while it is public.
  function allowList(p) {
    const box = element("div");
    const list = element("ul", "keys");
    for (const user of p.allowedUsers) {
      const line = element("li", "key");
      line.append(element("span", null, user.name));
      const rest = p.allowedUsers.filter((u) => u.id !== user.id).map((u) => u.id);
      line.append(button("Remove", () => setAllowed(p, rest), "danger"));
      list.append(line);
    }
    if (p.allowedUsers.length === 0) list.append(element("li", "empty", "No one besides its owner."));
    box.append(list);
    const addable = users.filter(
      (u) => !u.revokedAt && u.id !== p.owner.id && !p.allowedUsers.some((a) => a.id === u.id),
    );
    if (addable.length > 0) {
      const choice = element("select");
      choice.setAttribute("aria-label", `Allow a user on "${p.name}"`);
      choice.append(...addable.map((u) => new Option(u.name, u.id)));
      const add = button("Allow", () => setAllowed(p, [...p.allowedUsers.map((a) => a.id), choice.value]));
      const actions = element("div", "actions");
      actions.append(choice, add);
      box.append(actions);
    }
    return box;
  }

  function setAllowed(p, allowedUserIds) {
    changeProducer(() => call("PATCH", `${PRODUCERS}/${p.id}`, { allowedUserIds }));
  }

  function toggleVisibility(p) {
    const toPublic = p.visibility !== "PUBLIC";
    const question = toPublic
      ? `Make "${p.name}" public? Every user may then see it and subscribe.`
      : `Make "${p.name}" private? Subscribers who are neither its owner nor allowed stop receiving it.`;
    if (!confirm(question)) return;
    changeProducer(() =>
      call("PATCH", `${PRODUCERS}/${p.id}`, { visibility: toPublic ? "PUBLIC" : "PRIVATE" }),
    );
  }

  function apiKey(p, key) {
    const item = element("li", key.revokedAt ? "key revoked" : "key");
    const text = element("span", null, `${key.id}, created ${time(key.createdAt)}`);
    item.append(text);
    if (key.revokedAt) {
      text.append(`, revoked ${time(key.revokedAt)}`);
    } else {
      item.append(button("Revoke", () => revokeKey(p, key), "danger"));
    }
    return item;
  }

  function issueKey(p) {
    changeProducer(async () => showKey(await call("POST", `${PRODUCERS}/${p.id}/keys`)));
  }

  function revokeKey(p, key) {
    const question = `Revoke key ${key.id} of "${p.name}"? It stops working at once, for good.`;
    if (!confirm(question)) return;
    changeProducer(() => call("POST", `${PRODUCERS}/${p.id}/keys/${key.id}/revoke`));
  }

  function disable(p) {
    if (!confirm(`Disable "${p.name}"? None of its keys work until it is enabled again.`)) return;
    changeProducer(() => call("POST", `${PRODUCERS}/${p.id}/disable`));
  }

  // The only time the key is on the page; it leaves with hideKey and is never stored.
  function showKey(issued) {
    $("new-key-producer").textContent = issued.producer.name;
    $("new-key-value").value = issued.apiKey;
    keyStatus("");
    $("new-key").hidden = false;
    $("new-key").scrollIntoView({ block: "nearest" });
  }

  function hideKey() {
    $("new-key-value").value = "";
    $("new-key").hidden = true;
  }

  function keyStatus(text) {
    $("new-key-status").textContent = text;
  }

  // --- Events ----------------------------------------------------------------------------------

  // The list, or one event when the address names one.
  function showEvents(eventId) {
    const one = EVENT_ID.test(eventId || "");
    $("event-browser").hidden = one;
    $("event-details").hidden = !one;
    return one ? openEvent(eventId) : Promise.all([refreshEvents(), refreshProducerChoices()]);
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

  // A value this page does not know yet is shown as it is; the reason, if any, follows it.
  function outcome(record) {
    const text = OUTCOMES[record.outcome] || record.outcome;
    return record.detail ? `${text} (${record.detail})` : text;
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

  // --- Status ----------------------------------------------------------------------------------

  // Reads every part at once; a part that cannot be read says so where it would be shown, and the
  // others are shown all the same. Anything that needs the operator is named in the summary.
  async function refreshStatus() {
    const [info, health, status, clients, latest] = await Promise.allSettled([
      probe(INFO),
      probe(HEALTH),
      call("GET", STATUS),
      call("GET", CLIENTS),
      call("GET", `${EVENTS}?limit=1`),
    ]);
    const problems = [];
    const facts = [];
    const fact = (name, value, problem) => {
      const cell = element("dd", null, value);
      if (problem) {
        cell.append(" ", element("span", "badge warn", "Check"));
        problems.push(problem);
      }
      facts.push(element("dt", null, name), cell);
    };
    const notRead = (part) => `Could not read: ${part.reason.message}`;

    if (info.status === "fulfilled") {
      const build = info.value.signalhub || {};
      fact("Version", build.version === "development" ? "Development build" : build.version || "Unknown");
      fact("Commit", build.revision || "Unknown");
    } else {
      fact("Version", notRead(info), "the version");
    }

    if (health.status === "fulfilled") {
      const up = health.value.status === "UP";
      fact("Health", up ? "Up" : "Down", !up && "health");
      // The database and the backend's own checks, by the name each reports.
      for (const check of health.value.checks || []) {
        fact(check.name, check.status === "UP" ? "Up" : "Down");
      }
    } else {
      fact("Health", notRead(health), "health");
    }

    if (status.status === "fulfilled") {
      const s = status.value;
      const push = s.pushProviders.length > 0;
      fact(
        "Push",
        push ? `Configured: ${s.pushProviders.join(", ")}` : "Not configured: nothing is pushed",
        !push && "push",
      );
      fact(
        "Push options for apps",
        s.pushClientOptions
          ? `Served for ${s.pushClientOptions}`
          : "Not served: only apps with Firebase options built in can receive pushes",
        push && !s.pushClientOptions && "the push options for apps",
      );
      fact("Pushes waiting to be sent", String(s.pendingDispatches));
      fact("Pushes waiting for a retry", String(s.pendingRetries));
      fact(
        "Retries given up since the backend started",
        String(s.abandonedRetries),
        s.abandonedRetries > 0 && "the retries given up",
      );
      fact(
        "Event retention",
        s.eventRetentionSeconds === null ? "Off: events are kept forever" : duration(s.eventRetentionSeconds),
      );
    } else {
      fact("Push", notRead(status), "push");
    }

    if (clients.status === "fulfilled") {
      const failing = clients.value.items.filter(lastPushFailed);
      fact("Devices whose last push failed", String(failing.length), failing.length > 0 && "the devices");
      renderFailing(failing);
    } else {
      fact("Devices whose last push failed", notRead(clients), "the devices");
      renderFailing([]);
    }

    if (latest.status === "fulfilled") {
      const [event] = latest.value.items;
      fact("Most recent event", event ? `${time(event.createdAt)} (${ago(event.createdAt)})` : "None stored");
    } else {
      fact("Most recent event", notRead(latest), "the events");
    }

    $("status-facts").replaceChildren(...facts);
    $("status-summary").replaceChildren(
      problems.length ? element("span", "badge warn", "Needs attention") : element("span", "badge", "Working"),
      problems.length ? ` Check ${problems.join(", ")}.` : " Nothing needs attention.",
    );
  }

  // /q/info and /q/health need no token, so none is sent; health answers 503 with its checks when
  // something is down, which is still an answer to show.
  async function probe(path) {
    let response;
    try {
      response = await fetch(path, { cache: "no-store" });
    } catch {
      throw new Error("Could not reach SignalHub.");
    }
    try {
      return await response.json();
    } catch {
      throw new Error(`SignalHub answered ${response.status}.`);
    }
  }

  // An active device whose latest push result is a failure; a later success clears it.
  function lastPushFailed(client) {
    const { lastSuccess, lastFailure } = client.pushStatus;
    if (client.revokedAt || !lastFailure) return false;
    return !lastSuccess || Date.parse(lastFailure.at) > Date.parse(lastSuccess.at);
  }

  function renderFailing(clients) {
    const list = $("failing-devices");
    list.replaceChildren(
      ...clients.map((client) => {
        const failure = client.pushStatus.lastFailure;
        return element("li", "key", `${client.name}: ${failure.result}, ${time(failure.at)} (${ago(failure.at)})`);
      }),
    );
    if (clients.length === 0) list.append(element("li", "empty", "None."));
  }

  function duration(seconds) {
    if (seconds % DAY_S === 0) return amount(seconds / DAY_S, "day");
    if (seconds % 3600 === 0) return amount(seconds / 3600, "hour");
    return amount(seconds, "second");
  }

  function amount(count, unit) {
    return `${count} ${unit}${count === 1 ? "" : "s"}`;
  }

  // --- Pairing ---------------------------------------------------------------------------------

  function show(pairing) {
    current = pairing;
    $("pairing-name").textContent = pairing.name;
    $("pairing-user").textContent = `For ${pairing.user.name} (${ROLES[pairing.user.role] || pairing.user.role}).`;
    $("pairing-admin").hidden = !pairing.admin;
    $("status").textContent = "";
    $("qr-box").classList.remove("expired");
    $("expired-cover").hidden = true;
    $("link").value = pairing.uri;
    for (const id of ["copy-image", "copy-link", "download"]) $(id).disabled = false;
    draw(pairing.uri);
    $("pairing").hidden = false;
    clearInterval(timer);
    clearInterval(poller);
    tick();
    timer = setInterval(tick, 1000);
    poller = setInterval(() => check(pairing), POLL_MS);
  }

  function tick() {
    const left = Math.max(0, Date.parse(current.expiresAt) - Date.now());
    if (left === 0) {
      clearInterval(timer);
      clearInterval(poller);
      // Once more: it may have been used in the last seconds.
      check(current);
      $("countdown").textContent = "This code has expired.";
      $("status").textContent = "";
      $("qr-box").classList.add("expired");
      $("expired-cover").hidden = false;
      $("link").value = "";
      for (const id of ["copy-image", "copy-link", "download"]) $(id).disabled = true;
      return;
    }
    const minutes = Math.floor(left / 60000);
    const seconds = String(Math.floor((left % 60000) / 1000)).padStart(2, "0");
    $("countdown").textContent = `Expires in ${minutes}:${seconds}. It works once.`;
  }

  // Whether the code shown was used. The server keeps a used pairing past its expiry, so a late
  // answer still says so; the countdown alone decides that a code expired.
  async function check(pairing) {
    let status;
    try {
      status = await call("GET", `${PAIRINGS}/${pairing.id}`);
    } catch {
      return; // Asked again at the next poll.
    }
    if (current !== pairing || status.state !== "REDEEMED") return;
    connected(status.client);
  }

  // Back to the first state, ready for the next device, and the new one in the list.
  function connected(client) {
    clearInterval(timer);
    clearInterval(poller);
    current = null;
    $("pairing").hidden = true;
    $("link").value = "";
    $("create").reset();
    toast(`"${client.name}" connected with the pairing code.`);
    refresh();
  }

  function toast(text) {
    $("toast").textContent = text;
    $("toast").hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => ($("toast").hidden = true), TOAST_MS);
  }

  function draw(text) {
    // Type 0 picks the smallest QR version that fits; level M survives a slightly blurry photo.
    const qr = qrcode(0, "M");
    qr.addData(text);
    qr.make();
    const modules = qr.getModuleCount();
    const quiet = 4;
    const scale = Math.floor(QR_SIZE / (modules + 2 * quiet));
    const offset = Math.floor((QR_SIZE - scale * modules) / 2);
    const context = $("qr").getContext("2d");
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, QR_SIZE, QR_SIZE);
    context.fillStyle = "#000000";
    for (let row = 0; row < modules; row++) {
      for (let col = 0; col < modules; col++) {
        if (qr.isDark(row, col)) {
          context.fillRect(offset + col * scale, offset + row * scale, scale, scale);
        }
      }
    }
  }

  function copyLink() {
    return copyFrom($("link"), "link", status);
  }

  // Copies an input's text, and says so with say.
  async function copyFrom(input, what, say) {
    try {
      await navigator.clipboard.writeText(input.value);
    } catch {
      // The clipboard API needs a secure context (https or localhost); selecting still works.
      input.select();
      if (!document.execCommand("copy")) {
        return say(`Copy the selected ${what} with Ctrl+C.`);
      }
    }
    say(`${what[0].toUpperCase()}${what.slice(1)} copied.`);
  }

  async function copyImage() {
    if (!navigator.clipboard || typeof ClipboardItem === "undefined") {
      return status("This browser cannot copy images here. Use Download QR.");
    }
    try {
      await navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob() })]);
      status("QR image copied.");
    } catch {
      status("Could not copy the image. Use Download QR.");
    }
  }

  function pngBlob() {
    return new Promise((resolve, reject) =>
      $("qr").toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png"),
    );
  }

  async function download() {
    const url = URL.createObjectURL(await pngBlob());
    const link = document.createElement("a");
    link.href = url;
    link.download = `signalhub-pairing-${current.name.replace(/[^\w.-]+/g, "_")}.png`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function status(text) {
    $("status").textContent = text;
  }

  function showError(id, text) {
    $(id).textContent = text || "";
    $(id).hidden = !text;
  }
})();
