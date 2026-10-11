// The design system's components (docs/design/users/DESIGN.md, section 9) as small functions.

import { el, focusable, icon, replace } from "./dom.js";

export const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Phone width: the rail is a bottom bar and a detail or a form is a screen of its own. */
export const phone = () => window.matchMedia("(max-width: 599px)").matches;

let uid = 0;
export const nextId = (prefix) => `${prefix}-${++uid}`;

// ---- Buttons ---------------------------------------------------------------------------

const BUTTON_CLASS = {
  filled: "btn-f",
  tonal: "btn-t",
  outlined: "btn-o",
  text: "btn-x",
  "text-error": "btn-x dng",
};

/** A pill button: `filled`, `tonal`, `outlined`, `text` or `text-error`; 48 px high. */
export function button(label, options = {}) {
  const { kind = "text", glyph, onClick, disabled, ariaLabel, type = "button", data, className } = options;
  const node = el(
    "button",
    { type, class: `${BUTTON_CLASS[kind]}${className ? ` ${className}` : ""}`, disabled, "aria-label": ariaLabel, data },
    glyph ? icon(glyph) : null,
    el("span", { class: "btn-label", text: label }),
  );
  if (onClick) node.addEventListener("click", onClick);
  return node;
}

/** The button shows a spinner and ignores presses while `busy`, keeping its width. */
export function setBusy(node, busy, busyLabel) {
  node.toggleAttribute("aria-busy", busy);
  node.disabled = busy;
  const label = node.querySelector(".btn-label");
  if (!label) return;
  if (busy && busyLabel) {
    node.dataset.label = label.textContent;
    label.textContent = busyLabel;
  } else if (!busy && node.dataset.label) {
    label.textContent = node.dataset.label;
    delete node.dataset.label;
  }
}

/** A 48 px icon-only button; `label` is its accessible name. */
export function iconButton(glyph, label, onClick, options = {}) {
  const node = el(
    "button",
    { type: "button", class: `ib${options.class ? ` ${options.class}` : ""}`, "aria-label": label, disabled: options.disabled },
    icon(glyph),
  );
  if (onClick) node.addEventListener("click", onClick);
  return node;
}

export const spinner = () => el("span", { class: "spin", "aria-hidden": "true" });

// ---- Small parts -----------------------------------------------------------------------

/** A tag beside a name: `plain`, `outlined` (Disabled, Revoked) or `primary` (Admin device). */
export function tag(text, kind = "plain") {
  return el("span", { class: `tg${kind === "outlined" ? " o" : kind === "primary" ? " p" : ""}`, text });
}

/** A neutral circle with the first letter of a name (never one per producer). */
export function avatar(name, { small = false, tint = false } = {}) {
  const letter = [...String(name).trim()][0]?.toUpperCase() ?? "?";
  return el("span", { class: tint ? "avs" : `av${small ? " s" : ""}`, "aria-hidden": "true", text: letter });
}

export const ROLES = { BASIC: "Basic", MOD: "Mod", ADMIN: "Admin" };

/** Rodrigo · Admin, as a user is named where one is chosen. */
export const userChoice = (user) => `${user.name} · ${ROLES[user.role] ?? user.role}`;

// ---- Fields ----------------------------------------------------------------------------

/**
 * A text field: outlined, its label notched into the border. `setError` turns the border, label and
 * help line to the error colour and shows an icon, so it is never colour alone.
 */
export function textField({ label, value = "", hint, mono = false, maxlength, onInput, id = nextId("field"), type = "text", multiline = false }) {
  const input = el(multiline ? "textarea" : "input", {
    id,
    type: multiline ? null : type,
    rows: multiline ? "3" : null,
    class: mono ? "mono" : null,
    maxlength,
    autocomplete: "off",
    spellcheck: "false",
    autocapitalize: "off",
    "aria-describedby": `${id}-help`,
  });
  input.value = value;
  const help = el("div", { class: "help", id: `${id}-help` }, hint ?? "");
  const box = el("div", { class: "tf" }, input, el("label", { class: "fl", for: id, text: label }), icon("error", "tf-ic tf-err"));
  const api = {
    node: el("div", { class: "field" }, box, help),
    input,
    box,
    setError(message) {
      const failed = Boolean(message);
      box.classList.toggle("err", failed);
      if (failed) input.setAttribute("aria-invalid", "true");
      else input.removeAttribute("aria-invalid");
      replace(help, failed ? message : (hint ?? ""));
      help.classList.toggle("err", failed);
      help.setAttribute("role", failed ? "alert" : "presentation");
    },
  };
  if (onInput) input.addEventListener("input", () => onInput(input.value));
  return api;
}

/** A select with its label notched into the border: `options` are `{value, text}`. */
export function selectField({ label, options, value, hint, id = nextId("field"), onChange }) {
  const select = el("select", { id, "aria-describedby": `${id}-help` });
  for (const option of options) select.append(el("option", { value: option.value, text: option.text }));
  if (value !== undefined) select.value = value;
  const help = el("div", { class: "help", id: `${id}-help` }, hint ?? "");
  const box = el("div", { class: "tf" }, select, el("label", { class: "fl", for: id, text: label }), icon("arrow_drop_down", "tf-ic"));
  if (onChange) select.addEventListener("change", () => onChange(select.value));
  return {
    node: el("div", { class: "field" }, box, help),
    select,
    box,
    setError(message) {
      box.classList.toggle("err", Boolean(message));
      replace(help, message || (hint ?? ""));
      help.classList.toggle("err", Boolean(message));
    },
  };
}

/**
 * A segmented button: single choice, spoken as a radio group ("Private, selected"). `options` are
 * `{value, label, glyph}`; arrow keys move.
 */
export function segmented({ options, value, onChange, label }) {
  const group = el("div", { class: "seg", role: "radiogroup", "aria-label": label });
  for (const option of options) {
    const selected = option.value === value;
    const node = el(
      "button",
      { type: "button", role: "radio", "aria-checked": String(selected), tabindex: selected ? "0" : "-1" },
      option.glyph ? icon(option.glyph, "ms18") : null,
      el("span", { text: option.label }),
    );
    node.addEventListener("click", () => {
      if (!selected) onChange(option.value);
    });
    group.append(node);
  }
  group.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) return;
    const at = options.findIndex((option) => option.value === value);
    const step = event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1;
    const next = options[(at + step + options.length) % options.length];
    event.preventDefault();
    if (next.value !== value) onChange(next.value);
  });
  return group;
}

// ---- Chips -----------------------------------------------------------------------------

/** A filter chip: 32 px, 8 px corners, a check when on; its hit area is 48 px high. */
export function chip({ label, on = false, onClick, menu = false, ariaLabel }) {
  const node = el(
    "button",
    { type: "button", class: `fc${on ? " on" : ""}`, "aria-pressed": menu ? null : String(on), "aria-haspopup": menu ? "menu" : null, "aria-label": ariaLabel },
    on && !menu ? icon("check", "ms18") : null,
    el("span", { text: label }),
    menu ? icon("arrow_drop_down", "ms18") : null,
  );
  if (onClick) node.addEventListener("click", onClick);
  return node;
}

// ---- Empty, loading and notices --------------------------------------------------------

export function emptyState({ glyph, title, body, action }) {
  return el(
    "div",
    { class: "empty" },
    icon(glyph),
    el("h2", { class: "h", text: title }),
    body ? el("p", { class: "p", text: body }) : null,
    action ?? null,
  );
}

/** Rows with the shape of the real rows, never a spinner for a whole list. */
export function skeletonRows(count = 7) {
  const rows = [];
  for (let i = 0; i < count; i += 1) {
    rows.push(
      el("div", { class: "sk2" }, el("span", { class: "sk c" }), el("span", { class: "sk", data: { w: i % 3 } }), el("span", { class: "sk" })),
    );
  }
  return el("div", { class: "skeletons", "aria-hidden": "true" }, rows);
}

/** A notice that sits inline and never covers a control. */
export function banner({ glyph, text, actions = [], error = false, role }) {
  return el(
    "div",
    { class: `bn ${error ? "err" : "neu"}`, role },
    icon(glyph, error ? "" : "c-var"),
    el("span", { class: "tx", text }),
    ...actions,
  );
}

// ---- Live region and the snack bar -----------------------------------------------------

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

const SNACK_MS = 8000;
let snackNode = null;
let snackTimer = null;

export function clearSnack() {
  clearTimeout(snackTimer);
  snackNode?.remove();
  snackNode = null;
}

/**
 * A result, at the bottom left of the list area so it never covers a control. It carries no Undo
 * (the page confirms first); a failure may offer Try again. It goes after 8 seconds or on Dismiss.
 */
export function snack(text, action) {
  clearSnack();
  const node = el("div", { class: "snack", role: "status" }, el("span", { text }));
  if (action) {
    node.append(
      el("button", {
        type: "button",
        text: action.label,
        on: {
          click: () => {
            clearSnack();
            action.onClick();
          },
        },
      }),
    );
  }
  node.append(el("button", { type: "button", text: "Dismiss", on: { click: clearSnack } }));
  document.body.append(node);
  snackNode = node;
  snackTimer = setTimeout(clearSnack, SNACK_MS);
}

// ---- Dialogs ---------------------------------------------------------------------------

const openDialogs = [];

function setInert(on) {
  const app = document.getElementById("app");
  if (app) app.toggleAttribute("inert", on);
}

/**
 * A modal dialog, 480 px, centred (a bottom sheet or a full screen on a phone: `variant` "sheet" or
 * "full"). Focus starts on `initialFocus` (an action's `value`, default the first, which is Cancel),
 * stays inside until it closes, and returns to what had it. Escape and a click on the scrim close
 * it unless `persistent`. An action's async `run` is awaited with its button busy; if it throws,
 * the message shows in the dialog and the dialog stays. Resolves with the closing action's `value`
 * (undefined when dismissed).
 */
export function openDialog({ title, content, actions, persistent = false, guard, initialFocus, wide = false, variant = "sheet", focusNode, onClose, onDismiss }) {
  const opener = document.activeElement;
  const titleId = nextId("dlg-title");
  const errorBox = el("p", { class: "dlg-error", role: "alert", hidden: true });
  const bar = el("div", { class: "acts" });
  const body = el("div", { class: "dlg-body" }, content ?? null, errorBox);
  const closeIcon = iconButton("close", "Close", () => dismiss(), { class: "dlg-close" });
  const dialog = el(
    "div",
    { class: `dlg${wide ? " wide" : ""} ${variant}`, role: "dialog", "aria-modal": "true", "aria-labelledby": titleId },
    variant === "full" && !persistent ? el("div", { class: "dlg-head" }, closeIcon, el("h2", { id: titleId, text: title, tabindex: "-1" })) : el("h2", { id: titleId, text: title, tabindex: "-1" }),
    body,
    bar,
  );
  const wrapper = el("div", { class: "dlgw" }, dialog);
  const scrim = el("div", { class: "scrim" });
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
    setTitle(text) {
      dialog.querySelector(`#${titleId}`).textContent = text;
    },
    /** Replaces the dialog's content and actions, for a dialog that goes on to its next step. */
    replace({ title: nextTitle, content: nextContent, actions: nextActions, initialFocus: nextFocus, focusNode: nextNode }) {
      if (nextTitle) controller.setTitle(nextTitle);
      replace(body, nextContent ?? null, errorBox);
      controller.error("");
      bar.replaceChildren();
      mountActions(nextActions);
      const start = nextNode ?? nextActions.find((action) => action.value === nextFocus)?.node ?? nextActions[0]?.node;
      start?.focus({ preventScroll: true });
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
      const target = opener && opener.isConnected ? opener : document.querySelector("main h1");
      target?.focus?.({ preventScroll: true });
      controller.onEnd?.();
      onClose?.(value);
      finish(value);
    },
  };

  function mountActions(list) {
    for (const action of list) {
      const node = button(action.label, { kind: action.kind ?? "text", glyph: action.glyph, disabled: action.disabled, ariaLabel: action.ariaLabel, data: { value: String(action.value) }, className: action.className });
      node.addEventListener("click", async () => {
        if (!action.run) {
          if (action.value === undefined || action.value === false) onDismiss?.(controller);
          controller.close(action.value);
          return;
        }
        controller.error("");
        setBusy(node, true, action.busyLabel);
        try {
          await action.run(controller);
          if (!closed) {
            setBusy(node, false);
            if (action.keepOpen !== true) controller.close(action.value ?? true);
          }
        } catch (error) {
          if (error.name === "SessionEnded") {
            // The page already says the session ended; nothing more to ask here.
            controller.close(undefined);
            return;
          }
          setBusy(node, false);
          // After a failure the confirming button offers to try again.
          if (action.retryLabel) node.querySelector(".btn-label").textContent = action.retryLabel;
          action.onError?.(error);
          controller.error(error.message || "Try again.");
        }
      });
      action.node = node;
      bar.append(node);
    }
  }
  mountActions(actions);
  controller.actions = actions;

  function onKey(event) {
    if (openDialogs.at(-1) !== controller) return;
    if (event.key === "Escape") {
      event.stopPropagation();
      event.preventDefault();
      dismiss();
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

  // Escape, a click on the scrim and the close icon all ask `guard` first, if there is one.
  async function dismiss() {
    if (persistent) return;
    if (guard && !(await guard())) return;
    onDismiss?.(controller);
    controller.close(undefined);
  }

  if (!persistent) scrim.addEventListener("click", () => dismiss());
  document.addEventListener("keydown", onKey, true);
  if (openDialogs.length) openDialogs.at(-1).node.parentElement.setAttribute("inert", "");
  openDialogs.push(controller);
  setInert(true);
  document.body.append(scrim, wrapper);
  const start = focusNode ?? actions.find((action) => action.value === initialFocus)?.node ?? actions[0]?.node ?? dialog;
  start.focus({ preventScroll: true });
  return controller;
}

/** A confirmation: the title names the thing, Cancel is first and focused, the action is a verb. */
export function confirmDialog({ title, message, action, destructive = false, run, busyLabel, retryLabel, ariaLabel, extra, cancel = "Cancel" }) {
  const dialog = openDialog({
    title,
    content: el("div", {}, el("p", { class: "p", text: message }), extra ?? null),
    actions: [
      { label: cancel, value: false, className: "cancel" },
      { label: action, value: true, kind: destructive ? "text-error" : "text", run, busyLabel, retryLabel, ariaLabel, className: "confirm" },
    ],
    initialFocus: false,
  });
  return dialog.done.then((value) => value === true);
}

// ---- Menu ------------------------------------------------------------------------------

let closeMenu = null;

/**
 * A menu opened from `anchor`. `header` is an optional `{title, subtitle}`; items are
 * `{label, glyph, onSelect, danger, sub, selected}`. Arrow keys move, Escape closes and returns
 * focus to the control that opened it.
 */
export function openMenu(anchor, { header, items, placement = "below-end", label, narrow = false }) {
  closeMenu?.();
  const menu = el("div", { class: `menu${narrow ? " s" : ""}`, role: "menu", "aria-label": label ?? anchor.getAttribute("aria-label") ?? undefined });
  if (header) {
    menu.append(
      el("div", { class: "mhd" }, el("div", { class: "n", text: header.title }), header.subtitle ? el("div", { class: "s", text: header.subtitle }) : null),
    );
  }
  const nodes = [];
  for (const item of items) {
    if (item.separator) {
      menu.append(el("div", { class: "msep", role: "separator" }));
      continue;
    }
    if (item.info) {
      // A line the menu only says: not a control.
      menu.append(el("div", { class: "mi info" }, item.glyph ? icon(item.glyph, "c-var") : null, el("span", { text: item.label }), item.sub ? el("span", { class: "sub", text: item.sub }) : null));
      continue;
    }
    const node = el(
      "button",
      { type: "button", role: item.selected === undefined ? "menuitem" : "menuitemradio", "aria-checked": item.selected === undefined ? null : String(item.selected), class: item.selected === undefined ? `mi${item.danger ? " er" : ""}` : "msel" },
      item.glyph ? icon(item.glyph, item.danger ? "" : "c-var") : item.selected !== undefined ? icon(item.selected ? "check" : "", "c-primary") : null,
      el("span", { text: item.label }),
      item.sub ? el("span", { class: "sub", text: item.sub }) : null,
    );
    node.addEventListener("click", () => {
      close();
      item.onSelect();
    });
    menu.append(node);
    nodes.push(node);
  }
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
  } else if (placement === "below-start") {
    left = rect.left;
    top = rect.bottom + 4;
  } else {
    left = rect.right - width;
    top = rect.bottom + 4;
  }
  left = Math.max(8, Math.min(left, window.innerWidth - width - 8));
  top = Math.max(8, Math.min(top, window.innerHeight - height - 8));
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  anchor.setAttribute("aria-expanded", "true");

  function close(restore = true) {
    document.removeEventListener("keydown", onKey, true);
    catcher.remove();
    menu.remove();
    anchor.setAttribute("aria-expanded", "false");
    closeMenu = null;
    if (restore && anchor.isConnected) anchor.focus({ preventScroll: true });
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
  const first = nodes.find((node) => node.getAttribute("aria-checked") === "true") ?? nodes[0];
  first?.focus({ preventScroll: true });
  return { close };
}
