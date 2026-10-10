// SignalHub's page for its users: starts the page, knows whether a session exists, and puts
// the screen the address names in the frame. Everything it shows comes from the client API, with
// the browser's own session; it never talks to another origin.

import { ApiError, SessionEnded, calls, setCsrfToken, whenSessionEnds } from "./api.js";
import { buildNavigation, setActiveDestination } from "./chrome.js";
import { el, icon, replace } from "./dom.js";
import { mountDevices } from "./devices.js";
import { mountInbox } from "./inbox.js";
import { mountPeople } from "./people.js";
import { mountProducers } from "./producers.js";
import { go, parseHash, replaceHash } from "./router.js";
import { mountSettings } from "./settings.js";
import { checkingPage, mountSignIn } from "./signin.js";
import { hooks, isAdmin, setMe, setRole, setUnread, state } from "./state.js";
import { banner, bannerSlot, button, emptyState, hideBanner, showBanner, spinner, wideQuery } from "./ui.js";

const root = document.getElementById("app");
const HAD_SESSION = "signalhub.web.hadSession";
const REFRESH_MS = 30_000;

let shell = null; // { main }
let screen = null; // { name, controller, wide }
let signIn = null;
let ended = false;
let refreshTimer = null;
let wasWide = wideQuery.matches;

// Other tabs of this browser share one session: tell them when it starts or ends.
const channel = "BroadcastChannel" in window ? new BroadcastChannel("signalhub-session") : null;
const tell = (message) => channel?.postMessage(message);

function remember(value) {
  // Only a hint for the words on the sign-in page (signed out, or a first visit); not secret.
  try {
    if (value) localStorage.setItem(HAD_SESSION, "1");
    else localStorage.removeItem(HAD_SESSION);
  } catch {
    // Storage may be blocked; the first-visit wording is used.
  }
}

function hadSession() {
  try {
    return localStorage.getItem(HAD_SESSION) === "1";
  } catch {
    return false;
  }
}

// ---- Boot and sign-in ----------------------------------------------------------------------

async function boot() {
  replace(root, checkingPage());
  let session;
  try {
    session = await calls.session();
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      showSignIn(hadSession() ? "signedout" : "fresh");
    } else {
      offlineAtStart();
    }
    return;
  }
  enter(session);
}

function offlineAtStart() {
  const retry = () => boot();
  const timer = setTimeout(retry, 4000);
  replace(
    root,
    el(
      "div",
      { class: "signin-page" },
      el(
        "div",
        { class: "card" },
        el("span", { class: "okmark n" }, icon("cloud_off")),
        el("h1", { class: "h", text: "Can't reach SignalHub" }),
        el("p", { class: "p", text: "Check your connection. This page keeps trying." }),
        el("div", { class: "wait", role: "status" }, spinner(), "Trying again…"),
        button("Try now", { glyph: "refresh", onClick: () => { clearTimeout(timer); retry(); } }),
      ),
    ),
  );
}

function showSignIn(mode) {
  teardownShell();
  signIn?.stop();
  const holder = el("div", { class: "signin-holder" });
  replace(root, holder);
  document.title = "Sign in · SignalHub";
  signIn = mountSignIn(holder, {
    mode,
    onSignedIn: (session) => {
      tell({ type: "signed-in" });
      enter(session);
    },
  });
}

function enter(session) {
  signIn?.stop();
  signIn = null;
  ended = false;
  setMe(session);
  setCsrfToken(session.csrfToken);
  remember(true);
  hideBanner("session");
  buildShell();
  if (!location.hash || location.hash === "#") replaceHash("#inbox");
  route(true);
  refreshUnread();
  clearInterval(refreshTimer);
  refreshTimer = setInterval(tick, REFRESH_MS);
}

function buildShell() {
  const nav = buildNavigation();
  const main = el("main", { class: "main", id: "main" });
  replace(root, nav, main);
  shell = { main };
}

function teardownShell() {
  clearInterval(refreshTimer);
  screen?.controller?.unmount?.();
  screen = null;
  shell = null;
  document.body.classList.remove("no-nav");
}

// ---- The session ends ----------------------------------------------------------------------

// A 401 on any call. After the 30 days the page says so and keeps what it shows; a session that
// was revoked (or signed out elsewhere) shows only "Checking…" and then the neutral signed-out
// page: the server answers both the same way, so the page tells no more than it knows.
whenSessionEnds(() => {
  if (ended || !shell) return;
  ended = true;
  clearInterval(refreshTimer);
  remember(true);
  const expiresAt = state.me?.expiresAt ? Date.parse(state.me.expiresAt) : null;
  if (expiresAt && Date.now() >= expiresAt) {
    showBanner("session", () => banner({ glyph: "lock_clock", text: "Your sign-in ended.", actions: [button("Sign in again", { onClick: () => showSignIn("again") })] }));
  } else {
    teardownShell();
    replace(root, checkingPage());
    setTimeout(() => showSignIn("signedout"), 450);
  }
});

hooks.signedOut = () => {
  tell({ type: "signed-out" });
  remember(true);
  ended = true;
  showSignIn("signedout");
};

channel?.addEventListener("message", async (event) => {
  const type = event.data?.type;
  if (type === "signed-out" && shell && !ended) {
    ended = true;
    clearInterval(refreshTimer);
    showBanner("session", () => banner({ glyph: "logout", text: "You signed out in another tab.", actions: [button("Sign in again", { onClick: () => showSignIn("again") })] }));
  } else if (type === "signed-in" && signIn) {
    try {
      const session = await calls.session();
      signIn?.alreadySignedIn(session.client.user.name, session);
    } catch {
      // Not signed in after all: this page keeps its own sign-in going.
    }
  }
});

// ---- Routing -------------------------------------------------------------------------------

const TITLES = { inbox: "Inbox", producers: "Producers", people: "People", settings: "Settings" };

function screenFor(route) {
  const [first, second] = route.segments;
  switch (first) {
    case "inbox":
      return route.segments.length <= 2 ? { name: "inbox", mount: mountInbox, update: true } : null;
    case "producers":
      return route.segments.length <= 2 ? { name: "producers", mount: mountProducers, update: true } : null;
    case "people":
      return isAdmin() && route.segments.length <= 2 ? { name: "people", mount: mountPeople, update: true } : null;
    case "settings":
      if (route.segments.length === 1) return { name: "settings", mount: mountSettings, update: false };
      if (route.segments.length === 2 && second === "devices") return { name: "settings/devices", mount: mountDevices, update: false, destination: "settings" };
      return null;
    default:
      return null;
  }
}

function route(force = false) {
  if (!shell) return;
  const wide = wideQuery.matches;
  const parsed = parseHash();
  if (!parsed.segments.length) {
    replaceHash("#inbox");
    return route(force);
  }
  const target = screenFor(parsed);
  const previous = screen;
  if (!target) {
    previous?.controller?.unmount?.();
    screen = { name: "not-found", controller: null, wide };
    setActiveDestination(null);
    document.body.classList.remove("no-nav");
    document.title = "Not found · SignalHub";
    paintNotFound(wide);
    return;
  }
  setActiveDestination(target.destination ?? target.name);
  document.title = `${target.name === "settings/devices" ? "Devices" : TITLES[target.name]} · SignalHub`;
  if (previous && previous.name === target.name && previous.wide === wide && !force && target.update) {
    previous.controller.update(parsed);
  } else {
    previous?.controller?.unmount?.();
    const controller = target.mount(shell.main, parsed, { wide });
    screen = { name: target.name, controller, wide };
  }
  // The first screen leaves focus where the browser put it (the top of the page: the rail first).
  if (previous && (previous.name !== target.name || (!wide && previous.depth !== parsed.segments.length))) focusHeading();
  screen.depth = parsed.segments.length;
}

function paintNotFound(wide) {
  shell.main.className = "main";
  replace(
    shell.main,
    el(
      "section",
      { class: "detp solo", "aria-label": "Not found" },
      bannerSlot(),
      emptyState({
        glyph: "search_off",
        title: "This page isn't here",
        body: "Check the address, or go back to your inbox.",
        action: button("Go to the inbox", { kind: "tonal", onClick: () => go("#inbox") }),
      }),
    ),
  );
  void wide;
}

// After moving to another screen, keyboard and screen reader users start at its heading.
function focusHeading() {
  requestAnimationFrame(() => {
    const heading = shell?.main.querySelector('.detp [tabindex="-1"], .listp [tabindex="-1"]');
    if (heading && heading.getClientRects().length && !document.querySelector('[role="dialog"]')) heading.focus({ preventScroll: true });
  });
}

window.addEventListener("hashchange", () => route());
wideQuery.addEventListener("change", () => {
  if (wasWide === wideQuery.matches) return;
  wasWide = wideQuery.matches;
  route(true);
});

// ---- Staying current -----------------------------------------------------------------------

async function refreshUnread() {
  try {
    const { unread } = await calls.unreadCount();
    setUnread(unread);
  } catch {
    // The badge keeps its last number; the screens say when the server cannot be reached.
  }
}

async function tick() {
  if (!shell || ended || document.visibilityState !== "visible") return;
  try {
    const session = await calls.session();
    // The role is the host's to change: People appears or goes with it.
    const before = state.me.role;
    setRole(session.client.user.role);
    if (before !== state.me.role) route(true);
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      // The session is over: the same path as any other 401.
      try {
        await calls.unreadCount();
      } catch {
        // SessionEnded already handled.
      }
      return;
    }
  }
  refreshUnread();
  try {
    await screen?.controller?.refresh?.();
  } catch (error) {
    if (!(error instanceof SessionEnded)) {
      // Each screen shows its own problems.
    }
  }
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") tick();
});
window.addEventListener("online", () => tick());

boot();
