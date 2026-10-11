// The shape of Producers and Devices: a header (title, count, when it was read, Refresh, the one
// action that creates), a search and filter chips, a table with one tab stop, and a detail pane
// beside it that becomes a side sheet below 1180 px and a screen of its own on a phone. It reads
// its list again every 30 seconds while the page is visible and after every change; a failed read
// never clears the list, it says what failed and shows the older list dimmed.
//
// Each section says what its rows and its detail are; the rest is here, once, so the two behave the
// same: the address (#section/<id>?f=chip&q=text), focus, keys, states and motion.

import { SessionEnded } from "./api.js";
import { el, icon } from "./dom.js";
import { clock } from "./format.js";
import { go, hashFor, keepAddress } from "./router.js";
import { setDetailOpen } from "./shell.js";
import { announce, avatar, button, chip, emptyState, iconButton, openMenu, skeletonRows, banner } from "./ui.js";
import { ID } from "./router.js";

const REFRESH_MS = 30_000;
const NOTE_MS = 8000;

/**
 * `cfg`: name, title, noun [one, many], searchLabel, columns [{label, className}], gridClass,
 * fetch(), onLoaded(items), idOf(item), rowParts(item, ctx) -> {name, sub, cells, label, line2,
 * revoked}, chips [{key, label(items), test(item)}], menus [{key, prefix, anyLabel,
 * options(items) -> [{value, text}], test(item, value)}], searchText(item), countText(items, shown),
 * primary {label, glyph, onClick(ctx), enabled(ctx)}, emptyAll {glyph, title, body}, prompt {glyph,
 * title, text}, renderPane(item, ctx) -> {title, titleExtra, actions, body}, kind (what to say a
 * list failed to load as: "producers").
 */
export function createList(cfg) {
  const [one, many] = cfg.noun;
  let host = null;
  let items = null;
  let loadedAt = null;
  let error = null;
  let loading = false;
  let timer = null;
  let selectedId = null;
  let focusPane = false;
  let restoreFocus = null;
  let note = null;
  let noteTimer = null;
  let rendered = null;
  const filters = { q: "", chip: "all", menus: {} };
  let nodes = null;
  let route = null;

  const ctx = {
    get items() {
      return items;
    },
    get selected() {
      return items?.find((item) => cfg.idOf(item) === selectedId) ?? null;
    },
    get older() {
      return error !== null && items !== null;
    },
    reload,
    /** Reads the list again after a change, and shows `text` where it was made. */
    changed(text) {
      if (text) setNote({ type: "ok", text });
      return reload();
    },
    failed(text, retry) {
      setNote({ type: "err", text, retry });
    },
    setNote,
    select,
    close,
    paintPane: () => paintPane(true),
    paintExtra: () => nodes && paintExtra(),
    focusRow,
  };

  // ---- Address ------------------------------------------------------------------------------

  function query() {
    const params = new URLSearchParams();
    if (filters.chip !== "all") params.set("f", filters.chip);
    if (filters.q) params.set("q", filters.q);
    for (const [key, value] of Object.entries(filters.menus)) if (value) params.set(key, value);
    return params;
  }

  const addressFor = (id) => hashFor(cfg.name, id, query());

  function readQuery(params) {
    filters.q = params.get("q") ?? "";
    const chipKey = params.get("f");
    filters.chip = cfg.chips.some((candidate) => candidate.key === chipKey) ? chipKey : "all";
    filters.menus = {};
    for (const menu of cfg.menus ?? []) {
      const value = params.get(menu.key);
      if (value) filters.menus[menu.key] = value;
    }
  }

  // ---- Data ---------------------------------------------------------------------------------

  async function reload() {
    if (loading) return;
    loading = true;
    paintHead();
    try {
      const next = await cfg.fetch();
      // Left while it was being read: nothing to show it in.
      if (!nodes) {
        loading = false;
        return;
      }
      items = next;
      error = null;
      loadedAt = new Date();
      cfg.onLoaded?.(next);
    } catch (failure) {
      if (failure instanceof SessionEnded || failure.name === "SessionEnded") {
        loading = false;
        return;
      }
      if (!nodes) {
        loading = false;
        return;
      }
      error = failure;
    }
    loading = false;
    // The section may have been left while the list was being read.
    if (nodes) paintAll();
  }

  function visible() {
    if (!items) return [];
    const needle = filters.q.trim().toLowerCase();
    return items.filter((item) => {
      const chipDef = cfg.chips.find((candidate) => candidate.key === filters.chip);
      if (chipDef?.test && !chipDef.test(item)) return false;
      for (const menu of cfg.menus ?? []) {
        const value = filters.menus[menu.key];
        if (value && !menu.test(item, value)) return false;
      }
      return !needle || cfg.searchText(item).toLowerCase().includes(needle);
    });
  }

  const filtered = () => filters.q.trim() !== "" || filters.chip !== "all" || Object.keys(filters.menus).length > 0;

  // ---- Painting -----------------------------------------------------------------------------

  function build() {
    const count = el("span", { class: "cnt", "aria-live": "polite" });
    const stamp = el("span", { class: "cnt small keep" });
    const refresh = iconButton("refresh", "Refresh", () => reload());
    const primary = button(cfg.primary.label, { kind: "tonal", glyph: cfg.primary.glyph, onClick: () => cfg.primary.onClick(ctx), ariaLabel: cfg.primary.ariaLabel });
    primary.classList.add("primary");
    const head = el("div", { class: "mhead" }, el("h1", { text: cfg.title, tabindex: "-1" }), count, el("span", { class: "sp" }), stamp, refresh, primary);

    const search = el("input", {
      type: "search",
      placeholder: cfg.searchLabel,
      "aria-label": cfg.searchLabel,
      autocomplete: "off",
      spellcheck: "false",
      on: {
        input: () => {
          filters.q = search.value;
          keepAddress(addressFor(selectedId));
          paintRows();
          paintHead();
          paintChips();
        },
      },
    });
    const clearSearch = iconButton("close", "Clear search", () => {
      search.value = "";
      filters.q = "";
      keepAddress(addressFor(selectedId));
      search.focus();
      paintRows();
      paintHead();
      paintChips();
    });
    clearSearch.hidden = true;
    const searchBox = el("div", { class: "search" }, icon("search"), search, clearSearch);
    const chips = el("div", { class: "fchips", role: "group", "aria-label": `Filter ${many}` });
    const tools = el("div", { class: "tools" }, searchBox, chips);
    const slot = el("div", { class: "banner-slot" });
    const extra = el("div", { class: "extra" });
    const bar = el("div", { class: "prog", role: "progressbar", "aria-label": `Loading ${many}`, hidden: true });
    const table = el("div", { class: "tbl" });
    const left = el("div", { class: "left" }, head, bar, tools, slot, extra, table);
    const scrim = el("div", { class: "sheet-scrim", hidden: true, on: { click: () => close() } });
    const pane = el("section", { class: "pane", hidden: true });
    const prompt = el("div", { class: "pane prompt" }, cfg.prompt ? emptyState({ glyph: cfg.prompt.glyph, title: cfg.prompt.title, body: cfg.prompt.text }) : null);
    const cols = el("div", { class: "cols" }, left, scrim, pane, prompt);
    return { count, stamp, refresh, primary, head, search, clearSearch, chips, tools, slot, extra, bar, table, left, scrim, pane, prompt, cols };
  }

  function paintAll() {
    paintHead();
    paintChips();
    paintBanner();
    paintRows();
    paintPane();
  }

  function paintHead() {
    if (!nodes) return;
    const first = items === null && error === null;
    const total = items?.length ?? 0;
    const shown = items ? visible().length : 0;
    let text = "";
    if (first) text = `Loading ${many}…`;
    else if (items) text = cfg.countText ? cfg.countText(items, shown, filtered()) : filtered() ? `${shown} of ${total} ${many}` : `${total} ${total === 1 ? one : many}`;
    nodes.count.textContent = text;
    nodes.stamp.textContent = first ? "" : error && items ? `Older list · ${clock(loadedAt)}` : loadedAt ? `Updated ${clock(loadedAt)}` : "";
    nodes.bar.hidden = !loading;
    nodes.refresh.disabled = loading && first;
    const enabled = cfg.primary.enabled ? cfg.primary.enabled(ctx) : true;
    nodes.primary.disabled = !enabled;
    nodes.clearSearch.hidden = filters.q === "";
    nodes.search.value = filters.q;
  }

  function paintChips() {
    if (!nodes) return;
    const empty = items !== null && items.length === 0;
    nodes.tools.hidden = empty || (items === null && error !== null);
    const list = items ?? [];
    const group = nodes.chips;
    group.replaceChildren();
    for (const def of cfg.chips) {
      const on = filters.chip === def.key;
      const node = chip({
        label: def.label(list),
        on,
        onClick: () => {
          filters.chip = def.key;
          afterFilter(`chip-${def.key}`);
        },
      });
      node.dataset.key = `chip-${def.key}`;
      group.append(node);
    }
    for (const menu of cfg.menus ?? []) {
      const value = filters.menus[menu.key];
      const options = menu.options(list);
      const current = options.find((option) => option.value === value);
      const node = chip({
        label: current ? `${menu.prefix}: ${current.text}` : menu.anyLabel ? `${menu.prefix}: ${menu.anyLabel}` : menu.prefix,
        on: Boolean(current),
        menu: true,
        onClick: () => {
          openMenu(node, {
            placement: "below-start",
            label: `${menu.prefix} filter`,
            narrow: true,
            items: [
              { label: menu.anyLabel ?? "Any", selected: !value, onSelect: () => setMenu(menu.key, "") },
              ...options.map((option) => ({ label: option.text, selected: option.value === value, onSelect: () => setMenu(menu.key, option.value) })),
            ],
          });
        },
      });
      node.dataset.key = `menu-${menu.key}`;
      if (current) node.prepend(icon("check", "ms18"));
      group.append(node);
    }
  }

  function setMenu(key, value) {
    if (value) filters.menus[key] = value;
    else delete filters.menus[key];
    afterFilter(`menu-${key}`);
  }

  function afterFilter(focusKey) {
    keepAddress(addressFor(selectedId));
    paintHead();
    paintChips();
    paintRows();
    nodes.chips.querySelector(`[data-key='${focusKey}']`)?.focus();
  }

  function paintExtra() {
    nodes.extra.replaceChildren();
    const more = items && cfg.extra ? cfg.extra(ctx) : null;
    if (more) nodes.extra.append(more);
  }

  function paintBanner() {
    paintExtra();
    nodes.slot.replaceChildren();
    if (error && items) {
      const text = `Could not load the ${many}. ${error.message} This is the list from ${clock(loadedAt)}.`;
      nodes.slot.append(banner({ glyph: "cloud_off", text, error: true, role: "alert", actions: [button("Try again", { onClick: () => reload() })] }));
    }
  }

  function rowId(item) {
    return `row-${cfg.idOf(item)}`;
  }

  function paintRows() {
    if (!nodes) return;
    const table = nodes.table;
    const focusedRow = document.activeElement?.closest?.(".tr")?.id ?? null;
    nodes.table.classList.toggle("older", Boolean(error && items));
    if (items === null && error === null) {
      table.replaceChildren(skeletonRows());
      table.setAttribute("aria-busy", "true");
      return;
    }
    table.removeAttribute("aria-busy");
    if (items === null) {
      // The very first read failed: there is no older list to show.
      table.replaceChildren(
        emptyState({
          glyph: "cloud_off",
          title: `Could not load the ${many}`,
          body: `${error.message} It tries again by itself every 30 seconds.`,
          action: button("Try again", { kind: "tonal", glyph: "refresh", onClick: () => reload() }),
        }),
      );
      return;
    }
    if (items.length === 0) {
      table.replaceChildren(
        emptyState({
          glyph: cfg.emptyAll.glyph,
          title: cfg.emptyAll.title,
          body: cfg.emptyAll.body,
          action: cfg.primary.emptyAction === false ? null : button(cfg.primary.label, { kind: "tonal", glyph: cfg.primary.glyph, onClick: () => cfg.primary.onClick(ctx), ariaLabel: cfg.primary.ariaLabel }),
        }),
      );
      return;
    }
    const shown = visible();
    if (shown.length === 0) {
      const text = filters.q.trim() ? `Nothing is named “${filters.q.trim()}” with these filters. Check the spelling, or clear the search and filters.` : "Nothing matches these filters. Clear them to see every one.";
      table.replaceChildren(
        emptyState({
          glyph: "search_off",
          title: `No ${many} match`,
          body: text,
          action: button("Clear search and filters", { kind: "tonal", onClick: clearFilters }),
        }),
      );
      return;
    }
    const grid = el("div", { role: "grid", "aria-label": cfg.title, "aria-rowcount": String(shown.length + 1) });
    grid.append(el("div", { class: `th ${cfg.gridClass}`, role: "row" }, cfg.columns.map((column) => el("span", { role: "columnheader", class: column.className ?? null, text: column.label }))));
    const rows = shown.map((item) => buildRow(item));
    grid.append(...rows);
    // One tab stop: the selected row, else the first.
    const stop = rows.find((row) => row.getAttribute("aria-selected") === "true") ?? rows[0];
    stop.tabIndex = 0;
    grid.addEventListener("keydown", onGridKey);
    table.replaceChildren(grid);
    if (focusedRow) document.getElementById(focusedRow)?.focus({ preventScroll: true });
  }

  function buildRow(item) {
    const parts = cfg.rowParts(item, ctx);
    const selected = cfg.idOf(item) === selectedId;
    const row = el(
      "div",
      { class: `tr ${cfg.gridClass}${parts.revoked ? " rev" : ""}`, id: rowId(item), role: "row", tabindex: "-1", "aria-selected": String(selected), "aria-label": parts.label, data: { id: cfg.idOf(item) } },
      el("span", { class: "nmc", role: "gridcell" }, parts.name, parts.sub ? el("span", { class: "sub", text: parts.sub }) : null),
      ...parts.cells.map((cell, index) => {
        const column = cfg.columns[index + 1];
        return el("span", { class: `cell ${column?.className ?? ""}`.trim(), role: "gridcell" }, cell);
      }),
      parts.line2 ? el("span", { class: "m2", "aria-hidden": "true", text: parts.line2 }) : null,
    );
    row.addEventListener("click", () => open(cfg.idOf(item)));
    return row;
  }

  function onGridKey(event) {
    const rows = [...nodes.table.querySelectorAll(".tr")];
    const at = rows.indexOf(document.activeElement);
    if (at < 0) return;
    let next = null;
    if (event.key === "ArrowDown") next = rows[Math.min(rows.length - 1, at + 1)];
    else if (event.key === "ArrowUp") next = rows[Math.max(0, at - 1)];
    else if (event.key === "Home") next = rows[0];
    else if (event.key === "End") next = rows.at(-1);
    else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      open(rows[at].dataset.id);
      return;
    }
    if (!next) return;
    event.preventDefault();
    for (const row of rows) row.tabIndex = row === next ? 0 : -1;
    next.focus();
  }

  function clearFilters() {
    filters.q = "";
    filters.chip = "all";
    filters.menus = {};
    keepAddress(addressFor(selectedId));
    paintHead();
    paintChips();
    paintRows();
    nodes.search.focus();
  }

  // ---- The pane -----------------------------------------------------------------------------

  function open(id) {
    focusPane = true;
    restoreFocus = id;
    go(addressFor(id));
  }

  function select(id) {
    open(id);
  }

  function close() {
    if (!selectedId) return;
    restoreFocus = selectedId;
    go(addressFor(null));
  }

  function focusRow(id) {
    const node = document.getElementById(`row-${id}`);
    if (node) {
      for (const row of nodes.table.querySelectorAll(".tr")) row.tabIndex = row === node ? 0 : -1;
      node.focus({ preventScroll: false });
    }
  }

  function setNote(next) {
    clearTimeout(noteTimer);
    note = next;
    if (next && next.type === "ok") noteTimer = setTimeout(() => dismissNote(), NOTE_MS);
    if (selectedId) paintPane(true);
  }

  function dismissNote() {
    clearTimeout(noteTimer);
    note = null;
    if (selectedId) paintPane(true);
  }

  function noteNode() {
    if (!note) return null;
    if (note.type === "ok") {
      return el(
        "div",
        { class: "bn neu", role: "status" },
        icon("check_circle", "c-primary fill"),
        el("span", { class: "tx", text: note.text }),
        iconButton("close", "Dismiss", () => dismissNote()),
      );
    }
    return el(
      "div",
      { class: "bn err", role: "alert" },
      icon("error"),
      el("span", { class: "tx", text: note.text }),
      note.retry ? button("Try again", { onClick: () => { const retry = note.retry; dismissNote(); retry(); } }) : null,
    );
  }

  /** Draws the pane for the selected item. `force` draws again even if nothing it shows changed. */
  function paintPane(force = false) {
    if (!nodes) return;
    const item = ctx.selected;
    const showing = selectedId !== null;
    setDetailOpen(showing && item !== null);
    nodes.scrim.hidden = !showing || item === null;
    nodes.prompt.hidden = showing || items === null || items.length === 0;
    for (const row of nodes.table.querySelectorAll(".tr")) row.setAttribute("aria-selected", String(row.dataset.id === selectedId));
    if (!showing || !item) {
      nodes.pane.hidden = true;
      rendered = null;
      if (showing && items !== null && !loading) {
        // An address naming something that is not in the list (deleted since): back to the list.
        selectedId = null;
        keepAddress(addressFor(null));
        setDetailOpen(false);
        nodes.prompt.hidden = items.length === 0;
      }
      return;
    }
    const signature = JSON.stringify([item, note ? [note.type, note.text] : null]);
    if (!force && rendered === signature && !nodes.pane.hidden) return;
    const wasOpen = !nodes.pane.hidden;
    const body = nodes.pane.querySelector(".pbody");
    const scroll = wasOpen && body ? body.scrollTop : 0;
    const parts = cfg.renderPane(item, ctx);
    const titleId = "pane-title";
    const header = el(
      "div",
      { class: "phd" },
      iconButton("arrow_back", "Back", () => close(), { class: "back" }),
      el("div", { class: "hd" }, el("h2", { id: titleId, tabindex: "-1", title: parts.title, text: parts.title }), parts.titleExtra ?? null),
      ...(parts.actions ?? []),
      iconButton("close", `Close ${parts.title}`, () => close(), { class: "close" }),
    );
    const content = el("div", { class: "pbody" }, noteNode(), parts.body);
    nodes.pane.setAttribute("aria-labelledby", titleId);
    nodes.pane.replaceChildren(header, content);
    nodes.pane.hidden = false;
    content.scrollTop = scroll;
    rendered = signature;
    if (focusPane) {
      focusPane = false;
      nodes.pane.querySelector("h2").focus({ preventScroll: true });
    }
    document.getElementById(`row-${selectedId}`)?.scrollIntoView?.({ block: "nearest" });
  }

  function onKey(event) {
    if (event.key !== "Escape" || !selectedId) return;
    if (document.querySelector(".scrim, .menu")) return;
    event.preventDefault();
    close();
  }

  function onVisible() {
    if (document.visibilityState === "visible" && host) reload();
  }

  // ---- Section ------------------------------------------------------------------------------

  return {
    ctx,
    mount({ container, route: where }) {
      host = container;
      route = where;
      items = null;
      error = null;
      loadedAt = null;
      loading = false;
      note = null;
      rendered = null;
      readQuery(where.query);
      selectedId = where.id && ID.test(where.id) ? where.id : null;
      nodes = build();
      host.replaceChildren(nodes.cols);
      host.hidden = false;
      paintAll();
      document.addEventListener("keydown", onKey);
      document.addEventListener("visibilitychange", onVisible);
      timer = setInterval(() => {
        if (document.visibilityState === "visible" && !document.querySelector(".scrim")) reload();
      }, REFRESH_MS);
      reload();
    },
    update(where) {
      route = where;
      const before = selectedId;
      const nextId = where.id && ID.test(where.id) ? where.id : null;
      readQuery(where.query);
      selectedId = nextId;
      if (before !== nextId) note = null;
      paintHead();
      paintChips();
      paintRows();
      paintPane(before !== nextId);
      if (before && !nextId && restoreFocus) {
        focusRow(restoreFocus);
        restoreFocus = null;
      }
    },
    unmount() {
      clearInterval(timer);
      clearTimeout(noteTimer);
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("visibilitychange", onVisible);
      host = null;
      nodes = null;
      items = null;
      setDetailOpen(false);
    },
  };
}

export { avatar, announce };
