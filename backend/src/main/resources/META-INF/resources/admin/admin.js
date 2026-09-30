"use strict";

// The admin page (docs/architecture.md#the-admin-page), in sections kept in the address's fragment:
// Devices lists every client with the management API, changes them, deletes revoked ones, and
// creates pairings shown as a QR code until they are used or expire; Producers lists every producer,
// creates them, issues and revokes their keys, and disables and enables them.
// The admin token lives only in this closure; it is never stored, and every request goes to this
// same origin. A new producer key is shown once and dropped when the operator is done with it.
// Names come from the server and are always set as text, never as HTML.
(() => {
  const CLIENTS = "/api/v1/admin/clients";
  const PAIRINGS = "/api/v1/admin/pairings";
  const PRODUCERS = "/api/v1/admin/producers";
  const SECTIONS = ["devices", "producers"];
  // An enabled producer with no event for this long is marked quiet, so one that stopped stands out.
  const QUIET_DAYS = 7;
  const DAY_MS = 24 * 60 * 60 * 1000;
  const QR_SIZE = 320;
  // Asked only while a code is shown; one owner's page, so a few seconds late is fine.
  const POLL_MS = 2500;
  const TOAST_MS = 8000;
  const $ = (id) => document.getElementById(id);

  let token = null;
  let timer = null;
  let poller = null;
  let current = null;
  let toastTimer = null;

  $("unlock").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("error", null);
    try {
      await call("GET", CLIENTS, null, $("token").value.trim());
      // Kept only once it has worked, so a wrong token never replaces a right one.
      token = $("token").value.trim();
      $("token").value = "";
      $("unlock").hidden = true;
      $("admin").hidden = false;
      showSection();
    } catch (e) {
      showError("error", e.message);
    }
  });

  window.addEventListener("hashchange", () => {
    if (token) showSection();
  });

  $("refresh").addEventListener("click", () => refresh());
  $("refresh-producers").addEventListener("click", () => refreshProducers());

  $("create").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("pair-error", null);
    try {
      const pairing = await call("POST", PAIRINGS, {
        name: $("name").value.trim(),
        admin: $("pair-admin").checked,
      });
      // The app pairs only from a link, and the link needs the server's public address.
      if (!pairing.uri) {
        throw new Error("No pairing link: set SIGNALHUB_PUBLIC_URL on the server to its public address.");
      }
      show(pairing);
    } catch (e) {
      showError("pair-error", e.message);
    }
  });

  $("create-producer").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("create-producer-error", null);
    try {
      const issued = await call("POST", PRODUCERS, { name: $("producer-name").value.trim() });
      $("create-producer").reset();
      showKey(issued);
      await refreshProducers();
    } catch (e) {
      showError("create-producer-error", e.message);
    }
  });

  $("copy-key").addEventListener("click", () => copyFrom($("new-key-value"), "key", keyStatus));
  $("new-key-done").addEventListener("click", () => hideKey());

  $("copy-link").addEventListener("click", () => copyLink());
  $("copy-image").addEventListener("click", () => copyImage());
  $("download").addEventListener("click", () => download());

  async function call(method, path, body, withToken = token) {
    let response;
    try {
      response = await fetch(path, {
        method,
        headers: body
          ? { Authorization: `Bearer ${withToken}`, "Content-Type": "application/json" }
          : { Authorization: `Bearer ${withToken}` },
        body: body ? JSON.stringify(body) : undefined,
        cache: "no-store",
      });
    } catch {
      throw new Error("Could not reach SignalHub.");
    }
    if (response.status === 401) throw new Error("Wrong admin token.");
    if (response.status === 404 && (path === CLIENTS || path === PRODUCERS)) {
      throw new Error("The management API is off: set SIGNALHUB_ADMIN_TOKEN on the server.");
    }
    if (!response.ok) throw new Error(await errorTitle(response));
    return response.status === 204 ? null : response.json();
  }

  async function errorTitle(response) {
    try {
      const body = await response.json();
      const details = (body.violations || []).map((v) => v.message).join(", ");
      return details ? `${body.title}: ${details}` : body.title;
    } catch {
      return `SignalHub answered ${response.status}.`;
    }
  }

  // --- Sections --------------------------------------------------------------------------------

  // Shows the section named in the address, Devices when it names none, and reads its list again.
  function showSection() {
    const name = SECTIONS.find((section) => location.hash === `#${section}`) || SECTIONS[0];
    for (const node of document.querySelectorAll("#admin > [data-section]")) {
      node.hidden = node.dataset.section !== name;
    }
    for (const link of document.querySelectorAll("#sections a")) {
      if (link.dataset.section === name) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
    return name === "producers" ? refreshProducers() : refresh();
  }

  // --- Devices ---------------------------------------------------------------------------------

  async function refresh() {
    showError("devices-error", null);
    try {
      render((await call("GET", CLIENTS)).items);
    } catch (e) {
      showError("devices-error", e.message);
    }
  }

  // Shows the list as the server has it afterwards, whether the change worked or not.
  async function change(action) {
    let failure = null;
    try {
      await action();
    } catch (e) {
      failure = e.message;
    }
    await refresh();
    if (failure) showError("devices-error", failure);
  }

  function render(clients) {
    // Active devices first, newest first, as the owner looks for the one just paired.
    const sorted = [...clients].sort(
      (a, b) => (a.revokedAt ? 1 : 0) - (b.revokedAt ? 1 : 0) || b.createdAt.localeCompare(a.createdAt),
    );
    const list = $("device-list");
    list.replaceChildren(...sorted.map(device));
    if (sorted.length === 0) list.append(element("li", "empty", "No devices yet."));
  }

  function device(client) {
    const item = element("li", client.revokedAt ? "device revoked" : "device");
    const title = element("h3", null, client.name);
    if (client.admin) title.append(" ", element("span", "badge", "Admin"));
    if (client.revokedAt) title.append(" ", element("span", "badge muted", "Revoked"));
    item.append(title);

    const facts = element("dl");
    const fact = (name, value) => facts.append(element("dt", null, name), element("dd", null, value));
    fact("Created", time(client.createdAt));
    if (client.revokedAt) fact("Revoked", time(client.revokedAt));
    fact(
      "Push target",
      client.pushTarget ? `${client.pushTarget.provider}, set ${time(client.pushTarget.updatedAt)}` : "None",
    );
    const status = client.pushStatus;
    fact(
      "Last push",
      status.lastSuccess ? `${time(status.lastSuccess.at)}, event ${status.lastSuccess.eventId}` : "None yet",
    );
    fact(
      "Last failure",
      status.lastFailure
        ? `${time(status.lastFailure.at)}, ${status.lastFailure.result}, event ${status.lastFailure.eventId}`
        : "None",
    );
    fact("Waiting for a retry", String(status.pendingRetries));
    fact("ID", client.id);
    item.append(facts);

    // A revoked client never changes; it can only be deleted. An active one must be revoked first.
    const actions = element("div", "actions");
    if (client.revokedAt) {
      actions.append(button("Delete", () => remove(client), "danger"));
    } else {
      actions.append(
        button("Rename", () => rename(client)),
        button(client.admin ? "Take admin rights away" : "Make admin", () =>
          change(() => update(client, { admin: !client.admin })),
        ),
        button("Revoke", () => revoke(client), "danger"),
      );
    }
    item.append(actions);
    return item;
  }

  function rename(client) {
    const name = prompt(`New name for "${client.name}":`, client.name);
    if (name === null || name.trim() === "" || name.trim() === client.name) return;
    change(() => update(client, { name: name.trim() }));
  }

  function revoke(client) {
    const what = client.admin ? "admin device" : "device";
    if (!confirm(`Revoke the ${what} "${client.name}"? It stops working at once, for good.`)) return;
    change(() => call("POST", `${CLIENTS}/${client.id}/revoke`));
  }

  function remove(client) {
    if (!confirm(`Delete the revoked device "${client.name}"? It leaves this list for good.`)) return;
    change(() => call("DELETE", `${CLIENTS}/${client.id}`));
  }

  function update(client, changes) {
    return call("PATCH", `${CLIENTS}/${client.id}`, changes);
  }

  function time(iso) {
    return new Date(iso).toLocaleString();
  }

  function ago(iso) {
    const minutes = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 60000));
    if (minutes < 1) return "just now";
    if (minutes < 60) return plural(minutes, "minute");
    if (minutes < 60 * 24) return plural(Math.round(minutes / 60), "hour");
    return plural(Math.round(minutes / (60 * 24)), "day");
  }

  function plural(count, unit) {
    return `${count} ${unit}${count === 1 ? "" : "s"} ago`;
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function button(text, onClick, className = "secondary") {
    const node = element("button", className, text);
    node.type = "button";
    node.addEventListener("click", onClick);
    return node;
  }

  // --- Producers -------------------------------------------------------------------------------

  async function refreshProducers() {
    showError("producers-error", null);
    try {
      renderProducers((await call("GET", PRODUCERS)).items);
    } catch (e) {
      showError("producers-error", e.message);
    }
  }

  // Shows the list as the server has it afterwards, whether the change worked or not.
  async function changeProducer(action) {
    let failure = null;
    try {
      await action();
    } catch (e) {
      failure = e.message;
    }
    await refreshProducers();
    if (failure) showError("producers-error", failure);
  }

  function renderProducers(producers) {
    // By name, as the server lists them; a quiet one stands out by its badge.
    const list = $("producer-list");
    list.replaceChildren(...producers.map(producer));
    if (producers.length === 0) list.append(element("li", "empty", "No producers yet."));
  }

  function quiet(producer) {
    if (producer.disabledAt) return false;
    return !producer.lastEventAt || Date.now() - Date.parse(producer.lastEventAt) > QUIET_DAYS * DAY_MS;
  }

  function producer(p) {
    const item = element("li", p.disabledAt ? "producer disabled" : "producer");
    const title = element("h3", null, p.name);
    if (p.disabledAt) title.append(" ", element("span", "badge muted", "Disabled"));
    if (quiet(p)) title.append(" ", element("span", "badge warn", "Quiet"));
    item.append(title);

    const facts = element("dl");
    const fact = (name, value) => facts.append(element("dt", null, name), element("dd", null, value));
    // Only events still stored count: retention may have deleted older ones.
    fact("Last event", p.lastEventAt ? `${time(p.lastEventAt)} (${ago(p.lastEventAt)})` : "None stored");
    fact("Created", time(p.createdAt));
    if (p.disabledAt) fact("Disabled", time(p.disabledAt));
    fact("ID", p.id);
    item.append(facts);

    item.append(element("h4", null, "Keys"));
    const keys = element("ul", "keys");
    // Valid keys first, newest first, as the one just issued is the one looked for.
    const sorted = [...p.keys].sort(
      (a, b) => (a.revokedAt ? 1 : 0) - (b.revokedAt ? 1 : 0) || b.createdAt.localeCompare(a.createdAt),
    );
    keys.append(...sorted.map((key) => apiKey(p, key)));
    if (sorted.length === 0) keys.append(element("li", "empty", "No keys."));
    item.append(keys);

    const actions = element("div", "actions");
    actions.append(
      button("Issue a key", () => issueKey(p)),
      p.disabledAt
        ? button("Enable", () => changeProducer(() => call("POST", `${PRODUCERS}/${p.id}/enable`)))
        : button("Disable", () => disable(p), "danger"),
    );
    item.append(actions);
    return item;
  }

  function apiKey(p, key) {
    const item = element("li", key.revokedAt ? "key revoked" : "key");
    const text = element("span", null, `${key.id}, created ${time(key.createdAt)}`);
    item.append(text);
    if (key.revokedAt) {
      text.append(`, revoked ${time(key.revokedAt)}`);
    } else {
      item.append(button("Revoke", () => revokeKey(p, key), "danger"));
    }
    return item;
  }

  function issueKey(p) {
    changeProducer(async () => showKey(await call("POST", `${PRODUCERS}/${p.id}/keys`)));
  }

  function revokeKey(p, key) {
    const question = `Revoke key ${key.id} of "${p.name}"? It stops working at once, for good.`;
    if (!confirm(question)) return;
    changeProducer(() => call("POST", `${PRODUCERS}/${p.id}/keys/${key.id}/revoke`));
  }

  function disable(p) {
    if (!confirm(`Disable "${p.name}"? None of its keys work until it is enabled again.`)) return;
    changeProducer(() => call("POST", `${PRODUCERS}/${p.id}/disable`));
  }

  // The only time the key is on the page; it leaves with hideKey and is never stored.
  function showKey(issued) {
    $("new-key-producer").textContent = issued.producer.name;
    $("new-key-value").value = issued.apiKey;
    keyStatus("");
    $("new-key").hidden = false;
    $("new-key").scrollIntoView({ block: "nearest" });
  }

  function hideKey() {
    $("new-key-value").value = "";
    $("new-key").hidden = true;
  }

  function keyStatus(text) {
    $("new-key-status").textContent = text;
  }

  // --- Pairing ---------------------------------------------------------------------------------

  function show(pairing) {
    current = pairing;
    $("pairing-name").textContent = pairing.name;
    $("pairing-admin").hidden = !pairing.admin;
    $("status").textContent = "";
    $("qr-box").classList.remove("expired");
    $("expired-cover").hidden = true;
    $("link").value = pairing.uri;
    for (const id of ["copy-image", "copy-link", "download"]) $(id).disabled = false;
    draw(pairing.uri);
    $("pairing").hidden = false;
    clearInterval(timer);
    clearInterval(poller);
    tick();
    timer = setInterval(tick, 1000);
    poller = setInterval(() => check(pairing), POLL_MS);
  }

  function tick() {
    const left = Math.max(0, Date.parse(current.expiresAt) - Date.now());
    if (left === 0) {
      clearInterval(timer);
      clearInterval(poller);
      // Once more: it may have been used in the last seconds.
      check(current);
      $("countdown").textContent = "This code has expired.";
      $("status").textContent = "";
      $("qr-box").classList.add("expired");
      $("expired-cover").hidden = false;
      $("link").value = "";
      for (const id of ["copy-image", "copy-link", "download"]) $(id).disabled = true;
      return;
    }
    const minutes = Math.floor(left / 60000);
    const seconds = String(Math.floor((left % 60000) / 1000)).padStart(2, "0");
    $("countdown").textContent = `Expires in ${minutes}:${seconds}. It works once.`;
  }

  // Whether the code shown was used. The server keeps a used pairing past its expiry, so a late
  // answer still says so; the countdown alone decides that a code expired.
  async function check(pairing) {
    let status;
    try {
      status = await call("GET", `${PAIRINGS}/${pairing.id}`);
    } catch {
      return; // Asked again at the next poll.
    }
    if (current !== pairing || status.state !== "REDEEMED") return;
    connected(status.client);
  }

  // Back to the first state, ready for the next device, and the new one in the list.
  function connected(client) {
    clearInterval(timer);
    clearInterval(poller);
    current = null;
    $("pairing").hidden = true;
    $("link").value = "";
    $("create").reset();
    toast(`"${client.name}" connected with the pairing code.`);
    refresh();
  }

  function toast(text) {
    $("toast").textContent = text;
    $("toast").hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => ($("toast").hidden = true), TOAST_MS);
  }

  function draw(text) {
    // Type 0 picks the smallest QR version that fits; level M survives a slightly blurry photo.
    const qr = qrcode(0, "M");
    qr.addData(text);
    qr.make();
    const modules = qr.getModuleCount();
    const quiet = 4;
    const scale = Math.floor(QR_SIZE / (modules + 2 * quiet));
    const offset = Math.floor((QR_SIZE - scale * modules) / 2);
    const context = $("qr").getContext("2d");
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, QR_SIZE, QR_SIZE);
    context.fillStyle = "#000000";
    for (let row = 0; row < modules; row++) {
      for (let col = 0; col < modules; col++) {
        if (qr.isDark(row, col)) {
          context.fillRect(offset + col * scale, offset + row * scale, scale, scale);
        }
      }
    }
  }

  function copyLink() {
    return copyFrom($("link"), "link", status);
  }

  // Copies an input's text, and says so with say.
  async function copyFrom(input, what, say) {
    try {
      await navigator.clipboard.writeText(input.value);
    } catch {
      // The clipboard API needs a secure context (https or localhost); selecting still works.
      input.select();
      if (!document.execCommand("copy")) {
        return say(`Copy the selected ${what} with Ctrl+C.`);
      }
    }
    say(`${what[0].toUpperCase()}${what.slice(1)} copied.`);
  }

  async function copyImage() {
    if (!navigator.clipboard || typeof ClipboardItem === "undefined") {
      return status("This browser cannot copy images here. Use Download QR.");
    }
    try {
      await navigator.clipboard.write([new ClipboardItem({ "image/png": pngBlob() })]);
      status("QR image copied.");
    } catch {
      status("Could not copy the image. Use Download QR.");
    }
  }

  function pngBlob() {
    return new Promise((resolve, reject) =>
      $("qr").toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no image"))), "image/png"),
    );
  }

  async function download() {
    const url = URL.createObjectURL(await pngBlob());
    const link = document.createElement("a");
    link.href = url;
    link.download = `signalhub-pairing-${current.name.replace(/[^\w.-]+/g, "_")}.png`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function status(text) {
    $("status").textContent = text;
  }

  function showError(id, text) {
    $(id).textContent = text || "";
    $(id).hidden = !text;
  }
})();
