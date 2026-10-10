// Settings: Devices, About this server, and this browser. There is no group for push filters,
// sound or vibration: the page does not notify.

import { SessionEnded, calls } from "./api.js";
import { renameDevice, summaryOf } from "./devices.js";
import { el, icon, replace } from "./dom.js";
import { isoDate } from "./format.js";
import { paneHeader } from "./parts.js";
import { signOut } from "./chrome.js";
import { go } from "./router.js";
import { state } from "./state.js";
import { button } from "./ui.js";

const STORE = "signalhub.web.groups";

// Folding groups stay as the person left them. A UI preference only, never anything secret.
function readOpen(id, fallback) {
  try {
    const saved = JSON.parse(localStorage.getItem(STORE) ?? "{}");
    return typeof saved[id] === "boolean" ? saved[id] : fallback;
  } catch {
    return fallback;
  }
}

function saveOpen(id, open) {
  try {
    const saved = JSON.parse(localStorage.getItem(STORE) ?? "{}");
    saved[id] = open;
    localStorage.setItem(STORE, JSON.stringify(saved));
  } catch {
    // Storage may be blocked or full; the group just opens as it did before.
  }
}

/** A folding group: a header that sums up its values in one line, and its rows. */
function group({ id, glyph, title, summary, rows, open }) {
  const bodyId = `group-${id}`;
  const body = el("div", { class: "gb", id: bodyId }, rows);
  const chevron = icon(open ? "expand_less" : "expand_more", "c-var");
  const summaryNode = el("span", { class: "t2n nw", text: summary });
  const head = el(
    "button",
    { type: "button", class: "gh", "aria-expanded": String(open), "aria-controls": bodyId },
    icon(glyph, "c-var"),
    el("div", { class: "tx" }, el("span", { class: "t1", text: title }), summaryNode),
    chevron,
  );
  body.hidden = !open;
  head.addEventListener("click", () => {
    const next = head.getAttribute("aria-expanded") !== "true";
    head.setAttribute("aria-expanded", String(next));
    body.hidden = !next;
    chevron.textContent = next ? "expand_less" : "expand_more";
    saveOpen(id, next);
  });
  return { node: el("div", { class: "grp" }, head, body), summaryNode };
}

const fact = (name, value, extra) =>
  el("div", { class: "kvr" }, el("div", { class: "tx" }, el("span", { class: "t2n", text: name }), el("span", { class: "t1 wrap", text: value })), extra ?? null);

/** `SignalHub 3.4.0 · commit a1b2c3d`; a build no release made says so. */
export function releaseLine(server) {
  const release = !server.version || server.version === "development" ? "SignalHub development build" : `SignalHub ${server.version}`;
  const commit = !server.commit ? "unknown" : server.commit.length > 7 ? server.commit.slice(0, 7) : server.commit;
  return `${release} · commit ${commit}`;
}

export function mountSettings(container, route, { wide }) {
  let gone = false;
  const me = state.me;
  container.className = "main";

  const host = location.host;
  const until = me.expiresAt ? isoDate(me.expiresAt) : null;
  const versionLine = el("span", { class: "t1 wrap", text: "Reading…" });
  const versionRow = el("div", { class: "kvr" }, el("div", { class: "tx" }, el("span", { class: "t2n", text: "Server version" }), versionLine));
  const pageRow = el("div", { class: "kvr" }, el("div", { class: "tx" }, el("span", { class: "t2n", text: "This page" }), el("span", { class: "t1 wrap", text: "Reading…" })));

  // Devices: a row that opens the list, summing it up once it is read.
  const devicesSummary = el("span", { class: "t2n", text: "" });
  const devicesRow = el("a", { class: "grp gh link-row", href: "#settings/devices" }, icon("devices", "c-var"), el("div", { class: "tx" }, el("span", { class: "t1", text: "Devices" }), devicesSummary), icon("chevron_right", "c-var"));

  const about = group({
    id: "about",
    glyph: "dns",
    title: "About this server",
    summary: host,
    open: readOpen("about", wide),
    rows: [
      fact("Server", location.origin),
      versionRow,
      el("div", { class: "kvr" }, icon("info", "c-var"), el("span", { class: "p", text: "The host runs this server and can see every event on it." })),
    ],
  });

  const nameLine = el("span", { class: "t1 wrap", text: me.clientName });
  const here = group({
    id: "browser",
    glyph: "language",
    title: "This browser",
    summary: `${me.clientName}${until ? ` · signed in until ${until}` : ""}`,
    open: readOpen("browser", true),
    rows: [
      el("div", { class: "kvr" }, el("div", { class: "tx" }, el("span", { class: "t2n", text: "Name" }), nameLine), button("Rename", { kind: "text", glyph: "edit", onClick: renameThis })),
      fact("Signed in", `${isoDate(me.createdAt)}${until ? ` · lasts 30 days, until ${until}` : ""}`),
      pageRow,
      el("div", { class: "kvr sign-out-row" }, button("Sign out", { kind: "outlined", glyph: "logout", onClick: () => signOut() }), el("span", { class: "p", text: "Signing out here leaves your phone's app untouched." })),
    ],
  });

  function renameThis() {
    // The browser is a client like a device: the same rename, the same rules.
    renameDevice({ id: me.clientId, name: me.clientName, kind: "BROWSER" }, {
      reload: async () => {
        try {
          const { client } = await calls.session();
          me.clientName = client.name;
          replace(nameLine, client.name);
          replace(here.summaryNode, `${client.name}${until ? ` · signed in until ${until}` : ""}`);
        } catch (error) {
          if (!(error instanceof SessionEnded)) return;
        }
      },
    });
  }

  const pane = el(
    "section",
    { class: "detp solo", "aria-label": "Settings" },
    wide ? el("h1", { class: "h", tabindex: "-1", text: "Settings" }) : paneHeader({ title: "Settings", account: true }),
    el("div", { class: "settings-groups" }, devicesRow, about.node, here.node),
  );
  replace(container, pane);

  async function load() {
    try {
      const [devices, server] = await Promise.all([calls.devices(), calls.server().catch(() => null)]);
      if (gone) return;
      replace(devicesSummary, summaryOf(devices.items));
      const line = server ? releaseLine(server) : "This server does not say";
      replace(versionLine, line);
      replace(pageRow.querySelector(".t1"), line);
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      replace(devicesSummary, "Couldn't load devices");
    }
  }
  load();

  return {
    update() {},
    refresh: load,
    unmount() {
      gone = true;
    },
  };
}

export { go };
