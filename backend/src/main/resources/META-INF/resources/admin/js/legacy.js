// Helpers of the Events and Users sections, which keep their earlier content inside the new shell
// until the admin page's next item rebuilds them (docs/roadmap.md, R79). Everything a server sent is
// set as text, never as HTML.

import { snack } from "./ui.js";

export const $ = (id) => document.getElementById(id);

export const ROLES = { BASIC: "Basic", MOD: "Mod", ADMIN: "Admin" };

export const LABELS = {
  ACTION_REQUIRED: "Action required",
  BLOCKED: "Blocked",
  COMPLETED: "Completed",
  INFO: "Info",
  LOW: "Low",
  NORMAL: "Normal",
  HIGH: "High",
  CRITICAL: "Critical",
};

// How a delivery record's attempt went, as the operator reads it.
export const OUTCOMES = {
  DELIVERED: "Delivered",
  FILTERED: "Filtered out by its push preferences",
  NO_TARGET: "Not sent: no push target",
  UNSUPPORTED_PROVIDER: "Not sent: push provider not configured",
  INVALID_TARGET: "Push target rejected, and removed",
  TRANSIENT_FAILURE: "Temporary failure",
  PERMANENT_FAILURE: "Failed",
};

export function time(iso) {
  return new Date(iso).toLocaleString();
}

export function ago(iso) {
  const minutes = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000));
  if (minutes < 1) return "just now";
  if (minutes < 60) return plural(minutes, "minute");
  if (minutes < 60 * 24) return plural(Math.round(minutes / 60), "hour");
  return plural(Math.round(minutes / (60 * 24)), "day");
}

export function plural(count, unit) {
  return `${count} ${unit}${count === 1 ? "" : "s"} ago`;
}

export function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

export function button(text, onClick, className = "secondary") {
  const node = element("button", className, text);
  node.type = "button";
  node.addEventListener("click", onClick);
  return node;
}

export function showError(id, text) {
  $(id).textContent = text || "";
  $(id).hidden = !text;
}

export function toast(text) {
  snack(text);
}

// A value this page does not know yet is shown as it is; the reason, if any, follows it.
export function outcome(record) {
  const text = OUTCOMES[record.outcome] || record.outcome;
  return record.detail ? `${text} (${record.detail})` : text;
}

/** Shows one of the old sections, hiding the new-style container. */
export function showLegacy(name) {
  $("sect").hidden = true;
  for (const node of document.querySelectorAll(".legacy-section")) node.hidden = node.dataset.section !== name;
}

export function hideLegacy() {
  for (const node of document.querySelectorAll(".legacy-section")) node.hidden = true;
  $("sect").hidden = false;
}
