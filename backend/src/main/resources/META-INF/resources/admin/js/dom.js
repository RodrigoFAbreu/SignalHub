// Builds DOM nodes without ever parsing markup: every value, from the server or the address bar,
// becomes a text node or an attribute value, never HTML. The page's Content-Security-Policy also
// forbids inline scripts and styles, so nothing here sets either; a position is set through the
// CSSOM (node.style) where it has to be.

const URL_ATTRIBUTES = new Set(["href", "src", "action", "formaction", "xlink:href"]);

// What a link on this page may point to: another place in the page, or a web address the
// operator chose to open.
function safeUrl(value) {
  if (value.startsWith("#")) return true;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:";
  } catch {
    return false;
  }
}

/** An absolute http(s) URL with a host, or null: the only kind of link the page opens. */
export function webLink(value) {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    if ((url.protocol === "https:" || url.protocol === "http:") && url.host) return url.href;
  } catch {
    // Not an address.
  }
  return null;
}

function append(parent, child) {
  if (child === null || child === undefined || child === false) return;
  if (Array.isArray(child)) {
    for (const item of child) append(parent, item);
  } else if (child instanceof Node) {
    parent.append(child);
  } else {
    parent.append(document.createTextNode(String(child)));
  }
}

/**
 * Creates an element. `props`: `class`, `text` (textContent), `on` ({event: handler}), `data`
 * ({name: value}), and any other attribute (`true` sets it empty, `false`/null skips it).
 * Event-handler and style attributes are refused, and so is a URL that is not a page address or a
 * web address.
 */
export function el(tag, props, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(props ?? {})) {
    if (value === null || value === undefined || value === false) continue;
    if (name === "class") node.className = value;
    else if (name === "text") node.textContent = String(value);
    else if (name === "on") {
      for (const [type, handler] of Object.entries(value)) node.addEventListener(type, handler);
    } else if (name === "data") {
      for (const [key, item] of Object.entries(value)) node.dataset[key] = String(item);
    } else {
      const lower = name.toLowerCase();
      if (lower.startsWith("on") || lower === "style" || lower === "srcdoc") {
        throw new Error(`attribute ${name} is not allowed`);
      }
      const text = value === true ? "" : String(value);
      if (URL_ATTRIBUTES.has(lower) && !safeUrl(text)) throw new Error(`unsafe ${name}`);
      node.setAttribute(name, text);
    }
  }
  for (const child of children) append(node, child);
  return node;
}

/** A Material Symbols Outlined glyph. Decorative: the control around it has the name. */
export function icon(name, extra) {
  return el("span", { class: `ms${extra ? ` ${extra}` : ""}`, "aria-hidden": "true", text: name });
}

/** Replaces everything in `parent` with `children`. */
export function replace(parent, ...children) {
  parent.replaceChildren();
  for (const child of children) append(parent, child);
}

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function focusable(root) {
  return [...root.querySelectorAll(FOCUSABLE)].filter(
    (node) => !node.closest("[hidden]") && !node.closest("[inert]") && node.getClientRects().length,
  );
}
