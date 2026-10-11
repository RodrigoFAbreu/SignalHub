// Connect a device: one dialog (a name, a user) that leads, in the same place, to the pairing code:
// the QR, a link to copy, a countdown, and the two ways it ends (expired, or used by a named
// device). A code can be cancelled while it is unused, and the unused ones are listed in Devices.
// The code is shown only in this dialog: the server never lists it again.

import { ApiError, PAIRINGS, call } from "./api.js";
import { el, icon } from "./dom.js";
import { clock } from "./format.js";
import { loadUsers } from "./store.js";
import { announce, button, confirmDialog, openDialog, ROLES, selectField, snack, textField, userChoice } from "./ui.js";

const POLL_MS = 3000;
const QR_PIXELS = 416;
const LOW_SECONDS = 60;

/**
 * Opens the dialog. `user` fixes the user (when it is opened from a user); `onChange` is told when
 * a code was made, used or cancelled, so the lists behind it can be read again.
 */
export function connectDevice({ user = null, onChange = () => {} } = {}) {
  const name = textField({ label: "Device name", value: "New device", hint: "Up to 100 characters. The device can be renamed later.", maxlength: 100 });
  const choice = selectField({ label: "User", options: [], hint: "The device belongs to this user." });
  const adminNote = el("div", { class: "warn", hidden: true }, icon("admin_panel_settings"), el("div", {}, el("b", { text: "It will be an admin device." }), el("br"), "An admin device connects and revokes other devices and invites users. It is one exactly when its user is an admin."));
  let users = [];
  let create = null;

  const content = el(
    "div",
    {},
    el("p", { class: "p small-p", text: "Make a one-time pairing code. The device redeems it in the SignalHub app, or the user scans it." }),
    name.node,
    choice.node,
    adminNote,
  );

  const showAdmin = () => {
    const chosen = users.find((candidate) => candidate.id === choice.select.value);
    adminNote.hidden = chosen?.role !== "ADMIN";
  };
  const check = (blurred) => {
    const empty = name.input.value.trim() === "";
    name.setError(empty && blurred ? "Give the device a name." : "");
    create.disabled = empty || users.length === 0;
  };

  const dialog = openDialog({
    title: "Connect a device",
    content,
    variant: "full",
    focusNode: name.input,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Create pairing code",
        value: true,
        className: "confirm",
        disabled: true,
        keepOpen: true,
        run: async (controller) => {
          await make(controller, name.input.value.trim(), users.find((candidate) => candidate.id === choice.select.value));
        },
      },
    ],
  });
  create = dialog.actions[1].node;
  name.input.addEventListener("input", () => check(false));
  name.input.addEventListener("blur", () => check(true));
  name.input.select();
  choice.select.addEventListener("change", showAdmin);

  loadUsers().then(
    (all) => {
      users = user ? all.filter((candidate) => candidate.id === user.id) : all.filter((candidate) => !candidate.revokedAt);
      // Rodrigo first: the operator usually connects their own device.
      users.sort((a, b) => (b.role === "ADMIN") - (a.role === "ADMIN"));
      choice.select.replaceChildren(...users.map((candidate) => el("option", { value: candidate.id, text: userChoice(candidate) })));
      choice.select.disabled = Boolean(user);
      showAdmin();
      check(false);
    },
    (error) => {
      if (error.name !== "SessionEnded") dialog.error(`Could not read the users. ${error.message}`);
    },
  );

  // The code, then what became of it. Every timer stops when the dialog does.
  async function make(controller, deviceName, owner) {
    let pairing;
    try {
      pairing = await call("POST", PAIRINGS, { name: deviceName, userId: owner.id });
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) {
        choice.setError(error.message.includes("revoked") ? "User is revoked" : error.message);
        throw new ApiError("", "refused", 409);
      }
      throw error;
    }
    onChange();
    snack("Pairing code ready.");
    showCode(controller, pairing, owner);
  }

  function showCode(controller, pairing, owner) {
    let timer = null;
    let poller = null;
    let ended = false;
    const stop = () => {
      clearInterval(timer);
      clearInterval(poller);
      ended = true;
    };
    const who = `${owner.name} (${ROLES[owner.role] ?? owner.role})`;
    const total = Math.max(1, Date.parse(pairing.expiresAt) - Date.now());
    const bar = el("i", {});
    const meter = el("div", { class: "cd", "aria-hidden": "true" }, bar);
    const countdown = el("span", { class: "t1" });
    const waiting = el("span", { class: "t2", text: "Waiting for the device to use it…" });
    const status = el("span", { class: "t2", role: "status" });
    const canvas = el("canvas", { width: QR_PIXELS, height: QR_PIXELS, role: "img", "aria-label": "Pairing QR code" });
    const wrap = el("div", { class: "qrwrap" }, canvas);
    const right = el("div", { class: "rt" });
    let announcedMinute = null;

    const noLink = !pairing.uri;
    const copyCode = () => copy(pairing.code, "Code copied.", status);
    const copyLink = () => copy(pairing.uri, "Link copied.", status);

    const body = el("div", {});
    if (noLink) {
      body.append(
        el("div", { class: "bn neu" }, icon("link_off", "c-var"), el("div", { class: "tx", text: "No link or QR code this time: SignalHub does not know its public address. Type the code in the app (Connect with a code). To get a link and a QR code, set SIGNALHUB_PUBLIC_URL on the server to the address devices reach it at." })),
        el("div", { class: "key big-key", text: pairing.code }),
        el("div", {}, meter, countdown, el("br"), waiting, el("br"), status),
      );
    } else {
      draw(canvas, pairing.uri);
      right.append(
        el("span", { class: "big", text: "Scan it in the app" }),
        el("span", { class: "t2 med", text: `For ${who}. Open SignalHub on the phone, then Connect with a code.` }),
        meter,
        countdown,
        waiting,
        status,
        el("div", { class: "lnk", text: pairing.uri }),
        el("div", { class: "keyrow wrap" }, button("Copy link", { kind: "outlined", glyph: "link", onClick: copyLink }), button("Copy QR image", { kind: "outlined", glyph: "image", onClick: () => copyImage(canvas, status) }), button("Download QR", { kind: "outlined", glyph: "download", onClick: () => download(canvas, pairing.name) })),
      );
      body.append(el("div", { class: "pair" }, wrap, right));
    }
    body.append(el("div", { class: "warn" }, icon("warning"), el("div", { text: noLink ? `Anyone with this code can pair a device as ${owner.name} until it expires or is used.` : `Anyone with this code, its link or a picture of it can pair a device as ${owner.name} until it expires or is used.` })));

    const cancelCode = () =>
      confirmDialog({
        title: "Cancel this code?",
        message: "It can never be used then. A device that already scanned it is not affected: it has been paired, or it has not.",
        action: "Cancel this code",
        cancel: "Keep it",
        destructive: true,
        run: async () => {
          await call("DELETE", `${PAIRINGS}/${pairing.id}`);
          stop();
          onChange();
          snack("Pairing code cancelled.");
          controller.close(false);
        },
      });

    controller.replace({
      title: `Pairing code for ${pairing.name}`,
      content: body,
      actions: [
        ...(noLink ? [{ label: "Copy code", value: "copy", glyph: "content_copy", run: async () => copyCode(), keepOpen: true }] : []),
        { label: "Cancel this code", value: "cancel", kind: "text-error", run: async () => { await cancelCode(); }, keepOpen: true, className: "cancel-code" },
        { label: "Done", value: true, className: "confirm", run: async () => stop() },
      ],
      initialFocus: true,
    });
    controller.node.classList.add("wide");

    const tick = () => {
      const left = Date.parse(pairing.expiresAt) - Date.now();
      if (left <= 0) {
        stop();
        check().then(() => {
          if (!usedState) expired(controller, pairing, owner);
        });
        return;
      }
      const seconds = Math.ceil(left / 1000);
      const minutes = Math.floor(seconds / 60);
      countdown.textContent = `Expires in ${minutes}:${String(seconds % 60).padStart(2, "0")}. It works once.`;
      bar.style.width = `${Math.max(0, Math.min(100, (left / total) * 100))}%`;
      meter.classList.toggle("low", seconds <= LOW_SECONDS);
      // A screen reader hears the countdown at the minute marks only.
      if (seconds % 60 === 0 && announcedMinute !== minutes) {
        announcedMinute = minutes;
        announce(`The code expires in ${minutes} ${minutes === 1 ? "minute" : "minutes"}.`);
      }
    };
    let usedState = false;
    async function check() {
      let answer;
      try {
        answer = await call("GET", `${PAIRINGS}/${pairing.id}`);
      } catch {
        return; // Asked again at the next poll.
      }
      if (ended && !usedState && answer.state !== "REDEEMED") return;
      if (answer.state !== "REDEEMED" || usedState) return;
      usedState = true;
      stop();
      onChange();
      used(controller, pairing, owner, answer.client, answer.redeemedAt);
    }
    tick();
    timer = setInterval(tick, 1000);
    poller = setInterval(check, POLL_MS);
    controller.onEnd = stop;
  }

  function expired(controller, pairing, owner) {
    const canvas = el("canvas", { width: QR_PIXELS, height: QR_PIXELS, "aria-hidden": "true" });
    const body = el(
      "div",
      { class: "pair" },
      pairing.uri
        ? el("div", { class: "qrwrap old" }, canvas, el("div", { class: "qrover" }, icon("timer_off"), el("b", { text: "Expired" })))
        : null,
      el(
        "div",
        { class: "rt" },
        el("span", { class: "big", text: "This code expired" }),
        el("span", { class: "t2 med", text: "Nobody used it in time, and it no longer works. Make a new one for the same device and user." }),
        el("div", { class: "cd low", "aria-hidden": "true" }, el("i", { class: "empty-bar" })),
        el("span", { class: "t2", text: `Expired at ${clock(pairing.expiresAt)}.` }),
      ),
    );
    controller.replace({
      title: `Pairing code for ${pairing.name}`,
      content: body,
      actions: [
        { label: "Close", value: false },
        { label: "Make a new code", value: "again", glyph: "refresh", className: "confirm", keepOpen: true, run: async () => { await make(controller, pairing.name, owner); } },
      ],
      initialFocus: "again",
    });
  }

  function used(controller, pairing, owner, client, usedAt) {
    const who = `${owner.name} (${ROLES[owner.role] ?? owner.role})`;
    const body = el(
      "div",
      {},
      el(
        "div",
        { class: "okbox" },
        icon("check_circle"),
        el("div", {}, el("b", { text: `Used by “${client?.name ?? pairing.name}”, ${clock(usedAt ?? new Date())}.` }), el("br"), `${pairing.admin ? "An admin device. " : ""}The code worked once and is spent. The device belongs to ${who} and is connected; it gets pushes once the app has registered for them.`),
      ),
      el("p", { class: "p small-p spaced", text: `The name is the device's name now: it may have been renamed on the phone since. ${owner.name}'s other devices and the admins were told that it paired.` }),
    );
    controller.replace({
      title: "Device connected",
      content: body,
      actions: [
        {
          label: "Show the device",
          value: "show",
          run: async () => {
            if (client) location.hash = `#devices/${client.id}`;
          },
        },
        { label: "Done", value: true, className: "confirm" },
      ],
      initialFocus: true,
    });
    announce(`Device connected: ${client?.name ?? pairing.name}.`);
  }
}

// The QR, black modules on a white plate in both themes so a camera reads it.
function draw(canvas, text) {
  // Type 0 picks the smallest QR version that fits; level M survives a slightly blurry photo.
  const qr = window.qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const modules = qr.getModuleCount();
  const quiet = 4;
  const scale = Math.floor(QR_PIXELS / (modules + 2 * quiet));
  const offset = Math.floor((QR_PIXELS - scale * modules) / 2);
  const context = canvas.getContext("2d");
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, QR_PIXELS, QR_PIXELS);
  context.fillStyle = "#000000";
  for (let row = 0; row < modules; row++) {
    for (let col = 0; col < modules; col++) {
      if (qr.isDark(row, col)) context.fillRect(offset + col * scale, offset + row * scale, scale, scale);
    }
  }
}

/** Copies text, and says so; the clipboard needs a secure context (https or localhost). */
async function copy(text, done, status) {
  try {
    await navigator.clipboard.writeText(text);
    status.textContent = done;
  } catch {
    status.textContent = "Copy the selected text with Ctrl+C.";
    const target = [...document.querySelectorAll(".lnk, .big-key")].find((node) => node.textContent === text);
    if (target) {
      const range = document.createRange();
      range.selectNodeContents(target);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    }
  }
}

function pngBlob(canvas) {
  return new Promise((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png"));
}

async function copyImage(canvas, status) {
  if (!navigator.clipboard || typeof ClipboardItem === "undefined") {
    status.textContent = "This browser cannot copy images here. Use Download QR.";
    return;
  }
  try {
    await navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob(canvas) })]);
    status.textContent = "QR image copied.";
  } catch {
    status.textContent = "Could not copy the image. Use Download QR.";
  }
}

async function download(canvas, name) {
  const url = URL.createObjectURL(await pngBlob(canvas));
  const link = document.createElement("a");
  link.href = url;
  link.download = `signalhub-pairing-${name.replace(/[^\w.-]+/g, "_")}.png`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
