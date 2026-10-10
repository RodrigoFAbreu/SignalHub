// People, for an admin: everyone on the server by role, a person's page with their role, devices
// and producers, and inviting someone with a pairing code. Only an admin's session reaches the
// calls behind this; for anyone else the address is a page that isn't there.

import qrcode from "../vendor/qrcode.mjs";
import { ApiError, SessionEnded, calls } from "./api.js";
import { ordered, deviceRow, allowed } from "./devices.js";
import { el, icon, replace } from "./dom.js";
import { failureMessage, silent } from "./messages.js";
import { paneHeader, selectPrompt } from "./parts.js";
import { go } from "./router.js";
import { state } from "./state.js";
import {
  announce,
  avatar,
  banner,
  bannerSlot,
  button,
  confirmDialog,
  emptyState,
  hideBanner,
  iconButton,
  label,
  noticeBox,
  openDialog,
  qrSvg,
  segmented,
  sectionLabel,
  showBanner,
  skeletonRows,
  tag,
  textField,
} from "./ui.js";

const EXPLANATION = {
  ADMIN: "Manage people and their devices, except other admins. Set on the admin page.",
  MOD: "Manage their own devices, producers and subscriptions.",
  BASIC: "Create producers and subscribe. Their devices are read only.",
};
const SECTION = { ADMIN: "Admins", MOD: "Mods", BASIC: "Basic" };

function summaryOf(person) {
  if (person.hasPaired === false) return "Invited · not paired yet";
  if (person.activeDevices === undefined || person.activeDevices === null) return null;
  return person.activeDevices === 0 ? "No devices" : person.activeDevices === 1 ? "1 device" : `${person.activeDevices} devices`;
}

export function mountPeople(container, route, { wide }) {
  let selected = route.segments[1] ?? null;
  let people = null;
  let phase = "loading";
  let query = "";
  let searching = false;
  let loadedAt = null;
  let gone = false;
  let token = 0;

  const header = el("div", { class: "head-host" });
  const searchHost = el("div", { class: "search-host" });
  const listHost = el("div", { class: "list-host" });
  const invite = el("button", { type: "button", class: "fab", on: { click: () => inviteDialog() } }, icon("person_add"), el("span", { text: "Invite" }));
  const listPane = el("section", { class: "listp", "aria-label": "People" }, header, searchHost, bannerSlot(), listHost, invite);
  const detail = el("section", { class: "detp", "aria-label": "Person" });
  container.className = `main${selected ? " has-detail" : ""}`;
  replace(container, listPane, detail);

  // ---- The list -------------------------------------------------------------------------

  async function load(quiet = false) {
    if (!quiet && !people) {
      phase = "loading";
      paintList();
    }
    try {
      people = (await calls.users()).items;
      phase = "ready";
      loadedAt = new Date();
      hideBanner("people");
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      if (people) showBanner("people", () => banner({ glyph: "cloud_off", text: "Couldn't refresh. This is the list from earlier.", actions: [button("Try again", { onClick: () => load(true) })] }));
      else phase = "failed";
    }
    if (gone) return;
    paintList();
    if (selected) paintDetail();
  }

  function paintHeader() {
    replace(
      header,
      paneHeader({
        title: "People",
        account: !wide,
        actions: [iconButton("search", "Search people", () => { searching = !searching; if (!searching) query = ""; paintHeader(); paintList(); }, { aria: { "aria-expanded": String(searching) } })],
      }),
    );
    if (searching) {
      const input = el("input", { type: "search", class: "search-input", placeholder: "Search people", "aria-label": "Search people", autocomplete: "off", spellcheck: "false" });
      input.value = query;
      input.addEventListener("input", () => { query = input.value.trim(); paintList(); });
      replace(searchHost, el("div", { class: "search" }, icon("search"), input));
      input.focus();
    } else {
      clearHost();
    }
  }
  const clearHost = () => replace(searchHost);

  function paintList() {
    if (phase === "loading") {
      replace(listHost, skeletonRows(6, { circle: true }));
      return;
    }
    if (phase === "failed") {
      replace(listHost, emptyState({ glyph: "error_outline", title: "Couldn't load people", body: "Check your connection and try again.", action: button("Try again", { kind: "filled", glyph: "refresh", onClick: () => load() }) }));
      return;
    }
    const needle = query.toLowerCase();
    const matches = (person) => !needle || person.name.toLowerCase().includes(needle);
    if (needle && !people.some(matches)) {
      replace(listHost, emptyState({ glyph: "search_off", title: `No one matches "${query}".` }));
      return;
    }
    const sections = [];
    for (const role of ["ADMIN", "MOD", "BASIC"]) {
      const all = people.filter((person) => person.role === role);
      if (!all.length) continue;
      const shown = all.filter(matches);
      sections.push(sectionLabel(SECTION[role], needle ? `${shown.length} of ${all.length}` : all.length));
      if (!needle) sections.push(el("div", { class: "rolesub", text: EXPLANATION[role] }));
      else if (!shown.length) sections.push(el("div", { class: "rolesub", text: "No one matches." }));
      for (const person of shown) sections.push(personRow(person));
    }
    replace(listHost, el("div", { class: "people-list" }, sections));
  }

  function personRow(person) {
    const you = person.id === state.me.userId;
    const sel = person.id === selected;
    const summary = summaryOf(person);
    return el(
      "a",
      { class: `lt prow${sel ? " sel" : ""}`, href: `#people/${encodeURIComponent(person.id)}`, "aria-current": sel ? "true" : null },
      avatar(person.name, { primary: you }),
      el("div", { class: "tx" }, el("span", { class: "t1" }, el("span", { class: "name", text: person.name }), you ? tag("You", "me") : null), summary ? el("span", { class: "t2n", text: summary }) : null),
    );
  }

  // ---- A person -------------------------------------------------------------------------

  async function paintDetail() {
    container.className = `main${selected ? " has-detail" : ""}`;
    paintListSelection();
    if (!selected) {
      replace(detail, wide ? selectPrompt("group", "Select a person", "Pick one from the list to see their role, devices and producers.") : null);
      return;
    }
    const person = people?.find((p) => p.id === selected);
    if (!person) {
      if (phase === "loading") {
        replace(detail, wide ? null : paneHeader({ title: "Person", back: "#people" }), skeletonRows(3));
        return;
      }
      replace(
        detail,
        wide ? null : paneHeader({ title: "Person", back: "#people" }),
        emptyState({ glyph: "search_off", title: "This isn't here", body: "It may have been removed.", action: button("Back to People", { kind: "tonal", onClick: () => go("#people") }) }),
      );
      return;
    }
    const mine = ++token;
    const you = person.id === state.me.userId;
    const isAdminPerson = person.role === "ADMIN";
    const devicesHost = el("div", { class: "person-devices" }, skeletonRows(1));
    const producersHost = el("div", { class: "person-producers" }, skeletonRows(1));
    const parts = [];
    parts.push(
      wide
        ? el("h2", { class: "h", text: person.name }, you ? tag("You", "me") : null)
        : paneHeader({ title: person.name, back: "#people" }),
      el("span", { class: "t2n", text: SECTION[person.role] === "Basic" ? "Basic" : person.role === "MOD" ? "Mod" : "Admin" }),
      label("Role"),
    );
    if (isAdminPerson) {
      parts.push(el("span", { class: "t2n", text: "Admins are managed on the admin page, on the computer running SignalHub." }));
    } else {
      parts.push(
        segmented({
          label: "Role",
          className: "role-seg",
          value: person.role,
          options: [
            { value: "BASIC", label: "Basic", glyph: "check" },
            { value: "MOD", label: "Mod", glyph: "check" },
            { value: "ADMIN", label: "Admin", disabled: true, name: "Admin, not available. Set on the admin page" },
          ],
          onChange: (role) => changeRole(person, role),
        }),
        el("span", { class: "t2n", text: "Admin is set on the admin page, on the computer running SignalHub." }),
      );
    }
    parts.push(label("Devices"), devicesHost);
    if (person.hasPaired === false || person.activeDevices === 0) {
      parts.push(el("div", { class: "row" }, button(`Pair a device for ${person.name}`, { kind: "outlined", glyph: "add", onClick: () => pairDialog(person) })));
    }
    parts.push(label("Producers"), producersHost);
    replace(detail, ...parts);
    fillDevices(person, devicesHost, mine);
    fillProducers(person, producersHost, mine);
  }

  function paintListSelection() {
    for (const link of listHost.querySelectorAll("a.prow")) {
      const on = link.getAttribute("href") === `#people/${encodeURIComponent(selected ?? "")}`;
      link.classList.toggle("sel", on);
      link.toggleAttribute("aria-current", on);
    }
  }

  async function fillDevices(person, host, mine) {
    const ctx = { reload: () => fillDevices(person, host, ++token), report: () => {} };
    try {
      const all = (await calls.devices()).items.filter((device) => device.user?.id === person.id);
      if (gone || mine !== token) return;
      replace(host, all.length ? ordered(all).map((device) => deviceRow(device, ctx)) : el("span", { class: "t2n", text: "No devices." }));
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      replace(host, el("div", { class: "inline-failure" }, el("span", { class: "p", text: "Couldn't load devices." }), button("Try again", { onClick: () => fillDevices(person, host, ++token) })));
    }
  }

  async function fillProducers(person, host, mine) {
    try {
      const { items } = await calls.userProducers(person.id);
      if (gone || mine !== token) return;
      replace(
        host,
        items.length
          ? items.map((producer) =>
              el("div", { class: "lt" }, el("span", { class: "av", "aria-hidden": "true" }, icon("sensors")), el("div", { class: "tx" }, el("span", { class: "t1", text: producer.name }), el("span", { class: "t2n", text: producer.disabled ? `${producer.visibility === "PUBLIC" ? "Public" : "Private"} · Disabled` : producer.visibility === "PUBLIC" ? "Public" : "Private" }))),
            )
          : el("span", { class: "t2n", text: `${person.name} has no producers.` }),
      );
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      replace(host, el("div", { class: "inline-failure" }, el("span", { class: "p", text: "Couldn't load their producers." }), button("Try again", { onClick: () => fillProducers(person, host, token) })));
    }
  }

  async function changeRole(person, role) {
    const basic = role === "BASIC";
    const ok = await confirmDialog({
      title: basic ? `Make ${person.name} a Basic user?` : `Make ${person.name} a Mod?`,
      message: basic
        ? `${person.name} will no longer be able to connect, rename or revoke devices. Their producers and subscriptions stay. It applies on their next action.`
        : `${person.name} will be able to connect, rename, revoke and delete their own devices.`,
      action: basic ? "Make Basic" : "Make Mod",
      run: async () => {
        try {
          await calls.setRole(person.id, role);
        } catch (error) {
          if (error instanceof SessionEnded) throw error;
          if (error instanceof ApiError && error.status === 409) throw new Error(`${person.name} is an admin, or their access was removed. Roles of admins are set on the admin page.`);
          throw new Error(failureMessage(error, "change the role"));
        }
      },
    });
    if (ok) {
      await load(true);
    }
  }

  // ---- Inviting -------------------------------------------------------------------------

  function inviteDialog() {
    let role = "BASIC";
    let deviceEdited = false;
    const name = textField({ label: "Their name", maxlength: 100 });
    const device = textField({ label: "First device name", maxlength: 100 });
    const roleHost = el("div", { class: "role-host" });
    const paintRole = () =>
      replace(
        roleHost,
        segmented({
          label: "Role",
          value: role,
          options: [
            { value: "BASIC", label: "Basic", glyph: "check" },
            { value: "MOD", label: "Mod", glyph: "check" },
            { value: "ADMIN", label: "Admin", disabled: true, name: "Admin, not available. Set on the admin page" },
          ],
          onChange: (value) => { role = value; paintRole(); },
        }),
      );
    paintRole();
    let dialog;
    const refresh = () => {
      const typed = name.input.value.trim();
      if (!deviceEdited) device.input.value = typed ? `${typed} - phone` : "";
      dialog.make.node.disabled = !typed;
    };
    name.input.addEventListener("input", () => { name.setError(null); refresh(); });
    device.input.addEventListener("input", () => { deviceEdited = true; });
    const make = {
      label: "Make invitation",
      kind: "filled",
      value: "made",
      disabled: true,
      run: async (controller) => {
        const typed = name.input.value.trim();
        let made;
        try {
          made = await calls.inviteUser(typed, role, device.input.value.trim());
        } catch (error) {
          if (error instanceof SessionEnded) throw error;
          if (error instanceof ApiError && error.status === 409) {
            name.setError("Someone on this server already has that name. Use another.");
            throw silent();
          }
          throw new Error(failureMessage(error, "make the invitation"));
        }
        controller.made = made;
      },
    };
    dialog = openDialog({
      title: "Invite someone",
      content: el("div", { class: "invite-form" }, name.node, roleHost, el("p", { class: "p", text: "Basic: their own producers and subscriptions. Mod: also pairs and removes their own devices." }), device.node),
      actions: [{ label: "Cancel", value: false }, make],
      initialFocus: true,
    });
    dialog.make = make;
    name.input.focus();
    refresh();
    dialog.done.then(async (value) => {
      if (value !== "made") return;
      await load(true);
      if (dialog.made) await pairingDialog({ title: `Invite ${dialog.made.user.name}`, person: dialog.made.user, pairing: dialog.made.pairing });
      await load(true);
    });
  }

  async function pairDialog(person) {
    const field = textField({ label: "Device name", value: `${person.name} - phone`, maxlength: 100 });
    const make = {
      label: "Make code",
      kind: "filled",
      value: "made",
      run: async (controller) => {
        try {
          controller.pairing = await calls.createPairing(person.id, field.input.value.trim());
        } catch (error) {
          if (error instanceof SessionEnded) throw error;
          throw new Error(failureMessage(error, "make the code"));
        }
      },
    };
    const dialog = openDialog({ title: `Pair a device for ${person.name}`, content: field.node, actions: [{ label: "Cancel", value: false }, make], initialFocus: true });
    field.input.focus();
    field.input.select();
    dialog.done.then(async (value) => {
      if (value === "made" && dialog.pairing) await pairingDialog({ title: `Pair a device for ${person.name}`, person, pairing: dialog.pairing });
      await load(true);
    });
  }

  // ---- Public ---------------------------------------------------------------------------

  paintHeader();
  paintList();
  paintDetail();
  load();

  return {
    update(next) {
      selected = next.segments[1] ?? null;
      paintDetail();
    },
    refresh: () => load(true),
    unmount() {
      gone = true;
      hideBanner("people");
    },
  };
}

/**
 * The pairing code of a person's first device: a QR code to scan, the link to paste, and a line
 * that says when the code was used or ran out. It works once and runs out in 10 minutes.
 */
function pairingDialog({ title, person, pairing }) {
  const uri = pairing.uri && pairing.uri.startsWith("signalhub://") ? pairing.uri : `signalhub://pair?server=${encodeURIComponent(location.origin)}&code=${encodeURIComponent(pairing.code)}`;
  const status = el("p", { class: "p dlg-text pairing-status", role: "status", text: "" });
  const copy = button("Copy link", { kind: "outlined", glyph: "content_copy" });
  copy.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(uri);
      replace(copy, icon("check"), el("span", { class: "btn-label", text: "Copied" }));
      setTimeout(() => replace(copy, icon("content_copy"), el("span", { class: "btn-label", text: "Copy link" })), 2000);
    } catch {
      status.textContent = "Couldn't copy it. Select the link and copy it by hand.";
    }
  });
  const body = el(
    "div",
    { class: "pairing" },
    el("p", { class: "p dlg-text", text: `${person.name} opens the SignalHub app and scans this code, or pastes the link below. It works once and runs out in 10 minutes.` }),
    qrSvg(qrcode, uri, { size: 176, label: `Pairing QR code for ${person.name}` }),
    el("div", { class: "linkbox", text: uri }),
    el("div", { class: "row center" }, copy),
    noticeBox({ glyph: "info", text: `Whoever uses this code joins as ${person.name}. Share it only with ${person.name}.` }),
    status,
  );
  const dialog = openDialog({ title, content: body, actions: [{ label: "Done", value: true, kind: "filled" }], initialFocus: true });
  let timer;
  const poll = async () => {
    if (!pairing.id) return;
    try {
      const result = await calls.pairing(pairing.id);
      if (result.state === "REDEEMED") {
        status.textContent = `${person.name} joined${result.client ? ` on ${result.client.name}` : ""}. The code can't be used again.`;
        return;
      }
      if (result.state === "EXPIRED") {
        status.textContent = `This code ran out. Make a new one for ${person.name}; the old one no longer works.`;
        return;
      }
    } catch {
      // Not knowing is fine: the code stays on screen and the next ask may work.
    }
    timer = setTimeout(poll, 2500);
  };
  timer = setTimeout(poll, 2500);
  dialog.done.then(() => clearTimeout(timer));
  return dialog.done;
}
