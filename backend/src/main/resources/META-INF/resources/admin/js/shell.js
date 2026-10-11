// The page around a section: the rail (and the bottom bar on a phone) with the current section, the
// status button at the foot of the rail, and the account menu with Sign out.

import { probe, INFO } from "./api.js";
import { el, icon } from "./dom.js";
import { onSignal, signal } from "./signal.js";
import { confirmDialog, openMenu } from "./ui.js";

const $ = (id) => document.getElementById(id);

const WORDS = { working: "Working", check: "Check", checking: "Checking", unknown: "Unknown" };

let build = null;

/** The running release and commit, from the server's info page; read once. */
async function loadBuild() {
  if (build) return build;
  try {
    const info = (await probe(INFO)).signalhub || {};
    const development = !info.version || info.version === "development";
    build = {
      title: development ? "SignalHub development build" : `SignalHub ${info.version}`,
      commit: !development && info.revision ? `commit ${info.revision.slice(0, 7)}` : null,
    };
  } catch {
    build = { title: "SignalHub", commit: null };
  }
  return build;
}

export function forgetBuild() {
  build = null;
}

/** Marks the section shown in the rail and the bottom bar. */
export function setCurrent(section) {
  for (const link of document.querySelectorAll("#rail a[data-section], #bottom-bar a[data-section]")) {
    const current = link.dataset.section === section;
    if (current) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
    link.querySelector(".ms")?.classList.toggle("fill", current);
  }
}

/** A phone shows a detail as a screen of its own, without the bottom bar. */
export function setDetailOpen(open) {
  $("app").classList.toggle("detail", open);
}

function statusLabel(state, count) {
  if (state === "check") return `Server status: needs attention, ${count} ${count === 1 ? "thing" : "things"}`;
  return `Server status: ${state}`;
}

/** The rail's button and the bottom bar's Status item follow the one rule of model.js. */
function paintStatus() {
  const { state, count, stale } = signal;
  const button = $("status-button");
  button.className = `ri${state === "check" ? " bad" : state === "checking" || state === "unknown" ? " un" : ""}`;
  button.setAttribute("aria-label", `${statusLabel(state, count)}${stale ? ". The last check read nothing: this is the older state" : ""}`);
  const pill = button.querySelector(".pill");
  const glyph = state === "check" ? icon("warning", "fill") : state === "unknown" ? icon("help") : icon("dns");
  pill.replaceChildren(glyph);
  if (state === "working" || state === "checking") pill.append(el("span", { class: `sdot${state === "checking" ? " un" : ""}` }));
  if (stale) pill.append(icon("help", "qm"));
  button.querySelector(".word").textContent = WORDS[state];

  // On a phone the Status item of the bar carries the same dot or the warning icon.
  const item = document.querySelector("#bottom-bar a[data-section='status']");
  const itemPill = item.querySelector(".pill");
  itemPill.replaceChildren(icon(state === "check" ? "warning" : state === "unknown" ? "help" : "monitor_heart", item.hasAttribute("aria-current") || state === "check" ? "fill" : ""));
  if (state === "check") itemPill.firstChild.classList.add("c-error");
  else if (state === "working") itemPill.append(el("span", { class: "sdot" }));
  item.setAttribute("aria-label", state === "check" ? `Status, needs attention, ${count} ${count === 1 ? "thing" : "things"}` : "Status");
}

async function openAccount(signOut) {
  const anchor = $("account");
  const info = await loadBuild();
  openMenu(anchor, {
    placement: "right-end",
    label: "Account",
    header: { title: "Admin", subtitle: `${location.host} · admin token` },
    items: [
      { info: true, glyph: "info", label: info.title, sub: info.commit },
      {
        glyph: "dns",
        label: "Server status",
        sub: WORDS[signal.state],
        onSelect: () => {
          location.hash = "#status";
        },
      },
      { separator: true },
      {
        glyph: "logout",
        label: "Sign out",
        onSelect: () => confirmSignOut(signOut),
      },
    ],
  });
}

function confirmSignOut(signOut) {
  return confirmDialog({
    title: "Sign out of the admin page?",
    message: "This browser forgets the admin token. To open the page again you need the token.",
    action: "Sign out",
    run: () => {
      // Not awaited: the sign-in screen waits for the token, and the dialog closes now.
      signOut();
    },
  });
}

/** Wires the rail once; `signOut` forgets the token and shows the sign-in screen. */
export function initShell(signOut) {
  $("account").addEventListener("click", () => openAccount(signOut));
  onSignal(paintStatus);
  paintStatus();
}
