// Producers: the ones this person sees, subscribing with the bell, their own with keys, who may
// see them, and creating one. The same screen as the app's Producers tab, laid out for a page.

import { ApiError, SessionEnded, calls } from "./api.js";
import { clear, el, icon, replace } from "./dom.js";
import { lastEvent, whenLabel } from "./format.js";
import { NameMessages, failureMessage, nameProblem, silent } from "./messages.js";
import { chip, paneHeader, selectPrompt } from "./parts.js";
import { go, hashFor } from "./router.js";
import { state } from "./state.js";
import {
  announce,
  avatar,
  banner,
  bannerSlot,
  button,
  confirmDialog,
  emptyState,
  hideBanner,
  iconButton,
  label,
  noticeBox,
  openDialog,
  row,
  segmented,
  setBusy,
  showBanner,
  skeletonRows,
  spinner,
  tag,
  textField,
  toggle,
  nextId,
} from "./ui.js";

const FILTERS = [
  { id: "all", label: "All", admits: () => true },
  { id: "yours", label: "Yours", admits: (row) => row.yours },
  { id: "subscribed", label: "Subscribed", admits: (row) => row.subscribed },
  { id: "can", label: "Can subscribe", admits: (row) => !row.subscribed },
  { id: "disabled", label: "Disabled", admits: (row) => row.disabled },
];

const keyLabel = (key) => `${key.prefix}…`;
const sharingLine = (people) => (people === 0 ? "Only you" : people === 1 ? "Shared with 1 person" : `Shared with ${people} people`);

/** The sentence under a producer's name in the list (see the design system, wording). */
export function summaryOf(row) {
  const own = row.own;
  if (!own) {
    return [row.owner.name, row.disabled ? "Disabled" : row.visibility === "PUBLIC" ? "Public" : "Private"].join(" · ");
  }
  if (own.disabledAt) return own.disabledByOperator ? "Disabled by the host · ask the host" : "Disabled by you · its keys do not work";
  const isPrivate = row.visibility === "PRIVATE";
  const people = own.allowedUsers.length;
  const keys = own.keys.filter((key) => !key.revokedAt).length;
  return [
    isPrivate ? "Private" : "Public",
    isPrivate && people > 0 ? (people === 1 ? "1 person" : `${people} people`) : keys === 1 ? "1 key" : `${keys} keys`,
    own.lastEventAt ? `last event ${lastEvent(own.lastEventAt)}` : "no events yet",
  ].join(" · ");
}

export function mountProducers(container, route, { wide }) {
  let selected = route.segments[1] ?? null;
  let visible = null; // the list, once read
  let own = new Map(); // by id
  let phase = "loading"; // loading | ready | failed
  let offline = false;
  let query = "";
  let filterId = "all";
  const changing = new Map(); // id -> true when subscribing, false when unsubscribing
  let loadedAt = null;
  let detailToken = 0;
  let gone = false;

  const header = el("div", { class: "head-host" });
  const searchHost = el("div", { class: "search-host" });
  const listHost = el("div", { class: "list-host" });
  const listPane = el("section", { class: "listp no-fab", "aria-label": "Producers" }, header, searchHost, bannerSlot(), listHost);
  const detail = el("section", { class: "detp prod", "aria-label": "Producer" });
  setLayout();
  replace(container, listPane, detail);

  function setLayout() {
    container.className = `main${selected ? " has-detail" : ""}`;
    document.body.classList.toggle("no-nav", !wide && selected === "new");
  }

  // ---- Data -----------------------------------------------------------------------------

  function rows() {
    const list = visible ?? [];
    const seen = new Set(list.map((producer) => producer.id));
    const all = list.map((producer) => rowOf(producer));
    for (const mine of own.values()) {
      // Owned, but not listed as visible: still the owner's to see.
      if (!seen.has(mine.id)) {
        all.push(rowOf({ id: mine.id, name: mine.name, owner: { id: state.me.userId, name: state.me.name }, visibility: mine.visibility, disabled: Boolean(mine.disabledAt), subscribed: mine.subscribed }));
      }
    }
    // Disabled producers (by their owner or by the host) follow, in the same order.
    const group = (r) => (r.disabled ? 3 : 0) + (r.yours ? 0 : r.subscribed ? 1 : 2);
    return all.sort((a, b) => group(a) - group(b) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()) || a.id.localeCompare(b.id));
  }

  function rowOf(producer) {
    const mine = own.get(producer.id) ?? null;
    return {
      id: producer.id,
      name: producer.name,
      owner: producer.owner,
      visibility: mine?.visibility ?? producer.visibility,
      subscribed: mine ? mine.subscribed : producer.subscribed,
      canAnswer: Boolean(mine) || Boolean(producer.canAnswer),
      disabled: mine ? Boolean(mine.disabledAt) : producer.disabled,
      yours: Boolean(mine),
      own: mine,
    };
  }

  async function load(quiet = false) {
    if (!quiet && !visible) {
      phase = "loading";
      paintList();
    }
    try {
      const [shown, mine] = await Promise.all([calls.visibleProducers(), calls.ownProducers()]);
      if (gone) return;
      visible = shown.items;
      own = new Map(mine.items.map((producer) => [producer.id, producer]));
      phase = "ready";
      offline = false;
      loadedAt = new Date();
    } catch (error) {
      if (gone || error instanceof SessionEnded) return;
      if (visible) offline = error instanceof ApiError && error.offline;
      else phase = "failed";
    }
    paintProblem();
    paintList();
    if (selected && selected !== "new") paintDetail();
  }

  function paintProblem() {
    if (offline) {
      showBanner("producers", () => banner({ glyph: "cloud_off", text: `You're offline. This is the list from ${loadedAt ? whenLabel(loadedAt) : ""}. Changes are paused until you're back.` }));
    } else {
      hideBanner("producers");
    }
  }

  // ---- The list -------------------------------------------------------------------------

  // A link, so Enter opens the form and it is the pane's first tab stop.
  function newProducerLink() {
    return el("a", { class: "btn btn-t", href: "#producers/new" }, icon("add"), el("span", { class: "btn-label", text: "New producer" }));
  }

  function paintHeader() {
    replace(header, paneHeader({ title: "Producers", actions: [newProducerLink()], account: !wide }));
    const input = el("input", { type: "search", class: "search-input", placeholder: "Find a producer", "aria-label": "Find a producer", autocomplete: "off", spellcheck: "false" });
    input.value = query;
    input.addEventListener("input", () => {
      query = input.value;
      clearButton.hidden = !query;
      paintList();
    });
    const clearButton = iconButton("close", "Clear search", () => {
      query = "";
      input.value = "";
      clearButton.hidden = true;
      paintList();
      input.focus();
    });
    clearButton.hidden = !query;
    const chips = el("div", { class: "fchips", role: "radiogroup", "aria-label": "Filter producers" });
    for (const filter of FILTERS) {
      chips.append(chip({ label: filter.label, on: filter.id === filterId, role: "radio", onClick: () => { filterId = filter.id; paintHeader(); paintList(); } }));
    }
    replace(searchHost, el("div", { class: "search" }, icon("search"), input, clearButton), chips);
  }

  function shownRows() {
    const filter = FILTERS.find((f) => f.id === filterId);
    const needle = query.trim().toLowerCase();
    return rows().filter((r) => filter.admits(r) && (!needle || r.name.toLowerCase().includes(needle)));
  }

  function paintList() {
    if (phase === "loading") {
      replace(listHost, skeletonRows(5, { circle: true }));
      return;
    }
    if (phase === "failed") {
      replace(
        listHost,
        emptyState({
          glyph: "error_outline",
          title: "Couldn't load producers",
          body: "Check your connection and try again.",
          action: button("Try again", { kind: "filled", glyph: "refresh", onClick: () => load() }),
        }),
      );
      return;
    }
    const shown = shownRows();
    if (!shown.length) {
      replace(listHost, emptyList());
      return;
    }
    const list = el("ul", { class: "producer-list", "aria-label": "Producers" }, shown.map(producerRow));
    list.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
      const links = [...list.querySelectorAll("a.prow")];
      const at = links.indexOf(document.activeElement);
      if (at < 0) return;
      event.preventDefault();
      links[Math.max(0, Math.min(links.length - 1, at + (event.key === "ArrowDown" ? 1 : -1)))].focus();
    });
    replace(listHost, list);
  }

  function emptyList() {
    const total = rows();
    if (query.trim()) {
      return emptyState({
        glyph: "search_off",
        title: "No producers match",
        body: `Nothing you can see is named “${query.trim()}”. Check the spelling, or clear the search.`,
        action: button("Clear search", { kind: "tonal", onClick: () => { query = ""; paintHeader(); paintList(); } }),
      });
    }
    if (!total.length) {
      return emptyState({
        glyph: "sensors",
        title: "No producers yet",
        body: "Nobody has shared a producer with you, and there is no public one on this server. Make your own to send yourself events.",
        action: button("New producer", { kind: "tonal", onClick: () => go("#producers/new") }),
      });
    }
    const show = { yours: ["You don't have a producer yet", "A producer sends events to you and, if you let them, to others. Each one has its own key.", "New producer"], subscribed: ["You aren't subscribed to any producer", "Subscribe with the bell on a producer, and its events show up in your inbox.", "Show all"], can: ["Nothing else to subscribe to", "You get events from every producer you can see. New public producers and ones shared with you will appear here.", "Show all"], disabled: ["No disabled producers", "A producer you disable, or the host disables, is listed here and at the bottom of the list.", "Show all"] }[filterId];
    return emptyState({
      glyph: "sensors",
      title: show[0],
      body: show[1],
      action: button(show[2], { kind: "tonal", onClick: () => (filterId === "yours" ? go("#producers/new") : (filterId = "all", paintHeader(), paintList())) }),
    });
  }

  function producerRow(r) {
    const busy = changing.has(r.id);
    const sel = r.id === selected;
    const glyph = r.own?.disabledAt && !r.own.disabledByOperator ? "pause_circle" : r.disabled ? "block" : "sensors";
    const summary = summaryOf(r);
    const link = el(
      "a",
      { class: "prow", href: `#producers/${encodeURIComponent(r.id)}`, "aria-current": sel ? "true" : null },
      el("span", { class: "av", "aria-hidden": "true" }, icon(glyph)),
      el(
        "div",
        { class: "tx" },
        el("span", { class: "t1" }, el("span", { class: "name", text: r.name }), r.yours ? el("span", { class: "own", text: "Yours" }) : null),
        el("span", { class: `t2n${r.own?.disabledByOperator && r.own.disabledAt ? " c-error" : ""}`, text: summary }),
      ),
    );
    return el("li", { class: `prow-item${sel ? " sel" : ""}`, data: { id: r.id } }, link, bell(r, busy));
  }

  function bell(r, busy) {
    const name = r.name;
    const direction = changing.get(r.id);
    const description = busy
      ? direction
        ? `Subscribing to ${name}`
        : `Unsubscribing from ${name}`
      : r.subscribed
        ? `Subscribed to ${name}. Double tap to unsubscribe.`
        : `Not subscribed to ${name}. Double tap to subscribe.`;
    const node = el(
      "button",
      { type: "button", class: `tbtn ${r.subscribed ? "on" : "off"}`, "aria-label": description, "aria-busy": busy ? "true" : null, disabled: offline || busy },
      busy ? spinner("ring") : icon(r.subscribed ? "notifications_active" : "notifications", r.subscribed ? "fill" : ""),
    );
    node.addEventListener("click", () => setSubscribed(r, !r.subscribed));
    return node;
  }

  async function setSubscribed(r, subscribe) {
    if (changing.has(r.id)) return;
    if (!subscribe) {
      const confirmed = await confirmDialog({
        title: `Unsubscribe from ${r.name}?`,
        message: "Its events leave your inbox. They come back if you subscribe again.",
        action: "Unsubscribe",
      });
      if (!confirmed) return;
    }
    changing.set(r.id, subscribe);
    hideBanner("producers-error");
    paintList();
    try {
      const changed = subscribe ? await calls.subscribe(r.id) : await calls.unsubscribe(r.id);
      replaceVisible(changed);
      announce(subscribe ? `Subscribed to ${r.name}. Its older events are in your inbox too.` : `Unsubscribed from ${r.name}. Its events leave your inbox.`);
    } catch (error) {
      if (error instanceof SessionEnded) {
        changing.delete(r.id);
        return;
      }
      if (error instanceof ApiError && error.status === 404) {
        // It went away, or this person lost access: it just leaves the list.
        visible = visible?.filter((producer) => producer.id !== r.id) ?? null;
        own.delete(r.id);
        if (selected === r.id) go("#producers");
      } else {
        const text = subscribe ? `Couldn't subscribe to ${r.name}. Try again.` : `Couldn't unsubscribe from ${r.name}. Try again.`;
        showBanner("producers-error", () =>
          banner({ glyph: "error", error: true, role: "alert", text, actions: [button("Retry", { onClick: () => setSubscribed(r, subscribe) })] }),
        );
      }
    }
    changing.delete(r.id);
    paintList();
    if (selected === r.id) paintDetail();
  }

  function replaceVisible(changed) {
    if (visible?.some((producer) => producer.id === changed.id)) {
      visible = visible.map((producer) => (producer.id === changed.id ? changed : producer));
    }
    const mine = own.get(changed.id);
    if (mine) own.set(changed.id, { ...mine, subscribed: changed.subscribed });
  }

  // ---- A producer -----------------------------------------------------------------------

  function paintDetail() {
    setLayout();
    if (!selected) {
      replace(detail, wide ? selectPrompt("sensors", "Select a producer", "Pick one from the list to see it here.") : null);
      return;
    }
    if (selected === "new") {
      newProducerForm();
      return;
    }
    if (phase === "loading" && !visible) {
      replace(detail, wide ? null : paneHeader({ title: "Producer", back: "#producers" }), skeletonRows(3));
      return;
    }
    const found = rows().find((r) => r.id === selected);
    if (!found) {
      replace(
        detail,
        wide ? null : paneHeader({ title: "Producer", back: "#producers" }),
        emptyState({
          glyph: "search_off",
          title: "This isn't here",
          body: "It may have been deleted, or it isn't one of yours.",
          action: button("Back to producers", { kind: "tonal", onClick: () => go("#producers") }),
        }),
      );
      return;
    }
    if (found.own) replace(detail, ...ownerView(found.own));
    else replace(detail, ...otherView(found));
  }

  function titleRow(name, ownerControls) {
    if (wide) {
      return el("div", { class: "row title-row" }, el("h2", { class: "h", text: name }), ownerControls ? iconButton("edit", `Rename ${name}`, () => renameDialog(ownerControls)) : null);
    }
    return paneHeader({
      title: name,
      back: "#producers",
      actions: ownerControls ? [iconButton("edit", `Rename ${name}`, () => renameDialog(ownerControls))] : [],
    });
  }

  function subscribedRow(producer, line, onChange) {
    const switchRow = el(
      "div",
      { class: "lt switch-row" },
      icon(producer.subscribed ? "notifications_active" : "notifications", producer.subscribed ? "c-primary" : "c-var"),
      el("div", { class: "tx" }, el("span", { class: "t1", text: "Subscribed" }), el("span", { class: "t2w", text: line })),
      toggle({ checked: producer.subscribed, label: "Subscribed", onChange, disabled: offline || changing.has(producer.id) }),
    );
    // Only the owner or an answerer, and only while unsubscribed: an unsubscribed person cannot
    // read the event, so this page is the one place that says why they cannot answer.
    if (!producer.canAnswer || producer.subscribed) return switchRow;
    return el(
      "div",
      { class: "stay-wrap" },
      switchRow,
      el(
        "div",
        { class: "stay" },
        icon("info", "c-var"),
        el("div", { class: "tx" }, el("span", { class: "t1", text: "Stay subscribed to answer" }), el("span", { class: "t2w", text: `While you're unsubscribed, ${producer.name}'s questions don't reach you, and you can't answer them.` })),
      ),
    );
  }

  // A row that does something when pressed (a plain row when there is nothing to do).
  function linkRow(glyph, title, text, onClick, trailing) {
    const node = el(
      onClick ? "button" : "div",
      { type: onClick ? "button" : null, class: `keyrow action-row${onClick ? "" : " quiet"}` },
      icon(glyph, "c-var"),
      el("div", { class: "tx" }, el("span", { class: "t1", text: title }), text ? el("span", { class: "t2w", text }) : null),
      trailing ?? null,
    );
    if (onClick) node.addEventListener("click", onClick);
    return node;
  }

  function otherView(r) {
    const owner = r.owner.name;
    const isPublic = r.visibility === "PUBLIC";
    const parts = [titleRow(r.name, null)];
    parts.push(bannerSlot());
    if (r.disabled) parts.push(noticeBox({ glyph: "pause_circle", text: "Disabled. It isn't sending events." }));
    parts.push(
      el(
        "div",
        { class: "lt owner-row" },
        avatar(owner),
        el(
          "div",
          { class: "tx" },
          el("span", { class: "t1", text: isPublic ? `${owner}'s producer` : `${owner} added you` }),
          el("span", { class: "t2w", text: isPublic ? "Public · anyone on this server can subscribe" : `Private · only ${owner} and the people ${owner} added can see it` }),
        ),
      ),
      subscribedRow(
        r,
        r.subscribed
          ? "Its events are in your inbox, and pushed as your filters allow. Turn it off and they leave your inbox; they come back if you subscribe again."
          : "Subscribe to get its events in your inbox. You'll find its older events too.",
        (on) => setSubscribed(r, on),
      ),
    );
    if (r.subscribed) parts.push(linkRow("filter_list", "See its events", null, () => go(hashFor(["inbox"], { producer: r.id })), icon("chevron_right", "c-var")));
    return parts;
  }

  function ownerView(p) {
    const r = rowOf({ id: p.id, name: p.name, owner: { id: state.me.userId, name: state.me.name }, visibility: p.visibility, disabled: Boolean(p.disabledAt), subscribed: p.subscribed });
    const byHost = Boolean(p.disabledAt) && p.disabledByOperator;
    const byYou = Boolean(p.disabledAt) && !byHost;
    const working = p.keys.filter((key) => !key.revokedAt);
    const noKey = !p.keys.length
      ? `No key yet. Nothing can send events as ${p.name}. Make a new key to start.`
      : !working.length
        ? `No working key. Nothing can send events as ${p.name}. Make a new key to start again.`
        : null;
    const writable = !offline;
    const parts = [titleRow(p.name, p), bannerSlot()];
    if (byHost) parts.push(noticeBox({ glyph: "block", error: true, text: "Disabled by the host. Its keys don't work. Ask the host to enable it." }));
    if (byYou) parts.push(noticeBox({ glyph: "pause_circle", text: "Disabled by you. Its keys don't work, so it sends nothing. Its events stay." }));
    if (noKey) parts.push(noticeBox({ glyph: "key_off", text: noKey }));
    parts.push(el("span", { class: "t2n", text: p.lastEventAt ? `Last event ${whenLabel(p.lastEventAt)}` : "No events yet" }));
    const subscribedLine = p.subscribed ? "Its events are in your inbox" : `You own it but don't get its events.${p.visibility === "PUBLIC" ? " Anyone on this server can still subscribe." : ""}`;
    parts.push(subscribedRow(r, subscribedLine, (on) => setSubscribed(r, on)));

    parts.push(label("Who can see it"));
    parts.push(
      segmented({
        label: "Who can see it",
        value: p.visibility,
        options: [
          { value: "PRIVATE", label: "Private", glyph: "lock", alwaysGlyph: true },
          { value: "PUBLIC", label: "Public", glyph: "public", alwaysGlyph: true },
        ],
        onChange: (value) => setVisibility(p, value),
        className: writable ? "" : "dis-all",
      }),
    );
    if (p.visibility === "PRIVATE") {
      parts.push(el("span", { class: "t2n", text: sharingLine(p.allowedUsers.length) }));
      const chips = el("div", { class: "chips" });
      for (const person of p.allowedUsers) {
        chips.append(
          el(
            "span",
            { class: "pchip" },
            el("span", { class: "avs", "aria-hidden": "true", text: [...person.name][0]?.toUpperCase() ?? "?" }),
            el("span", { text: person.name }),
            el("button", { type: "button", class: "pchip-x", "aria-label": `Remove ${person.name}`, disabled: !writable, on: { click: () => removePerson(p, person) } }, icon("close", "ms18 c-var")),
          ),
        );
      }
      chips.append(el("button", { type: "button", class: "pchip add", disabled: !writable, on: { click: () => addPeople(p) } }, icon("person_add", "ms18"), el("span", { text: "Add people" })));
      parts.push(chips);
    } else {
      parts.push(el("span", { class: "t2w", text: "Anyone on this server can find and subscribe to it." }));
    }

    parts.push(label("Who can answer"));
    parts.push(...answerersSection(p, writable));

    parts.push(label("Keys"));
    if (!p.keys.length) parts.push(el("div", { class: "keyrow" }, icon("key_off", "c-var"), el("div", { class: "tx" }, el("span", { class: "t1", text: "No keys" }))));
    for (const key of p.keys) parts.push(keyRow(p, key, byHost, byYou, writable));
    parts.push(el("div", { class: "row" }, button("New key", { kind: noKey ? "filled" : "outlined", glyph: "add", disabled: !writable, onClick: () => newKey(p) })));
    if (p.subscribed) parts.push(linkRow("filter_list", "See its events", null, () => go(hashFor(["inbox"], { producer: p.id })), icon("chevron_right", "c-var")));
    if (!p.disabledAt) {
      parts.push(linkRow("pause_circle", "Disable", "Its keys stop working. Its events stay.", writable ? () => disable(p) : null));
    } else if (byHost) {
      parts.push(linkRow("play_circle", "Enable", "Only the host can enable it", null));
    } else {
      parts.push(linkRow("play_circle", "Enable", "Its keys work again", writable ? () => change(p, () => calls.enableProducer(p.id), `enable ${p.name}`) : null));
    }
    return parts;
  }

  // The owner always can; each person the owner added can too, and the owner takes them away.
  function answerersSection(p, writable) {
    const answerers = p.answerers ?? [];
    const rows = [
      el("div", { class: "lt answerer-row" }, avatar(state.me.name), el("div", { class: "tx" }, el("span", { class: "t1", text: `${state.me.name} (you)` }), el("span", { class: "t2n", text: "Owner · can always answer" }))),
    ];
    for (const person of answerers) {
      rows.push(
        el(
          "div",
          { class: "lt answerer-row" },
          avatar(person.name),
          el("div", { class: "tx" }, el("span", { class: "t1", text: person.name }), el("span", { class: "t2n", text: "Can answer its questions" })),
          iconButton("close", `Remove ${person.name} from Who can answer`, () => removeAnswerer(p, person), { disabled: !writable }),
        ),
      );
    }
    if (!answerers.length) rows.push(el("span", { class: "t2n", text: "Only you can answer this producer's questions." }));
    rows.push(el("div", { class: "row" }, button("Add people who can answer", { kind: "text", glyph: "person_add", disabled: !writable, onClick: () => addAnswerers(p) })));
    return rows;
  }

  async function removeAnswerer(p, person) {
    const ok = await confirmDialog({
      title: `Remove ${person.name}?`,
      message: `${person.name} won't be able to answer ${p.name}'s questions any more. Answers ${person.name} already gave stay as they are.`,
      action: "Remove",
      destructive: true,
    });
    if (!ok) return;
    const attempt = () => change(p, () => calls.removeAnswerer(p.id, person.id), `remove ${person.name}`, { text: "Not removed", retry: attempt });
    await attempt();
  }

  async function addAnswerers(p) {
    let people;
    try {
      people = (await calls.users()).items;
    } catch (error) {
      if (error instanceof SessionEnded) return;
      showBanner("producers-error", () => banner({ glyph: "error", error: true, role: "alert", text: failureMessage(error, "load the people") }));
      return;
    }
    // Only people who can see the producer and cannot answer yet; the owner is not listed.
    const named = new Set(p.answerers.map((person) => person.id));
    const seeing = p.visibility === "PUBLIC" ? people.filter((person) => person.id !== state.me.userId) : p.allowedUsers;
    const candidates = seeing.filter((person) => !named.has(person.id));
    const checked = new Set();
    const body = el("div", { class: "answerer-pick" });
    let dialog;
    const refresh = () => {
      const add = dialog?.node.querySelector('[data-value="add"]');
      if (add) add.disabled = checked.size === 0;
    };
    if (!candidates.length) {
      const text = seeing.length ? `Everyone who can see ${p.name} can already answer.` : `Nobody else can see ${p.name}. Add people under Who can see it first.`;
      body.append(el("p", { class: "p dlg-text", text }));
    } else {
      body.append(el("p", { class: "p dlg-text", text: `Only people who can see ${p.name} and can't answer yet are listed. They also need to be subscribed to get its questions.` }));
      body.append(
        el(
          "div",
          { class: "pick-checks" },
          candidates.map((person) => {
            const input = el("input", { type: "checkbox", value: person.id });
            input.addEventListener("change", () => {
              if (input.checked) checked.add(person.id);
              else checked.delete(person.id);
              refresh();
            });
            return el("label", { class: "prow check-row" }, input, avatar(person.name), el("span", { class: "t1", text: person.name }), el("span", { class: "cb", "aria-hidden": "true" }, icon("check")));
          }),
        ),
      );
    }
    const actions = [{ label: "Cancel", value: "cancel", kind: "text" }];
    if (candidates.length) {
      actions.push({
        label: "Add",
        value: "add",
        kind: "text",
        disabled: true,
        run: async () => {
          for (const person of candidates.filter((c) => checked.has(c.id))) {
            const updated = await change(p, () => calls.addAnswerer(p.id, person.id), `add ${person.name}`);
            if (!updated) throw Object.assign(new Error(`Couldn't add ${person.name}. Try again.`), { silent: true });
            p = updated;
          }
        },
      });
    }
    dialog = openDialog({ title: "Add people who can answer", content: body, actions, initialFocus: "cancel" });
    body.querySelector("input")?.focus();
  }

  function keyRow(p, key, byHost, byYou, writable) {
    const lines = [
      key.revokedAt ? `Revoked ${whenLabel(key.revokedAt)}` : `Created ${whenLabel(key.createdAt)} · ${key.lastUsedAt ? `last used ${whenLabel(key.lastUsedAt)}` : "not used yet"}`,
    ];
    if (!key.revokedAt && p.disabledAt) lines.push(byHost ? "Not working while disabled" : "Not working while paused");
    return el(
      "div",
      { class: `keyrow${key.revokedAt ? " quiet" : ""}` },
      icon(key.revokedAt ? "key_off" : "key", "c-var"),
      el("div", { class: "tx" }, el("span", { class: "t1 mono small", text: keyLabel(key) }), ...lines.map((line) => el("span", { class: "t2n", text: line }))),
      key.revokedAt ? null : button("Revoke", { kind: "text", ariaLabel: `Revoke key ${keyLabel(key)}`, disabled: !writable, onClick: () => revokeKey(p, key) }),
    );
  }

  // ---- Changes to an owned producer -----------------------------------------------------

  // Runs a change, replaces the producer with the answer, and says a failure in a banner.
  async function change(p, call, doing, failed = null) {
    hideBanner("producers-error");
    try {
      const updated = await call();
      own.set(updated.id, updated);
      if (visible) visible = visible.map((producer) => (producer.id === updated.id ? { ...producer, name: updated.name, visibility: updated.visibility, subscribed: updated.subscribed, disabled: Boolean(updated.disabledAt) } : producer));
      paintList();
      if (selected === updated.id) paintDetail();
      return updated;
    } catch (error) {
      if (error instanceof SessionEnded) return null;
      if (error instanceof ApiError && error.status === 404) {
        await load(true);
        return null;
      }
      const text = error instanceof ApiError && error.status === 409 && p.disabledByOperator ? "Disabled by the host. Ask the host to enable it." : failureMessage(error, doing);
      showBanner("producers-error", () => banner({ glyph: "error", error: true, role: "alert", text: failed ? failed.text : text, actions: failed ? [button("Retry", { onClick: failed.retry })] : [] }));
      return null;
    }
  }

  async function setVisibility(p, value) {
    if (offline || value === p.visibility) return;
    if (value === "PRIVATE") {
      const others = p.allowedUsers.length ? "Only you and the people you add will see it. Everyone not on your list stops getting its events" : "Only you will see it. Everyone else stops getting its events";
      const ok = await confirmDialog({ title: `Make ${p.name} private?`, message: `${others}, and you'd have to add them to bring it back.`, action: "Make private" });
      if (!ok) return;
    }
    await change(p, () => calls.updateProducer(p.id, { visibility: value }), `change who can see ${p.name}`);
  }

  async function removePerson(p, person) {
    const ok = await confirmDialog({
      title: `Remove ${person.name}?`,
      message: `${person.name} can't see ${p.name} any more. If they were subscribed, they stop getting its events, and they have to subscribe again after you add them back.`,
      action: "Remove",
      destructive: true,
    });
    if (ok) await change(p, () => calls.disallowUser(p.id, person.id), `remove ${person.name}`);
  }

  async function addPeople(p) {
    let people;
    try {
      people = (await calls.users()).items;
    } catch (error) {
      if (error instanceof SessionEnded) return;
      showBanner("producers-error", () => banner({ glyph: "error", error: true, role: "alert", text: failureMessage(error, "load the people") }));
      return;
    }
    const added = new Set(p.allowedUsers.map((person) => person.id));
    const body = el("div", { class: "people-pick" });
    const search = textField({ label: "Search people", onInput: () => paint() });
    const listHolder = el("ul", { class: "pick-list" });
    const paint = () => {
      const needle = search.input.value.trim().toLowerCase();
      const candidates = people.filter((person) => person.id !== state.me.userId && (!needle || person.name.toLowerCase().includes(needle)));
      if (!candidates.length) {
        replace(listHolder, el("li", { class: "p pick-empty", text: needle ? "No one matches." : "There is no one else on this server yet." }));
        return;
      }
      replace(
        listHolder,
        candidates.map((person) => {
          const done = added.has(person.id);
          const add = button(done ? "Added" : "Add", { kind: "text", disabled: done, ariaLabel: `${done ? "Added" : "Add"} ${person.name}` });
          add.addEventListener("click", async () => {
            setBusy(add, true);
            const updated = await change(p, () => calls.allowUser(p.id, person.id), `add ${person.name}`);
            if (updated) {
              added.add(person.id);
              p = updated;
              paint();
            } else setBusy(add, false);
          });
          return el("li", { class: "lt" }, avatar(person.name), el("div", { class: "tx" }, el("span", { class: "t1", text: person.name })), add);
        }),
      );
    };
    paint();
    body.append(search.node, listHolder);
    openDialog({ title: "Add people", content: body, actions: [{ label: "Done", value: true, kind: "text" }], initialFocus: true });
  }

  async function revokeKey(p, key) {
    const working = p.keys.filter((k) => !k.revokedAt);
    const only = working.length === 1 && working[0].id === key.id;
    const ok = await confirmDialog({
      title: only ? "Revoke the only key?" : "Revoke this key?",
      message: only
        ? `${keyLabel(key)} is the only working key of ${p.name}. Once it is revoked, nothing can send its events until you make a new key. This can't be undone.`
        : `${keyLabel(key)} stops working at once, and whatever sends with it is turned away. This can't be undone.`,
      action: "Revoke",
      destructive: true,
    });
    if (ok) await change(p, () => calls.revokeKey(p.id, key.id), `revoke ${keyLabel(key)}`);
  }

  async function newKey(p) {
    let issued;
    try {
      issued = await calls.issueKey(p.id);
    } catch (error) {
      if (error instanceof SessionEnded) return;
      showBanner("producers-error", () => banner({ glyph: "error", error: true, role: "alert", text: failureMessage(error, `make a new key for ${p.name}`) }));
      return;
    }
    own.set(issued.producer.id, issued.producer);
    paintList();
    paintDetail();
    // The key is in this answer only: the dialog is the one chance to keep it.
    await keyDialog({ name: issued.producer.name, apiKey: issued.apiKey, isNew: false });
  }

  async function disable(p) {
    const ok = await confirmDialog({ title: `Disable ${p.name}?`, message: "Its keys stop working. Its events stay. You can enable it again.", action: "Disable" });
    if (ok) await change(p, () => calls.disableProducer(p.id), `disable ${p.name}`);
  }

  function renameDialog(p) {
    const field = textField({ label: "Name", value: p.name, hint: NameMessages.help, maxlength: 100 });
    let asked = null;
    let refusal = null;
    let dialog;
    const refresh = () => {
      const text = field.input.value;
      const problem = text === asked && refusal ? refusal : nameProblem(text);
      field.setError(problem && (text || asked !== null || field.touched) ? problem : null);
      const valid = !problem && text !== p.name;
      if (dialog) dialog.rename.node.disabled = !valid;
    };
    field.input.addEventListener("input", () => { field.touched = true; refresh(); });
    const body = el("div", {}, field.node, el("p", { class: "p dlg-text", text: "Events keep the producer. They show the new name, and so does everyone it is shared with." }));
    const rename = {
      label: "Rename",
      value: true,
      disabled: true,
      run: async () => {
        const text = field.input.value;
        try {
          const updated = await calls.updateProducer(p.id, { name: text });
          own.set(updated.id, updated);
          if (visible) visible = visible.map((producer) => (producer.id === updated.id ? { ...producer, name: updated.name } : producer));
          paintList();
          paintDetail();
        } catch (error) {
          if (error instanceof ApiError && (error.status === 409 || error.status === 400)) {
            asked = text;
            refusal = error.status === 409 ? NameMessages.taken : NameMessages.notAllowed;
            refresh();
            throw silent();
          }
          if (error instanceof SessionEnded) throw error;
          throw new Error(failureMessage(error, `rename ${p.name}`));
        }
      },
    };
    dialog = openDialog({ title: "Rename producer", content: body, actions: [{ label: "Cancel", value: false }, rename], initialFocus: true });
    dialog.rename = rename;
    field.input.focus();
    field.input.select();
    refresh();
  }

  // ---- New producer ---------------------------------------------------------------------

  function newProducerForm() {
    let visibility = "PRIVATE";
    let asked = null;
    let refusal = null;
    let busy = false;
    let touched = false;
    const field = textField({ label: "Name", hint: NameMessages.help, maxlength: 100 });
    const visibilityHost = el("div", { class: "vis-host" });
    const create = button("Create", { kind: "filled", full: true, type: "submit", disabled: true });
    const errorHost = el("div", { class: "form-error", role: "alert" });
    const form = el("form", { class: "pform", novalidate: true },
      el("p", { class: "t2w", text: "A producer is anything that sends you events: a script, a CI pipeline, a home server. It gets its own key." }),
      field.node,
      label("Who can see it"),
      visibilityHost,
      errorHost,
      el("div", { class: "grow" }),
      create,
    );
    const paintVisibility = () => {
      replace(
        visibilityHost,
        segmented({ label: "Who can see it", value: visibility, options: [{ value: "PRIVATE", label: "Private", glyph: "lock", alwaysGlyph: true }, { value: "PUBLIC", label: "Public", glyph: "public", alwaysGlyph: true }], onChange: (value) => { visibility = value; paintVisibility(); } }),
        el("div", { class: "hint", text: "Only you, and people you add later. Anyone on this server can find and subscribe to a public producer." }),
      );
    };
    const refresh = () => {
      const text = field.input.value;
      const problem = text === asked && refusal ? refusal : nameProblem(text);
      field.setError(problem && (touched || text) ? problem : null);
      create.disabled = Boolean(problem) || busy;
    };
    field.input.addEventListener("input", () => { touched = true; refresh(); });
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (create.disabled) return;
      const name = field.input.value;
      busy = true;
      setBusy(create, true);
      replace(errorHost);
      try {
        const issued = await calls.createProducer(name, visibility);
        own.set(issued.producer.id, issued.producer);
        busy = false;
        await keyDialog({ name: issued.producer.name, apiKey: issued.apiKey, isNew: true });
        await load(true);
        go(`#producers/${encodeURIComponent(issued.producer.id)}`);
      } catch (error) {
        busy = false;
        setBusy(create, false);
        if (error instanceof SessionEnded) return;
        if (error instanceof ApiError && (error.status === 409 || error.status === 400)) {
          asked = name;
          refusal = error.status === 409 ? NameMessages.taken : NameMessages.notAllowed;
        } else {
          replace(errorHost, el("p", { class: "err-text", text: failureMessage(error, `create ${name}`) }));
        }
        refresh();
      }
    });
    paintVisibility();
    // A form closes with an x; on a narrow page it takes the screen and the bottom bar hides.
    replace(detail, paneHeader({ title: "New producer", close: "#producers", level: wide ? 2 : 1 }), form);
    refresh();
    field.input.focus();
  }

  // ---- Public ---------------------------------------------------------------------------

  paintHeader();
  paintList();
  paintDetail();
  load();
  if (selected && selected !== "new") refreshOwn(selected);

  async function refreshOwn(id) {
    const token = ++detailToken;
    try {
      const fresh = await calls.ownProducer(id);
      if (gone || token !== detailToken) return;
      own.set(fresh.id, fresh);
      paintList();
      paintDetail();
    } catch {
      // Not an owned producer (404), or no answer: the list's own copy is shown.
    }
  }

  return {
    update(next) {
      selected = next.segments[1] ?? null;
      setLayout();
      paintList();
      paintDetail();
      if (selected && selected !== "new") refreshOwn(selected);
    },
    refresh: () => load(true),
    unmount() {
      gone = true;
      document.body.classList.remove("no-nav");
      hideBanner("producers");
      hideBanner("producers-error");
    },
  };
}

// ---- The key, shown once --------------------------------------------------------------

/**
 * A new key in a dialog that only its button closes: Escape and the scrim do nothing, so it
 * cannot be lost by accident. Copy turns to Copied and stays; if the browser refuses the
 * clipboard, the key is selected and a line says how to copy by hand.
 */
export function keyDialog({ name, apiKey, isNew }) {
  let copied = false;
  let refused = false;
  const curl = `curl -X POST ${location.origin}/api/v1/events \\\n  -H "Authorization: Bearer ${apiKey}" \\\n  -H "Content-Type: application/json" \\\n  -d '{"category":"INFO","severity":"NORMAL","title":"Hello"}'`;
  const body = el("div", { class: "key-dialog" });
  const keybox = el("div", { class: "keybox", tabindex: "0", "aria-label": "Key", text: apiKey });
  const selectKey = () => {
    const range = document.createRange();
    range.selectNodeContents(keybox);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  };
  keybox.addEventListener("click", selectKey);
  const copyButton = button("Copy", { kind: "tonal", glyph: "content_copy", onClick: () => copy() });
  const shareButton = typeof navigator.share === "function" ? button("Share", { kind: "tonal", glyph: "share", onClick: () => navigator.share({ text: apiKey }).catch(() => {}) }) : null;
  const warning = noticeBox({
    glyph: "visibility_off",
    text: isNew ? "Shown once. You won't see this key again. If you lose it, make a new key on the producer's screen." : "Shown once. You won't see this key again. If you lose it, make another new key.",
  });
  const refusedBox = noticeBox({ glyph: "content_paste_off", error: true, text: "This browser did not allow copying. The key is selected below: press Ctrl+C (Cmd+C on a Mac) to copy it. Don't close this until you have." });
  refusedBox.hidden = true;
  const primary = {
    label: "Copy and close",
    value: true,
    kind: "filled",
    run: async () => {
      if (copied || refused) return;
      if (!(await writeClipboard(apiKey))) {
        refuse();
        throw silent();
      }
      copied = true;
    },
  };

  function paintButtons() {
    replace(copyButton, icon(copied ? "check" : "content_copy"), el("span", { class: "btn-label", text: copied ? "Copied" : refused ? "Try copy again" : "Copy" }));
    primary.node.querySelector(".btn-label").textContent = copied ? "Done" : refused ? "I have saved the key" : "Copy and close";
    keybox.classList.toggle("sel", refused && !copied);
    refusedBox.hidden = !(refused && !copied);
    warning.hidden = refused && !copied;
  }

  function refuse() {
    refused = true;
    selectKey();
    paintButtons();
  }

  async function copy() {
    if (await writeClipboard(apiKey)) {
      copied = true;
      refused = false;
      paintButtons();
      announce("Copied");
    } else {
      refuse();
    }
  }

  body.append(
    el("p", { class: "p dlg-text", text: isNew ? "This is its key. Put it where the producer runs; it sends events with it." : "This is its new key. Switch the producer to it, then revoke the old one." }),
    warning,
    refusedBox,
    keybox,
    el("div", { class: "row" }, copyButton, shareButton),
    el("div", { class: "lab", text: "To send a test event" }),
    el("div", { class: "snip", text: curl }),
  );
  const dialog = openDialog({ title: isNew ? `${name} is ready` : `New key for ${name}`, content: body, persistent: true, actions: [primary], wide: true });
  paintButtons();
  copyButton.focus();
  return dialog.done;
}

async function writeClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}
