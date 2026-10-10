// Devices, and the browsers signed in from them. What a row offers follows the person's role and
// the server's rules (docs/architecture.md#device-management-from-a-device); nothing is drawn
// as a disabled button, what a role cannot do is simply not there.

import { ApiError, SessionEnded, calls } from "./api.js";
import { el, icon, replace } from "./dom.js";
import { count, isoDate, lastActive, possessive } from "./format.js";
import { failureMessage } from "./messages.js";
import { paneHeader } from "./parts.js";
import { state } from "./state.js";
import { announce, banner, bannerSlot, button, confirmDialog, emptyState, hideBanner, iconButton, noticeBox, openDialog, openMenu, sectionLabel, showBanner, skeletonRows, tag, textField } from "./ui.js";

export const ADMIN_DEVICE_MESSAGE = "That's an admin device. Admin devices are managed on the admin page.";
export const LAST_ACTIVE_MESSAGE = "It's your last active device. Revoking it would lock you out. Connect another device first.";

export const isBrowser = (device) => device.kind === "BROWSER";
const isThisBrowser = (device) => device.id === state.me.clientId;
const isMine = (device) => !device.user || device.user.id === state.me.userId;

/** What this person may do with a device, from their role and what the device is. */
export function allowed(device) {
  if (isThisBrowser(device)) return { rename: false, revoke: false, remove: false };
  const role = state.me.role;
  // Any role changes its own browsers, an admin's included.
  const ownBrowser = isBrowser(device) && isMine(device);
  if (ownBrowser) return { rename: !device.revokedAt, revoke: !device.revokedAt, remove: Boolean(device.revokedAt) };
  if (role === "BASIC" || device.admin) return { rename: false, revoke: false, remove: false };
  if (role === "MOD" && !isMine(device)) return { rename: false, revoke: false, remove: false };
  return { rename: !device.revokedAt, revoke: !device.revokedAt, remove: Boolean(device.revokedAt) };
}

/** One line under a device's name. */
export function activity(device) {
  if (device.revokedAt) return `Revoked ${isoDate(device.revokedAt)}`;
  if (isBrowser(device)) {
    const since = `Signed in ${isoDate(device.createdAt)}`;
    return isThisBrowser(device) && device.expiresAt ? `${since} · until ${isoDate(device.expiresAt)}` : since;
  }
  return lastActive(device.lastActiveAt);
}

export function summaryOf(devices) {
  const active = devices.filter((device) => !device.revokedAt);
  if (!active.length) return "No devices";
  const browsers = active.filter(isBrowser).length;
  return [count(active.length, "device"), browsers ? count(browsers, "browser") : null].filter(Boolean).join(" · ");
}

/**
 * A device as a row: the icon (a globe for a browser), the name with its tags, one line of
 * activity, then what this role can do. `reload` re-reads the list after a change.
 */
export function deviceRow(device, { reload, report }) {
  const can = allowed(device);
  const browser = isBrowser(device);
  const tags = [];
  if (device.admin && !device.revokedAt && !browser) tags.push(tag("Admin device", "me"));
  if (browser) tags.push(isThisBrowser(device) && !device.revokedAt ? tag("This browser", "me") : tag("Browser"));
  if (device.revokedAt) tags.push(tag("Revoked"));
  const trailing = [];
  if (can.revoke) trailing.push(button("Revoke", { kind: "text-error", ariaLabel: `Revoke ${device.name}`, onClick: () => revoke(device, { reload, report }) }));
  if (can.remove) trailing.push(button("Delete", { kind: "text-error", ariaLabel: `Delete ${device.name}`, onClick: () => remove(device, { reload, report }) }));
  if (can.rename || can.revoke) {
    const items = [];
    if (can.rename) items.push({ label: "Rename", glyph: "edit", onSelect: () => rename(device, { reload, report }) });
    if (can.revoke) items.push({ label: "Revoke", glyph: "block", danger: true, onSelect: () => revoke(device, { reload, report }) });
    const menu = iconButton("more_vert", `More actions for ${device.name}`, () => openMenu(menu, { items }), { aria: { "aria-haspopup": "menu", "aria-expanded": "false" } });
    trailing.push(menu);
  }
  return el(
    "div",
    { class: `lt device-row${device.revokedAt ? " revoked" : ""}`, data: { id: device.id } },
    el("span", { class: "av", "aria-hidden": "true" }, icon(browser ? "language" : "smartphone")),
    el("div", { class: "tx" }, el("span", { class: "t1" }, el("span", { class: "name", text: device.name }), ...tags), el("span", { class: "t2n", text: activity(device) })),
    ...trailing,
  );
}

function ownerOf(device) {
  const user = device.user;
  if (!user || user.id === state.me.userId) return { name: state.me.name, you: true };
  return { name: user.name, you: false };
}

async function revoke(device, ctx) {
  const owner = ownerOf(device);
  const browser = isBrowser(device);
  const message = browser
    ? owner.you
      ? "It is signed out at once and stops being a device of yours. You can sign it in again later from your phone."
      : `It is signed out at once and stops being a device of ${possessive(owner.name)}. ${owner.name} can sign it in again from their phone.`
    : owner.you
      ? "It stops getting events at once and can't be used again. To use it again, you have to connect it with a new code. Your other devices and the admins are told."
      : `It stops getting events at once and can't be used again. To use it again, ${owner.name} has to connect it with a new code. ${possessive(owner.name)} other devices and the admins are told.`;
  await change(ctx, device, `revoke ${device.name}`, {
    title: `Revoke ${device.name}?`,
    message,
    action: "Revoke",
    destructive: true,
    call: () => calls.revokeDevice(device.id),
  });
}

async function remove(device, ctx) {
  await change(ctx, device, `delete ${device.name}`, {
    title: `Delete ${device.name}?`,
    message: "It is removed from the list with its push history. Events stay. This can't be undone, and nobody is notified.",
    action: "Delete",
    destructive: true,
    call: () => calls.deleteDevice(device.id),
  });
}

// Asks first, then makes the call inside the dialog (its button busy, a failure said in it).
async function change(ctx, device, doing, { title, message, action, destructive, call }) {
  hideBanner("devices");
  const ok = await confirmDialog({
    title,
    message,
    action,
    destructive,
    run: async () => {
      try {
        await call();
      } catch (error) {
        if (error instanceof SessionEnded) throw error;
        throw new Error(await explain(error, device, doing));
      }
    },
  });
  if (ok) {
    announce(`${action === "Delete" ? "Deleted" : "Revoked"} ${device.name}`);
    await ctx.reload();
  }
}

// What a refusal means, said in words. The list is read again first: the device may have changed.
async function explain(error, device, doing) {
  if (error instanceof ApiError && (error.status === 409 || error.status === 404)) {
    if (device.admin && error.status === 409 && /admin device/i.test(error.message)) return ADMIN_DEVICE_MESSAGE;
    if (error.status === 409 && state.me.role === "MOD" && /last active/i.test(error.message)) return LAST_ACTIVE_MESSAGE;
    if (error.status === 404) return "That device was already removed.";
    if (/revoked/i.test(error.message)) return "That device is revoked, so its name can't change.";
    if (/not revoked/i.test(error.message)) return "That device isn't revoked, so it can't be deleted.";
  }
  return failureMessage(error, doing);
}

function rename(device, ctx) {
  const field = textField({ label: "Device name", value: device.name, hint: "1 to 100 characters. The device keeps working. Nobody is notified.", maxlength: 100 });
  let dialog;
  const refresh = () => {
    const text = field.input.value.trim();
    const empty = text === "";
    field.setError(empty ? "Enter a name." : null);
    dialog.save.node.disabled = empty || text === device.name;
  };
  const save = {
    label: "Save",
    value: true,
    disabled: true,
    run: async () => {
      try {
        await calls.renameDevice(device.id, field.input.value.trim());
      } catch (error) {
        if (error instanceof SessionEnded) throw error;
        throw new Error(await explain(error, device, `rename ${device.name}`));
      }
    },
  };
  dialog = openDialog({ title: "Rename device", content: field.node, actions: [{ label: "Cancel", value: false }, save], initialFocus: true });
  dialog.save = save;
  field.input.addEventListener("input", refresh);
  field.input.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !save.node.disabled) save.node.click();
  });
  field.input.focus();
  field.input.select();
  refresh();
  dialog.done.then(async (value) => {
    if (value === true) await ctx.reload();
  });
}

export { rename as renameDevice };

// ---- The Devices page ---------------------------------------------------------------------

const ORDER = { ADMIN: 2, MOD: 1, BASIC: 0 };

/** Devices in the order of the lists: this browser, the active ones, then the revoked. */
export function ordered(devices) {
  return [...devices.filter(isThisBrowser), ...devices.filter((d) => !isThisBrowser(d) && !d.revokedAt), ...devices.filter((d) => !isThisBrowser(d) && d.revokedAt)];
}

export function mountDevices(container, route, { wide }) {
  let devices = null;
  let phase = "loading";
  let gone = false;
  const body = el("div", { class: "devices-body" });
  const header = paneHeader({ title: "Devices", back: "#settings" });
  const pane = el("section", { class: "detp solo flush", "aria-label": "Devices" }, header, bannerSlot(), body);
  container.className = "main";
  replace(container, pane);

  const ctx = { reload: () => load(true), report: (text) => showBanner("devices", () => banner({ glyph: "error", error: true, role: "alert", text })) };

  async function load(quiet = false) {
    if (!quiet && !devices) {
      phase = "loading";
      paint();
    }
    try {
      devices = (await calls.devices()).items;
      phase = "ready";
      hideBanner("devices-offline");
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      if (devices) showBanner("devices-offline", () => banner({ glyph: "cloud_off", text: "Couldn't refresh. This is the list from earlier." }));
      else phase = "failed";
    }
    if (!gone) paint();
  }

  function groupsOf(list) {
    const byUser = new Map();
    for (const device of list) {
      const key = device.user?.id ?? "";
      if (!byUser.has(key)) byUser.set(key, { user: device.user ?? null, devices: [] });
      byUser.get(key).devices.push(device);
    }
    const me = state.me.userId;
    return [...byUser.values()].sort((a, b) => {
      if (a.user?.id === me || b.user?.id === me) return a.user?.id === me ? -1 : 1;
      return (ORDER[b.user?.role] ?? 0) - (ORDER[a.user?.role] ?? 0) || (a.user?.name ?? "").toLowerCase().localeCompare((b.user?.name ?? "").toLowerCase());
    });
  }

  function paint() {
    if (phase === "loading") {
      replace(body, skeletonRows(4));
      return;
    }
    if (phase === "failed") {
      replace(body, emptyState({ glyph: "error_outline", title: "Couldn't load devices", body: "Check your connection and try again.", action: button("Try again", { kind: "filled", glyph: "refresh", onClick: () => load() }) }));
      return;
    }
    const role = state.me.role;
    const rows = [];
    if (role === "ADMIN") {
      for (const group of groupsOf(devices)) {
        const you = group.user?.id === state.me.userId;
        rows.push(el("div", { class: "rolesec", role: "heading", "aria-level": "2" }, group.user?.name ?? "Devices", you ? tag("You", "me") : null));
        for (const device of ordered(group.devices)) rows.push(deviceRow(device, ctx));
      }
    } else {
      rows.push(sectionLabel("Your devices"));
      for (const device of ordered(devices.filter(isMine))) rows.push(deviceRow(device, ctx));
    }
    if (role === "BASIC") {
      rows.push(el("div", { class: "pad" }, noticeBox({ glyph: "info", text: "To add or remove a device, ask an admin of this server." })));
    }
    replace(body, rows);
  }

  paint();
  load();
  return {
    update() {},
    refresh: () => load(true),
    unmount() {
      gone = true;
      hideBanner("devices");
      hideBanner("devices-offline");
    },
  };
}
