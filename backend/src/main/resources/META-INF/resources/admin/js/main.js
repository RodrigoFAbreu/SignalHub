// The admin page: sign in, then the section named in the address. Sections are kept in the
// address's fragment (#devices, #producers/<id>, ...), so a reload stays where the operator was.
// The admin token lives only in api.js; nothing here stores it.

import { forget, signedIn, whenSessionLost } from "./api.js";
import { clearSnack } from "./ui.js";
import { parseHash, keepAddress } from "./router.js";
import { check, setFull, start, stop } from "./signal.js";
import { initShell, setCurrent, setDetailOpen, forgetBuild } from "./shell.js";
import { requestSignIn } from "./signin.js";
import { clearStore } from "./store.js";
import { devicesSection } from "./devices.js";
import { producersSection } from "./producers.js";
import { statusSection } from "./status.js";
import { eventsSection } from "./events.js";
import { usersSection } from "./users.js";

const $ = (id) => document.getElementById(id);

const SECTIONS = {
  devices: devicesSection,
  users: usersSection,
  producers: producersSection,
  events: eventsSection,
  status: statusSection,
};

let current = null;
let routing = Promise.resolve();

function route() {
  if (!signedIn()) return;
  const where = parseHash();
  if (!where.known) keepAddress(`#${where.section}`);
  const next = SECTIONS[where.section];
  if (current?.name !== where.section) {
    clearSnack();
    current?.section.unmount();
    setDetailOpen(false);
    current = { name: where.section, section: next };
    setFull(where.section === "status");
    setCurrent(where.section);
    next.mount({ container: $("sect"), route: where });
  } else {
    next.update(where);
  }
}

window.addEventListener("hashchange", () => {
  routing = routing.then(route);
});

function leave() {
  stop();
  current?.section.unmount();
  current = null;
  clearSnack();
  clearStore();
  forgetBuild();
  forget();
  $("app").hidden = true;
}

async function signInAgain(reason) {
  leave();
  if (reason === "signedOut") keepAddress(location.pathname + location.search);
  await enter(reason);
}

async function enter(reason) {
  await requestSignIn($("signin"), reason);
  $("app").hidden = false;
  start();
  route();
}

// A 401 while signed in: back to sign-in, keeping the section and what was open in the address.
let ending = false;
whenSessionLost(() => {
  if (ending) return;
  ending = true;
  signInAgain("lost").finally(() => {
    ending = false;
  });
});

initShell(() => signInAgain("signedOut"));
enter("first");

export { check };
