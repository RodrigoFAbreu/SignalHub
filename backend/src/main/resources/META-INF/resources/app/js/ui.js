// The design system's components (docs/design/users/DESIGN.md) as small functions.

import { clear, el, focusable, icon, replace, svg } from "./dom.js";

export const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Whether the page has room for the navigation rail and a list beside its detail. */
export const wideQuery = window.matchMedia("(min-width: 840px)");

let uid = 0;
export const nextId = (prefix) => `${prefix}-${++uid}`;

// ---- Buttons ---------------------------------------------------------------------------

const BUTTON_CLASS = {
  filled: "btn btn-f",
  tonal: "btn btn-t",
  outlined: "btn btn-o",
  text: "btn btn-x",
  "text-error": "btn btn-x er",
};

/** A pill button: `filled`, `tonal`, `outlined`, `text` or `text-error`. */
export function button(label, options = {}) {
  const { kind = "text", glyph, onClick, disabled, full, ariaLabel, type = "button", data } = options;
  const node = el(
    "button",
    {
      type,
      class: `${BUTTON_CLASS[kind]}${full ? " full" : ""}`,
      disabled,
      "aria-label": ariaLabel,
      data,
    },
    glyph ? icon(glyph) : null,
    el("span", { class: "btn-label", text: label }),
  );
  if (onClick) node.addEventListener("click", onClick);
  return node;
}

/** Shows a spinner in the button's icon slot and ignores presses, keeping its width. */
export function setBusy(node, busy) {
  node.toggleAttribute("aria-busy", busy);
  node.disabled = busy;
  node.classList.toggle("busy", busy);
}

/** A 48 px icon-only button; `label` is its accessible name. */
export function iconButton(glyph, label, onClick, options = {}) {
  const node = el(
    "button",
    { type: "button", class: `ib${options.class ? ` ${options.class}` : ""}`, "aria-label": label, disabled: options.disabled, ...(options.aria ?? {}) },
    icon(glyph, options.fill ? "fill" : ""),
  );
  if (onClick) node.addEventListener("click", onClick);
  return node;
}

export const spinner = (extra) => el("span", { class: `spin${extra ? ` ${extra}` : ""}`, "aria-hidden": "true" });

// ---- Small parts -----------------------------------------------------------------------

/** A label tag: `neutral` or `me` (primary container). */
export function tag(text, kind = "neutral") {
  return el("span", { class: `tag${kind === "me" ? " me" : ""}`, text });
}

/** A role tag, a word in a 24 px pill: Admin (filled), Mod (tonal), Basic (outlined). */
export function roleTag(role) {
  const name = { ADMIN: "Admin", MOD: "Mod", BASIC: "Basic" }[role] ?? role;
  return el("span", { class: `role-tag ${String(role).toLowerCase()}`, text: name });
}

export function roleLabel(role) {
  return { ADMIN: "Admin", MOD: "Mod", BASIC: "Basic" }[role] ?? "Basic";
}

/** A neutral circle with the first letter of a name (never one per producer). */
export function avatar(name, { primary = false } = {}) {
  const letter = [...String(name).trim()][0]?.toUpperCase() ?? "?";
  return el("span", { class: `av${primary ? " avp" : ""}`, "aria-hidden": "true", text: letter });
}

export function label(text) {
  return el("div", { class: "lab", text });
}

export function sectionLabel(text, count) {
  return el(
    "div",
    { class: "rolesec", role: "heading", "aria-level": "2" },
    text,
    count === undefined ? null : el("span", { class: "rolecount", text: String(count) }),
  );
}

/** One-line rows of a list: leading, text lines, trailing. */
export function row({ leading, title, tags, lines = [], trailing, className = "" }) {
  return el(
    "div",
    { class: `lt ${className}`.trim() },
    leading,
    el(
      "div",
      { class: "tx" },
      el("span", { class: "t1" }, title, ...(tags ?? [])),
      ...lines.map((line) => el("span", { class: "t2n" }, line)),
    ),
    trailing,
  );
}

// ---- Fields ----------------------------------------------------------------------------

/**
 * A text field: outlined, with its label notched into the border. `error` turns the border,
 * label and help line to the error colour and adds an icon, so it is never colour alone.
 */
export function textField({ label: text, value = "", hint, mono, maxlength, autocomplete = "off", onInput, id = nextId("field"), spellcheck = false }) {
  const input = el("input", {
    id,
    type: "text",
    class: mono ? "mono" : null,
    value,
    maxlength,
    autocomplete,
    spellcheck: String(spellcheck),
    autocapitalize: "off",
    "aria-describedby": `${id}-help`,
  });
  input.value = value;
  const help = el("div", { class: "hint", id: `${id}-help` }, hint ?? "");
  const box = el("div", { class: "tf" }, input, el("label", { class: "fl", for: id, text }), icon("error", "tf-err"));
  const wrap = el("div", { class: "field" }, box, help);
  const api = {
    node: wrap,
    input,
    setError(message) {
      const failed = Boolean(message);
      box.classList.toggle("err", failed);
      input.toggleAttribute("aria-invalid", failed);
      replace(help, failed ? message : (hint ?? ""));
      help.classList.toggle("err", failed);
    },
  };
  if (onInput) input.addEventListener("input", () => onInput(input.value));
  return api;
}

/** A Material 3 switch. `name` is spoken with its state. */
export function toggle({ checked, onChange, label: name, disabled }) {
  const node = el("button", { type: "button", class: "sw", role: "switch", "aria-checked": String(checked), "aria-label": name, disabled });
  node.append(el("span", { class: "sw-knob", "aria-hidden": "true" }));
  node.addEventListener("click", () => {
    if (node.disabled) return;
    onChange(node.getAttribute("aria-checked") !== "true");
  });
  return node;
}

/**
 * A segmented button: single choice, spoken as a radio group ("Private, selected"). `options`
 * are `{value, label, glyph?, disabled?, name?}`; the selected one shows its glyph.
 */
export function segmented({ options, value, onChange, label: name, className = "" }) {
  const group = el("div", { class: `seg ${className}`.trim(), role: "radiogroup", "aria-label": name });
  for (const option of options) {
    const selected = option.value === value;
    const node = el(
      "button",
      {
        type: "button",
        role: "radio",
        class: `${selected ? "on" : ""}${option.disabled ? " dis" : ""}`.trim(),
        "aria-checked": String(selected),
        "aria-disabled": option.disabled ? "true" : null,
        "aria-label": option.name ?? option.label,
        tabindex: selected || (!options.some((o) => o.value === value) && option === options[0]) ? "0" : "-1",
      },
      (selected || option.alwaysGlyph) && option.glyph ? icon(option.glyph, "ms18") : null,
      el("span", { text: option.label }),
    );
    node.addEventListener("click", () => {
      if (!option.disabled && !selected) onChange(option.value);
    });
    group.append(node);
  }
  group.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) return;
    const enabled = options.filter((option) => !option.disabled);
    const at = enabled.findIndex((option) => option.value === value);
    const step = event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1;
    const next = enabled[(at + step + enabled.length) % enabled.length];
    event.preventDefault();
    if (next && next.value !== value) onChange(next.value);
  });
  return group;
}

// ---- Empty, loading and notices --------------------------------------------------------

export function emptyState({ glyph, title, body, action, role }) {
  return el(
    "div",
    { class: "empty", role },
    icon(glyph),
    el("h2", { class: "h3", text: title }),
    body ? el("p", { class: "p", text: body }) : null,
    action ?? null,
  );
}

/** Rows with the shape of the real rows, never a spinner for a whole list. */
export function skeletonRows(count = 6, { circle = false } = {}) {
  const rows = [];
  for (let i = 0; i < count; i += 1) {
    rows.push(
      el(
        "div",
        { class: "lt skeleton" },
        circle ? el("span", { class: "skel-av" }) : el("span", { class: "skel-ic" }),
        el(
          "div",
          { class: "tx" },
          el("span", { class: "skel-line", data: { w: i % 3 } }),
          el("span", { class: "skel-line short" }),
        ),
      ),
    );
  }
  return el("div", { class: "skeletons", "aria-hidden": "true" }, rows);
}

/** A notice that sits inline: pushes the list down and never covers it. */
export function banner({ glyph, text, actions = [], error = false, role }) {
  return el(
    "div",
    { class: `banner${error ? " error" : ""}`, role },
    icon(glyph),
    el("span", { class: "tx", text }),
    ...actions,
  );
}

/** A box with an icon and a sentence, in its own low container. */
export function noticeBox({ glyph, text, error = false }) {
  return el("div", { class: `warn${error ? " er" : ""}` }, icon(glyph), el("span", { text }));
}

const slots = new Set();
const makers = new Map();

/**
 * Where banners show: right under a screen's header. A banner is kept as a function that builds
 * it, because every slot needs its own node with its own listeners.
 */
export function bannerSlot() {
  const slot = el("div", { class: "banner-slot" });
  slots.add(slot);
  queueMicrotask(repaint);
  return slot;
}

/** Shows a banner under `key`; `make` builds it. Showing the same key again replaces it. */
export function showBanner(key, make) {
  makers.set(key, make);
  repaint();
}

export function hideBanner(key) {
  if (makers.delete(key)) repaint();
}

export function bannerShown(key) {
  return makers.has(key);
}

function repaint() {
  for (const slot of [...slots]) {
    if (!slot.isConnected) {
      // A slot not attached yet is kept for the next paint; one that was attached is gone.
      if (slot.dataset.attached) slots.delete(slot);
      continue;
    }
    slot.dataset.attached = "1";
    clear(slot);
    for (const make of makers.values()) slot.append(make());
  }
}

// ---- Live region -----------------------------------------------------------------------

/** Says something to a screen reader without moving focus. */
export function announce(message) {
  const region = document.getElementById("live");
  if (!region) return;
  region.textContent = "";
  // A change of text is what is read; setting the same text twice would say nothing.
  setTimeout(() => {
    region.textContent = message;
  }, 30);
}

// ---- Dialogs ---------------------------------------------------------------------------

const openDialogs = [];

function setInert(on) {
  const app = document.getElementById("app");
  if (app) app.toggleAttribute("inert", on);
}

/**
 * A modal dialog, 480 px, centred. Focus starts on `initialFocus` (an action's `value`, default
 * the first action, which is Cancel), stays inside until it closes, and returns to what had it.
 * Escape and a click on the scrim close it unless `persistent`. Each action may carry an async
 * `run` that is awaited with the button busy; if it throws, the message shows in the dialog and
 * the dialog stays. Resolves with the closing action's `value` (or `undefined` when dismissed).
 */
export function openDialog({ title, content, actions, persistent = false, initialFocus, wide = false, role = "dialog" }) {
  const opener = document.activeElement;
  const titleId = nextId("dlg-title");
  const errorBox = el("p", { class: "dlg-error", role: "alert", hidden: true });
  const bar = el("div", { class: "acts" });
  const body = el("div", { class: "dlg-body" }, content ?? null, errorBox);
  const dialog = el("div", { class: `dlg${wide ? " wide" : ""}`, role, "aria-modal": "true", "aria-labelledby": titleId }, el("h2", { class: "h2", id: titleId, text: title }), body, bar);
  const wrapper = el("div", { class: "dlgw" });
  const scrim = el("div", { class: "scrim" });
  wrapper.append(dialog);
  let finish;
  const done = new Promise((resolve) => {
    finish = resolve;
  });
  let closed = false;

  const controller = {
    node: dialog,
    done,
    error(message) {
      errorBox.textContent = message;
      errorBox.hidden = !message;
    },
    close(value) {
      if (closed) return;
      closed = true;
      const index = openDialogs.indexOf(controller);
      if (index >= 0) openDialogs.splice(index, 1);
      document.removeEventListener("keydown", onKey, true);
      const remove = () => {
        scrim.remove();
        wrapper.remove();
      };
      if (reducedMotion()) remove();
      else {
        scrim.classList.add("closing");
        wrapper.classList.add("closing");
        setTimeout(remove, 100);
      }
      if (!openDialogs.length) setInert(false);
      else openDialogs.at(-1).node.parentElement.removeAttribute("inert");
      const target = opener && opener.isConnected ? opener : document.querySelector("main h1, main [tabindex='-1']");
      target?.focus?.({ preventScroll: true });
      finish(value);
    },
  };

  for (const action of actions) {
    const node = button(action.label, { kind: action.kind ?? "text", disabled: action.disabled, data: { value: String(action.value) } });
    node.addEventListener("click", async () => {
      if (!action.run) {
        controller.close(action.value);
        return;
      }
      controller.error("");
      setBusy(node, true);
      try {
        await action.run(controller);
        controller.close(action.value ?? true);
      } catch (error) {
        if (error.name === "SessionEnded") {
          // The page already says the sign-in ended; nothing more to ask here.
          controller.close(undefined);
          return;
        }
        setBusy(node, false);
        controller.error(error.silent ? error.message : error.message || "Try again.");
      }
    });
    action.node = node;
    bar.append(node);
  }

  function onKey(event) {
    if (openDialogs.at(-1) !== controller) return;
    if (event.key === "Escape") {
      event.stopPropagation();
      event.preventDefault();
      if (!persistent) controller.close(undefined);
    } else if (event.key === "Tab") {
      const items = focusable(dialog);
      if (!items.length) return;
      const first = items[0];
      const last = items.at(-1);
      if (event.shiftKey && (document.activeElement === first || !dialog.contains(document.activeElement))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || !dialog.contains(document.activeElement))) {
        event.preventDefault();
        first.focus();
      }
    }
  }

  if (!persistent) scrim.addEventListener("click", () => controller.close(undefined));
  document.addEventListener("keydown", onKey, true);
  if (openDialogs.length) openDialogs.at(-1).node.parentElement.setAttribute("inert", "");
  openDialogs.push(controller);
  setInert(true);
  document.body.append(scrim, wrapper);
  const start = actions.find((action) => action.value === initialFocus)?.node ?? actions[0]?.node ?? dialog;
  if (start === dialog) dialog.tabIndex = -1;
  start.focus({ preventScroll: true });
  return controller;
}

/** A confirmation: the title names the thing, Cancel is first and focused, the action is a verb. */
export function confirmDialog({ title, message, action, destructive = false, run }) {
  const dialog = openDialog({
    title,
    content: el("p", { class: "p dlg-text", text: message }),
    actions: [
      { label: "Cancel", value: false },
      { label: action, value: true, kind: destructive ? "text-error" : "text", run },
    ],
    initialFocus: false,
  });
  return dialog.done.then((value) => value === true);
}

// ---- Menu ------------------------------------------------------------------------------

let closeMenu = null;

/**
 * A menu opened from `anchor`. `header` is an optional `{title, subtitle}`; items are
 * `{label, glyph, onSelect, danger}`. Arrow keys move, Escape closes and returns focus.
 */
export function openMenu(anchor, { header, items, placement = "below-end" }) {
  closeMenu?.();
  const menu = el("div", { class: "menu", role: "menu", "aria-label": anchor.getAttribute("aria-label") ?? undefined });
  if (header) {
    menu.append(el("div", { class: "mhead" }, el("div", { class: "n", text: header.title }), header.subtitle ? el("div", { class: "s", text: header.subtitle }) : null));
  }
  const nodes = items.map((item) => {
    const node = el("button", { type: "button", role: "menuitem", class: `mi${item.danger ? " er" : ""}` }, icon(item.glyph, item.danger ? "" : "c-var"), el("span", { text: item.label }));
    node.addEventListener("click", () => {
      close();
      item.onSelect();
    });
    menu.append(node);
    return node;
  });
  const catcher = el("div", { class: "menu-catcher" });
  document.body.append(catcher, menu);
  const rect = anchor.getBoundingClientRect();
  const width = menu.offsetWidth;
  const height = menu.offsetHeight;
  let left;
  let top;
  if (placement === "right-end") {
    left = rect.right + 8;
    top = rect.bottom - height;
  } else {
    left = rect.right - width;
    top = rect.bottom + 4;
  }
  left = Math.max(8, Math.min(left, window.innerWidth - width - 8));
  top = Math.max(8, Math.min(top, window.innerHeight - height - 8));
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  anchor.setAttribute("aria-expanded", "true");
  const returnFocus = anchor;

  function close(restore = true) {
    document.removeEventListener("keydown", onKey, true);
    catcher.remove();
    menu.remove();
    anchor.setAttribute("aria-expanded", "false");
    closeMenu = null;
    if (restore) returnFocus.focus({ preventScroll: true });
  }
  function onKey(event) {
    const at = nodes.indexOf(document.activeElement);
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      close();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      nodes[(at + step + nodes.length) % nodes.length].focus();
    } else if (event.key === "Home") {
      event.preventDefault();
      nodes[0].focus();
    } else if (event.key === "End") {
      event.preventDefault();
      nodes.at(-1).focus();
    } else if (event.key === "Tab") {
      close(false);
    }
  }
  document.addEventListener("keydown", onKey, true);
  catcher.addEventListener("click", () => close());
  closeMenu = close;
  nodes[0]?.focus({ preventScroll: true });
  return { close };
}

// ---- QR code ---------------------------------------------------------------------------

/** An SVG QR code on a light plate; `text` is encoded as is. */
export function qrSvg(qrcode, text, { size = 168, label: name }) {
  const code = qrcode(0, "M");
  code.addData(text);
  code.make();
  const count = code.getModuleCount();
  const quiet = 3;
  const total = count + quiet * 2;
  let path = "";
  for (let y = 0; y < count; y += 1) {
    for (let x = 0; x < count; x += 1) {
      if (code.isDark(y, x)) path += `M${x + quiet} ${y + quiet}h1v1h-1z`;
    }
  }
  const node = svg("svg", { viewBox: `0 0 ${total} ${total}`, width: size, height: size, role: "img", "aria-label": name, class: "qr", "shape-rendering": "crispEdges" });
  node.append(svg("rect", { width: total, height: total, fill: "#ffffff" }), svg("path", { d: path, fill: "#121318" }));
  return node;
}
