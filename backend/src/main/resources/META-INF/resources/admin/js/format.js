// Times as the operator reads them: local, to the minute, and short.

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const two = (number) => String(number).padStart(2, "0");

/** 12:41, in this browser's time zone. */
export function clock(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  return `${two(date.getHours())}:${two(date.getMinutes())}`;
}

/** 25 Sep, or 25 Sep 2025 when it was not this year. */
export function shortDate(iso) {
  const date = new Date(iso);
  const year = date.getFullYear() === new Date().getFullYear() ? "" : ` ${date.getFullYear()}`;
  return `${date.getDate()} ${MONTHS[date.getMonth()]}${year}`;
}

/** 25 Sep 12:41, for a time that matters to the minute. */
export function dateTime(iso) {
  return `${shortDate(iso)} ${clock(iso)}`;
}

export function plural(count, one, many = `${one}s`) {
  return `${count} ${count === 1 ? one : many}`;
}

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

/** just now, 12 min ago, 2 h ago, yesterday, 3 days ago, then the date. */
export function ago(iso, now = Date.now()) {
  const then = Date.parse(iso);
  const age = Math.max(0, now - then);
  if (age < MINUTE) return "just now";
  if (age < HOUR) return `${Math.round(age / MINUTE)} min ago`;
  const days = Math.round((startOfDay(new Date(now)) - startOfDay(new Date(then))) / DAY);
  if (age < DAY && days === 0) return `${Math.round(age / HOUR)} h ago`;
  if (days === 1) return "yesterday";
  if (days < 30) return `${days} days ago`;
  return shortDate(iso);
}

/** 1 minute ago, 3 hours ago: the longer form Status uses in a sentence. */
export function agoLong(iso, now = Date.now()) {
  const age = Math.max(0, now - Date.parse(iso));
  if (age < MINUTE) return "just now";
  if (age < HOUR) return `${plural(Math.round(age / MINUTE), "minute")} ago`;
  if (age < DAY) return `${plural(Math.round(age / HOUR), "hour")} ago`;
  return `${plural(Math.round(age / DAY), "day")} ago`;
}

/** A length of time, from seconds, in the largest whole unit. */
export function duration(seconds) {
  if (seconds % 86400 === 0) return plural(seconds / 86400, "day");
  if (seconds % 3600 === 0) return plural(seconds / 3600, "hour");
  return plural(seconds, "second");
}
