// What narrows the Events list, and how it is written in the address and asked of the listing. A
// chosen filter is in the address (`#events?severity=HIGH,CRITICAL&read=false`), so a reload or a
// link keeps it; the address is never trusted: every value is checked against what the page offers
// before it becomes a request.

import { ID } from "./router.js";
import { shortDate } from "./format.js";

export const SEVERITIES = [
  { value: "LOW", text: "Low", glyph: "arrow_downward", tone: "low" },
  { value: "NORMAL", text: "Normal", glyph: "trending_flat", tone: "norm" },
  { value: "HIGH", text: "High", glyph: "warning", tone: "high" },
  { value: "CRITICAL", text: "Critical", glyph: "error", tone: "crit" },
];

export const CATEGORIES = [
  { value: "INFO", text: "Info", glyph: "info" },
  { value: "ACTION_REQUIRED", text: "Action required", glyph: "pending_actions" },
  { value: "BLOCKED", text: "Blocked", glyph: "block" },
  { value: "COMPLETED", text: "Completed", glyph: "check_circle" },
];

export const READ_STATES = [
  { value: "", text: "Read and unread" },
  { value: "false", text: "Unread only" },
  { value: "true", text: "Read only" },
];

export const RELATIONS = [
  { value: "", text: "Owned or subscribed to" },
  { value: "OWNED", text: "Owned" },
  { value: "SUBSCRIBED", text: "Subscribed to" },
];

// What the Push problems chip asks the listing for (docs/architecture.md, the push summary).
export const PUSH_PROBLEMS = ["FAILED", "GAVE_UP"];

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

export const severityOf = (value) => SEVERITIES.find((item) => item.value === value);
export const categoryOf = (value) => CATEGORIES.find((item) => item.value === value);

export function emptyFilters() {
  return { read: "", severity: [], push: false, producer: [], category: [], user: "", relation: "", from: "", before: "" };
}

const known = (list, values) => list.map((item) => item.value).filter((value) => values.includes(value));

/** The filters named by an address's query; anything that is not one of the page's own values is dropped. */
export function fromQuery(params) {
  const filters = emptyFilters();
  const many = (name) => (params.get(name) ?? "").split(",").filter(Boolean);
  const read = params.get("read");
  if (read === "true" || read === "false") filters.read = read;
  filters.severity = known(SEVERITIES, many("severity"));
  filters.category = known(CATEGORIES, many("category"));
  filters.producer = [...new Set(many("producer").filter((id) => ID.test(id)))];
  filters.push = params.get("push") === "problems";
  const user = params.get("user");
  if (user && ID.test(user)) {
    filters.user = user;
    filters.relation = known(RELATIONS.slice(1), [params.get("relation")])[0] ?? "";
  }
  for (const name of ["from", "before"]) {
    const value = params.get(name);
    if (value && DATE.test(value) && !Number.isNaN(Date.parse(`${value}T00:00`))) filters[name] = value;
  }
  return filters;
}

/** The query part of the address. */
export function toQuery(filters) {
  const params = new URLSearchParams();
  if (filters.read) params.set("read", filters.read);
  if (filters.severity.length) params.set("severity", filters.severity.join(","));
  if (filters.push) params.set("push", "problems");
  if (filters.producer.length) params.set("producer", filters.producer.join(","));
  if (filters.category.length) params.set("category", filters.category.join(","));
  if (filters.user) {
    params.set("user", filters.user);
    if (filters.relation) params.set("relation", filters.relation);
  }
  if (filters.from) params.set("from", filters.from);
  if (filters.before) params.set("before", filters.before);
  return params;
}

/** A day typed or picked is midnight in this browser's time zone, the server being given the instant. */
const midnight = (day) => new Date(`${day}T00:00`).toISOString();

/** The listing's own parameters for these filters. */
export function toApi(filters) {
  const params = new URLSearchParams();
  for (const id of filters.producer) params.append("producerId", id);
  for (const value of filters.category) params.append("category", value);
  for (const value of filters.severity) params.append("severity", value);
  if (filters.read) params.set("read", filters.read);
  if (filters.user) {
    params.set("userId", filters.user);
    if (filters.relation) params.set("relation", filters.relation);
  }
  if (filters.push) for (const value of PUSH_PROBLEMS) params.append("push", value);
  if (filters.from) params.set("createdFrom", midnight(filters.from));
  if (filters.before) params.set("createdBefore", midnight(filters.before));
  return params;
}

export function isFiltered(filters) {
  return [...toQuery(filters).keys()].length > 0;
}

/** How many of the chips are in force: the number on the phone's Filters button. */
export function filterCount(filters) {
  const on = [filters.read, filters.severity.length, filters.push, filters.producer.length, filters.category.length, filters.user, filters.from || filters.before];
  return on.filter(Boolean).length;
}

// ---- Dates -----------------------------------------------------------------------------------

/** A calendar day as the date fields hold it (2026-10-08), in this browser's time zone. */
export function dayString(date) {
  const two = (number) => String(number).padStart(2, "0");
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

export function addDays(day, days) {
  const date = new Date(`${day}T12:00`);
  date.setTime(date.getTime() + days * DAY_MS);
  return dayString(date);
}

const shortDay = (day) => shortDate(new Date(`${day}T12:00`).toISOString());

/** Received: 1 Oct to 7 Oct. Events on the day before “Before” are in; the day itself is not. */
export function rangeText(filters) {
  const { from, before } = filters;
  if (from && before) {
    const last = addDays(before, -1);
    return last <= from ? shortDay(from) : `${shortDay(from)} to ${shortDay(last)}`;
  }
  if (from) return `since ${shortDay(from)}`;
  if (before) return `before ${shortDay(before)}`;
  return "";
}

// ---- Words -----------------------------------------------------------------------------------

/** “Critical, High”, or a count when the values do not fit a chip. */
export function valuesText(values) {
  const text = values.join(", ");
  return values.length > 2 || text.length > 30 ? String(values.length) : text;
}

/** The filters in force, in words, for the “no match” message. */
export function describe(filters, names) {
  const parts = [];
  if (filters.severity.length) parts.push(`Severity ${filters.severity.map((value) => severityOf(value).text).join(" or ")}`);
  if (filters.category.length) parts.push(`Category ${filters.category.map((value) => categoryOf(value).text).join(" or ")}`);
  if (filters.read) parts.push(`Read state ${READ_STATES.find((item) => item.value === filters.read).text}`);
  if (filters.push) parts.push("Push problems");
  if (filters.from || filters.before) parts.push(`Received ${rangeText(filters)}`);
  if (filters.user) parts.push(`User ${names.user(filters.user)}`);
  const of = filters.producer.map((id) => names.producer(id)).join(" or ");
  if (parts.length === 0) return `Nothing is stored for ${of}.`;
  const text = parts.length > 1 ? `${parts.slice(0, -1).join(", ")} and ${parts.at(-1)}` : parts[0];
  return `Nothing has ${text}${of ? ` for ${of}` : ""}.`;
}
