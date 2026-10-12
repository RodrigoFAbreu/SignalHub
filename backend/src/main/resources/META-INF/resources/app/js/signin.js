// Signing in: the page shows a QR code, the app scans it and a person approves in the app. There
// are no passwords (docs/architecture.md#signing-in-a-browser). The poll secret lives in this
// module's variables only: never on screen, in the address, or in any storage.

import qrcode from "../vendor/qrcode.mjs";
import { ApiError, calls } from "./api.js";
import { el, icon, replace } from "./dom.js";
import { countdown } from "./format.js";
import { button, qrSvg, reducedMotion, spinner } from "./ui.js";

// The server's codes live three minutes. The page asks for new ones by itself, up to five
// times, then says it stopped waiting so an abandoned tab does not keep asking.
const MAX_REFRESHES = 5;
// A cancel in the app is noticed by polling; every 1.5 seconds is quick without being a load.
const POLL_MS = 1500;
const RETRY_MS = 4000;
// The server says "try again in a few minutes" when too many sign-ins wait.
const TOO_MANY_MS = 5 * 60 * 1000;
const SUCCESS_MS = 1000;

const phoneQuery = window.matchMedia("(max-width: 599.98px)");

const HEADINGS = {
  fresh: ["Sign in with your phone", "Open SignalHub on your phone, go to Settings › Sign in a browser, and scan this code."],
  again: ["Sign in again", "Your sign-in on this browser ended. Sign in with your phone and you'll come back to the page you were on."],
  signedout: ["You're signed out", "This browser isn't signed in. Sign in with your phone to use SignalHub here."],
};

const brand = () =>
  el("div", { class: "brand" }, el("span", { class: "logo" }, icon("sensors")), "SignalHub");

const wait = (text, remaining) =>
  el(
    "div",
    { class: "wait", role: "status" },
    spinner(),
    el("span", {}, text, remaining === undefined ? null : [" · ", el("span", { class: "cd", "aria-hidden": "true", text: remaining })]),
  );

/**
 * Shows the sign-in in `container`. `mode`: `fresh` (never signed in here), `again` (the
 * session ended while the page was in use) or `signedout` (revoked, or signed out). Calls
 * `onSignedIn(session)` a moment after the session exists. `peer` tells it that another tab
 * signed this browser in. Returns `{ stop, alreadySignedIn }`.
 */
export function mountSignIn(container, { mode, onSignedIn }) {
  let view = phoneQuery.matches ? "code" : "qr";
  let phase = "starting";
  let current = null;
  let deadline = 0;
  let refreshes = 0;
  let pollTimer = null;
  let tickTimer = null;
  let retryTimer = null;
  let stopped = false;
  let tooManyUntil = 0;
  let message = null;
  let session = null;
  let generation = 0;

  const root = el("div", { class: "signin-page" });
  container.replaceChildren(root);

  function clearTimers() {
    clearTimeout(pollTimer);
    clearInterval(tickTimer);
    clearTimeout(retryTimer);
  }

  function remaining() {
    return deadline - performance.now();
  }

  function uriFor(sign) {
    if (sign.uri?.startsWith("signalhub://")) return sign.uri;
    // The host did not set the address devices reach it at: the page's own address is where
    // the new browser should go, too.
    return `signalhub://signin?server=${encodeURIComponent(location.origin)}&code=${encodeURIComponent(sign.scanCode)}`;
  }

  // ---- The flow -----------------------------------------------------------------------

  async function begin() {
    clearTimers();
    const mine = ++generation;
    // An old code stays on screen, faded, until the new one replaces it.
    phase = current ? "refreshing" : "starting";
    paint();
    let started;
    try {
      started = await calls.startSignIn();
    } catch (error) {
      if (stopped || mine !== generation) return;
      if (error instanceof ApiError && error.status === 429) {
        phase = "tooMany";
        tooManyUntil = performance.now() + TOO_MANY_MS;
        paint();
        tickTimer = setInterval(tickTooMany, 500);
      } else {
        phase = "offline";
        paint();
        retryTimer = setTimeout(begin, RETRY_MS);
      }
      return;
    }
    if (stopped || mine !== generation) return;
    const { result, date } = started;
    // The server's Date header is the instant it set expiresAt from, so the codes' life is
    // measured by the server's clock alone; the page's clock may be off, and is only a fallback.
    const serverNow = date ? Date.parse(date) : Date.now();
    deadline = performance.now() + (Date.parse(result.expiresAt) - serverNow);
    current = result;
    phase = "waiting";
    paint();
    tickTimer = setInterval(tick, 250);
    pollTimer = setTimeout(poll, POLL_MS);
  }

  function tick() {
    const left = remaining();
    for (const node of root.querySelectorAll(".cd")) node.textContent = countdown(left);
    if (left <= 0 && phase === "waiting") runOut();
  }

  function tickTooMany() {
    const left = tooManyUntil - performance.now();
    if (left <= 0) {
      clearInterval(tickTimer);
      paint();
      return;
    }
    for (const node of root.querySelectorAll(".cd")) node.textContent = countdown(left);
  }

  // The codes ran out, or the server says so: ask for new ones, unless it has been enough.
  function runOut() {
    clearTimers();
    if (refreshes >= MAX_REFRESHES) {
      phase = "stopped";
      paint();
      return;
    }
    refreshes += 1;
    phase = "refreshing";
    paint();
    retryTimer = setTimeout(begin, reducedMotion() ? 200 : 600);
  }

  async function poll() {
    if (stopped || !current) return;
    const mine = generation;
    let polled;
    try {
      polled = await calls.pollSignIn(current.id, current.pollSecret);
    } catch (error) {
      if (stopped || mine !== generation) return;
      if (error instanceof ApiError && error.status === 401) {
        // Unknown to the server now (it forgot the sign-in): the same as one that ran out.
        runOut();
        return;
      }
      phase = "offline";
      paint();
      pollTimer = setTimeout(poll, RETRY_MS);
      return;
    }
    if (stopped || mine !== generation) return;
    if (phase === "offline") {
      phase = "waiting";
      paint();
    }
    switch (polled.state) {
      case "SIGNED_IN":
        await signedIn();
        return;
      case "CANCELLED":
        clearTimers();
        phase = "cancelled";
        paint();
        return;
      case "EXPIRED":
        runOut();
        return;
      default:
        pollTimer = setTimeout(poll, POLL_MS);
    }
  }

  async function signedIn() {
    clearTimers();
    try {
      session = await calls.session();
    } catch {
      // The cookie did not take (blocked cookies): ask again, for a code that works.
      phase = "noCookie";
      paint();
      return;
    }
    phase = "success";
    paint();
    retryTimer = setTimeout(() => onSignedIn(session), reducedMotion() ? 300 : SUCCESS_MS);
  }

  function restart() {
    refreshes = 0;
    begin();
  }

  // ---- The page -----------------------------------------------------------------------

  function qrBlock(size) {
    const wrap = el("div", { class: "qrwrap" });
    if (!current) {
      const placeholder = el("div", { class: "qr placeholder" });
      placeholder.style.width = `${size}px`;
      placeholder.style.height = `${size}px`;
      wrap.append(placeholder);
      return wrap;
    }
    const code = qrSvg(qrcode, uriFor(current), {
      size,
      label: "Sign-in QR code. To sign in without scanning, use a code instead.",
    });
    code.classList.add("fresh");
    wrap.append(code);
    if (phase === "refreshing") {
      code.classList.add("stale");
      code.setAttribute("aria-label", "Sign-in QR code, expired");
      wrap.append(el("div", { class: "qrover" }, icon("timer_off"), "This code ran out"));
    }
    return wrap;
  }

  function codeBox() {
    return el("div", { class: "code", text: current?.code ?? "" });
  }

  function statusCard(glyph, title, text, action, tone = "n") {
    return el(
      "div",
      { class: "card" },
      el("span", { class: `okmark ${tone}` }, icon(glyph)),
      el("h1", { class: "h", text: title }),
      el("p", { class: "p", text }),
      action ?? null,
    );
  }

  function waitingCard() {
    const phone = phoneQuery.matches;
    const [heading, text] = HEADINGS[mode];
    const switchTo = (next) => {
      view = next;
      paint();
      root.querySelector(".link")?.focus();
    };
    const waitLine =
      phase === "refreshing"
        ? wait("Making a new code…")
        : wait(view === "code" && phone ? "Waiting for the app" : "Waiting for your phone", phase === "waiting" ? countdown(remaining()) : undefined);

    if (view === "code") {
      const openApp = current
        ? el("a", { class: "btn btn-f full", href: uriFor(current) }, icon("open_in_new"), el("span", { class: "btn-label", text: "Open the app" }))
        : null;
      if (phone) {
        return el(
          "div",
          { class: "card phone-code" },
          brand(),
          el("h1", { class: "h", text: "Sign in with the app" }),
          el("p", { class: "p", text: "A phone can't scan its own screen, so type this code in the SignalHub app." }),
          codeBox(),
          waitLine,
          openApp,
          el("ol", { class: "steps" }, el("li", { text: "Open the app." }), el("li", { text: "Go to Settings › Sign in a browser." }), el("li", { text: 'Choose "Type a code" and enter the code above.' })),
          el("p", { class: "p small", text: "No app on this phone? Ask an admin of this server." }),
        );
      }
      return el(
        "div",
        { class: "card tight" },
        brand(),
        el("h1", { class: "h", text: "Sign in with a code" }),
        el("p", { class: "p", text: "Open SignalHub on your phone, go to Settings › Sign in a browser, choose Type a code and enter this code." }),
        codeBox(),
        waitLine,
        el("button", { type: "button", class: "link", on: { click: () => switchTo("qr") }, text: "Back to the QR code" }),
      );
    }
    return el(
      "div",
      { class: "card tight" },
      brand(),
      el("h1", { class: "h", text: heading }),
      el("p", { class: "p", text }),
      // The link comes first in the focus order and shows after the QR code.
      el("button", { type: "button", class: "link", on: { click: () => switchTo("code") }, text: "Use a code instead" }),
      qrBlock(mode === "fresh" ? 168 : 128),
      waitLine,
    );
  }

  function paint() {
    if (stopped) return;
    const phone = phoneQuery.matches;
    root.classList.toggle("phone-code-page", phase !== "success" && view === "code" && phone && ["waiting", "refreshing", "starting"].includes(phase));
    let card;
    switch (phase) {
      case "starting":
      case "waiting":
      case "refreshing":
        card = waitingCard();
        break;
      case "cancelled":
        card = statusCard("cancel", "Sign-in was cancelled", "Nothing was signed in on this browser.", button("Show a new code", { kind: "filled", onClick: restart }));
        break;
      case "tooMany": {
        const left = tooManyUntil - performance.now();
        const ready = left <= 0;
        card = statusCard("hourglass_top", "Too many tries", "Wait a few minutes, then try again.", ready ? button("Try again", { kind: "filled", onClick: restart }) : el("button", { type: "button", class: "btn btn-f off", disabled: true }, el("span", { class: "btn-label" }, "Try again in ", el("span", { class: "cd", text: countdown(left) }))));
        break;
      }
      case "offline":
        card = statusCard("cloud_off", "Can't reach SignalHub", "Check your connection. This page keeps trying.", [wait("Trying again…"), button("Try now", { glyph: "refresh", onClick: () => (current ? (clearTimeout(pollTimer), poll()) : (clearTimeout(retryTimer), begin())) })]);
        card.lastChild.classList.add("self-center");
        break;
      case "stopped":
        card = statusCard("schedule", "Still waiting for your phone", "This page stopped asking, so it doesn't wait forever.", button("Show a new code", { kind: "filled", onClick: restart }));
        break;
      case "noCookie":
        card = statusCard("cookie_off", "This browser did not keep the sign-in", "Allow this site to use cookies, then try again.", button("Show a new code", { kind: "filled", onClick: restart }));
        break;
      case "already":
        card = statusCard("check", "You're already signed in", `This browser is signed in${message ? ` as ${message}` : ""} in another tab.`, button("Open the inbox", { kind: "filled", onClick: () => onSignedIn(session) }), "");
        break;
      case "success":
        card = el(
          "div",
          { class: "card" },
          brand(),
          el("span", { class: "okmark" }, icon("check")),
          el("h1", { class: "h center", text: `Signed in as ${session.client.user.name}` }),
          el("p", { class: "p center", text: "Opening your inbox…" }),
          el("div", { class: "wait" }, spinner()),
        );
        break;
      default:
        card = wait("Checking…");
    }
    replace(root, card);
  }

  // A phone-width page shows the typed code; a wider one the QR code, until asked otherwise.
  function onViewport() {
    view = phoneQuery.matches ? "code" : "qr";
    paint();
  }
  phoneQuery.addEventListener("change", onViewport);

  begin();

  return {
    stop() {
      stopped = true;
      generation += 1;
      clearTimers();
      phoneQuery.removeEventListener("change", onViewport);
    },
    /** Another tab of this browser signed in: this page has nothing left to do. */
    alreadySignedIn(name, existing) {
      clearTimers();
      generation += 1;
      message = name;
      session = existing;
      phase = "already";
      paint();
    },
  };
}

/** The neutral page shown while a request decides whether the session is still there. */
export function checkingPage() {
  return el("div", { class: "signin-page checking" }, wait("Checking…"));
}
