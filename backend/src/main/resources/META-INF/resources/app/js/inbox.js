// The inbox: events of the producers the person subscribed to, newest first, with the app's
// filters; on a wide page an open event sits beside the list, on a narrow one it takes the screen.

import { ApiError, SessionEnded, calls } from "./api.js";
import { clear, el, icon, replace, webLink } from "./dom.js";
import { CATEGORIES, SEVERITIES, categoryOf, severityLabel, toneOf } from "./event-style.js";
import { clock, rowTime, timestamp } from "./format.js";
import { chip, paneHeader, selectPrompt } from "./parts.js";
import { go, hashFor, parseHash } from "./router.js";
import { setUnread, state } from "./state.js";
import { announce, bannerSlot, button, emptyState, hideBanner, iconButton, openDialog, setBusy, showBanner, skeletonRows, spinner, banner } from "./ui.js";

const PAGE = 50;

/** The filter in the address: `?unread=1&producer=ID&category=INFO&severity=HIGH`. */
export function readFilter(query) {
  return {
    unread: query.get("unread") === "1",
    producers: query.getAll("producer"),
    categories: query.getAll("category").filter((value) => CATEGORIES.some((c) => c.value === value)),
    severities: query.getAll("severity").filter((value) => SEVERITIES.some((s) => s.value === value)),
  };
}

function filterQuery(filter) {
  const query = new URLSearchParams();
  if (filter.unread) query.set("unread", "1");
  for (const id of filter.producers) query.append("producer", id);
  for (const value of filter.categories) query.append("category", value);
  for (const value of filter.severities) query.append("severity", value);
  return query;
}

const isActive = (filter) => filter.unread || narrows(filter);
// Marking everything read up to an event would mark events the person cannot see, so it is
// off while a filter leaves some out by what they are.
const narrows = (filter) => filter.producers.length || filter.categories.length || filter.severities.length;

function admits(filter, event) {
  return (
    (!filter.unread || !event.readAt) &&
    (!filter.producers.length || filter.producers.includes(event.producer.id)) &&
    (!filter.categories.length || filter.categories.includes(event.category)) &&
    (!filter.severities.length || filter.severities.includes(event.severity))
  );
}

function listQuery(filter, cursor) {
  const query = new URLSearchParams({ limit: String(PAGE) });
  if (cursor) query.set("cursor", cursor);
  if (filter.unread) query.set("read", "false");
  for (const id of [...filter.producers].sort()) query.append("producerId", id);
  for (const value of [...filter.categories].sort()) query.append("category", value);
  for (const value of [...filter.severities].sort()) query.append("severity", value);
  return query.toString();
}

export function mountInbox(container, route, { wide }) {
  let filter = readFilter(route.query);
  let selected = route.segments[1] ?? null;
  let events = [];
  let nextCursor = null;
  let phase = "loading"; // loading | ready | failed
  let problem = null; // null | "offline" | "stale"
  let loadedAt = null;
  let loadingMore = false;
  let moreFailed = false;
  let producerNames = new Map();
  let subscribed = [];
  let detailToken = 0;
  let current = null; // the event shown in the detail pane
  let observer = null;
  let retryTimer = null;
  let gone = false;

  const address = () => hashFor(["inbox"], filterQuery(filter));
  const eventHash = (id) => hashFor(["inbox", id], filterQuery(filter));

  // ---- Frame ----------------------------------------------------------------------------

  const listHost = el("div", { class: "list-host" });
  const filterBar = el("div", { class: "filter-bar" });
  const header = el("div", { class: "head-host" });
  const listPane = el("section", { class: "listp", "aria-label": "Events" }, header, filterBar, bannerSlot(), listHost);
  const detail = el("section", { class: "detp", "aria-label": "Event" });
  container.className = `main${selected ? " has-detail" : ""}`;
  replace(container, listPane, detail);

  function paintHeader() {
    const active = isActive(filter);
    const unread = state.unread ?? 0;
    const markAll = iconButton("done_all", "Mark all as read", markAllRead, {
      disabled: !events.length || unread === 0 || Boolean(narrows(filter)) || problem === "offline",
    });
    const filterButton = iconButton(active ? "filter_alt" : "filter_list", "Filter events", editFilter, {
      fill: active,
      aria: { "aria-haspopup": "dialog", "aria-pressed": String(active) },
    });
    replace(header, paneHeader({ title: wide ? "Inbox" : "SignalHub", actions: [filterButton, markAll], account: !wide }));
  }

  function paintFilterBar() {
    if (!isActive(filter)) {
      clear(filterBar);
      filterBar.hidden = true;
      return;
    }
    filterBar.hidden = false;
    const chips = [];
    const change = (next) => go(hashFor(selected ? ["inbox", selected] : ["inbox"], filterQuery(next)));
    if (filter.unread) chips.push(chip({ label: "Unread", on: true, remove: () => change({ ...filter, unread: false }) }));
    for (const id of filter.producers) {
      chips.push(chip({ label: producerNames.get(id) ?? "Producer", on: true, remove: () => change({ ...filter, producers: filter.producers.filter((p) => p !== id) }) }));
    }
    for (const value of filter.categories) {
      chips.push(chip({ label: categoryOf(value).label, on: true, remove: () => change({ ...filter, categories: filter.categories.filter((c) => c !== value) }) }));
    }
    for (const value of filter.severities) {
      chips.push(chip({ label: severityLabel(value), on: true, remove: () => change({ ...filter, severities: filter.severities.filter((s) => s !== value) }) }));
    }
    replace(filterBar, ...chips, button("Clear", { kind: "text", onClick: () => change({ unread: false, producers: [], categories: [], severities: [] }) }));
  }

  // ---- The list -------------------------------------------------------------------------

  function eventRow(event) {
    const unread = !event.readAt;
    const category = categoryOf(event.category);
    return el(
      "li",
      { data: { id: event.id } },
      el(
        "a",
        { class: `lt event-row${event.id === selected ? " sel" : ""}`, href: eventHash(event.id), "aria-current": event.id === selected ? "true" : null },
        icon(category.glyph, toneOf(event.severity)),
        el(
          "div",
          { class: "tx" },
          el("span", { class: unread ? "t1b" : "t1", text: event.title }),
          el(
            "div",
            { class: "meta" },
            el("span", { class: "m1", text: `${category.label} · ${severityLabel(event.severity)} · ${event.producer.name}` }),
            webLink(event.link) ? icon("link", "ms16 c-var link-ic") : null,
            el("span", { class: "when", text: rowTime(event.createdAt) }),
          ),
        ),
        unread ? el("span", { class: "dot", role: "img", "aria-label": "Unread" }) : el("span", { class: "nodot" }),
      ),
    );
  }

  function paintList() {
    observer?.disconnect();
    observer = null;
    if (phase === "loading") {
      replace(listHost, skeletonRows(7));
      return;
    }
    if (phase === "failed") {
      replace(
        listHost,
        emptyState({
          glyph: "error_outline",
          title: "Couldn't load your events",
          body: "SignalHub didn't answer. Check your connection and try again.",
          action: button("Try again", { kind: "filled", glyph: "refresh", onClick: () => load() }),
        }),
      );
      return;
    }
    if (!events.length && !nextCursor) {
      replace(listHost, emptyInbox());
      return;
    }
    const list = el("ul", { class: "event-list", "aria-label": "Events" }, events.map(eventRow));
    list.addEventListener("keydown", onListKey);
    const footer = el("div", { class: "list-foot" });
    if (moreFailed) {
      footer.append(button("Couldn't load more. Try again", { kind: "text", glyph: "refresh", onClick: () => loadMore() }));
    } else if (nextCursor) {
      footer.append(skeletonRows(2));
      observer = new IntersectionObserver((entries) => entries.some((e) => e.isIntersecting) && loadMore(), { root: null, rootMargin: "200px" });
      observer.observe(footer);
    }
    replace(listHost, list, footer);
  }

  function emptyInbox() {
    if (isActive(filter)) {
      return emptyState({
        glyph: "filter_list_off",
        title: "No events match these filters",
        action: button("Clear filters", { kind: "tonal", onClick: () => go(selected ? hashFor(["inbox", selected]) : "#inbox") }),
      });
    }
    return emptyState({
      glyph: "inbox",
      title: "Nothing here yet",
      body: "Events from the producers you subscribed to will show up here.",
      action: button("Find producers", { kind: "tonal", onClick: () => go("#producers") }),
    });
  }

  function onListKey(event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    const rows = [...listHost.querySelectorAll("a.event-row")];
    const at = rows.indexOf(document.activeElement);
    if (at < 0) return;
    event.preventDefault();
    rows[Math.max(0, Math.min(rows.length - 1, at + (event.key === "ArrowDown" ? 1 : -1)))].focus();
  }

  function paintProblem() {
    if (problem === "offline") {
      const time = loadedAt ? clock(loadedAt) : "";
      showBanner("inbox", () => banner({ glyph: "cloud_off", text: `You're offline. This is what was loaded at ${time}. Changes are paused until you're back.` }));
    } else if (problem === "stale") {
      showBanner("inbox", () =>
        banner({ glyph: "history", text: `Couldn't refresh. This is the list from ${loadedAt ? clock(loadedAt) : ""}.`, actions: [button("Try again", { onClick: () => load(true) })] }),
      );
    } else {
      hideBanner("inbox");
    }
  }

  async function load(quiet = false) {
    clearTimeout(retryTimer);
    if (!quiet && !events.length) {
      phase = "loading";
      paintList();
    }
    try {
      const page = await calls.events(listQuery(filter));
      if (gone) return;
      mergeFirstPage(page);
      phase = "ready";
      problem = null;
      loadedAt = new Date();
      moreFailed = false;
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      if (events.length) {
        problem = error instanceof ApiError && error.offline ? "offline" : "stale";
        if (problem === "offline") retryTimer = setTimeout(() => load(true), 8000);
      } else {
        phase = "failed";
      }
    }
    paintProblem();
    paintHeader();
    paintList();
    refreshUnread();
  }

  // New events join at the top; older pages the person already scrolled to are kept.
  function mergeFirstPage(page) {
    const items = page.items;
    if (events.length <= PAGE || !items.length) {
      events = items;
      nextCursor = page.nextCursor;
      return;
    }
    // Ids are time-ordered (UUIDv7), newest first.
    const oldest = items.at(-1).id;
    events = [...items, ...events.filter((event) => event.id < oldest)];
  }

  async function loadMore() {
    if (loadingMore || !nextCursor) return;
    loadingMore = true;
    moreFailed = false;
    try {
      const page = await calls.events(listQuery(filter, nextCursor));
      if (gone) return;
      const known = new Set(events.map((event) => event.id));
      events = [...events, ...page.items.filter((event) => !known.has(event.id))];
      nextCursor = page.nextCursor;
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      moreFailed = true;
    }
    loadingMore = false;
    paintList();
  }

  async function refreshUnread() {
    try {
      const { unread } = await calls.unreadCount();
      if (!gone) {
        setUnread(unread);
        paintHeader();
      }
    } catch {
      // The banner already says what is wrong; the badge keeps its last number.
    }
  }

  async function markAllRead() {
    if (!events.length) return;
    try {
      await calls.markReadThrough(events[0].id);
      announce("All events marked as read");
    } catch (error) {
      if (error instanceof SessionEnded) return;
      announce("Couldn't mark the events as read. Try again.");
    }
    await load(true);
  }

  // ---- Filter ---------------------------------------------------------------------------

  async function loadProducers() {
    try {
      const { items } = await calls.visibleProducers();
      if (gone) return;
      producerNames = new Map(items.map((producer) => [producer.id, producer.name]));
      subscribed = items.filter((producer) => producer.subscribed);
      paintFilterBar();
    } catch {
      // The filter's producer list is optional; chips fall back to a generic name.
    }
  }

  function editFilter() {
    const draft = { unread: filter.unread, producers: [...filter.producers], categories: [...filter.categories], severities: [...filter.severities] };
    const toggled = (list, value) => (list.includes(value) ? list.filter((item) => item !== value) : [...list, value]);
    const body = el("div", { class: "filter-sheet" });
    const paint = () => {
      const group = (title, chips) => [el("div", { class: "lab", text: title }), el("div", { class: "chips" }, chips)];
      replace(
        body,
        el("div", { class: "lt switch-row" }, el("div", { class: "tx" }, el("span", { class: "t1", text: "Unread only" })), toggleSwitch(draft.unread, "Unread only", (on) => { draft.unread = on; paint(); })),
        ...group(
          "Producers",
          subscribed.length
            ? subscribed.map((producer) => chip({ label: producer.name, on: draft.producers.includes(producer.id), onClick: () => { draft.producers = toggled(draft.producers, producer.id); paint(); } }))
            : [el("span", { class: "p", text: "Producers you subscribe to appear here." })],
        ),
        ...group("Categories", CATEGORIES.map((category) => chip({ label: category.label, on: draft.categories.includes(category.value), onClick: () => { draft.categories = toggled(draft.categories, category.value); paint(); } }))),
        ...group("Severities", SEVERITIES.map((severity) => chip({ label: severity.label, on: draft.severities.includes(severity.value), onClick: () => { draft.severities = toggled(draft.severities, severity.value); paint(); } }))),
      );
    };
    paint();
    const dialog = openDialog({
      title: "Show in the inbox",
      content: body,
      actions: [
        { label: "Clear all", value: "clear" },
        { label: "Done", value: "done", kind: "text" },
      ],
      initialFocus: "done",
    });
    dialog.done.then((value) => {
      if (value === "clear") go(selected ? hashFor(["inbox", selected]) : "#inbox");
      else if (value === "done") go(hashFor(selected ? ["inbox", selected] : ["inbox"], filterQuery(draft)));
    });
  }

  // ---- The open event -------------------------------------------------------------------

  function detailHeader(event) {
    const mark = event
      ? button(event.readAt ? "Mark as unread" : "Mark as read", {
          glyph: event.readAt ? "mark_email_unread" : "mark_email_read",
          onClick: (click) => toggleRead(event, click.currentTarget),
        })
      : null;
    return mark;
  }

  async function toggleRead(event, node) {
    setBusy(node, true);
    try {
      const changed = event.readAt ? await calls.markUnread(event.id) : await calls.markRead(event.id);
      current = changed;
      replaceInList(changed);
      refreshUnread();
      if (!wide && !changed.readAt) {
        // Marked unread to come back to later: back to the inbox, as in the app.
        go(address());
        return;
      }
    } catch (error) {
      if (error instanceof SessionEnded) return;
      announce("Couldn't change it. Try again.");
    }
    paintDetail(current);
  }

  function replaceInList(changed) {
    const at = events.findIndex((event) => event.id === changed.id);
    if (at < 0) return;
    if (admits(filter, changed)) events[at] = changed;
    else events.splice(at, 1);
    const item = listHost.querySelector(`li[data-id="${CSS.escape(changed.id)}"]`);
    if (!item) return;
    if (!admits(filter, changed)) item.remove();
    else item.replaceWith(eventRow(changed));
    if (!events.length && !nextCursor) paintList();
  }

  function detailBody(event) {
    const category = categoryOf(event.category);
    const field = (name, value, className = "") => [el("b", { text: name }), el("span", { class: className, text: value })];
    const link = webLink(event.link);
    const rows = [
      ...field("Producer", event.producer.name),
      ...(event.context ? field("Context", event.context) : []),
      ...(event.link ? field("Link", event.link, "break") : []),
      ...(event.occurredAt ? field("Occurred", timestamp(event.occurredAt)) : []),
      ...field("Received", timestamp(event.createdAt)),
      ...field("Read", event.readAt ? timestamp(event.readAt) : "Unread"),
      ...field("Event ID", event.id, "mono break"),
    ];
    const metadata = event.metadata && Object.keys(event.metadata).length ? event.metadata : null;
    return [
      el("h2", { class: "h", text: event.title }),
      el("div", { class: "chips" }, el("span", { class: "chip" }, icon(category.glyph), category.label), el("span", { class: "chip" }, icon("priority_high", toneOf(event.severity)), severityLabel(event.severity))),
      event.message ? el("p", { class: "body", text: event.message }) : null,
      link ? el("div", {}, el("a", { class: "btn btn-t", href: link, target: "_blank", rel: "noopener noreferrer" }, icon("open_in_new"), el("span", { class: "btn-label", text: "Open link" }))) : null,
      el("div", { class: "kv" }, rows),
      metadata ? el("div", { class: "metadata-block" }, el("div", { class: "lab", text: "Metadata" }), el("pre", { class: "metadata mono", text: JSON.stringify(metadata, null, 2) })) : null,
    ];
  }

  function paintDetail(event, status = "ready") {
    if (!selected) {
      replace(detail, wide ? selectPrompt("inbox", "Select an event", "Pick one from the list to read it here.") : null);
      return;
    }
    if (status === "missing") {
      const body = emptyState({
        glyph: "search_off",
        title: "This isn't here",
        body: "It may have been deleted, or it isn't one of yours.",
        action: button("Back to the inbox", { kind: "tonal", onClick: () => go(address()) }),
      });
      replace(detail, wide ? null : paneHeader({ title: "Event", back: address() }), body);
      return;
    }
    if (status === "loading" || !event) {
      replace(detail, wide ? null : paneHeader({ title: "Event", back: address() }), el("div", { class: "detail-skeleton" }, skeletonRows(3)));
      return;
    }
    const mark = detailHeader(event);
    if (wide) {
      replace(detail, el("div", { class: "row end" }, mark), ...detailBody(event));
    } else {
      replace(detail, paneHeader({ title: "Event", back: address(), actions: [mark] }), el("div", { class: "detail-scroll" }, detailBody(event)));
    }
    detail.scrollTop = 0;
  }

  async function open(id) {
    const token = ++detailToken;
    const known = events.find((event) => event.id === id);
    current = known ?? null;
    paintDetail(known ?? null, known ? "ready" : "loading");
    let event;
    try {
      event = await calls.event(id);
    } catch (error) {
      if (gone || token !== detailToken || error instanceof SessionEnded) return;
      if (error instanceof ApiError && (error.status === 404 || error.status === 400)) paintDetail(null, "missing");
      else if (!known) paintDetail(null, "missing");
      return;
    }
    if (gone || token !== detailToken) return;
    current = event;
    // Opening an event reads it, as in the app.
    if (!event.readAt) {
      try {
        event = await calls.markRead(id);
        if (gone || token !== detailToken) return;
        current = event;
        replaceInList(event);
        refreshUnread();
      } catch (error) {
        if (error instanceof SessionEnded) return;
      }
    }
    paintDetail(current);
  }

  // ---- Public ---------------------------------------------------------------------------

  paintHeader();
  paintFilterBar();
  paintDetail(null);
  paintList();
  load();
  loadProducers();
  if (selected) open(selected);

  return {
    update(next) {
      const nextFilter = readFilter(next.query);
      const nextSelected = next.segments[1] ?? null;
      const filterChanged = JSON.stringify(nextFilter) !== JSON.stringify(filter);
      filter = nextFilter;
      selected = nextSelected;
      container.className = `main${selected ? " has-detail" : ""}`;
      paintHeader();
      paintFilterBar();
      if (filterChanged) {
        events = [];
        nextCursor = null;
        load();
      } else {
        for (const link of listHost.querySelectorAll("a.event-row")) {
          const id = link.parentElement.dataset.id;
          link.classList.toggle("sel", id === selected);
          link.toggleAttribute("aria-current", id === selected);
          link.setAttribute("href", eventHash(id));
        }
      }
      if (selected) open(selected);
      else {
        detailToken += 1;
        paintDetail(null);
      }
    },
    refresh() {
      return load(true);
    },
    unmount() {
      gone = true;
      observer?.disconnect();
      clearTimeout(retryTimer);
      hideBanner("inbox");
    },
  };
}

function toggleSwitch(checked, name, onChange) {
  const node = el("button", { type: "button", class: "sw", role: "switch", "aria-checked": String(checked), "aria-label": name }, el("span", { class: "sw-knob", "aria-hidden": "true" }));
  node.addEventListener("click", () => onChange(!checked));
  return node;
}

export { parseHash };
