"use strict";

// The admin page (docs/architecture.md#the-admin-page): lists every client with the management API,
// changes them, deletes revoked ones, and creates pairings shown as a QR code until they expire.
// The admin token lives only in this closure; it is never stored, and every request goes to this
// same origin.
// Names come from the server and are always set as text, never as HTML.
(() => {
  const CLIENTS = "/api/v1/admin/clients";
  const PAIRINGS = "/api/v1/admin/pairings";
  const QR_SIZE = 320;
  const $ = (id) => document.getElementById(id);

  let token = null;
  let timer = null;
  let current = null;

  $("unlock").addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("error", null);
    try {
      const clients = await call("GET", CLIENTS, null, $("token").value.trim());
      // Kept only once it has worked, so a wrong token never replaces a right one.
      token = $("token").value.trim();
      $("token").value = "";
      $("unlock").hidden = true;
      $("admin").hidden = false;
      render(clients.items);
    } catch (e) {
      showError("error", e.message);
    }
  });

  $("refresh").addEventListener("click", () => refresh());

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
    if (response.status === 404 && path === CLIENTS) {
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
    const list = $("devices");
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
    tick();
    timer = setInterval(tick, 1000);
  }

  function tick() {
    const left = Math.max(0, Date.parse(current.expiresAt) - Date.now());
    if (left === 0) {
      clearInterval(timer);
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

  async function copyLink() {
    const text = $("link").value;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // The clipboard API needs a secure context (https or localhost); selecting still works.
      $("link").select();
      if (!document.execCommand("copy")) {
        return status("Copy the selected link with Ctrl+C.");
      }
    }
    status("Link copied.");
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
