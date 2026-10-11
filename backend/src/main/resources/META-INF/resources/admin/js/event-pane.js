// The event's detail pane (a side sheet below 1180 px, a screen of its own on a phone): the Event
// tab, with what was sent, and the Pushes tab, with who it reached and how each device's push went.
// Its foot holds what applies to the whole event: mark it read or unread, and delete it. Everything
// the server sent is set as text; the event's link is only ever opened by the operator, in a new tab
// that cannot reach back to this page and is told nothing of where it came from.

import { ADMIN_EVENTS, EVENTS, call } from "./api.js";
import { webLink, el, icon } from "./dom.js";
import { categoryOf, severityOf } from "./event-filters.js";
import { recipients, summary } from "./event-pushes.js";
import { ago, clock, shortDate } from "./format.js";
import { store } from "./store.js";
import { avatar, banner, button, confirmDialog, iconButton, nextId } from "./ui.js";

const POLL_MS = 5000;
const POLL_LIMIT = 24;

const commaDate = (iso) => `${shortDate(iso)}, ${clock(iso)}`;
const seconds = (iso) => {
  const date = new Date(iso);
  return `${clock(date)}:${String(date.getSeconds()).padStart(2, "0")}`;
};

/** The severity as a small chip: its icon and its word, the colour never alone. */
export function severityChip(severity) {
  const item = severityOf(severity);
  return el("span", { class: `sv ${item?.tone ?? "low"}` }, icon(item?.glyph ?? "info"), item?.text ?? severity);
}

/**
 * `cfg`: producerOwner(id) -> the owner's name or null; onRead(event) after a read switch;
 * onDeleted(event) after a deletion; close() asks the section to close the pane.
 */
export function createEventPane(cfg) {
  const node = el("section", { class: "pane", hidden: true });
  let id = null;
  let event = null;
  let failure = null;
  let tab = "event";
  let answer = null;
  let pushesFailure = null;
  let loadingPushes = false;
  let techOpen = false;
  let busy = false;
  let notice = null;
  let polls = 0;
  let timer = null;
  let token = 0;
  let focusTitle = false;

  const titleId = nextId("pane-title");

  // ---- Loading -------------------------------------------------------------------------------

  async function load(wanted, fromList) {
    const mine = ++token;
    id = wanted;
    event = fromList ?? null;
    failure = null;
    answer = null;
    pushesFailure = null;
    notice = null;
    tab = "event";
    polls = 0;
    clearTimeout(timer);
    focusTitle = true;
    paint();
    const [got] = await Promise.allSettled([call("GET", `${EVENTS}/${wanted}`), loadPushes(mine)]);
    if (mine !== token) return;
    if (got.status === "fulfilled") {
      event = got.value;
      failure = null;
    } else if (got.reason?.name !== "SessionEnded") {
      failure = got.reason;
    }
    paint();
  }

  async function loadPushes(mine = token) {
    loadingPushes = true;
    pushesFailure = null;
    if (mine === token && !node.hidden) paint();
    try {
      const next = await call("GET", `${ADMIN_EVENTS}/${id}/deliveries`);
      if (mine !== token) return;
      answer = next;
      // Not dispatched yet: a just-received event has no records for a few seconds.
      if (answer.items.length === 0 && answer.users.length > 0 && polls < POLL_LIMIT) {
        polls += 1;
        timer = setTimeout(() => loadPushes(mine), POLL_MS);
      }
    } catch (error) {
      if (mine !== token || error.name === "SessionEnded") return;
      pushesFailure = error;
    } finally {
      if (mine === token) {
        loadingPushes = false;
        paint();
      }
    }
  }

  // ---- Painting ------------------------------------------------------------------------------

  function people() {
    return answer ? recipients(answer, store.clients ?? []) : null;
  }

  function paint() {
    if (id === null) return;
    const scroll = node.querySelector(".pbody")?.scrollTop ?? 0;
    const list = people();
    const counts = list ? summary(list) : null;
    const title = event?.title ?? "Event";
    const children = [
      el(
        "div",
        { class: "phd" },
        iconButton("arrow_back", "Back", () => cfg.close(), { class: "back" }),
        el("div", { class: "hd" }, el("h2", { id: titleId, tabindex: "-1", title, text: title })),
        event ? iconButton("delete", `Delete event ${event.title}`, () => remove(), { class: "trash" }) : null,
        iconButton("close", `Close ${title}`, () => cfg.close(), { class: "close" }),
      ),
    ];
    if (event) {
      children.push(tabs(counts, list));
      children.push(el("div", { class: "pbody", id: "event-panel", role: "tabpanel", "aria-label": tab === "event" ? "Event" : "Pushes" }, noteNode(), tab === "event" ? eventTab(counts) : pushesTab(list, counts)));
      children.push(foot());
    } else {
      children.push(el("div", { class: "pbody" }, failure ? failureBody() : loadingBody()));
    }
    node.setAttribute("aria-labelledby", titleId);
    node.replaceChildren(...children);
    node.hidden = false;
    const body = node.querySelector(".pbody");
    if (body) body.scrollTop = scroll;
    if (focusTitle) {
      focusTitle = false;
      node.querySelector("h2").focus({ preventScroll: true });
    }
  }

  function loadingBody() {
    return el("div", { class: "skeletons", "aria-hidden": "true" }, [0, 1, 2].map((n) => el("div", { class: "sk2 pane-sk" }, el("span", { class: "sk", data: { w: n } }))));
  }

  function failureBody() {
    const gone = failure.status === 404;
    return banner({
      glyph: "error",
      error: true,
      role: "alert",
      text: gone ? "This event was not found. It may have been deleted." : `Could not load this event. ${failure.message}`,
      actions: gone ? [] : [button("Try again", { onClick: () => load(id, null) })],
    });
  }

  function tabs(counts, list) {
    const group = el("div", { class: "seg3", role: "tablist", "aria-label": "Event" });
    const make = (value, glyph, label, extra) => {
      const selected = tab === value;
      const item = el(
        "button",
        {
          type: "button",
          role: "tab",
          id: `tab-${value}`,
          "aria-selected": String(selected),
          "aria-controls": "event-panel",
          tabindex: selected ? "0" : "-1",
          class: selected ? "on" : null,
          on: {
            click: () => {
              tab = value;
              paint();
              node.querySelector(`#tab-${value}`).focus();
            },
          },
        },
        icon(glyph, "ms18"),
        el("span", { text: label }),
        extra,
      );
      return item;
    };
    let mark = null;
    if (list && counts.problems > 0) {
      mark = el("span", { class: "tg o err" }, el("span", { class: "pc-word", text: counts.problems === 1 ? "1 problem" : `${counts.problems} problems` }), el("span", { class: "pc-n", "aria-hidden": "true", text: String(counts.problems) }));
    } else if (list && list.length === 0) {
      mark = el("span", { class: "tg o err", text: "none" });
    }
    group.append(make("event", "description", "Event"), make("pushes", "notifications", "Pushes", mark));
    group.addEventListener("keydown", (key) => {
      if (key.key !== "ArrowLeft" && key.key !== "ArrowRight") return;
      key.preventDefault();
      tab = tab === "event" ? "pushes" : "event";
      paint();
      node.querySelector(`#tab-${tab}`).focus();
    });
    return group;
  }

  function noteNode() {
    if (!notice) return null;
    return el("div", { class: "bn err note", role: "alert" }, icon("error"), el("span", { class: "tx", text: notice }));
  }

  // ---- The Event tab -------------------------------------------------------------------------

  function eventTab(counts) {
    const parts = [];
    const category = categoryOf(event.category);
    parts.push(
      el(
        "div",
        { class: "chips" },
        severityChip(event.severity),
        el("span", { class: "tg o flush" }, icon(category?.glyph ?? "info", "ms18 tg-ic"), category?.text ?? event.category),
        event.readAt ? null : el("span", { class: "tg p flush", text: "Unread" }),
      ),
    );
    if (event.message) parts.push(el("p", { class: "msg", text: event.message }));
    if (event.link) parts.push(linkRow(event.link));
    const owner = cfg.producerOwner(event.producer.id);
    const kv = el(
      "div",
      { class: "kv" },
      el("b", { text: "Producer" }),
      el("span", {}, el("a", { href: `#producers/${event.producer.id}`, text: event.producer.name }), owner ? ` · ${owner}'s` : null),
    );
    const row = (name, value) => kv.append(el("b", { text: name }), el("span", { text: value }));
    if (event.context) row("Context", event.context);
    if (event.occurredAt) row("Happened", commaDate(event.occurredAt));
    row("Received", `${commaDate(event.createdAt)} · ${ago(event.createdAt)}`);
    row("Read", event.readAt ? commaDate(event.readAt) : "Not by you yet");
    parts.push(kv);
    parts.push(el("div", { class: "lab spaced-s" }, "Metadata", el("span", { class: "cnt", text: "as the producer sent it" })));
    parts.push(metadata(event.metadata));
    parts.push(pushesRow(counts));
    return parts;
  }

  // The host is shown so the operator sees where the link goes before opening it.
  function linkRow(link) {
    const url = webLink(link);
    const shown = url ? link.replace(/^https?:\/\//i, "") : link;
    return el(
      "div",
      { class: "krow link-row" },
      icon("link", "c-var"),
      el("div", { class: "tx" }, el("span", { class: "t1", text: shown }), el("span", { class: "t2", text: url ? "Opens in a new tab" : "Not a web address, so it is not offered as a link" })),
      url
        ? el("a", { class: "btn-t sm", href: url, target: "_blank", rel: "noopener noreferrer", "aria-label": `Open link ${shown} in a new tab` }, icon("open_in_new"), el("span", { class: "w-wide", text: "Open link" }), el("span", { class: "w-phone", text: "Open" }))
        : null,
    );
  }

  // The producer's own words: a key and a value, a nested value as JSON on its line.
  function metadata(values) {
    const keys = Object.keys(values ?? {});
    if (keys.length === 0) return el("p", { class: "t2 sub-note", text: "None." });
    const grid = el("div", { class: "meta" });
    for (const key of keys) {
      const value = values[key];
      grid.append(el("b", { text: key }), el("span", { text: typeof value === "string" ? value : JSON.stringify(value) }));
    }
    return grid;
  }

  function pushesRow(counts) {
    let heading;
    let sub = "";
    if (pushesFailure) {
      heading = "Could not read the pushes";
      sub = "Open the Pushes tab to try again.";
    } else if (!counts) {
      heading = "Reading the pushes…";
    } else if (counts.users === 0) {
      heading = "No user receives it";
      sub = `Nobody is subscribed to ${event.producer.name}.`;
    } else if (counts.devices === 0) {
      heading = `Reaches ${counts.users === 1 ? "1 user" : `${counts.users} users`}`;
      sub = "Its push is not sent yet.";
    } else {
      heading = `Reached ${counts.users === 1 ? "1 user" : `${counts.users} users`} on ${counts.devices === 1 ? "1 device" : `${counts.devices} devices`}`;
      sub = counts.line;
    }
    return el(
      "div",
      { class: "krow push-row" },
      icon("notifications", "c-var"),
      el("div", { class: "tx" }, el("span", { class: "t1", text: heading }), sub ? el("span", { class: "t2", text: sub }) : null),
      button("See pushes", {
        kind: "text",
        onClick: () => {
          tab = "pushes";
          paint();
          node.querySelector("#tab-pushes").focus();
        },
      }),
    );
  }

  // ---- The Pushes tab ------------------------------------------------------------------------

  function pushesTab(list, counts) {
    if (pushesFailure) {
      return banner({ glyph: "error", error: true, role: "alert", text: "Could not load the pushes. Check the connection and try again.", actions: [button("Try again", { onClick: () => loadPushes() })] });
    }
    if (!list) return loadingBody();
    if (list.length === 0) {
      return el("div", { class: "empty compact" }, icon("notifications_off"), el("h3", { class: "h", text: "No user receives it" }), el("p", { class: "p", text: `Nobody is subscribed to ${event.producer.name}, so there was no one to push to.` }));
    }
    const parts = [el("p", { class: "t2 caveat", text: "The push service's answer is the last thing SignalHub knows. It cannot tell whether a device showed the push." })];
    if (counts.devices === 0) {
      parts.push(el("p", { class: "t2 caveat", role: "status", text: "Its push is not sent yet. This refreshes by itself." }));
    }
    for (const person of list) {
      parts.push(
        el(
          "div",
          { class: "ugrp", role: "group", "aria-label": person.name },
          avatar(person.name, { tint: true }),
          el("span", { text: person.name }),
          el("span", { class: "tg o", text: person.owner ? "Owns the producer" : person.left ? "No longer subscribed" : "Subscribed" }),
        ),
      );
      for (const device of person.devices) parts.push(...deviceLine(device));
      if (person.devices.length === 0 && counts.devices > 0) {
        parts.push(el("p", { class: "t2 nodev", text: "No device to push to: this user has no device that is not revoked." }));
      }
    }
    parts.push(technical(list));
    return parts;
  }

  function deviceLine(device) {
    const { words, last } = device;
    const reason = words.key === "sent" ? `${clock(last.at)} · ${words.reason}` : words.reason;
    const lines = [
      el(
        "div",
        { class: "drow" },
        icon(words.glyph, `d-${words.tone}`),
        el("div", { class: "tx" }, el("span", { class: "t1", text: `${device.name} · ${words.title}` }), el("span", { class: "t2", text: reason })),
      ),
    ];
    if (techOpen) {
      const code = ["DELIVERED", "TRANSIENT_FAILURE", "PERMANENT_FAILURE", "INVALID_TARGET", "UNSUPPORTED_PROVIDER"].includes(last.outcome) ? `${last.outcome} · attempt ${last.attempt} · ${seconds(last.at)}` : `${last.outcome} · ${seconds(last.at)}`;
      lines.push(el("div", { class: "tech indent", text: last.detail ? `${code} provider: ${last.detail}` : code }));
    }
    return lines;
  }

  function technical(list) {
    const records = answer.items.length;
    const parts = [
      el(
        "button",
        {
          type: "button",
          class: "fold",
          "aria-expanded": String(techOpen),
          on: {
            click: () => {
              techOpen = !techOpen;
              paint();
              node.querySelector(".fold").focus();
            },
          },
        },
        icon(techOpen ? "expand_less" : "expand_more"),
        el("span", { text: "Technical details" }),
      ),
    ];
    if (techOpen) {
      parts.push(el("div", { class: "tech", text: `event ${event.id}\nproducer ${event.producer.id}\nrecords: ${records}, oldest first` }));
    }
    void list;
    return el("div", { class: "tfold" }, parts);
  }

  // ---- The foot ------------------------------------------------------------------------------

  function foot() {
    const unread = !event.readAt;
    return el(
      "div",
      { class: "pfoot" },
      button(unread ? "Mark read" : "Mark unread", { kind: "tonal", glyph: unread ? "mark_email_read" : "mark_email_unread", disabled: busy, onClick: () => toggleRead() }),
      el("span", { class: "sp" }),
      button("Delete event", { kind: "text-error", glyph: "delete", ariaLabel: `Delete event ${event.title}`, className: "del", onClick: () => remove() }),
    );
  }

  async function toggleRead() {
    const current = event;
    busy = true;
    notice = null;
    paint();
    try {
      event = await call(current.readAt ? "DELETE" : "PUT", `${EVENTS}/${current.id}/read`);
      cfg.onRead(event);
    } catch (error) {
      if (error.name !== "SessionEnded") notice = `Could not mark it ${current.readAt ? "unread" : "read"}. ${error.message} Nothing changed.`;
    }
    busy = false;
    paint();
    node.querySelector(".pfoot button")?.focus();
  }

  function remove() {
    const current = event;
    return confirmDialog({
      title: "Delete this event?",
      message: `“${current.title}” is gone for good, with its waiting pushes and delivery records. Producers and users are not touched. This cannot be undone.`,
      action: "Delete event",
      ariaLabel: `Delete event ${current.title}`,
      destructive: true,
      busyLabel: "Deleting…",
      retryLabel: "Try again",
      run: async () => {
        await call("DELETE", `${ADMIN_EVENTS}/${current.id}`);
        cfg.onDeleted(current);
      },
    });
  }

  return {
    node,
    show(wanted, fromList) {
      if (wanted === id && !node.hidden) return;
      load(wanted, fromList);
    },
    /** The list was read again: the event shown follows what it says now. */
    follow(fresh) {
      if (fresh && fresh.id === id && event && (fresh.readAt ?? null) !== (event.readAt ?? null)) {
        event = fresh;
        paint();
      }
    },
    hide() {
      token += 1;
      id = null;
      event = null;
      clearTimeout(timer);
      node.hidden = true;
      node.replaceChildren();
    },
    get id() {
      return id;
    },
    get event() {
      return event;
    },
    focusTitle() {
      node.querySelector("h2")?.focus({ preventScroll: true });
    },
  };
}
