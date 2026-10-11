// The address is the state the operator may bookmark or reload: #section, #section/<id> for an
// open detail, and ?filters after it (kept as typed, never trusted: an id is checked against the
// canonical form before it is used in a request).

export const SECTIONS = ["devices", "users", "producers", "events", "status"];

// Canonical IDs only, so nothing typed into the address becomes another request path.
export const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `#producers/<id>?filter=quiet` as `{section, id, query}`; Devices when it names no section. */
export function parseHash(hash = location.hash) {
  const [path, search = ""] = hash.replace(/^#/, "").split("?");
  const [first, second] = path.split("/");
  const section = SECTIONS.find((name) => name === first) ?? SECTIONS[0];
  return { section, id: second || null, query: new URLSearchParams(search), known: section === first };
}

/** The address for a route. */
export function hashFor(section, id, query) {
  const search = query && [...query.keys()].length ? `?${query}` : "";
  return `#${section}${id ? `/${id}` : ""}${search}`;
}

/** Goes to an address: a step in the browser's history, and the page follows its hashchange. */
export function go(hash) {
  location.hash = hash;
}

/** Changes the address without a step in the history and without leaving the screen: filters. */
export function keepAddress(hash) {
  history.replaceState(null, "", hash);
}
