// Pieces several screens share: a pane's header, filter chips and a few messages.

import { el, icon } from "./dom.js";
import { accountButton } from "./chrome.js";
import { go } from "./router.js";
import { iconButton } from "./ui.js";

/**
 * A pane's header, 64 px: an optional back arrow, the title, then actions. At phone width it
 * also carries the account button (`account`), which sits in the rail on a wide page.
 */
export function paneHeader({ title, back, close, actions = [], account = false, level = 1 }) {
  return el(
    "div",
    { class: `phead${back || close ? " has-back" : ""}` },
    back ? iconButton("arrow_back", "Back", () => go(back)) : null,
    close ? iconButton("close", "Close", () => go(close)) : null,
    el("div", { class: "t", role: "heading", "aria-level": String(level), tabindex: "-1", text: title }),
    ...actions,
    account ? accountButton() : null,
  );
}

/** A filter chip: 32 px, 8 px corners, a check when on; its hit area is padded to 48 px. */
export function chip({ label, on, onClick, remove, role, pressed = true }) {
  const node = el(
    "button",
    {
      type: "button",
      class: `fc${on ? " on" : ""}`,
      role,
      "aria-checked": role === "radio" ? String(Boolean(on)) : null,
      "aria-pressed": !role && pressed ? String(Boolean(on)) : null,
    },
    on ? icon("check", "ms18") : null,
    el("span", { text: label }),
  );
  if (onClick) node.addEventListener("click", onClick);
  if (!remove) return node;
  // A chip that can be taken away: the label and an x, each its own control.
  const wrap = el("span", { class: "fc on removable" }, el("span", { class: "fc-label", text: label }));
  wrap.append(
    el("button", { type: "button", class: "fc-x", "aria-label": `Remove filter ${label}`, on: { click: remove } }, icon("close", "ms18")),
  );
  return wrap;
}

/** The empty detail pane of a wide page. */
export function selectPrompt(glyph, title, text) {
  return el("div", { class: "empty" }, icon(glyph), el("h2", { class: "h3", text: title }), el("p", { class: "p", text }));
}
