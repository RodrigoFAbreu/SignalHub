// Dates and counts as the app writes them. Times are local, to the minute.

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const two = (n) => String(n).padStart(2, "0");

export function clock(date) {
  return `${two(date.getHours())}:${two(date.getMinutes())}`;
}

/** `2026-10-10 01:19` */
export function timestamp(value) {
  const date = new Date(value);
  return `${isoDate(date)} ${clock(date)}`;
}

/** `2026-10-10` */
export function isoDate(value) {
  const date = new Date(value);
  return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}`;
}

const sameDay = (a, b) =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

function daysBetween(from, to) {
  const start = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  const end = new Date(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((end - start) / 86_400_000);
}

/** `27 Sep`, with the year when it is not this year's. */
export function shortDate(value, now = new Date()) {
  const date = new Date(value);
  const year = date.getFullYear() === now.getFullYear() ? "" : ` ${date.getFullYear()}`;
  return `${date.getDate()} ${MONTHS[date.getMonth()]}${year}`;
}

/** When something happened: the time today (`00:36`), otherwise the date (`27 Sep`). */
export function whenLabel(value, now = new Date()) {
  const date = new Date(value);
  return sameDay(date, now) ? clock(date) : shortDate(date, now);
}

/** The time at the end of an inbox row: `01:19`, `Yesterday`, `Mon`, then the date. */
export function rowTime(value, now = new Date()) {
  const date = new Date(value);
  const days = daysBetween(date, now);
  if (days <= 0) return clock(date);
  if (days === 1) return "Yesterday";
  if (days < 7) return WEEKDAYS[date.getDay()];
  return shortDate(date, now);
}

/** A producer's last event: the time today, otherwise the full stamp. */
export function lastEvent(value, now = new Date()) {
  const date = new Date(value);
  return sameDay(date, now) ? clock(date) : timestamp(date);
}

/** `Last active today`, `3 days ago`, `4 Oct`, or `Not used yet`. */
export function lastActive(value, now = new Date()) {
  if (!value) return "Not used yet";
  const date = new Date(value);
  const days = daysBetween(date, now);
  if (days <= 0) return "Last active today";
  if (days === 1) return "Last active yesterday";
  if (days < 7) return `Last active ${days} days ago`;
  return `Last active ${shortDate(date, now)}`;
}

export function count(n, noun) {
  return n === 1 ? `1 ${noun}` : `${n} ${noun}s`;
}

/** `2:41` from milliseconds. */
export function countdown(ms) {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${two(seconds % 60)}`;
}

/** `Rodrigo's`, `Ana's`; a name ending in s takes only the apostrophe. */
export function possessive(name) {
  return name.endsWith("s") || name.endsWith("S") ? `${name}'` : `${name}'s`;
}

export function joinNames(names) {
  if (names.length <= 1) return names.join("");
  return `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;
}
