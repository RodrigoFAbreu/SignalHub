// Producers: the whole inventory with a search and filter chips; a selected row opens its detail in
// the pane. Everything that was a form under the list or a browser prompt is a dialog: New producer,
// Rename, the key shown once, and the confirmations. A change is confirmed in the pane in words and
// a failed one is said where it was made. Everything the server sends is set as text.

import { ApiError, PRODUCERS, call } from "./api.js";
import { el, icon } from "./dom.js";
import { ago, dateTime, shortDate } from "./format.js";
import { createList } from "./list.js";
import { hashFor } from "./router.js";
import { loadUsers } from "./store.js";
import { announce, avatar, button, confirmDialog, iconButton, openDialog, openMenu, phone, ROLES, segmented, selectField, textField, userChoice } from "./ui.js";

const QUIET_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;
const NAME_RULE = /^[A-Za-z0-9][A-Za-z0-9._:/-]*$/;
const NAME_TAKEN = "That name is taken. Names are shared by everyone on this server.";
const NAME_HINT = "Letters, numbers and . _ : / - only, up to 100 characters. Names are shared by everyone on this server.";

let techOpen = false;

// ---- What a producer is, in the words of the page ------------------------------------------

/** Enabled with no event for more than 7 days, or none stored. */
export function isQuiet(producer) {
  if (producer.disabledAt) return false;
  return !producer.lastEventAt || Date.now() - Date.parse(producer.lastEventAt) > QUIET_DAYS * DAY_MS;
}

const working = (producer) => producer.keys.filter((key) => !key.revokedAt);

/** shpk1_ plus the key's id without its dashes, shortened: the server sends no prefix. */
export function keyLabel(key) {
  return `shpk1_${key.id.replaceAll("-", "").slice(0, 12)}…`;
}

function sharing(producer) {
  if (producer.visibility === "PUBLIC") return "Public";
  const people = producer.allowedUsers.length;
  return people === 0 ? "Private" : `Private · ${people} ${people === 1 ? "person" : "people"}`;
}

function keyCount(producer) {
  const count = working(producer).length;
  return producer.disabledAt && count > 0 ? `${count} (off)` : String(count);
}

function lastEvent(producer) {
  return producer.lastEventAt ? ago(producer.lastEventAt) : "None stored";
}

function nameError(value, { blurred }) {
  if (value.length > 100) return "Use 100 characters or fewer.";
  if (value && !NAME_RULE.test(value)) return "Use letters, numbers and . _ : / - only, starting with a letter or number.";
  if (!value && blurred) return "Give it a name.";
  return "";
}

// ---- The list ------------------------------------------------------------------------------

const list = createList({
  name: "producers",
  title: "Producers",
  noun: ["producer", "producers"],
  searchLabel: "Find a producer",
  gridClass: "gA",
  columns: [
    { label: "Producer" },
    { label: "Owner", className: "c-owner" },
    { label: "Who sees it", className: "c-sees" },
    { label: "Keys", className: "c-keys" },
    { label: "Last event", className: "c-last" },
  ],
  fetch: async () => (await call("GET", PRODUCERS)).items,
  idOf: (producer) => producer.id,
  searchText: (producer) => producer.name,
  chips: [
    { key: "all", label: () => "All" },
    { key: "quiet", label: () => "Quiet", test: isQuiet },
    { key: "disabled", label: () => "Disabled", test: (producer) => Boolean(producer.disabledAt) },
    { key: "public", label: () => "Public", test: (producer) => producer.visibility === "PUBLIC" },
    { key: "private", label: () => "Private", test: (producer) => producer.visibility === "PRIVATE" },
  ],
  menus: [
    {
      key: "owner",
      prefix: "Owner",
      anyLabel: "anyone",
      options: (producers) => {
        const owners = new Map();
        for (const producer of producers) owners.set(producer.owner.id, producer.owner.name);
        return [...owners].map(([value, text]) => ({ value, text })).sort((a, b) => a.text.localeCompare(b.text));
      },
      test: (producer, value) => producer.owner.id === value,
    },
  ],
  primary: { label: "New producer", glyph: "add", onClick: (ctx) => newProducer(ctx), ariaLabel: "New producer" },
  emptyAll: {
    glyph: "sensors",
    title: "No producers yet",
    body: "A producer is anything that sends events: a script, a CI pipeline, a home server. Create one, then give it the key you are shown once.",
  },
  prompt: { glyph: "sensors", title: "Select a producer", text: "Its keys, who can see it and its latest event show here." },
  rowParts: (producer) => {
    const keys = working(producer).length;
    const line = [producer.owner.name, sharing(producer), `${keys} ${keys === 1 ? "key" : "keys"}`, lastEvent(producer)].join(" · ");
    return {
      name: [el("span", { class: "nm", text: producer.name }), producer.disabledAt ? el("span", { class: "tg o", text: "Disabled" }) : null, isQuiet(producer) ? el("span", { class: "tg", text: "Quiet" }) : null],
      sub: producer.owner.name,
      cells: [
        el("span", { class: "own" }, avatar(producer.owner.name, { small: true }), el("span", { text: producer.owner.name })),
        sharing(producer),
        keyCount(producer),
        lastEvent(producer),
      ],
      label: `${producer.name}${producer.disabledAt ? ", disabled" : ""}${isQuiet(producer) ? ", quiet" : ""}, owner ${producer.owner.name}, ${sharing(producer)}, ${keyCount(producer)} keys, last event ${lastEvent(producer).toLowerCase()}`,
      line2: line,
    };
  },
  renderPane: (producer, ctx) => renderPane(producer, ctx),
});

export const producersSection = list;

// ---- The pane ------------------------------------------------------------------------------

function renderPane(producer, ctx) {
  const body = [];
  if (producer.disabledAt) {
    const who = producer.disabledBy === "OWNER" ? "Disabled by its owner" : "Disabled by the host";
    body.push(banner("pause_circle", `${who} on ${shortDate(producer.disabledAt)}. Its keys do not work, so it sends nothing. Its events stay.`));
  } else if (isQuiet(producer)) {
    body.push(
      banner(
        "schedule",
        producer.lastEventAt
          ? `Its last event was ${ago(producer.lastEventAt)}. A producer is quiet after ${QUIET_DAYS} days without an event.`
          : `No event has been stored for it. A producer is quiet after ${QUIET_DAYS} days without an event.`,
      ),
    );
  }
  if (!producer.disabledAt && working(producer).length === 0) {
    body.push(banner("key_off", `No working key. Nothing can send events as ${producer.name} until you issue a key.`));
  }

  const events = el("a", { href: "#events", text: "See its events" });
  events.href = `#events?producer=${producer.id}`;
  body.push(
    el(
      "div",
      { class: "kv" },
      el("b", { text: "Owner" }),
      el("span", { text: producer.owner.name }),
      el("b", { text: "Last event" }),
      el("span", {}, `${lastEvent(producer)} · `, events),
      el("b", { text: "Created" }),
      el("span", { text: shortDate(producer.createdAt) }),
    ),
  );

  // Keys
  const valid = working(producer);
  const revoked = producer.keys.filter((key) => key.revokedAt);
  const only = valid.length === 0;
  body.push(
    el(
      "div",
      { class: "lab" },
      "Keys",
      el("span", { class: "cnt", text: producer.disabledAt && valid.length ? `${valid.length} · not working while disabled` : `${valid.length} working` }),
      el("span", { class: "sp" }),
      button("Issue key", { kind: only && !producer.disabledAt ? "filled" : "outlined", glyph: "add", onClick: () => issueKey(producer, ctx), ariaLabel: `Issue a key for ${producer.name}` }),
    ),
  );
  for (const key of valid) body.push(keyRow(producer, key, ctx));
  for (const key of revoked) body.push(keyRow(producer, key, ctx));

  // Who can see it
  body.push(el("div", { class: "lab", style: null, text: "Who can see it" }));
  body.push(
    segmented({
      label: "Who can see it",
      value: producer.visibility,
      options: [
        { value: "PRIVATE", label: "Private", glyph: "lock" },
        { value: "PUBLIC", label: "Public", glyph: "public" },
      ],
      onChange: (value) => setVisibility(producer, value, ctx),
    }),
  );
  if (producer.visibility === "PUBLIC") {
    body.push(el("div", { class: "t2 sub-note", text: "Every user can see it and subscribe." }));
  } else {
    body.push(el("div", { class: "lab compact", text: "Allowed users" }));
    body.push(allowedUsers(producer, ctx));
  }

  // Disable or enable
  body.push(
    el(
      "div",
      { class: "act" },
      producer.disabledAt
        ? button("Enable", { kind: "filled", glyph: "play_arrow", onClick: () => enable(producer, ctx), ariaLabel: `Enable ${producer.name}` })
        : button("Disable", { kind: "outlined", glyph: "pause_circle", onClick: () => disable(producer, ctx), ariaLabel: `Disable ${producer.name}` }),
      el("span", { class: "t2", text: producer.disabledAt ? "Its keys work again." : "Its keys stop working. Its events stay." }),
    ),
  );

  body.push(technical(producer));
  return {
    title: producer.name,
    actions: [iconButton("edit", `Rename ${producer.name}`, () => rename(producer, ctx))],
    body,
  };
}

function banner(glyph, text) {
  return el("div", { class: "bn neu note" }, icon(glyph, "c-var"), el("span", { class: "tx", text }));
}

function keyRow(producer, key, ctx) {
  const revoked = Boolean(key.revokedAt);
  const dim = revoked || producer.disabledAt;
  const text = revoked
    ? `Created ${shortDate(key.createdAt)} · revoked ${shortDate(key.revokedAt)}`
    : `Created ${shortDate(key.createdAt)} · ${key.lastUsedAt ? `last used ${ago(key.lastUsedAt)}` : "not used yet"}`;
  return el(
    "div",
    { class: `krow${dim ? " dim" : ""}${revoked ? " gone" : ""}` },
    icon(revoked ? "key_off" : "key", "c-var"),
    el("div", { class: "tx" }, el("span", { class: "t1 mono", text: keyLabel(key) }), el("span", { class: "t2", text })),
    revoked ? null : button("Revoke", { kind: "text-error", onClick: () => revokeKey(producer, key, ctx), ariaLabel: `Revoke key ${keyLabel(key)}` }),
  );
}

function allowedUsers(producer, ctx) {
  const wrap = el("div", {});
  const chips = el("div", { class: "pchips" });
  for (const user of producer.allowedUsers) {
    chips.append(
      el(
        "span",
        { class: "pchip" },
        avatar(user.name, { tint: true }),
        el("span", { text: user.name }),
        el("button", { type: "button", class: "x", "aria-label": `Remove ${user.name} from the list`, on: { click: () => removeAllowed(producer, user, ctx) } }, icon("close", "ms18")),
      ),
    );
  }
  const add = el("button", { type: "button", class: "pchip add", "aria-haspopup": "menu", "aria-label": `Add a user to ${producer.name}`, on: { click: () => addAllowed(producer, add, ctx) } }, icon("person_add", "ms18"), el("span", { text: "Add user" }));
  chips.append(add);
  wrap.append(chips);
  if (producer.allowedUsers.length === 0) wrap.append(el("div", { class: "t2 sub-note", text: "Only its owner, until you add someone." }));
  return wrap;
}

function technical(producer) {
  const wrap = el("div", { class: "tfold" });
  const draw = () => {
    const toggle = el(
      "button",
      { type: "button", class: "fold", "aria-expanded": String(techOpen), on: { click: () => { techOpen = !techOpen; draw(); wrap.querySelector(".fold").focus(); } } },
      icon(techOpen ? "expand_less" : "expand_more"),
      el("span", { text: "Technical details" }),
    );
    wrap.replaceChildren(toggle);
    if (!techOpen) return;
    wrap.append(
      el(
        "div",
        { class: "kv fold-body" },
        el("b", { text: "ID" }),
        el("span", { class: "mono small", text: producer.id }),
        el("b", { text: "Key IDs" }),
        el("span", { class: "mono small" }, producer.keys.length ? producer.keys.flatMap((key, index) => [index ? el("br") : null, key.id]) : "None"),
      ),
    );
  };
  draw();
  return wrap;
}

// ---- Changes, each confirmed in the pane or failed where it was made ------------------------

/** Runs a change; a success reads the list again and says so, a failure is said in the pane. */
async function change(ctx, { action, done, failure, retry }) {
  try {
    await action();
  } catch (error) {
    if (error.name === "SessionEnded") return;
    ctx.failed(`${failure} ${error.message.replace(/^SignalHub answered/, "SignalHub answered")} Nothing changed.`, retry);
    return;
  }
  await ctx.changed(done);
}

function setVisibility(producer, value, ctx) {
  const run = () =>
    change(ctx, {
      action: () => call("PATCH", `${PRODUCERS}/${producer.id}`, { visibility: value }),
      done: value === "PUBLIC" ? "Now public." : "Now private.",
      failure: `Could not make it ${value === "PUBLIC" ? "public" : "private"}.`,
      // Try again does not ask again: the question was answered.
      retry: run,
    });
  if (value === "PUBLIC") return run();
  // The control does not move until this is confirmed.
  return confirmDialog({
    title: `Make ${producer.name} private?`,
    message: "Only its owner and the users on its list will see it. Everyone else stops getting its events. To get them back they must be added to its list and subscribe again.",
    action: "Make private",
    run,
  });
}

function removeAllowed(producer, user, ctx) {
  const rest = producer.allowedUsers.filter((other) => other.id !== user.id).map((other) => other.id);
  const run = () =>
    change(ctx, {
      action: () => call("PATCH", `${PRODUCERS}/${producer.id}`, { allowedUserIds: rest }),
      done: `${user.name} removed from the list.`,
      failure: `Could not remove ${user.name}.`,
      retry: run,
    });
  return confirmDialog({
    title: `Remove ${user.name} from ${producer.name}?`,
    message: `${user.name} can no longer see this private producer. If they were subscribed, they stop getting its events, and have to subscribe again after being added back.`,
    action: "Remove",
    destructive: true,
    ariaLabel: `Remove ${user.name}`,
    run,
  });
}

async function addAllowed(producer, anchor, ctx) {
  let users;
  try {
    users = await loadUsers();
  } catch (error) {
    if (error.name !== "SessionEnded") ctx.failed(`Could not read the users. ${error.message} Nothing changed.`, () => addAllowed(producer, anchor, ctx));
    return;
  }
  const taken = new Set([producer.owner.id, ...producer.allowedUsers.map((user) => user.id)]);
  const open = users.filter((user) => !user.revokedAt && !taken.has(user.id));
  if (open.length === 0) {
    openMenu(anchor, { placement: "below-start", label: "Add a user", items: [{ info: true, glyph: "info", label: "Everyone who is not revoked is already on the list." }] });
    return;
  }
  openMenu(anchor, {
    placement: "below-start",
    label: "Add a user",
    items: open.map((user) => ({
      glyph: "person",
      label: user.name,
      sub: ROLES[user.role],
      onSelect: () => {
        const run = () =>
          change(ctx, {
            action: () => call("PATCH", `${PRODUCERS}/${producer.id}`, { allowedUserIds: [...producer.allowedUsers.map((other) => other.id), user.id] }),
            done: `${user.name} added to the list.`,
            failure: `Could not add ${user.name}.`,
            retry: run,
          });
        return run();
      },
    })),
  });
}

function disable(producer, ctx) {
  const who = producer.owner.name;
  const run = () =>
    change(ctx, {
      action: () => call("POST", `${PRODUCERS}/${producer.id}/disable`),
      done: "Disabled.",
      failure: "Could not disable it.",
      retry: run,
    });
  return confirmDialog({
    title: `Disable ${producer.name}?`,
    message: `Its keys stop working and it sends nothing, so ${who} will see it as “Disabled by the host”. Its events stay. You can enable it again.`,
    action: "Disable",
    run,
  });
}

// Enabling needs no confirmation: its keys work again and nothing is lost.
function enable(producer, ctx) {
  const run = () =>
    change(ctx, {
      action: () => call("POST", `${PRODUCERS}/${producer.id}/enable`),
      done: "Enabled.",
      failure: "Could not enable it.",
      retry: run,
    });
  return run();
}

function revokeKey(producer, key, ctx) {
  const onlyKey = working(producer).length === 1;
  const used = key.lastUsedAt ? `It was last used ${ago(key.lastUsedAt)}.` : "It has not been used yet.";
  const run = () =>
    change(ctx, {
      action: () => call("POST", `${PRODUCERS}/${producer.id}/keys/${key.id}/revoke`),
      done: `Key revoked. ${keyLabel(key)} no longer works.`,
      failure: "Could not revoke the key.",
      retry: run,
    });
  return confirmDialog({
    title: onlyKey ? "Revoke the only key?" : "Revoke this key?",
    message: `${keyLabel(key)} stops working at once, and whatever sends with it is turned away. ${used} This cannot be undone.${onlyKey ? " Once it is revoked, nothing can send its events until you issue a new key." : ""}`,
    action: "Revoke",
    destructive: true,
    ariaLabel: `Revoke key ${keyLabel(key)}`,
    run,
  });
}

async function issueKey(producer, ctx) {
  let issued;
  try {
    issued = await call("POST", `${PRODUCERS}/${producer.id}/keys`);
  } catch (error) {
    if (error.name !== "SessionEnded") ctx.failed(`Could not issue a key. ${error.message} Nothing changed.`, () => issueKey(producer, ctx));
    return;
  }
  ctx.reload();
  showKey({ name: producer.name, apiKey: issued.apiKey, fresh: false });
}

function rename(producer, ctx) {
  const field = textField({ label: "Name", value: producer.name, hint: NAME_HINT, maxlength: 120 });
  const dialog = openDialog({
    title: "Rename producer",
    content: field.node,
    focusNode: field.input,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Rename",
        value: true,
        className: "confirm",
        disabled: true,
        onError: (error) => {
          if (error.kind === "taken") confirm.disabled = true;
        },
        run: async () => {
          const name = field.input.value.trim();
          try {
            await call("PATCH", `${PRODUCERS}/${producer.id}`, { name });
          } catch (error) {
            if (error instanceof ApiError && error.status === 409) {
              field.setError(NAME_TAKEN);
              throw new ApiError("", "taken", 409);
            }
            throw error;
          }
          ctx.changed(`Renamed to ${name}.`);
        },
      },
    ],
  });
  const confirm = dialog.actions[1].node;
  const check = (blurred) => {
    const value = field.input.value.trim();
    const problem = nameError(value, { blurred });
    field.setError(problem);
    confirm.disabled = Boolean(problem) || value === "" || value === producer.name;
  };
  field.input.addEventListener("input", () => check(false));
  field.input.addEventListener("blur", () => check(true));
  field.input.select();
}

function newProducer(ctx) {
  let ownerList = [];
  const name = textField({ label: "Name", hint: NAME_HINT, maxlength: 120 });
  const owner = selectField({ label: "Owner", options: [], hint: "The owner sees it in their app and manages its keys." });
  let visibility = "PRIVATE";
  const visibilityNote = el("p", { class: "vis-note" });
  const segmentSlot = el("div", {});
  const drawVisibility = () => {
    segmentSlot.replaceChildren(
      segmented({
        label: "Who can see it",
        value: visibility,
        options: [
          { value: "PRIVATE", label: "Private", glyph: "lock" },
          { value: "PUBLIC", label: "Public", glyph: "public" },
        ],
        onChange: (value) => {
          visibility = value;
          drawVisibility();
          segmentSlot.querySelector("[aria-checked='true']").focus();
        },
      }),
    );
    visibilityNote.textContent = visibility === "PRIVATE" ? "Only its owner, and users you add later. A public producer can be found and subscribed to by every user." : "Every user can see it and subscribe.";
  };
  drawVisibility();
  const content = el(
    "div",
    {},
    el("p", { class: "p", text: "A producer is anything that sends events: a script, a CI pipeline, a home server. It gets its own key." }),
    name.node,
    owner.node,
    el("div", { class: "lab spaced", text: "Who can see it" }),
    segmentSlot,
    visibilityNote,
  );
  let create = null;
  const dialog = openDialog({
    title: "New producer",
    content,
    variant: "full",
    focusNode: name.input,
    actions: [
      { label: "Cancel", value: false, className: "cancel" },
      {
        label: "Create",
        value: true,
        className: "confirm",
        disabled: true,
        keepOpen: true,
        // Off again after a name that is taken, until the name is changed.
        onError: (error) => {
          if (error.kind === "taken") create.disabled = true;
        },
        run: async (controller) => {
          const value = name.input.value.trim();
          let issued;
          try {
            issued = await call("POST", PRODUCERS, { name: value, ownerId: owner.select.value, visibility });
          } catch (error) {
            if (error instanceof ApiError && error.status === 409) {
              name.setError(NAME_TAKEN);
              throw new ApiError("", "taken", 409);
            }
            throw error;
          }
          ctx.reload();
          controller.close(true);
          showKey({ name: value, apiKey: issued.apiKey, fresh: true });
        },
      },
    ],
  });
  create = dialog.actions[1].node;
  const refresh = (blurred) => {
    const value = name.input.value.trim();
    name.setError(nameError(value, { blurred }));
    create.disabled = value === "" || Boolean(nameError(value, { blurred: false })) || ownerList.length === 0;
  };
  name.input.addEventListener("input", () => refresh(false));
  name.input.addEventListener("blur", () => refresh(true));
  loadUsers().then(
    (users) => {
      ownerList = users.filter((user) => !user.revokedAt);
      // The operator is usually the owner: an admin first.
      ownerList.sort((a, b) => (b.role === "ADMIN") - (a.role === "ADMIN"));
      owner.select.replaceChildren(...ownerList.map((user) => el("option", { value: user.id, text: userChoice(user) })));
      refresh(false);
    },
    (error) => {
      if (error.name !== "SessionEnded") dialog.error(`Could not read the users. ${error.message}`);
    },
  );
}

// ---- The key, shown once -------------------------------------------------------------------

function showKey({ name, apiKey, fresh }) {
  let copied = false;
  const copy = button("Copy", { kind: "tonal", glyph: "content_copy", onClick: () => doCopy() });
  const text = el("div", { class: "key", text: apiKey, "data-testid": "key" });
  const content = el(
    "div",
    {},
    el("p", { class: "p", text: fresh ? "This is its key. Put it where the producer runs; it sends events with it." : "This is its new key. Switch the producer to it, then revoke the old one." }),
    el("div", { class: "keybox" }, text),
    el("div", { class: "keyrow" }, copy),
    el("div", { class: "warn" }, icon("visibility_off", "c-var"), el("span", { text: "Shown once. You won't see this key again. If you lose it, issue a new key on the producer's page." })),
  );
  if (fresh) {
    content.append(
      el("div", { class: "lab compact", text: "To send a test event" }),
      el("div", { class: "code", text: `curl -X POST ${location.origin}/api/v1/events \\\n  -H "Authorization: Bearer ${apiKey}" \\\n  -H "Content-Type: application/json" \\\n  -d '{"category":"INFO","severity":"NORMAL","title":"Hello"}'` }),
    );
  }
  async function doCopy() {
    try {
      await navigator.clipboard.writeText(apiKey);
    } catch {
      // The clipboard needs a secure context (https or localhost); selecting still works.
      const range = document.createRange();
      range.selectNodeContents(text);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      announce("Press Ctrl+C to copy the key.");
      return;
    }
    copied = true;
    copy.querySelector(".btn-label").textContent = "Copied";
    primary.querySelector(".btn-label").textContent = "Done";
    announce("Key copied.");
  }
  const dialog = openDialog({
    title: fresh ? `${name} is ready` : `New key for ${name}`,
    content,
    variant: "full",
    // Escape and a click outside do nothing until the key was copied; then they ask.
    guard: async () => {
      if (copied) return true;
      return confirmDialog({
        title: "Did you copy the key?",
        message: `It's shown once. If you leave now, you'll need to issue a new key for ${name}.`,
        action: "Leave",
        cancel: "Stay",
        destructive: false,
      });
    },
    actions: [
      {
        label: "Copy and close",
        value: true,
        kind: "filled",
        className: "confirm",
        run: async () => {
          if (!copied) await doCopy();
          if (!copied) throw new Error("Press Ctrl+C to copy the selected key, then choose Done.");
        },
      },
    ],
    initialFocus: true,
  });
  const primary = dialog.actions[0].node;
}

export { hashFor };
