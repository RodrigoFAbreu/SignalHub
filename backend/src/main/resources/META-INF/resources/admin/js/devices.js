// Devices: every device and every signed-in browser is one row: its name with tags (Admin device on a
// device only, Browser, Revoked), its user, when it was last active and how its push is going in
// plain words. Search and filters are done in the page from the one list the management API returns;
// the pane says whether the device is fine and what can be done to it, with its codes and ids only
// in Technical details. Rename, Revoke, Delete and Connect a device are dialogs. Changes made here
// send no push to any device. Everything the server sends is set as text.

import { ADMIN_EVENTS, CLIENTS, EVENTS, PAIRINGS, call } from "./api.js";
import { el, icon } from "./dom.js";
import { ago, dateTime, shortDate } from "./format.js";
import { createList } from "./list.js";
import { connectDevice } from "./pairing.js";
import { lastPushFailed } from "./model.js";
import { ID } from "./router.js";
import { setClients } from "./store.js";
import { avatar, button, confirmDialog, iconButton, openDialog, ROLES, snack, tag, textField } from "./ui.js";

const TRIES = 5;
let techOpen = false;
// The open pairing codes, read with the list.
let openCodes = [];
// An event's title by id: null once it is known to be gone.
const eventTitles = new Map();

// ---- What a device is, in the words of the page --------------------------------------------

const isBrowser = (client) => client.kind === "BROWSER";

/** The push column: an icon, words, and whether it is a problem that needs a look. */
export function pushWords(client) {
  if (client.revokedAt) return { glyph: "block", text: `Revoked ${shortDate(client.revokedAt)}`, tone: "no" };
  if (isBrowser(client)) return { glyph: "notifications_off", text: "No push address", tone: "no" };
  const { lastSuccess, lastFailure, pendingRetries } = client.pushStatus;
  const failed = lastPushFailed(client);
  if (!client.pushTarget) {
    return failed && lastFailure.result === "INVALID_TARGET" ? { glyph: "error", text: "Push address rejected", tone: "bad" } : { glyph: "notifications_off", text: "No push address", tone: "no" };
  }
  if (failed) {
    if (lastFailure.result === "INVALID_TARGET") return { glyph: "error", text: "Push address rejected", tone: "bad" };
    if (lastFailure.result === "TRANSIENT_FAILURE") {
      return pendingRetries > 0 ? { glyph: "error", text: "Last push failed, retrying", tone: "bad" } : { glyph: "error", text: `Gave up after ${TRIES} tries`, tone: "bad" };
    }
    return { glyph: "error", text: "Last push failed", tone: "bad" };
  }
  void lastSuccess;
  return { glyph: "check_circle", text: "Working", tone: "ok" };
}

const hasProblem = (client) => pushWords(client).tone === "bad";

function userLine(client) {
  return `${client.user.name} · ${ROLES[client.user.role] ?? client.user.role}`;
}

function lastActive(client) {
  if (client.revokedAt) return shortDate(client.lastActiveAt ?? client.revokedAt);
  return client.lastActiveAt ? ago(client.lastActiveAt) : "Never";
}

/** Active devices first, by last activity; revoked ones last. */
export function ordered(clients) {
  return [...clients].sort(
    (a, b) =>
      (a.revokedAt ? 1 : 0) - (b.revokedAt ? 1 : 0) ||
      (Date.parse(b.revokedAt ?? b.lastActiveAt ?? b.createdAt) || 0) - (Date.parse(a.revokedAt ?? a.lastActiveAt ?? a.createdAt) || 0),
  );
}

function tags(client) {
  return [client.admin && !isBrowser(client) ? tag("Admin device", "primary") : null, isBrowser(client) ? tag("Browser") : null, client.revokedAt ? tag("Revoked", "outlined") : null];
}

// ---- The list ------------------------------------------------------------------------------

const list = createList({
  name: "devices",
  title: "Devices",
  noun: ["device", "devices"],
  searchLabel: "Find a device",
  gridClass: "gD",
  columns: [{ label: "Device" }, { label: "User", className: "c-user" }, { label: "Last active", className: "c-last" }, { label: "Push", className: "c-push" }],
  fetch: async () => {
    const [clients, codes] = await Promise.all([call("GET", CLIENTS), call("GET", PAIRINGS).catch((error) => (error.name === "SessionEnded" ? Promise.reject(error) : { items: [] }))]);
    openCodes = codes.items;
    return ordered(clients.items);
  },
  onLoaded: (items) => setClients(items),
  idOf: (client) => client.id,
  searchText: (client) => `${client.name} ${client.user.name}`,
  chips: [
    { key: "all", label: () => "All" },
    { key: "active", label: () => "Active", test: (client) => !client.revokedAt },
    { key: "revoked", label: () => "Revoked", test: (client) => Boolean(client.revokedAt) },
    { key: "problems", label: (items) => {
        const count = items.filter(hasProblem).length;
        return count > 0 ? `Push problems · ${count}` : "Push problems";
      }, test: hasProblem },
  ],
  menus: [
    {
      key: "kind",
      prefix: "Kind",
      anyLabel: null,
      options: () => [
        { value: "DEVICE", text: "Devices" },
        { value: "BROWSER", text: "Browsers" },
      ],
      test: (client, value) => client.kind === value,
    },
    {
      key: "user",
      prefix: "User",
      anyLabel: null,
      options: (clients) => {
        const users = new Map();
        for (const client of clients) users.set(client.user.id, client.user.name);
        return [...users].map(([value, text]) => ({ value, text })).sort((a, b) => a.text.localeCompare(b.text));
      },
      test: (client, value) => client.user.id === value,
    },
  ],
  countText: (items, shown, filtered) => {
    const active = items.filter((client) => !client.revokedAt).length;
    const base = `${items.length} ${items.length === 1 ? "device" : "devices"} · ${active} active`;
    return filtered ? `${shown} of ${base}` : base;
  },
  primary: {
    label: "Connect a device",
    glyph: "add",
    ariaLabel: "Connect a device",
    emptyAction: true,
    onClick: (ctx) => connectDevice({ onChange: () => ctx.reload() }),
  },
  emptyAll: {
    glyph: "devices",
    title: "No device yet",
    body: "A device is a phone running the SignalHub app, or a signed-in browser. Connect the first one with a pairing code; it receives its user's events.",
  },
  prompt: { glyph: "devices", title: "Select a device", text: "Its user, how its push is going and what you can do to it show here." },
  extra: (ctx) => (openCodes.length ? codesBlock(ctx) : null),
  rowParts: (client) => {
    const words = pushWords(client);
    const kind = isBrowser(client) ? "browser" : "device";
    return {
      name: [el("span", { class: "nm", text: client.name }), ...tags(client)],
      cells: [
        el("span", { class: "own" }, avatar(client.user.name, { small: true }), el("span", { text: client.user.name })),
        lastActive(client),
        el("span", { class: `ps ${words.tone}` }, icon(words.glyph), el("span", { class: "pt", text: words.text })),
      ],
      label: `${client.name}, ${kind}${client.revokedAt ? ", revoked" : ""}, ${client.user.name}, last active ${lastActive(client)}, ${words.text}`,
      line2: [client.user.name, lastActive(client), words.text].join(" · "),
      revoked: Boolean(client.revokedAt),
    };
  },
  renderPane: (client, ctx) => renderPane(client, ctx),
});

export const devicesSection = list;

// ---- Pairing codes that are open, and can be cancelled -------------------------------------

function codesBlock(ctx) {
  const block = el("div", { class: "codes", role: "region", "aria-label": "Open pairing codes" });
  block.append(el("div", { class: "lab", role: "heading", "aria-level": "2" }, "Open pairing codes", el("span", { class: "cnt", text: String(openCodes.length) })));
  for (const code of openCodes) {
    const minutes = Math.max(0, Math.ceil((Date.parse(code.expiresAt) - Date.now()) / 60000));
    block.append(
      el(
        "div",
        { class: "krow" },
        icon("qr_code_2", "c-var"),
        el("div", { class: "tx" }, el("span", { class: "t1", text: code.name }), el("span", { class: "t2", text: `For ${code.user.name} · expires in ${minutes} ${minutes === 1 ? "minute" : "minutes"} · unused` })),
        button("Cancel this code", {
          kind: "text-error",
          ariaLabel: `Cancel the pairing code for ${code.name}`,
          onClick: () =>
            confirmDialog({
              title: "Cancel this code?",
              message: `The code for “${code.name}” can never be used then. The code itself is not shown again either way.`,
              action: "Cancel this code",
              cancel: "Keep it",
              destructive: true,
              run: async () => {
                await call("DELETE", `${PAIRINGS}/${code.id}`);
                snack("Pairing code cancelled.");
                ctx.reload();
              },
            }),
        }),
      ),
    );
  }
  return block;
}

// ---- The pane ------------------------------------------------------------------------------

/** What happened to an event, looked up once: its title, or null when it was deleted. */
function eventTitle(id) {
  if (!ID.test(id)) return Promise.resolve(null);
  if (eventTitles.has(id)) return Promise.resolve(eventTitles.get(id));
  return call("GET", `${EVENTS}/${id}`).then(
    (event) => {
      eventTitles.set(id, event.title);
      return event.title;
    },
    (error) => {
      if (error.name === "SessionEnded") return null;
      // Gone, or not readable now: the line says so rather than guess.
      if (error.status === 404) eventTitles.set(id, null);
      return null;
    },
  );
}

function eventLine(id, ctxPaint) {
  const out = el("span", { class: "t2" }, "Looking up the event…");
  eventTitle(id).then((title) => {
    out.replaceChildren();
    if (title === null) {
      out.append("That event was deleted");
      return;
    }
    out.append(title, " · ", el("a", { href: `#events/${id}`, text: "Open event" }));
  });
  void ctxPaint;
  return out;
}

function renderPane(client, ctx) {
  const body = [];
  const browser = isBrowser(client);
  if (client.revokedAt) {
    body.push(el("div", { class: "bn neu note" }, icon("block", "c-var"), el("div", { class: "tx", text: `${browser ? "Signed out" : "Revoked"} on ${shortDate(client.revokedAt)}. It stopped working at once and gets no pushes.` })));
  }
  const facts = [el("b", { text: "User" }), el("span", { text: userLine(client) })];
  facts.push(el("b", { text: browser ? "Signed in" : "Created" }), el("span", { text: shortDate(client.createdAt) }));
  facts.push(el("b", { text: "Last active" }), el("span", { text: client.lastActiveAt ? (client.revokedAt ? shortDate(client.lastActiveAt) : ago(client.lastActiveAt)) : "Never" }));
  if (client.revokedAt) facts.push(el("b", { text: "Revoked" }), el("span", { text: shortDate(client.revokedAt) }));
  else if (browser && client.expiresAt) facts.push(el("b", { text: "Signs out" }), el("span", { text: `${shortDate(client.expiresAt)}, by itself` }));
  body.push(el("div", { class: "kv pad" }, ...facts));
  if (client.admin && !browser && !client.revokedAt) {
    body.push(el("div", { class: "t2 pad-note", text: `An admin device because ${client.user.name} is an admin: it can connect and revoke other devices and invite users.` }));
  }

  if (browser && !client.revokedAt) {
    body.push(
      el("div", { class: "rrow" }, icon("notifications_off", "c-var"), el("div", { class: "tx" }, el("span", { class: "nm2", text: "No push for browsers" }), el("span", { class: "t2", text: "A browser shows the inbox while its page is open; pushes go to the user's phones." }))),
    );
  } else if (!client.revokedAt) {
    body.push(...pushSection(client, ctx));
  }

  if (client.revokedAt) {
    body.push(
      el(
        "div",
        { class: "act" },
        button("Delete", { kind: "outlined", glyph: "delete", className: "er", ariaLabel: `Delete ${client.name}`, onClick: () => remove(client, ctx) }),
        el("span", { class: "t2 small-t", text: "Removes it from this list for good. Events stay in the user's inbox, with their read state." }),
      ),
    );
  } else {
    body.push(
      el(
        "div",
        { class: "act" },
        button("Rename", { kind: "outlined", glyph: "edit", ariaLabel: `Rename ${client.name}`, onClick: () => rename(client, ctx) }),
        button("Revoke", { kind: "outlined", glyph: "block", className: "er", ariaLabel: `Revoke ${client.name}`, onClick: () => revoke(client, ctx) }),
        el("span", { class: "t2 small-t", text: browser ? "Signs this browser out at once." : "Revoking stops it at once, for good." }),
      ),
    );
  }
  body.push(technical(client));
  return {
    title: client.name,
    titleExtra: client.admin && !browser || browser || client.revokedAt ? el("div", { class: "tagrow" }, ...tags(client).filter(Boolean).map((node) => { node.classList.add("flush"); return node; })) : null,
    actions: client.revokedAt ? [] : [iconButton("edit", `Rename ${client.name}`, () => rename(client, ctx))],
    body,
  };
}

function pushSection(client, ctx) {
  const words = pushWords(client);
  const { lastSuccess, lastFailure, pendingRetries } = client.pushStatus;
  const rows = [];
  rows.push(el("div", { class: "lab" }, "Push", el("span", { class: "sp" }), el("span", { class: `ps ${words.tone} plain` }, icon(words.glyph), words.text)));
  if (lastPushFailed(client)) {
    const gaveUp = lastFailure.result === "TRANSIENT_FAILURE" && pendingRetries === 0;
    const why = {
      TRANSIENT_FAILURE: gaveUp ? `Gave up after ${TRIES} tries.` : `The push service did not accept it this time. SignalHub tries again by itself, up to ${TRIES} tries in all.`,
      INVALID_TARGET: "Its push address was refused for good and removed.",
      PERMANENT_FAILURE: "The push service refused it.",
      UNSUPPORTED_PROVIDER: "This device's push service is not supported by this server.",
    }[lastFailure.result] ?? "The push failed.";
    const detail = el("span", { class: "t2" }, why);
    // A given-up push says how many tries it had, from the delivery records' final marker.
    if (lastFailure.result === "TRANSIENT_FAILURE" && ID.test(lastFailure.eventId)) {
      call("GET", `${ADMIN_EVENTS}/${lastFailure.eventId}/deliveries`).then(
        (answer) => {
          const mine = answer.items.filter((record) => record.clientId === client.id);
          const last = mine.at(-1);
          if (last?.final && last.outcome === "TRANSIENT_FAILURE") detail.textContent = `Gave up after ${last.attempt} ${last.attempt === 1 ? "try" : "tries"}.`;
        },
        () => {},
      );
    }
    rows.push(
      el("div", { class: "rrow" }, icon("error", "c-error"), el("div", { class: "tx" }, el("span", { class: "nm2", text: `Last push failed · ${ago(lastFailure.at)}` }), eventLine(lastFailure.eventId), detail)),
    );
  }
  if (pendingRetries > 0) {
    rows.push(el("div", { class: "rrow" }, icon("schedule"), el("div", { class: "tx" }, el("span", { class: "nm2", text: `${pendingRetries} ${pendingRetries === 1 ? "push" : "pushes"} waiting for a retry` }), el("span", { class: "t2", text: "Nothing to do; they leave when the service answers." }))));
  }
  if (lastSuccess) {
    rows.push(el("div", { class: "rrow" }, icon("check_circle", "c-primary"), el("div", { class: "tx" }, el("span", { class: "nm2", text: `Last push accepted · ${ago(lastSuccess.at)}` }), eventLine(lastSuccess.eventId))));
  }
  if (!lastFailure) {
    rows.push(el("div", { class: "rrow" }, icon("check"), el("div", { class: "tx" }, el("span", { class: "nm2", text: "No push has failed" }), el("span", { class: "t2", text: pendingRetries > 0 ? "" : "Nothing is waiting for a retry." }))));
  }
  rows.push(
    client.pushTarget
      ? el("div", { class: "rrow" }, icon("notifications_active", "c-primary"), el("div", { class: "tx" }, el("span", { class: "nm2", text: "Push address" }), el("span", { class: "t2", text: `${providerName(client.pushTarget.provider)}, set ${shortDate(client.pushTarget.updatedAt)}` })))
      : el("div", { class: "rrow" }, icon("notifications_off", "c-var"), el("div", { class: "tx" }, el("span", { class: "nm2", text: "No push address" }), el("span", { class: "t2", text: "The app has not registered for pushes yet." }))),
  );
  void ctx;
  return rows;
}

function providerName(provider) {
  return provider === "fcm" ? "Firebase Cloud Messaging" : provider;
}

function technical(client) {
  const wrap = el("div", { class: "tfold" });
  const draw = () => {
    const toggle = el(
      "button",
      { type: "button", class: "fold", "aria-expanded": String(techOpen), on: { click: () => { techOpen = !techOpen; draw(); wrap.querySelector(".fold").focus(); } } },
      icon(techOpen ? "expand_less" : "expand_more"),
      el("span", { text: "Technical details" }),
    );
    wrap.replaceChildren(toggle);
    if (!techOpen) return;
    const { lastSuccess, lastFailure, pendingRetries } = client.pushStatus;
    const lines = [`device id          ${client.id}`, `kind               ${client.kind}`];
    if (client.pushTarget) lines.push(`push provider      ${client.pushTarget.provider}`);
    if (lastFailure) lines.push(`last failure       ${lastFailure.result}`, `failed event       ${lastFailure.eventId}`);
    if (lastSuccess) lines.push(`last sent event    ${lastSuccess.eventId}`);
    lines.push(`pending retries    ${pendingRetries}`);
    wrap.append(el("div", { class: "tech", text: lines.join("\n") }));
  };
  draw();
  return wrap;
}

// ---- Changes -------------------------------------------------------------------------------

function rename(client, ctx) {
  const field = textField({ label: "Name", value: client.name, hint: "Up to 100 characters.", maxlength: 100 });
  const dialog = openDialog({
    title: "Rename the device",
    content: field.node,
    focusNode: field.input,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Rename",
        value: true,
        className: "confirm",
        run: async () => {
          const name = field.input.value.trim();
          if (name === "") {
            field.setError("Give the device a name.");
            throw new Error("");
          }
          await call("PATCH", `${CLIENTS}/${client.id}`, { name });
          snack(`Renamed to “${name}”.`);
          ctx.reload();
        },
      },
    ],
  });
  void dialog;
  field.input.addEventListener("input", () => field.setError(""));
  field.input.select();
}

function revoke(client, ctx) {
  const browser = isBrowser(client);
  const what = client.admin && !browser ? " It is an admin device, so it also stops managing other devices." : "";
  return confirmDialog({
    title: browser ? `Sign out “${client.name}”?` : `Revoke “${client.name}”?`,
    message: browser
      ? "The browser is signed out at once. Signing in again needs a new approval from a device."
      : `It stops working at once, for good, and gets no more pushes.${what} Its past events stay. Nobody is told.`,
    action: "Revoke",
    busyLabel: "Revoking…",
    retryLabel: "Try again",
    destructive: true,
    ariaLabel: `Revoke ${client.name}`,
    run: async () => {
      try {
        await call("POST", `${CLIENTS}/${client.id}/revoke`);
      } catch (error) {
        if (error.name === "SessionEnded") throw error;
        throw new Error(`Could not revoke it: ${error.message} Nothing changed.`);
      }
      snack(`Revoked “${client.name}”.`);
      ctx.reload();
    },
  });
}

function remove(client, ctx) {
  return confirmDialog({
    title: `Delete “${client.name}”?`,
    message: "It leaves this list for good; its delivery records go with it. Events stay in the user's inbox, with their read state. Nobody is told.",
    action: "Delete",
    busyLabel: "Deleting…",
    retryLabel: "Try again",
    destructive: true,
    ariaLabel: `Delete ${client.name}`,
    run: async () => {
      try {
        await call("DELETE", `${CLIENTS}/${client.id}`);
      } catch (error) {
        if (error.name === "SessionEnded") throw error;
        throw new Error(`Could not delete it: ${error.message} Nothing changed.`);
      }
      snack(`Deleted “${client.name}”.`);
      ctx.close();
      ctx.reload();
    },
  });
}

void dateTime;
