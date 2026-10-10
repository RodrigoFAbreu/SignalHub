// The address is the page: `#inbox`, `#inbox/<event id>`, `#producers/<id>`, `#settings/devices`,
// with filters after a `?`. A reload returns to the same place, and the server needs no fallback.

/** `#inbox/abc?unread=1` becomes `{ segments: ["inbox", "abc"], query }`. */
export function parseHash(hash = location.hash) {
  const raw = hash.replace(/^#\/?/, "");
  const at = raw.indexOf("?");
  const path = at < 0 ? raw : raw.slice(0, at);
  const query = new URLSearchParams(at < 0 ? "" : raw.slice(at + 1));
  const segments = path
    .split("/")
    .filter(Boolean)
    .map((part) => {
      try {
        return decodeURIComponent(part);
      } catch {
        return part;
      }
    });
  return { segments, query };
}

/** The hash for segments and a query (a URLSearchParams or an object). */
export function hashFor(segments, query) {
  const path = segments.map(encodeURIComponent).join("/");
  const text = new URLSearchParams(query ?? {}).toString();
  return `#${path}${text ? `?${text}` : ""}`;
}

export function go(hash) {
  if (location.hash === hash) window.dispatchEvent(new HashChangeEvent("hashchange"));
  else location.hash = hash;
}

/** Replaces the current address without adding a history entry. */
export function replaceHash(hash) {
  history.replaceState(null, "", `${location.pathname}${location.search}${hash}`);
}
