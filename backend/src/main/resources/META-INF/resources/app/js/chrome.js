// The frame around every screen: the navigation rail (a bottom bar on a narrow page), the
// account button and its menu, and signing out.

import { calls } from "./api.js";
import { clear, el, icon } from "./dom.js";
import { go } from "./router.js";
import { hooks, isAdmin, onChange, state } from "./state.js";
import { confirmDialog, openMenu, roleLabel } from "./ui.js";

const DESTINATIONS = [
  { name: "inbox", label: "Inbox", glyph: "inbox", hash: "#inbox" },
  { name: "producers", label: "Producers", glyph: "sensors", hash: "#producers" },
  { name: "people", label: "People", glyph: "group", hash: "#people", adminOnly: true },
  { name: "settings", label: "Settings", glyph: "settings", hash: "#settings" },
];

let nav = null;
let active = "inbox";

const badgeText = (count) => (count > 99 ? "99+" : String(count));

/** The rail (or the bottom bar): the same four destinations, People for an admin only. */
export function buildNavigation() {
  nav = el("nav", { class: "rail", "aria-label": "Main" });
  paintNavigation();
  onChange(() => paintNavigation());
  return nav;
}

function paintNavigation() {
  clear(nav);
  nav.append(el("span", { class: "rlogo", "aria-hidden": "true" }, icon("sensors")));
  for (const destination of DESTINATIONS) {
    if (destination.adminOnly && !isAdmin()) continue;
    const on = destination.name === active;
    const unread = destination.name === "inbox" ? (state.unread ?? 0) : 0;
    nav.append(
      el(
        "a",
        {
          class: `ri${on ? " on" : ""}`,
          href: destination.hash,
          "aria-current": on ? "page" : null,
          "aria-label": unread > 0 ? `${destination.label}, ${unread} unread` : null,
        },
        el("span", { class: "pill" }, icon(destination.glyph, on ? "fill" : ""), unread > 0 ? el("span", { class: "nbadge", "aria-hidden": "true", text: badgeText(unread) }) : null),
        el("span", { class: "ri-label", text: destination.label }),
      ),
    );
  }
  if (state.me) {
    nav.append(accountButton("acct"));
  }
}

export function setActiveDestination(name) {
  if (active === name) return;
  active = name;
  if (nav) paintNavigation();
}

/**
 * The account button. In the rail it is a circle with the person's initial; in a phone-width
 * header it is the same, 32 px inside a 48 px target. `Account menu, NAME` is its name.
 */
export function accountButton(kind = "ib") {
  const name = state.me?.name ?? "";
  const letter = [...name][0]?.toUpperCase() ?? "?";
  const node = el(
    "button",
    { type: "button", class: kind === "acct" ? "acct" : "ib account", "aria-label": `Account menu, ${name}`, "aria-haspopup": "menu", "aria-expanded": "false" },
    el("span", { class: kind === "acct" ? "av avp" : "mini", "aria-hidden": "true", text: letter }),
  );
  node.addEventListener("click", () => openAccountMenu(node, kind === "acct"));
  return node;
}

function openAccountMenu(anchor, inRail) {
  const me = state.me;
  openMenu(anchor, {
    placement: inRail ? "right-end" : "below-end",
    header: { title: me.name, subtitle: `${roleLabel(me.role)} · signed in on ${me.clientName}` },
    items: [
      { label: "Devices", glyph: "devices", onSelect: () => go("#settings/devices") },
      { label: "Sign out", glyph: "logout", onSelect: signOut },
    ],
  });
}

/** Asks first; signing out leaves the phone's app and the other devices untouched. */
export async function signOut() {
  const confirmed = await confirmDialog({
    title: "Sign out of this browser?",
    message: "This browser stops being a device of yours. Your phone and your other devices are not affected.",
    action: "Sign out",
    run: async () => {
      await calls.signOut();
    },
  });
  if (confirmed) hooks.signedOut();
}
