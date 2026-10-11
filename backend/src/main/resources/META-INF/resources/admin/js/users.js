// Users: every user in a table with a search and filter chips; a selected row opens the user in the
// pane: their role (changed after a question), devices, producers, subscriptions, recent traffic and
// Revoke. Inviting is a dialog that leads to the user's first device. Everything is a dialog or a
// pane, never a form under the list, and a change is said in a snack bar that carries no Undo.
// Everything the server sends is set as text.

import { ApiError, CLIENTS, PRODUCERS, USERS, call } from "./api.js";
import { el, icon } from "./dom.js";
import { categoryOf, severityOf } from "./event-filters.js";
import { wording } from "./event-pushes.js";
import { ago, plural, shortDate } from "./format.js";
import { createList } from "./list.js";
import { connectDevice } from "./pairing.js";
import { isQuiet } from "./producers.js";
import { setClients } from "./store.js";
import { avatar, button, confirmDialog, iconButton, openDialog, openMenu, ROLES, segmented, snack, tag, textField } from "./ui.js";

const NAME_TAKEN = "That name is taken. Names are not case-sensitive, and a revoked user keeps theirs.";
const NAME_HINT = "Up to 100 characters. Names are not case-sensitive.";

const ROLE_NOTES = {
  BASIC: "A Basic user owns producers and subscribes. Manages no devices.",
  MOD: "A Mod owns producers and subscribes, and manages their own devices.",
  ADMIN: "An Admin is a Mod who also sees every device, manages those of users who are not admins, and invites users. Made and taken away only on this page.",
};

const ROLE_CHOICES = {
  BASIC: "Owns producers and subscribes to them. Manages no devices.",
  MOD: "As Basic, and manages their own devices.",
  ADMIN: "As Mod, and sees every device, manages those of users who are not admins, and invites users.",
};

// What the list read besides the users: every device (for when each user was last active) and every
// producer (for who may subscribe to what). A part that could not be read leaves its columns empty.
let everyUser = [];
let everyProducer = [];
const traffic = { id: null, status: "idle", data: null, error: null, tab: "events" };
let techOpen = false;

const activeDevices = (user) => user.devices.filter((device) => !device.revokedAt);
const hasNoDevice = (user) => !user.revokedAt && activeDevices(user).length === 0;

function lastActive(user) {
  let best = null;
  for (const client of user.clients ?? []) {
    if (client.lastActiveAt && (!best || Date.parse(client.lastActiveAt) > Date.parse(best.lastActiveAt))) best = client;
  }
  return best;
}

const withClass = (node, name) => {
  node.classList.add(name);
  return node;
};

const roleTag = (user) => {
  const node = tag(ROLES[user.role] ?? user.role, user.role === "ADMIN" ? "primary" : user.role === "BASIC" ? "outlined" : "plain");
  node.classList.add("flush");
  return node;
};

/** The producers a user could subscribe to and is not subscribed to: public, or private and allowing them. */
function open(user) {
  const subscribed = new Set(user.subscriptions.map((producer) => producer.id));
  return everyProducer.filter((producer) => !subscribed.has(producer.id) && !producer.disabledAt && (producer.visibility === "PUBLIC" || producer.owner.id === user.id || producer.allowedUsers.some((allowed) => allowed.id === user.id)));
}

/** Whether changing or revoking this user would leave nobody an admin. */
const lastAdmin = (user) => user.role === "ADMIN" && !user.revokedAt && !everyUser.some((other) => other.id !== user.id && other.role === "ADMIN" && !other.revokedAt);

// ---- The list ------------------------------------------------------------------------------------

async function fetchUsers() {
  const [users, clients, producers] = await Promise.allSettled([call("GET", USERS), call("GET", CLIENTS), call("GET", PRODUCERS)]);
  if (users.status === "rejected") throw users.reason;
  const clientItems = clients.status === "fulfilled" ? clients.value.items : [];
  if (clients.status === "fulfilled") setClients(clientItems);
  everyProducer = producers.status === "fulfilled" ? producers.value.items : [];
  const items = users.value.items.map((user) => ({ ...user, clients: clientItems.filter((client) => client.user.id === user.id), producerList: everyProducer.filter((producer) => producer.owner.id === user.id) }));
  // Active users first, by name; revoked ones last.
  items.sort((a, b) => Number(Boolean(a.revokedAt)) - Number(Boolean(b.revokedAt)) || a.name.localeCompare(b.name));
  everyUser = items;
  return items;
}

const list = createList({
  name: "users",
  title: "Users",
  noun: ["user", "users"],
  searchLabel: "Find a user",
  gridClass: "gU",
  columns: [
    { label: "User" },
    { label: "Role" },
    { label: "Devices", className: "c-num" },
    { label: "Producers", className: "c-prod" },
    { label: "Subscribed", className: "c-subs" },
    { label: "Last active", className: "c-last" },
  ],
  fetch: fetchUsers,
  idOf: (user) => user.id,
  searchText: (user) => user.name,
  chips: [
    { key: "all", label: () => "All" },
    { key: "admin", label: () => "Admin", test: (user) => user.role === "ADMIN" && !user.revokedAt },
    { key: "mod", label: () => "Mod", test: (user) => user.role === "MOD" && !user.revokedAt },
    { key: "basic", label: () => "Basic", test: (user) => user.role === "BASIC" && !user.revokedAt },
    { key: "revoked", label: () => "Revoked", test: (user) => Boolean(user.revokedAt) },
    { key: "nodevice", label: (users) => `No device yet · ${users.filter(hasNoDevice).length}`, test: hasNoDevice },
  ],
  countText: (users, shown, filtered) => {
    const active = users.filter((user) => !user.revokedAt).length;
    return filtered ? `${shown} of ${users.length} users` : `${plural(users.length, "user")} · ${active} active`;
  },
  primary: { label: "Invite a user", glyph: "person_add", onClick: (ctx) => invite(ctx), ariaLabel: "Invite a user" },
  emptyAll: {
    glyph: "group",
    title: "No users yet",
    body: "Invite the first user, then connect a device for them with a pairing code. Their app receives the events of the producers they subscribe to.",
  },
  prompt: { glyph: "group", title: "Select a user", text: "Their role, devices, producers, subscriptions and traffic show here." },
  rowParts: (user) => {
    const devices = activeDevices(user).length;
    const last = lastActive(user);
    const when = last ? ago(last.lastActiveAt) : "—";
    const revoked = Boolean(user.revokedAt);
    const line2 = revoked ? `Revoked ${shortDate(user.revokedAt)}` : hasNoDevice(user) ? "No device yet" : `${plural(devices, "device")} · ${plural(user.producers.length, "producer")} · ${when}`;
    return {
      name: [avatar(user.name, { small: true }), el("span", { class: "nm", text: user.name }), revoked ? tag("Revoked", "outlined") : hasNoDevice(user) ? withClass(tag("No device yet", "outlined"), "no-phone") : null, withClass(roleTag(user), "role-inline")],
      cells: [roleTag(user), String(devices), String(user.producers.length), String(user.subscriptions.length), revoked ? shortDate(user.revokedAt) : when],
      label: `${user.name}, ${ROLES[user.role] ?? user.role}${revoked ? ", revoked" : ""}${hasNoDevice(user) ? ", no device yet" : ""}, ${plural(devices, "device")}, ${plural(user.producers.length, "producer")}, ${plural(user.subscriptions.length, "subscription")}`,
      line2,
      revoked,
    };
  },
  renderPane: (user, ctx) => renderPane(user, ctx),
});

export const usersSection = list;

// ---- The pane ------------------------------------------------------------------------------------

function renderPane(user, ctx) {
  // Traffic belongs to the user shown: reading it starts when another user opens.
  if (traffic.id !== user.id) {
    traffic.id = user.id;
    traffic.status = "idle";
    traffic.data = null;
    traffic.tab = "events";
  }
  if (traffic.status === "idle") loadTraffic(user, ctx);

  const revoked = Boolean(user.revokedAt);
  const body = [];
  if (revoked) {
    body.push(banner("block", `Revoked ${shortDate(user.revokedAt)}. Their devices are revoked and their producers disabled. Their events stay.`));
  }
  const last = lastActive(user);
  body.push(
    el(
      "div",
      { class: "kv" },
      el("b", { text: "Created" }),
      el("span", { text: `${shortDate(user.createdAt)}${hasNoDevice(user) ? ", invited" : ""}` }),
      el("b", { text: "Last active" }),
      el("span", { text: last ? `${ago(last.lastActiveAt)}, on ${last.name}` : "—" }),
    ),
  );
  if (!revoked) {
    body.push(el("div", { class: "lab", text: "Role" }));
    body.push(
      segmented({
        label: "Role",
        value: user.role,
        options: Object.entries(ROLES).map(([value, label]) => ({ value, label, glyph: value === user.role ? "check" : undefined })),
        onChange: (value) => changeRole(user, value, ctx),
      }),
    );
    body.push(el("div", { class: "rnote", text: ROLE_NOTES[user.role] }));
  }
  body.push(...devicesSection(user, ctx));
  if (user.producerList.length > 0) body.push(...producersSection(user));
  body.push(...subscriptionsSection(user, ctx));
  if (traffic.status !== "ready" || traffic.data.events.length + traffic.data.deliveries.length > 0) body.push(...trafficSection(user, ctx));
  if (!revoked) {
    body.push(
      el(
        "div",
        { class: "act" },
        button(`Revoke ${user.name}`, { kind: "outlined", glyph: "block", className: "er", ariaLabel: `Revoke ${user.name}`, onClick: () => revoke(user, ctx) }),
        el("span", { class: "t2 small-t", text: `Revokes their ${plural(activeDevices(user).length, "device")} and disables their ${plural(user.producerList.filter((producer) => !producer.disabledAt).length, "producer")}, for good. Their events stay.` }),
      ),
    );
  }
  body.push(technical(user));
  return {
    title: user.name,
    titleExtra: el("div", { class: "tagrow" }, roleTag(user), revoked ? tag("Revoked", "outlined") : null),
    actions: revoked ? [] : [iconButton("edit", `Rename ${user.name}`, () => rename(user, ctx))],
    body,
  };
}

function banner(glyph, text) {
  return el("div", { class: "bn neu note" }, icon(glyph, "c-var"), el("span", { class: "tx", text }));
}

function devicesSection(user, ctx) {
  const active = activeDevices(user);
  const revokedCount = user.devices.length - active.length;
  const head = el("div", { class: "lab" }, "Devices", el("span", { class: "cnt", text: active.length ? `${active.length} active` : "none" }), el("span", { class: "sp" }), user.revokedAt || active.length === 0 ? null : button("Connect", { kind: "outlined", glyph: "add", ariaLabel: `Connect a device for ${user.name}`, onClick: () => connect(user, ctx) }));
  const parts = [head];
  if (active.length === 0 && !user.revokedAt) {
    parts.push(
      el(
        "div",
        { class: "okbox first" },
        icon("devices", "c-var"),
        el("div", {}, el("b", { text: `${user.name} has no device yet.` }), el("br"), `${user.name} cannot receive anything until one is connected.`, el("div", { class: "okbox-act" }, button("Connect their first device", { kind: "tonal", glyph: "add", onClick: () => connect(user, ctx) }))),
      ),
    );
  }
  for (const device of active) {
    const client = (user.clients ?? []).find((candidate) => candidate.id === device.id);
    const browser = client?.kind === "BROWSER";
    const failed = client && !browser && client.pushTarget && client.pushStatus?.lastFailure && (!client.pushStatus.lastSuccess || Date.parse(client.pushStatus.lastFailure.at) > Date.parse(client.pushStatus.lastSuccess.at));
    let state = "push working";
    if (browser || (client && !client.pushTarget)) state = "no push address";
    else if (failed) state = client.pushStatus.pendingRetries > 0 ? "last push failed, retrying" : "last push failed";
    const when = client?.lastActiveAt ? `${ago(client.lastActiveAt)} · ` : "";
    parts.push(
      el(
        "a",
        { class: "rrow link", href: `#devices/${device.id}` },
        icon(browser ? "computer" : "smartphone", failed ? "c-error" : "c-var"),
        el("div", { class: "tx" }, el("span", { class: "nm2" }, device.name, client?.admin && !browser ? tag("Admin device", "primary") : null, browser ? tag("Browser") : null), el("span", { class: `t2${failed ? " c-error" : ""}`, text: `${when}${state}` })),
        icon("chevron_right", "c-var"),
      ),
    );
  }
  if (revokedCount > 0) parts.push(el("div", { class: "t2 sub-note", text: `${plural(revokedCount, "revoked device")} ${revokedCount === 1 ? "is" : "are"} kept out of this list.` }));
  return parts;
}

function producersSection(user) {
  return [
    el("div", { class: "lab compact" }, "Producers", el("span", { class: "cnt", text: `${user.producerList.length} owned` }), el("span", { class: "sp" }), el("a", { class: "small-link", href: `#producers?owner=${user.id}`, text: "See in Producers" })),
    el("div", { class: "pchips" }, user.producerList.map((producer) => el("a", { class: "chip-s", href: `#producers/${producer.id}` }, producer.name, producer.disabledAt ? tag("Disabled", "outlined") : isQuiet(producer) ? tag("Quiet") : null))),
  ];
}

function subscriptionsSection(user, ctx) {
  const chips = el("div", { class: "pchips" });
  for (const producer of user.subscriptions) {
    chips.append(
      el(
        "span",
        { class: "pchip" },
        avatar(producer.name, { tint: true }),
        el("span", { text: producer.name }),
        user.revokedAt ? null : el("button", { type: "button", class: "x", "aria-label": `Unsubscribe ${user.name} from ${producer.name}`, on: { click: () => unsubscribe(user, producer, ctx) } }, icon("close", "ms18")),
      ),
    );
  }
  if (!user.revokedAt) {
    const add = el("button", { type: "button", class: "pchip add", "aria-haspopup": "menu", "aria-label": `Subscribe ${user.name} to a producer`, on: { click: () => subscribeMenu(user, add, ctx) } }, icon("add", "ms18"), el("span", { text: "Subscribe" }));
    chips.append(add);
  }
  return [el("div", { class: "lab compact" }, "Subscriptions", el("span", { class: "cnt", text: String(user.subscriptions.length) })), chips];
}

function technical(user) {
  const wrap = el("div", { class: "tfold" });
  const draw = () => {
    wrap.replaceChildren(
      el("button", { type: "button", class: "fold", "aria-expanded": String(techOpen), on: { click: () => { techOpen = !techOpen; draw(); wrap.querySelector(".fold").focus(); } } }, icon(techOpen ? "expand_less" : "expand_more"), el("span", { text: "Technical details" })),
      techOpen ? el("div", { class: "kv fold-body" }, el("b", { text: "ID" }), el("span", { class: "mono small", text: user.id })) : null,
    );
  };
  draw();
  return wrap;
}

// ---- Recent traffic ------------------------------------------------------------------------------

async function loadTraffic(user, ctx) {
  traffic.status = "loading";
  traffic.error = null;
  try {
    const data = await call("GET", `${USERS}/${user.id}/traffic`);
    if (traffic.id !== user.id) return;
    traffic.data = data;
    traffic.status = "ready";
  } catch (error) {
    if (error.name === "SessionEnded" || traffic.id !== user.id) return;
    traffic.status = "failed";
    traffic.error = error;
  }
  ctx.paintPane();
}

function trafficSection(user, ctx) {
  const head = el("div", { class: "lab compact" }, "Recent traffic", el("span", { class: "sp" }), el("a", { class: "btn-x", href: `#events?user=${user.id}`, "aria-label": `Open ${user.name} in Events` }, icon("open_in_new"), "Open in Events"));
  if (traffic.status === "failed") {
    return [head, el("div", { class: "bn err", role: "alert" }, icon("error"), el("span", { class: "tx", text: `Could not load ${user.name}'s traffic.` }), button("Try again", { onClick: () => { traffic.status = "idle"; ctx.paintPane(); } }))];
  }
  if (traffic.status !== "ready") return [head, el("div", { class: "skeletons", "aria-hidden": "true" }, [0, 1].map((n) => el("div", { class: "sk2 pane-sk" }, el("span", { class: "sk", data: { w: n } }))))];
  const { events, deliveries } = traffic.data;
  const tabs = el("div", { class: "tabs2", role: "tablist", "aria-label": "Recent traffic" });
  for (const [key, label, count] of [["events", "Events", events.length], ["pushes", "Pushes", deliveries.length]]) {
    const on = traffic.tab === key;
    tabs.append(el("button", { type: "button", role: "tab", "aria-selected": String(on), class: on ? "on" : null, tabindex: on ? "0" : "-1", on: { click: () => { traffic.tab = key; ctx.paintPane(); } } }, `${label} · ${count === 20 ? "newest 20" : count}`));
  }
  const rows = [];
  if (traffic.tab === "events") {
    for (const event of events) {
      const severity = severityOf(event.severity);
      rows.push(
        el(
          "a",
          { class: "rrow link", href: `#events/${event.id}` },
          icon(categoryOf(event.category)?.glyph ?? "info", severity?.tone === "high" || severity?.tone === "crit" ? "c-error" : "c-primary"),
          el("div", { class: "tx" }, el("span", { class: "nm2", text: event.title }), el("span", { class: "t2", text: `${event.producer.name} · ${ago(event.createdAt)}` })),
          icon("chevron_right", "c-var"),
        ),
      );
    }
    rows.push(el("div", { class: "t2 sub-note", text: `The newest ${events.length === 20 ? "20 events" : plural(events.length, "event")} of ${user.name}'s producers and subscriptions. Pushes shows what happened to each device.` }));
  } else {
    for (const record of deliveries) {
      const words = wording(record, {});
      const text = words.key === "sent" ? "delivered" : words.title.charAt(0).toLowerCase() + words.title.slice(1);
      rows.push(
        el(
          "a",
          { class: "rrow link", href: `#events/${record.eventId}` },
          icon(words.glyph, words.tone === "bad" ? "c-error" : words.tone === "ok" ? "c-primary" : "c-var"),
          el("div", { class: "tx" }, el("span", { class: "nm2", text: `${record.clientName} · ${text}` }), el("span", { class: "t2", text: `${record.eventTitle} · ${ago(record.at)}` })),
          icon("chevron_right", "c-var"),
        ),
      );
    }
  }
  return [head, tabs, ...rows];
}

// ---- Changes -------------------------------------------------------------------------------------

/** A failed change is said in the pane, with what did not happen. */
async function change(ctx, { action, done, failure }) {
  try {
    await action();
  } catch (error) {
    if (error.name === "SessionEnded") return false;
    ctx.failed(`${failure} ${error.message} Nothing changed.`);
    return false;
  }
  snack(done);
  await ctx.reload();
  return true;
}

const warn = (glyph, text, danger = false) => el("div", { class: `warn${danger ? " danger" : ""}` }, icon(glyph), el("div", { text }));

function changeRole(user, role, ctx) {
  if (role === user.role) return;
  const name = user.name;
  const from = user.role;
  let title;
  let message;
  let action;
  let extra = null;
  let destructive = false;
  if (role === "ADMIN") {
    title = `Make ${name} an Admin?`;
    message = `${name} will see every device, manage the devices of users who are not admins, and invite users. Their devices become admin devices.`;
    action = "Make Admin";
    extra = warn("admin_panel_settings", "Only you can take it away again, on this page.", true);
    destructive = true;
  } else if (from === "ADMIN") {
    title = `Take Admin away from ${name}?`;
    message = role === "MOD" ? `${name} becomes a Mod. Their devices stop being admin devices at once and can no longer see or manage other people's.` : `${name} becomes a Basic user and loses the ability to manage their own devices. Their devices stop being admin devices at once and can no longer see or manage other people's.`;
    action = role === "MOD" ? "Make Mod" : "Make Basic";
    if (lastAdmin(user)) extra = warn("info", "Nobody will be an admin in the app. The admin token still works here.");
  } else if (role === "MOD") {
    title = `Make ${name} a Mod?`;
    message = `${name} will manage their own devices: rename, revoke, and connect new ones. Their devices and producers stay as they are.`;
    action = "Make Mod";
  } else {
    title = `Make ${name} a Basic user?`;
    message = `${name} will no longer connect, rename or revoke devices. The ones they have keep working.`;
    action = "Make Basic";
  }
  const word = ROLES[role];
  return confirmDialog({
    title,
    message,
    action,
    destructive,
    extra,
    run: async () => {
      await call("PATCH", `${USERS}/${user.id}`, { role });
      snack(`${name} is now ${role === "ADMIN" ? "an" : "a"} ${word}`);
      await ctx.reload();
    },
  });
}

function unsubscribe(user, producer, ctx) {
  return confirmDialog({
    title: `Unsubscribe ${user.name} from ${producer.name}?`,
    message: `${user.name} stops receiving its events in their app, and the events it already sent disappear from their inbox too. They come back if ${user.name} subscribes again, while the producer is public or allows them.`,
    action: "Unsubscribe",
    ariaLabel: `Unsubscribe ${user.name} from ${producer.name}`,
    run: async () => {
      await call("DELETE", `${USERS}/${user.id}/subscriptions/${producer.id}`);
      snack(`${user.name} unsubscribed from ${producer.name}`);
      await ctx.reload();
    },
  });
}

function subscribeMenu(user, anchor, ctx) {
  const choices = open(user);
  if (choices.length === 0) {
    openMenu(anchor, { placement: "below-start", label: `Subscribe ${user.name} to`, items: [{ info: true, glyph: "info", label: `Nothing is open to ${user.name} that they are not subscribed to.` }] });
    return;
  }
  openMenu(anchor, {
    placement: "below-start",
    label: `Subscribe ${user.name} to`,
    header: { title: `Subscribe ${user.name} to`, subtitle: `Producers open to ${user.name} and not yet subscribed` },
    items: choices.map((producer) => ({
      glyph: "sensors",
      label: producer.name,
      onSelect: () =>
        change(ctx, {
          action: () => call("PUT", `${USERS}/${user.id}/subscriptions/${producer.id}`),
          done: `${user.name} subscribed to ${producer.name}`,
          failure: `Could not subscribe ${user.name} to ${producer.name}.`,
        }),
    })),
  });
}

function revoke(user, ctx) {
  const devices = activeDevices(user).length;
  const producers = user.producerList.filter((producer) => !producer.disabledAt).length;
  const extra = el("div", {}, warn("warning", `This cannot be undone. ${user.name}'s name stays taken: names are not case-sensitive and a revoked user keeps theirs, so ${user.name} cannot be invited again under it.`, true), lastAdmin(user) ? warn("info", "Nobody will be an admin in the app. The admin token still works here.") : null);
  return confirmDialog({
    title: `Revoke ${user.name}?`,
    message: `Their ${plural(devices, "device")} ${devices === 1 ? "is" : "are"} revoked and their ${plural(producers, "producer")} disabled, at once and for good, so the people subscribed to ${producers === 1 ? "that producer stop" : "those producers stop"} receiving ${producers === 1 ? "it" : "them"}. Their events stay.`,
    action: `Revoke ${user.name}`,
    destructive: true,
    extra,
    busyLabel: "Revoking…",
    retryLabel: "Try again",
    run: async () => {
      await call("POST", `${USERS}/${user.id}/revoke`);
      snack(`${user.name} revoked`);
      await ctx.reload();
    },
  });
}

function connect(user, ctx) {
  connectDevice({ user, onChange: () => ctx.reload() });
}

function rename(user, ctx) {
  const field = textField({ label: "Name", value: user.name, hint: "Up to 100 characters. Their devices and producers keep their own names.", maxlength: 120 });
  let confirm = null;
  const dialog = openDialog({
    title: "Rename the user",
    content: field.node,
    focusNode: field.input,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Rename",
        value: true,
        className: "confirm",
        disabled: true,
        onError: (error) => {
          if (error.kind === "taken") confirm.disabled = true;
        },
        run: async () => {
          const name = field.input.value.trim();
          try {
            await call("PATCH", `${USERS}/${user.id}`, { name });
          } catch (error) {
            if (error instanceof ApiError && error.status === 409) {
              field.setError(NAME_TAKEN);
              throw new ApiError("", "taken", 409);
            }
            throw error;
          }
          snack(`Renamed to ${name}`);
          await ctx.reload();
        },
      },
    ],
  });
  confirm = dialog.actions[1].node;
  const check = () => {
    const value = field.input.value.trim();
    field.setError(value.length > 100 ? "Use 100 characters or fewer." : "");
    confirm.disabled = value === "" || value.length > 100 || value === user.name;
  };
  field.input.addEventListener("input", check);
  field.input.select();
}

// ---- Inviting ------------------------------------------------------------------------------------

function invite(ctx) {
  let role = "BASIC";
  const name = textField({ label: "Name", hint: NAME_HINT, maxlength: 120 });
  const choices = el("div", { class: "choices", role: "radiogroup", "aria-label": "Role" });
  const note = el("div", {});
  const drawRoles = () => {
    choices.replaceChildren(
      ...Object.keys(ROLES).map((value) =>
        el(
          "button",
          { type: "button", role: "radio", "aria-checked": String(role === value), class: `choice${role === value ? " on" : ""}`, on: { click: () => { role = value; drawRoles(); choices.querySelector("[aria-checked='true']").focus(); } } },
          el("span", { class: "rb" }),
          el("span", { class: "tx" }, el("span", { class: "t1", text: ROLES[value] }), role === value ? el("span", { class: "t2", text: ROLE_CHOICES[value] }) : null),
        ),
      ),
    );
    note.replaceChildren(role === "ADMIN" ? warn("admin_panel_settings", "An admin has wide powers. Their devices become admin devices. Admin is given only here, never by another admin.") : "");
  };
  drawRoles();
  choices.addEventListener("keydown", (event) => {
    if (!["ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight"].includes(event.key)) return;
    const keys = Object.keys(ROLES);
    const step = event.key === "ArrowDown" || event.key === "ArrowRight" ? 1 : -1;
    role = keys[(keys.indexOf(role) + step + keys.length) % keys.length];
    event.preventDefault();
    drawRoles();
    choices.querySelector("[aria-checked='true']").focus();
  });
  let send = null;
  const dialog = openDialog({
    title: "Invite a user",
    content: el("div", {}, el("p", { class: "p small-p", text: "Inviting creates the user. The next step connects their first device." }), name.node, el("div", { class: "lab compact", text: "Role" }), choices, note),
    variant: "full",
    focusNode: name.input,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Invite user",
        value: true,
        className: "confirm",
        disabled: true,
        keepOpen: true,
        busyLabel: "Inviting…",
        retryLabel: "Try again",
        onError: (error) => {
          if (error.kind === "taken") {
            send.disabled = true;
            send.querySelector(".btn-label").textContent = "Invite user";
          }
        },
        run: async (controller) => {
          const value = name.input.value.trim();
          let made;
          try {
            made = await call("POST", USERS, { name: value, role });
          } catch (error) {
            if (error instanceof ApiError && error.status === 409) {
              name.setError(NAME_TAKEN);
              throw new ApiError("", "taken", 409);
            }
            throw new ApiError(`Could not invite ${value}: ${error.message} Nobody was created.`, error.kind, error.status);
          }
          controller.close(true);
          await ctx.reload();
          connectDevice({ user: made, invited: true, onChange: () => ctx.reload() });
        },
      },
    ],
  });
  send = dialog.actions[1].node;
  const check = (blurred) => {
    const value = name.input.value.trim();
    name.setError(value.length > 100 ? "Use 100 characters or fewer." : !value && blurred ? "Give the user a name." : "");
    send.disabled = value === "" || value.length > 100;
  };
  name.input.addEventListener("input", () => check(false));
  name.input.addEventListener("blur", () => check(true));
}
