// Status: is SignalHub working? One column of answers in plain language, never a list with a pane.
// It reads /q/info, /q/health, /api/v1/admin/status, the device list and the newest event (signal.js
// does, every 30 seconds while the page is visible) and judges them by model.js. Nothing on it can be
// changed: settings live in the server's .env and take effect after a restart.

import { el, icon } from "./dom.js";
import { clock } from "./format.js";
import { check, onSignal, signal } from "./signal.js";
import { announce, button, iconButton } from "./ui.js";

let unsubscribe = null;
let tick = null;
// The fold and the opened rows are remembered only while the page is open.
let techOpen = false;
const opened = new Set();

function advice(item) {
  if (!item.advice?.text) return null;
  return el("span", { class: "do" }, item.advice.label ? [el("b", { text: `${item.advice.label}:` }), ` ${item.advice.text}`] : item.advice.text);
}

function chipFor(status) {
  if (status === "ok") return el("span", { class: "sc ok" }, icon("check_circle"), "Working");
  if (status === "bad") return el("span", { class: "sc bad" }, icon("error", "fill"), "Needs attention");
  if (status === "look") return el("span", { class: "sc look" }, icon("info"), "Look");
  if (status === "un") return el("span", { class: "sc un" }, icon("help"), "Could not read");
  return null;
}

function renderRow(item) {
  const bad = item.status === "bad";
  const kind = item.status === "ok" ? " ok" : bad ? " bad" : item.status === "un" || item.status === "look" ? " un" : "";
  const value = el("div", { class: "vl" }, item.text);
  if (item.mono) value.append(" · revision ", el("span", { class: "mono", text: item.mono }));
  if (item.link) value.append(" · ", el("a", { href: item.link.href, text: item.link.label }));
  const text = advice(item);
  if (text) value.append(text);
  const name = el("span", { class: "nmx" }, item.short ? [el("span", { class: "full", text: item.name }), el("span", { class: "short", text: item.short })] : item.name);
  const node = el("div", { class: `srow${kind}${opened.has(item.id) ? " open" : ""}`, id: `status-${item.id}`, tabindex: "-1", role: "group", "aria-label": item.name });
  node.append(icon(item.glyph, item.status === null ? "c-var" : ""), name, value);
  const chipNode = chipFor(item.status);
  if (chipNode) node.append(chipNode);
  // On a phone a working row shows its advice only when opened; a problem row is always open.
  if (!bad && text) {
    const open = opened.has(item.id);
    const chevron = el(
      "button",
      {
        type: "button",
        class: "chev",
        "aria-expanded": String(open),
        "aria-label": `${open ? "Hide" : "Show"} what to do for ${item.name}`,
        on: {
          click: () => {
            if (opened.has(item.id)) opened.delete(item.id);
            else opened.add(item.id);
            node.classList.toggle("open", opened.has(item.id));
            chevron.setAttribute("aria-expanded", String(opened.has(item.id)));
            chevron.setAttribute("aria-label", `${opened.has(item.id) ? "Hide" : "Show"} what to do for ${item.name}`);
            chevron.firstChild.textContent = opened.has(item.id) ? "expand_less" : "expand_more";
          },
        },
      },
      icon(open ? "expand_less" : "expand_more", "ms20"),
    );
    name.append(chevron);
  }
  return node;
}

function group(label, rows, { bad = false, glyph, count } = {}) {
  if (rows.length === 0) return [];
  return [
    el("div", { class: `sgrp${bad ? " bad" : ""}`, role: "heading", "aria-level": "2" }, glyph ? icon(glyph, "ms18") : null, count === undefined ? label : `${label} · ${count}`),
    ...rows.map(renderRow),
  ];
}

function jumpTo(id) {
  const row = document.getElementById(`status-${id}`);
  if (!row) return;
  row.scrollIntoView({ block: "center" });
  row.focus({ preventScroll: true });
}

function hero(headline, fresh) {
  const glyph = { working: "check_circle", attention: "warning", unknown: "help" }[headline.state];
  const text = el("div", { class: "tx" }, el("h2", { class: "h", text: headline.title }), el("span", { class: "s", text: headline.sentence }));
  if (headline.state === "attention") {
    text.append(
      el(
        "div",
        { class: "jumps" },
        headline.jumps.map((jump) => el("button", { type: "button", class: "fc", on: { click: () => jumpTo(jump.id) } }, el("span", { text: jump.label }))),
      ),
    );
  }
  if (headline.state === "unknown") {
    text.append(el("div", { class: "jumps" }, button("Try again", { kind: "tonal", glyph: "refresh", onClick: () => refresh() })));
  }
  return el(
    "div",
    { class: `hero${headline.state === "attention" ? " bad" : headline.state === "unknown" ? " un" : ""}`, role: fresh ? "status" : null },
    el("span", { class: "hi" }, icon(glyph, headline.state === "unknown" ? "" : "fill")),
    text,
  );
}

function checkList() {
  return [
    el("div", { class: "sgrp", role: "heading", "aria-level": "2", text: "WHAT TO CHECK" }),
    simple("terminal", "Is SignalHub running?", [
      "On the server, ",
      el("span", { class: "mono", text: "docker compose ps" }),
      " says whether the backend is up and healthy.",
      el("span", { class: "do", text: "If it is down, SignalHub cannot say so itself. Watch it from outside (docs/deployment.md, Health monitoring)." }),
    ]),
    simple("lan", "Is this the server's own port?", "A proxy or another address will not answer this page."),
    simple("key", "Is the token still right?", "On a 401 this page goes back to Sign in and returns here."),
  ];
}

function simple(glyph, name, text) {
  return el("div", { class: "srow", role: "group", "aria-label": name }, icon(glyph, "c-var"), el("span", { class: "nmx", text: name }), el("div", { class: "vl" }, text));
}

function skeleton() {
  const rows = [];
  for (let i = 0; i < 7; i += 1) {
    rows.push(el("div", { class: "sksr" }, el("span", { class: "sk c" }), el("span", { class: "sk", data: { w: 1 } }), el("span", { class: "sk" }), el("span", { class: "sk" })));
  }
  return [
    el("div", { class: "hero ld", "aria-hidden": "true" }, el("span", { class: "hi" }), el("div", { class: "tx" }, el("span", { class: "sk" }), el("span", { class: "sk" }))),
    el("div", { class: "sgrp", "aria-hidden": "true" }, el("span", { class: "sk" })),
    ...rows,
  ];
}

const mono = (parts) => parts;

/** The raw check names, values and endpoints the rows were made of, to match a log or a report. */
function technicalText() {
  const { info, health, status, clients, latest } = signal.parts;
  const lines = [];
  const unread = (part) => `  could not be read: ${part?.error?.message ?? "no answer"}`;
  const field = (name, value) => `  ${name.padEnd(30)}${value}`;
  lines.push("GET /q/health");
  if (health?.ok) {
    lines.push(field("status", health.value.status));
    for (const item of health.value.checks || []) lines.push(field(item.name, item.status));
  } else lines.push(unread(health));
  lines.push("GET /q/info");
  if (info?.ok) {
    const build = info.value.signalhub || {};
    lines.push(field("signalhub.version", build.version ?? "unknown"));
    if (build.revision) lines.push(field("signalhub.revision", build.revision));
  } else lines.push(unread(info));
  lines.push("GET /api/v1/admin/status");
  if (status?.ok) {
    const value = status.value;
    lines.push(field("pushProviders", JSON.stringify(value.pushProviders)));
    lines.push(field("pushClientOptions", JSON.stringify(value.pushClientOptions)));
    lines.push(field("pendingDispatches", String(value.pendingDispatches)));
    lines.push(field("pendingRetries", String(value.pendingRetries)));
    lines.push(field("abandonedRetries", `${value.abandonedRetries}   (${signal.baseline ?? value.abandonedRetries} when this page opened)`));
    lines.push(field("startedAt", JSON.stringify(value.startedAt ?? null)));
    lines.push(field("eventRetentionSeconds", JSON.stringify(value.eventRetentionSeconds)));
  } else lines.push(unread(status));
  if (clients?.ok) {
    const items = clients.value.items;
    const failed = items.filter((client) => !client.revokedAt && client.pushStatus.lastFailure && (!client.pushStatus.lastSuccess || Date.parse(client.pushStatus.lastFailure.at) > Date.parse(client.pushStatus.lastSuccess.at))).length;
    lines.push(`GET /api/v1/admin/clients      ${items.length} ${items.length === 1 ? "device" : "devices"}, ${failed} whose last push failed`);
  } else lines.push("GET /api/v1/admin/clients", unread(clients));
  if (latest?.ok) {
    const [event] = latest.value.items;
    lines.push(`GET /api/v1/events?limit=1     ${event ? `newest event received ${event.createdAt}` : "no event stored"}`);
  } else lines.push("GET /api/v1/events?limit=1", unread(latest));
  lines.push("", "Metrics for Prometheus are at /q/metrics on the server's own port.");
  return lines.join("\n");
}

export const statusSection = {
  mount({ container }) {
    const checked = el("span", { class: "cnt", id: "status-checked" });
    const refreshButton = iconButton("refresh", "Refresh the status", () => refresh());
    const head = el(
      "div",
      { class: "mhead" },
      el("h1", { text: "Status", tabindex: "-1" }),
      checked,
      el("span", { class: "sp" }),
      el("span", { class: "cnt small keep", text: "Looks again every 30 s" }),
      refreshButton,
    );
    const bar = el("div", { class: "prog", role: "progressbar", "aria-label": "Checking the status", hidden: true });
    const slot = el("div", { class: "banner-slot" });
    const body = el("div", { class: "sin", id: "status-body" });
    const scroller = el("div", { class: "sbody" }, slot, body);
    container.replaceChildren(head, bar, scroller);
    container.hidden = false;
    let announced = false;

    const paint = () => {
      const first = signal.readAt === null;
      const checking = signal.checking;
      checked.textContent = checking && !first ? "Checking…" : signal.readAt ? `Checked ${clock(signal.readAt)}` : "";
      bar.hidden = !checking;
      refreshButton.disabled = checking && first;
      slot.replaceChildren();
      if (first) {
        body.replaceChildren(...skeleton());
        body.setAttribute("aria-busy", "true");
        return;
      }
      body.removeAttribute("aria-busy");
      if (signal.failure) {
        slot.append(
          el(
            "div",
            { class: "bn err", role: "alert" },
            icon("cloud_off"),
            el("span", { class: "tx", text: `Could not refresh the status: ${signal.failure.message.replace(/\.$/, "")}. The rows below are from ${clock(signal.readAt)}.` }),
            button("Try again", { onClick: () => refresh() }),
          ),
        );
      }
      const verdict = signal.assessment();
      const nodes = [hero(verdict.headline, !announced)];
      announced = true;
      if (verdict.headline.state === "unknown") {
        nodes.push(...checkList());
      } else {
        nodes.push(
          ...group("NEEDS ATTENTION", verdict.attention, { bad: true, glyph: "warning", count: verdict.attention.length }),
          ...group("WORTH A LOOK", verdict.look, { glyph: "info", count: verdict.look.length }),
          ...group(verdict.attention.length || verdict.look.length ? "WORKING" : "DELIVERING EVENTS", verdict.working),
          ...group("ACTIVITY", verdict.rows.activity),
          ...group("THIS SERVER", verdict.rows.server),
        );
        nodes.push(technical());
      }
      nodes.push(el("div", { class: "sfoot", text: "Nothing is changed on this page: settings are in the server's .env and take effect after a restart." }));
      const focused = document.activeElement?.id;
      body.replaceChildren(...nodes);
      if (focused && focused.startsWith("status-")) document.getElementById(focused)?.focus({ preventScroll: true });
    };

    unsubscribe = onSignal(paint);
    tick = setInterval(paint, 30_000);
    paint();
    check({ fullRead: true });
  },
  update() {},
  unmount() {
    unsubscribe?.();
    unsubscribe = null;
    clearInterval(tick);
    tick = null;
  },
};

function refresh() {
  return check({ fullRead: true });
}

/** The fold at the end: closed by default, its state kept while the page is open. */
function technical() {
  const wrap = el("div", { class: "tfold" });
  const toggle = el("button", { type: "button", class: "sfold", "aria-expanded": String(techOpen), on: { click: () => flip() } }, icon(techOpen ? "expand_less" : "expand_more"), el("span", { text: "Technical details" }));
  const draw = () => {
    toggle.replaceChildren(icon(techOpen ? "expand_less" : "expand_more"), el("span", { text: "Technical details" }), el("span", { class: "sp" }));
    toggle.setAttribute("aria-expanded", String(techOpen));
    wrap.replaceChildren(toggle);
    if (!techOpen) return;
    const copy = el("button", { type: "button", class: "btn-x", "aria-label": "Copy the technical details", on: { click: () => copyText(copy) } }, icon("content_copy"), el("span", { class: "btn-label", text: "Copy" }));
    // The copy button is its own control beside the toggle, not inside it.
    wrap.replaceChildren(el("div", { class: "sfold-row" }, toggle, copy), el("div", { class: "techbox" }, el("div", { class: "tech", id: "status-tech", text: technicalText() })));
  };
  const flip = () => {
    techOpen = !techOpen;
    draw();
    toggle.focus();
  };
  draw();
  return wrap;
}

async function copyText(node) {
  const text = document.getElementById("status-tech")?.textContent ?? "";
  const label = node.querySelector(".btn-label");
  try {
    await navigator.clipboard.writeText(text);
    label.textContent = "Copied";
    announce("Copied");
  } catch {
    // The clipboard needs a secure context; selecting still works.
    const range = document.createRange();
    range.selectNodeContents(document.getElementById("status-tech"));
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    label.textContent = "Press Ctrl+C";
  }
  setTimeout(() => {
    label.textContent = "Copy";
  }, 2000);
}
